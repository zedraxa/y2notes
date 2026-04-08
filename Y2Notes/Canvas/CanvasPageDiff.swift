import UIKit
import PencilKit

// MARK: - CanvasPageDiff

/// Describes which aspects of a `CanvasPageConfiguration` changed between two
/// snapshots, enabling the coordinator's `updateUIView` to perform only the
/// necessary UIKit mutations.
///
/// ## Motivation
/// `CanvasPageView.updateUIView` currently performs ~30 individual property
/// comparisons every time SwiftUI re-renders the parent.  Many of those
/// checks are redundant when only a single property changed (e.g. the tool
/// colour changed but nothing else did).
///
/// `CanvasPageDiff` replaces scattered `if old != new` blocks with a single
/// up-front diff pass that produces an `OptionSet`, letting each sync block
/// short-circuit via a bitfield test.
///
/// ## Usage
/// ```swift
/// let diff = CanvasPageDiff.between(old: savedConfig, new: newConfig)
/// if diff.contains(.tool)          { syncTool(canvas, newConfig) }
/// if diff.contains(.drawingPolicy) { syncDrawingPolicy(canvas, newConfig) }
/// ```
struct CanvasPageDiff: OptionSet {
    let rawValue: UInt32

    // MARK: - Flags

    /// Drawing data changed (stroke committed, undo/redo).
    static let drawingData       = CanvasPageDiff(rawValue: 1 << 0)
    /// Active PencilKit tool changed.
    static let tool              = CanvasPageDiff(rawValue: 1 << 1)
    /// Finger vs. pencil drawing policy changed.
    static let drawingPolicy     = CanvasPageDiff(rawValue: 1 << 2)
    /// Canvas background colour changed.
    static let backgroundColor   = CanvasPageDiff(rawValue: 1 << 3)
    /// Contrasting ink colour changed.
    static let defaultInkColor   = CanvasPageDiff(rawValue: 1 << 4)
    /// Page ruling style changed.
    static let pageType          = CanvasPageDiff(rawValue: 1 << 5)
    /// Paper material changed.
    static let paperMaterial     = CanvasPageDiff(rawValue: 1 << 6)
    /// Shape tool state changed (active, type, colour, or width).
    static let shapeTool         = CanvasPageDiff(rawValue: 1 << 7)
    /// Ink effect type or colour changed.
    static let inkEffect         = CanvasPageDiff(rawValue: 1 << 8)
    /// Magic Mode toggled.
    static let magicMode         = CanvasPageDiff(rawValue: 1 << 9)
    /// Study Mode toggled.
    static let studyMode         = CanvasPageDiff(rawValue: 1 << 10)
    /// Ambient scene changed.
    static let ambientScene      = CanvasPageDiff(rawValue: 1 << 11)
    /// Shape objects changed.
    static let shapes            = CanvasPageDiff(rawValue: 1 << 12)
    /// Attachment objects changed.
    static let attachments       = CanvasPageDiff(rawValue: 1 << 13)
    /// Widget objects changed.
    static let widgets           = CanvasPageDiff(rawValue: 1 << 14)
    /// Text objects changed.
    static let textObjects       = CanvasPageDiff(rawValue: 1 << 15)
    /// Text tool active state changed.
    static let textToolActive    = CanvasPageDiff(rawValue: 1 << 16)
    /// PDF background URL changed.
    static let pdfURL            = CanvasPageDiff(rawValue: 1 << 17)
    /// Zoom reset trigger flipped.
    static let zoomReset         = CanvasPageDiff(rawValue: 1 << 18)
    /// Page count changed.
    static let pageCount         = CanvasPageDiff(rawValue: 1 << 19)
    /// Ambient sound enabled/disabled.
    static let ambientSound      = CanvasPageDiff(rawValue: 1 << 20)

    // MARK: - Compound sets

    /// All appearance-related changes (background, ruling, material).
    static let appearance: CanvasPageDiff = [.backgroundColor, .pageType, .paperMaterial]
    /// All effect-related changes.
    static let effects: CanvasPageDiff    = [.inkEffect, .magicMode, .studyMode, .ambientScene, .ambientSound]
    /// All object-layer changes.
    static let objects: CanvasPageDiff    = [.shapes, .attachments, .widgets, .textObjects, .textToolActive]
    /// Nothing changed.
    static let none: CanvasPageDiff       = []

    // MARK: - Diffing

    /// Computes which fields differ between two configurations.
    ///
    /// Each field comparison is a cheap value-type equality check (or
    /// `ToolSnapshot` for `PKTool`) followed by a single `insert` into
    /// the option set.  The result is a compact bitfield that downstream
    /// sync blocks can test in O(1).
    ///
    /// - Parameters:
    ///   - old: The previous configuration.
    ///   - new: The incoming configuration.
    /// - Returns: An `OptionSet` describing which aspects changed.
    static func between(old: CanvasPageConfiguration, new: CanvasPageConfiguration) -> CanvasPageDiff {
        var diff = CanvasPageDiff.none

        // Drawing state
        if old.drawingData != new.drawingData                        { diff.insert(.drawingData) }
        if ToolSnapshot(old.currentTool) != ToolSnapshot(new.currentTool) { diff.insert(.tool) }
        if old.drawingPolicy != new.drawingPolicy                    { diff.insert(.drawingPolicy) }

        // Appearance
        if old.backgroundColor.cgColor != new.backgroundColor.cgColor { diff.insert(.backgroundColor) }
        if old.defaultInkColor.cgColor != new.defaultInkColor.cgColor { diff.insert(.defaultInkColor) }
        if old.pageType != new.pageType                              { diff.insert(.pageType) }
        if old.paperMaterial != new.paperMaterial                    { diff.insert(.paperMaterial) }

        // Shape tool
        if old.isShapeToolActive != new.isShapeToolActive
            || old.activeShapeType != new.activeShapeType
            || old.shapeColor.cgColor != new.shapeColor.cgColor
            || old.shapeWidth != new.shapeWidth {
            diff.insert(.shapeTool)
        }

        // Effects
        if old.activeFX != new.activeFX
            || old.fxColor.cgColor != new.fxColor.cgColor {
            diff.insert(.inkEffect)
        }
        if old.isMagicModeActive != new.isMagicModeActive            { diff.insert(.magicMode) }
        if old.isStudyModeActive != new.isStudyModeActive            { diff.insert(.studyMode) }
        if old.activeAmbientScene != new.activeAmbientScene          { diff.insert(.ambientScene) }
        if old.isAmbientSoundEnabled != new.isAmbientSoundEnabled    { diff.insert(.ambientSound) }

        // Object layers
        if old.shapes != new.shapes                                  { diff.insert(.shapes) }
        if old.attachments != new.attachments                        { diff.insert(.attachments) }
        if old.widgets != new.widgets                                { diff.insert(.widgets) }
        if old.textObjects != new.textObjects                        { diff.insert(.textObjects) }
        if old.isTextToolActive != new.isTextToolActive              { diff.insert(.textToolActive) }

        // PDF
        if old.pdfURL != new.pdfURL                                  { diff.insert(.pdfURL) }

        // Page context
        if old.zoomResetTrigger != new.zoomResetTrigger              { diff.insert(.zoomReset) }
        if old.pageCount != new.pageCount                            { diff.insert(.pageCount) }

        return diff
    }
}
