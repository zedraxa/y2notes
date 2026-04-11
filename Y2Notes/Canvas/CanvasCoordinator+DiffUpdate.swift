import UIKit
import PencilKit
import OSLog

private let diffLogger = Logger(subsystem: "com.y2notes.app", category: "canvasPage.diff")

// MARK: - CanvasPageView.Coordinator + Diff-Based Update

/// Adds a `applyDiff(_:from:)` method to the coordinator that uses
/// `CanvasPageDiff` to perform only the UIKit mutations that actually changed.
///
/// ## Motivation
/// The monolithic `updateUIView` in `CanvasPageView` performs ~30 property
/// comparisons on every SwiftUI render, even when only one property changed.
/// This extension provides a structured alternative where each concern is
/// guarded by a single bitfield test.
///
/// ## Usage
/// Callers build a `CanvasPageDiff` from two configurations, then call:
/// ```swift
/// coordinator.applyDiff(diff, from: newConfig)
/// ```
/// Only the changed aspects are synced to UIKit, reducing unnecessary work.
extension CanvasPageView.Coordinator {

    /// Applies the changes described by `diff` to the coordinator's managed
    /// UIKit views.
    ///
    /// This is the structured replacement for the flat sequence of `if` blocks
    /// in `updateUIView`. Each sync block corresponds to one or more diff flags
    /// and is skipped entirely if the relevant flag is absent.
    ///
    /// - Parameters:
    ///   - diff: The set of changed aspects between the old and new configuration.
    ///   - config: The new (incoming) configuration to sync UIKit state to.
    ///   - container: The container view hosting the canvas and overlays.
    func applyDiff(
        _ diff: CanvasPageDiff,
        from config: CanvasPageConfiguration,
        container: UIView
    ) {
        guard let canvas = canvas else { return }

        // ── Appearance ─────────────────────────────────────────────────────
        if !diff.isDisjoint(with: .appearance) {
            syncAppearance(config, canvas: canvas)
        }

        // ── Drawing policy ─────────────────────────────────────────────────
        if diff.contains(.drawingPolicy) {
            syncDrawingPolicy(config, canvas: canvas)
        }

        // ── Tool ───────────────────────────────────────────────────────────
        if diff.contains(.tool) {
            syncTool(config, canvas: canvas)
        }

        // ── Shape tool ─────────────────────────────────────────────────────
        if diff.contains(.shapeTool) {
            syncShapeTool(config, canvas: canvas)
        }

        // ── Shape objects ──────────────────────────────────────────────────
        if diff.contains(.shapes) {
            syncShapeObjects(config)
        }

        // ── Attachment objects ──────────────────────────────────────────────
        if diff.contains(.attachments) {
            syncAttachmentObjects(config, canvas: canvas)
        }

        // ── Widget objects ─────────────────────────────────────────────────
        if diff.contains(.widgets) {
            syncWidgetObjects(config)
        }

        // ── Text objects ───────────────────────────────────────────────────
        if diff.contains(.textObjects) || diff.contains(.textToolActive) {
            syncTextObjects(config)
        }

        // ── Zoom reset ─────────────────────────────────────────────────────
        if diff.contains(.zoomReset) {
            syncZoomReset(config, canvas: canvas)
        }

        // ── Effects ────────────────────────────────────────────────────────
        if diff.contains(.inkEffect) {
            syncInkEffect(config, container: container)
        }
        if diff.contains(.magicMode) {
            effects.setMagicMode(active: config.isMagicModeActive, on: container.layer)
        }
        if diff.contains(.studyMode) {
            effects.setStudyMode(active: config.isStudyModeActive, on: container.layer)
        }
        if !diff.isDisjoint(with: [.ambientScene, .ambientSound]) {
            syncAmbient(config, container: container)
        }

        // ── Page context ───────────────────────────────────────────────────
        if diff.contains(.pageCount) {
            coordinatorPageCount = config.pageCount
            adaptiveEffectsEngine.pageCount = config.pageCount
        }

        diffLogger.trace("Applied diff: \(diff.rawValue, format: .hex)")
    }

    // MARK: - Sync Helpers

    private func syncAppearance(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        if let bg = pageBackground {
            if bg.pageColor != config.backgroundColor {
                bg.pageColor = config.backgroundColor
                bg.lineColor = CanvasConstants.rulingLineColor(for: config.backgroundColor)
            }
            if bg.pageType != config.pageType {
                bg.pageType = config.pageType
            }
            syncBackgroundWithCanvas(canvas)
        }
    }

    private func syncDrawingPolicy(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        canvas.drawingPolicy = config.drawingPolicy
        if WritingConfig.useTouchTypeFiltering {
            if config.drawingPolicy == .pencilOnly {
                canvas.drawingGestureRecognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]
            } else {
                canvas.drawingGestureRecognizer.allowedTouchTypes = [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue),
                ]
            }
        }
        palmGuard.reset()
    }

    private func syncTool(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        guard !isDrawing else { return }
        let snapshot = ToolSnapshot(config.currentTool)
        if lastToolSnapshot != snapshot {
            canvas.tool = config.currentTool
            lastToolSnapshot = snapshot
            if config.currentTool is PKEraserTool {
                interactionFeedback.play(.eraserEngage, on: canvas.layer)
            } else {
                interactionFeedback.play(.toolSwitch, on: canvas.layer)
                microInteractionEngine.playToolSwitchMorph(on: canvas.layer)
            }
        }
        canvas.isUserInteractionEnabled = !config.isShapeToolActive
    }

    private func syncShapeTool(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        if let overlay = shapeOverlay {
            overlay.isHidden    = !config.isShapeToolActive
            overlay.shapeType   = config.activeShapeType
            overlay.strokeColor = config.shapeColor
            overlay.strokeWidth = CGFloat(config.shapeWidth)
        }
        canvas.isUserInteractionEnabled = !config.isShapeToolActive
    }

    private func syncShapeObjects(_ config: CanvasPageConfiguration) {
        if let sc = shapeCanvas {
            sc.isShapeToolActive = config.isShapeToolActive
            sc.shapes = config.shapes
            sc.selectedShapeID = toolStoreRef?.activeShapeSelection
        }
    }

    private func syncAttachmentObjects(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        if let ac = attachmentCanvas {
            ac.attachments = config.attachments
            ac.noteID = config.attachmentNoteID
            ac.selectedAttachmentID = toolStoreRef?.activeAttachmentSelection
            ac.zoomScale = canvas.zoomScale
        }
    }

    private func syncWidgetObjects(_ config: CanvasPageConfiguration) {
        if let wc = widgetCanvas {
            wc.widgets = config.widgets
            wc.selectedWidgetID = toolStoreRef?.activeWidgetSelection
        }
    }

    private func syncTextObjects(_ config: CanvasPageConfiguration) {
        if let tc = textCanvas {
            tc.isTextToolActive = config.isTextToolActive
            tc.textObjects = config.textObjects
            tc.selectedTextObjectID = toolStoreRef?.activeTextObjectSelection
        }
    }

    private func syncZoomReset(
        _ config: CanvasPageConfiguration,
        canvas: PKCanvasView
    ) {
        lastZoomResetTrigger = config.zoomResetTrigger
        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            let canvasW = canvas.bounds.width
            let fitZoom = canvasW > 0 ? canvasW / CanvasConstants.pageSize.width : 1.0
            let clamped = max(canvas.minimumZoomScale,
                              min(canvas.maximumZoomScale, fitZoom))
            canvas.setZoomScale(clamped, animated: true)
        }
    }

    private func syncInkEffect(
        _ config: CanvasPageConfiguration,
        container: UIView
    ) {
        if let engine = effectEngine {
            engine.syncLayerFrames()
            engine.configure(fx: config.activeFX, color: config.fxColor)
        }
        writingPipeline.configure(
            config: toolStoreRef?.writingEffectConfig ?? .default,
            color: toolStoreRef?.activeColor ?? .black
        )
    }

    private func syncAmbient(
        _ config: CanvasPageConfiguration,
        container: UIView
    ) {
        ambientEngine.soundEnabled = config.isAmbientSoundEnabled
        if let ts = toolStoreRef {
            switch (config.activeAmbientScene, ambientEngine.activeScene) {
            case let (scene?, current) where current != scene:
                ambientEngine.activate(scene, on: container.layer, toolStore: ts)
            case (nil, .some):
                ambientEngine.deactivate(toolStore: ts)
            default:
                break
            }
        }
        if ambientEngine.activeScene != nil {
            ambientEngine.updateLayout(containerBounds: container.bounds)
        }
    }
}
