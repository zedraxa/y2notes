import UIKit
import PencilKit

// MARK: - CanvasPageConfiguration

/// Immutable value type that consolidates every parameter needed to render a
/// single canvas page.
///
/// Before this type, canvas properties were drilled through 3–4 view layers as
/// 60+ individual parameters, making the API fragile and hard to reason about.
/// `CanvasPageConfiguration` centralises them into a single, equatable struct
/// that can be created once per page in `NoteEditorView` and forwarded through
/// the carousel without any intermediate destructuring.
///
/// ## Usage
/// ```swift
/// let config = CanvasPageConfiguration(
///     noteID: note.id,
///     pageIndex: idx,
///     drawingData: note.pages[idx],
///     ...
/// )
/// NotebookCanvasView(configuration: config, callbacks: callbacks)
/// ```
struct CanvasPageConfiguration: Equatable {

    // MARK: - Identity

    /// Unique identifier of the note this page belongs to.
    let noteID: UUID
    /// Zero-based index of this page within the note.
    let pageIndex: Int

    // MARK: - Drawing State

    /// Serialised `PKDrawing` data for this page.
    let drawingData: Data
    /// The current PencilKit tool (pen, eraser, lasso, …).
    let currentTool: PKTool
    /// Whether finger touches draw or only pan/zoom.
    let drawingPolicy: PKCanvasViewDrawingPolicy

    // MARK: - Appearance

    /// Canvas background colour (blended theme + paper material).
    let backgroundColor: UIColor
    /// Contrasting ink colour derived from the theme for dark-mode awareness.
    let defaultInkColor: UIColor
    /// Page ruling style (blank, lined, grid, dotted, cornell, music).
    let pageType: PageType
    /// Paper material (standard, premium, craft, …) for grain and tint.
    let paperMaterial: PaperMaterial

    // MARK: - Shape Tool

    /// Whether the shape tool is active (disables PKCanvasView interaction).
    let isShapeToolActive: Bool
    /// Active shape type when the shape tool is selected.
    let activeShapeType: ShapeType
    /// Stroke colour for newly drawn shapes.
    let shapeColor: UIColor
    /// Stroke width for newly drawn shapes.
    let shapeWidth: Double

    // MARK: - Effects

    /// Active writing FX type (`.none` = no FX).
    let activeFX: WritingFXType
    /// Ink colour resolved for the active FX preset.
    let fxColor: UIColor
    /// Whether Magic Mode is active (keyword glow, highlight).
    let isMagicModeActive: Bool
    /// Whether Study Mode is active (heading glow, timer pulse).
    let isStudyModeActive: Bool
    /// Currently active ambient environment scene, or `nil`.
    let activeAmbientScene: AmbientScene?
    /// Whether ambient soundscapes are enabled.
    let isAmbientSoundEnabled: Bool

    // MARK: - Object Layers

    /// Shape objects for this page.
    let shapes: [ShapeInstance]
    /// Attachment objects for this page.
    let attachments: [AttachmentObject]
    /// Note ID used for attachment file lookups.
    let attachmentNoteID: UUID
    /// Interactive widget instances for this page.
    let widgets: [NoteWidget]
    /// Sticker instances for this page.
    let stickers: [StickerInstance]
    /// Text objects anchored on this page.
    let textObjects: [TextObject]
    /// Whether the text tool is active (text canvas intercepts taps).
    let isTextToolActive: Bool

    // MARK: - PDF Background

    /// On-disk URL of the note's backing PDF for book-like rendering.
    let pdfURL: URL?

    // MARK: - Page Context

    /// Total number of pages in the note.
    let pageCount: Int
    /// Whether this page was just added (triggers reveal animation).
    let isNewPage: Bool
    /// Flipped to trigger animated zoom reset.
    let zoomResetTrigger: Bool
    /// Initial zoom scale to restore (nil = fit-to-width).
    let initialZoomScale: CGFloat?

    // MARK: - Canvas Mode

    /// Whether this page uses infinite canvas mode (boundless whiteboard).
    let isInfiniteCanvas: Bool

    // MARK: - Equatable

    /// Custom Equatable conformance because `PKTool` and `UIColor` don't
    /// conform to `Equatable` out of the box.
    ///
    /// Uses `ToolSnapshot` for tool identity comparison (same pattern as the
    /// coordinator's guard against redundant `canvas.tool` assignments) and
    /// compares `UIColor` via their CGColor representations.
    static func == (lhs: CanvasPageConfiguration, rhs: CanvasPageConfiguration) -> Bool {
        // Identity & page context (fast, cheap)
        guard lhs.noteID == rhs.noteID,
              lhs.pageIndex == rhs.pageIndex,
              lhs.pageCount == rhs.pageCount,
              lhs.isNewPage == rhs.isNewPage,
              lhs.zoomResetTrigger == rhs.zoomResetTrigger,
              lhs.initialZoomScale == rhs.initialZoomScale
        else { return false }

        // Drawing state
        // NOTE: `drawingData` is intentionally EXCLUDED from equality.
        // PKCanvasView owns the drawing after makeUIView sets it once.
        // Including drawingData here causes a feedback loop:
        //   stroke → onDrawingChanged → noteStore @Published → SwiftUI re-eval
        //   → config inequality → updateUIView / view recreation → double writing.
        guard ToolSnapshot(lhs.currentTool) == ToolSnapshot(rhs.currentTool),
              lhs.drawingPolicy == rhs.drawingPolicy
        else { return false }

        // Appearance
        guard lhs.backgroundColor.cgColor == rhs.backgroundColor.cgColor,
              lhs.defaultInkColor.cgColor == rhs.defaultInkColor.cgColor,
              lhs.pageType == rhs.pageType,
              lhs.paperMaterial == rhs.paperMaterial
        else { return false }

        // Shape tool
        guard lhs.isShapeToolActive == rhs.isShapeToolActive,
              lhs.activeShapeType == rhs.activeShapeType,
              lhs.shapeColor.cgColor == rhs.shapeColor.cgColor,
              lhs.shapeWidth == rhs.shapeWidth
        else { return false }

        // Effects
        guard lhs.activeFX == rhs.activeFX,
              lhs.fxColor.cgColor == rhs.fxColor.cgColor,
              lhs.isMagicModeActive == rhs.isMagicModeActive,
              lhs.isStudyModeActive == rhs.isStudyModeActive,
              lhs.activeAmbientScene == rhs.activeAmbientScene,
              lhs.isAmbientSoundEnabled == rhs.isAmbientSoundEnabled
        else { return false }

        // Object layers
        guard lhs.shapes == rhs.shapes,
              lhs.attachments == rhs.attachments,
              lhs.attachmentNoteID == rhs.attachmentNoteID,
              lhs.widgets == rhs.widgets,
              lhs.stickers == rhs.stickers,
              lhs.textObjects == rhs.textObjects,
              lhs.isTextToolActive == rhs.isTextToolActive
        else { return false }

        // PDF background
        guard lhs.pdfURL == rhs.pdfURL
        else { return false }

        // Canvas mode
        guard lhs.isInfiniteCanvas == rhs.isInfiniteCanvas
        else { return false }

        return true
    }
}

// MARK: - Derived Configurations

extension CanvasPageConfiguration {

    /// Returns a copy with the `initialZoomScale` replaced.
    ///
    /// Used by the carousel to inject per-page zoom state without
    /// rebuilding the entire configuration.
    func withInitialZoomScale(_ scale: CGFloat?) -> CanvasPageConfiguration {
        CanvasPageConfiguration(
            noteID: noteID,
            pageIndex: pageIndex,
            drawingData: drawingData,
            currentTool: currentTool,
            drawingPolicy: drawingPolicy,
            backgroundColor: backgroundColor,
            defaultInkColor: defaultInkColor,
            pageType: pageType,
            paperMaterial: paperMaterial,
            isShapeToolActive: isShapeToolActive,
            activeShapeType: activeShapeType,
            shapeColor: shapeColor,
            shapeWidth: shapeWidth,
            activeFX: activeFX,
            fxColor: fxColor,
            isMagicModeActive: isMagicModeActive,
            isStudyModeActive: isStudyModeActive,
            activeAmbientScene: activeAmbientScene,
            isAmbientSoundEnabled: isAmbientSoundEnabled,
            shapes: shapes,
            attachments: attachments,
            attachmentNoteID: attachmentNoteID,
            widgets: widgets,
            stickers: stickers,
            textObjects: textObjects,
            isTextToolActive: isTextToolActive,
            pdfURL: pdfURL,
            pageCount: pageCount,
            isNewPage: isNewPage,
            zoomResetTrigger: zoomResetTrigger,
            initialZoomScale: scale,
            isInfiniteCanvas: isInfiniteCanvas
        )
    }
}

// MARK: - Factory from Note

extension CanvasPageConfiguration {

    /// Creates a configuration for the given page of a note.
    ///
    /// This factory centralises the scattered parameter assembly that was
    /// previously duplicated across `NoteEditorView.canvasSection` and
    /// `NotePageCarouselView.pageView(for:)`.
    ///
    /// - Parameters:
    ///   - note: The note model.
    ///   - pageIndex: Zero-based page index.
    ///   - toolStore: Current drawing tool state.
    ///   - inkStore: Current ink effect state.
    ///   - backgroundColor: Pre-computed canvas background colour.
    ///   - defaultInkColor: Contrasting ink colour from the theme.
    ///   - drawingPolicy: Finger vs. pencil drawing mode.
    ///   - paperMaterial: Resolved paper material for this note.
    ///   - pageTypeForIndex: Closure that resolves the page ruling per page.
    ///   - pdfURL: Optional backing PDF URL.
    ///   - zoomResetTrigger: Current zoom-reset trigger value.
    ///   - isNewPage: Whether this page was just created.
    ///   - initialZoomScale: Previously recorded zoom scale for this page.
    // swiftlint:disable:next function_parameter_count
    @MainActor static func page(
        for note: Note,
        at pageIndex: Int,
        toolStore: DrawingToolStore,
        inkStore: InkEffectStore,
        backgroundColor: UIColor,
        defaultInkColor: UIColor,
        drawingPolicy: PKCanvasViewDrawingPolicy,
        paperMaterial: PaperMaterial,
        pageTypeForIndex: (Int) -> PageType,
        pdfURL: URL?,
        zoomResetTrigger: Bool,
        isNewPage: Bool,
        initialZoomScale: CGFloat?,
        isInfiniteCanvas: Bool = false
    ) -> CanvasPageConfiguration {
        CanvasPageConfiguration(
            noteID: note.id,
            pageIndex: pageIndex,
            drawingData: pageIndex < note.pages.count ? note.pages[pageIndex] : Data(),
            currentTool: toolStore.pkTool,
            drawingPolicy: drawingPolicy,
            backgroundColor: backgroundColor,
            defaultInkColor: defaultInkColor,
            pageType: pageTypeForIndex(pageIndex),
            paperMaterial: paperMaterial,
            isShapeToolActive: toolStore.activeTool == .shape,
            activeShapeType: toolStore.activeShapeType,
            shapeColor: toolStore.activeColor,
            shapeWidth: toolStore.activeWidth,
            activeFX: inkStore.resolvedFX,
            fxColor: toolStore.activeColor,
            isMagicModeActive: toolStore.isMagicModeActive,
            isStudyModeActive: toolStore.isStudyModeActive,
            activeAmbientScene: toolStore.activeAmbientScene,
            isAmbientSoundEnabled: toolStore.isAmbientSoundEnabled,
            shapes: note.shapes(forPage: pageIndex),
            attachments: note.attachments(forPage: pageIndex),
            attachmentNoteID: note.id,
            widgets: note.widgets(forPage: pageIndex),
            stickers: note.stickers(forPage: pageIndex),
            textObjects: note.textObjects(forPage: pageIndex),
            isTextToolActive: toolStore.activeTool == .text,
            pdfURL: pdfURL,
            pageCount: note.pageCount,
            isNewPage: isNewPage,
            zoomResetTrigger: zoomResetTrigger,
            initialZoomScale: initialZoomScale,
            isInfiniteCanvas: isInfiniteCanvas
        )
    }
}
