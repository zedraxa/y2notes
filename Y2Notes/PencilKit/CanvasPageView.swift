// swiftlint:disable file_length type_body_length
import SwiftUI
import PencilKit
import PDFKit
import OSLog
import UniformTypeIdentifiers

private let canvasPageLogger = Logger(subsystem: "com.y2notes.app", category: "canvasPage")
private let canvasPageSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "canvasPage.perf")

struct CanvasPageView: UIViewRepresentable {
    let noteID: UUID
    let drawingData: Data
    let backgroundColor: UIColor
    let defaultInkColor: UIColor
    let currentTool: PKTool
    let isShapeToolActive: Bool
    let activeShapeType: ShapeType
    let shapeColor: UIColor
    let shapeWidth: Double
    /// Controls whether finger touches draw or pan/zoom the canvas.
    let drawingPolicy: PKCanvasViewDrawingPolicy
    /// Flip this value to trigger an animated reset to 1× zoom scale.
    let zoomResetTrigger: Bool
    /// Page ruling style rendered behind the canvas.
    let pageType: PageType
    /// Active writing FX type from the ink-effects system (`.none` = no FX).
    let activeFX: WritingFXType
    /// Ink colour resolved for the active FX preset.
    let fxColor: UIColor
    /// Zero-based page index within the multi-page note.
    let pageIndex: Int
    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void
    /// Called after each stroke with updated (canUndo, canRedo) from the canvas undo manager.
    let onUndoStateChanged: ((Bool, Bool) -> Void)?

    /// Called when the user performs a strong pinch-out gesture to return to the page overview.
    var onPinchToOverview: (() -> Void)?
    /// On-disk URL of the note's backing PDF, if available.
    /// When non-nil the canvas renders the PDF page as background instead of the
    /// procedural `PageBackgroundView`, giving the note a book-like appearance.
    let pdfURL: URL?
    /// Reference to the toolbar store, used to drive auto-fade during drawing.
    var toolStoreForFade: DrawingToolStore?

    /// Shape objects for the current page.
    var currentPageShapes: [ShapeInstance] = []
    /// Callback to persist shape changes.
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    /// Attachment objects for the current page.
    var currentPageAttachments: [AttachmentObject] = []
    /// Note ID used for attachment file lookups.
    var attachmentNoteID: UUID = UUID()
    /// Callback to persist attachment changes.
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    /// Callback when attachment selection changes.
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    /// Widget instances for the current page.
    var currentPageWidgets: [NoteWidget] = []
    /// Callback to persist widget changes.
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    /// Callback when widget selection changes.
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    /// Sticker instances for the current page.
    var currentPageStickers: [StickerInstance] = []
    /// Callback to persist sticker changes.
    var onStickersChanged: (([StickerInstance]) -> Void)?
    /// Callback when sticker selection changes.
    var onStickerSelectionChanged: ((UUID?) -> Void)?
    /// Image provider for rendering sticker assets.
    var stickerImageProvider: ((String) -> UIImage?)?

    /// Whether the text tool is active (text canvas overlay intercepts touches).
    var isTextToolActive: Bool = false
    /// Text objects for the current page.
    var currentPageTextObjects: [TextObject] = []
    /// Callback to persist text object changes.
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    /// Callback when text object selection changes.
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    /// Called when the user taps an empty area while the text tool is active.
    var onPlaceTextObject: ((CGPoint) -> Void)?

    /// Total number of pages in the note, used for adaptive effects complexity signals.
    var pageCount: Int = 1

    /// Whether Magic Mode is active (writing particles, keyword glow, highlight).
    var isMagicModeActive: Bool = false
    /// Whether Study Mode is active (heading glow, checklist pulse, timer pulse).
    var isStudyModeActive: Bool = false
    /// The currently active ambient environment scene, or `nil` when inactive.
    var activeAmbientScene: AmbientScene?
    /// Whether ambient soundscapes are enabled.
    var isAmbientSoundEnabled: Bool = true

    /// When `true`, `makeUIView` plays a paper-settle reveal animation on the
    /// container layer to celebrate the addition of a brand-new blank page.
    var isNewPage: Bool = false

    /// Called when the scroll view's zoom scale changes.
    var onZoomChanged: ((CGFloat) -> Void)?

    /// Initial zoom scale to restore when the page becomes visible. If `nil`,
    /// the page uses fit-to-width zoom. This allows the carousel to persist
    /// zoom state per-page across page switches.
    var initialZoomScale: CGFloat?

    // MARK: - Page dimensions

    /// Canonical page size, forwarded from `CanvasConstants` for call-site
    /// compatibility (e.g. `CanvasPageView.pageSize`).
    static var pageSize: CGSize { CanvasConstants.pageSize }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSaveRequested: onSaveRequested,
            onPinchToOverview: onPinchToOverview
        )
    }

    // swiftlint:disable:next function_body_length
    func makeUIView(context: Context) -> UIView {
        let setupState = canvasPageSignposter.beginInterval("CanvasSetup")
        canvasPageLogger.debug("[\(noteID, privacy: .public)] canvas setup - begin")

        let container = UIView()
        container.backgroundColor = CanvasConstants.deskSurfaceColor

        // ── Page background (ruling + paper tint, sits behind the canvas) ──────
        let ps = CanvasConstants.pageSize
        let pageBackground = PageBackgroundView(frame: CGRect(origin: .zero, size: ps))
        pageBackground.pageColor    = backgroundColor
        pageBackground.pageType     = pageType
        pageBackground.lineColor    = CanvasConstants.rulingLineColor(for: backgroundColor)
        pageBackground.isUserInteractionEnabled = false

        // Give the page a soft drop-shadow so it looks like a physical sheet
        // resting on the desk surface.
        pageBackground.layer.shadowColor = UIColor.black.cgColor
        pageBackground.layer.shadowOpacity = 0.18
        pageBackground.layer.shadowRadius = 12
        pageBackground.layer.shadowOffset = CGSize(width: 0, height: 3)
        pageBackground.layer.shadowPath =
            UIBezierPath(rect: CGRect(origin: .zero, size: ps)).cgPath

        container.addSubview(pageBackground)
        context.coordinator.pageBackground = pageBackground

        // ── PDF page background (book-like feel) ─────────────────────────────
        if let pdfURL,
           let pdfDoc = PDFDocument(url: pdfURL),
           let pdfPage = pdfDoc.page(at: pageIndex) {
            let mediaBox = pdfPage.bounds(for: .mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: ps, format: format)
            let pageImage = renderer.image { ctx in
                let cgCtx = ctx.cgContext
                cgCtx.setFillColor(backgroundColor.cgColor)
                cgCtx.fill(CGRect(origin: .zero, size: ps))
                let sx = ps.width / mediaBox.width
                let sy = ps.height / mediaBox.height
                let scale = min(sx, sy)
                cgCtx.saveGState()
                cgCtx.scaleBy(x: scale, y: -scale)
                cgCtx.translateBy(x: 0, y: -mediaBox.height)
                pdfPage.draw(with: .mediaBox, to: cgCtx)
                cgCtx.restoreGState()
            }
            let pdfImageView = UIImageView(image: pageImage)
            pdfImageView.frame = CGRect(origin: .zero, size: ps)
            pdfImageView.contentMode = .scaleToFill
            pdfImageView.isUserInteractionEnabled = false
            container.addSubview(pdfImageView)
            context.coordinator.pdfBackgroundView = pdfImageView
        }

        // ── PencilKit canvas ─────────────────────────────────────────────────
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = drawingPolicy
        canvas.alwaysBounceVertical   = true
        canvas.alwaysBounceHorizontal = true
        canvas.backgroundColor = .clear
        canvas.tool = currentTool

        if WritingConfig.useTouchTypeFiltering && drawingPolicy == .pencilOnly {
            canvas.drawingGestureRecognizer.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
        }

        // Paginated: 0.25× minimum lets users step back for a full-page view.
        // 5× maximum provides fine-detail writing precision.
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.bouncesZoom = true
        canvas.decelerationRate = .fast

        canvas.contentSize = ps

        if !drawingData.isEmpty, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }

        container.addSubview(canvas)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.canvas = canvas
        canvas.isUserInteractionEnabled = !isShapeToolActive

        context.coordinator.observeCanvasScroll(canvas)

        // ── Shape overlay ────────────────────────────────────────────────────
        let overlay = ShapeOverlayView(
            shapeType: activeShapeType,
            strokeColor: shapeColor,
            strokeWidth: CGFloat(shapeWidth)
        ) { stroke in
            canvas.drawing = PKDrawing(strokes: Array(canvas.drawing.strokes) + [stroke])
        }
        overlay.isHidden = !isShapeToolActive

        container.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.shapeOverlay = overlay

        // ── Shared overlays via builder ──────────────────────────────────────
        CanvasViewBuilder.buildOverlays(
            in: container,
            canvas: canvas,
            coordinator: context.coordinator,
            currentPageShapes: currentPageShapes,
            isShapeToolActive: isShapeToolActive,
            currentPageAttachments: currentPageAttachments,
            attachmentNoteID: attachmentNoteID,
            onAttachmentsChanged: onAttachmentsChanged,
            onAttachmentSelectionChanged: onAttachmentSelectionChanged,
            currentPageWidgets: currentPageWidgets,
            onWidgetsChanged: onWidgetsChanged,
            onWidgetSelectionChanged: onWidgetSelectionChanged,
            currentPageStickers: currentPageStickers,
            onStickersChanged: onStickersChanged,
            onStickerSelectionChanged: onStickerSelectionChanged,
            stickerImageProvider: stickerImageProvider,
            isTextToolActive: isTextToolActive,
            currentPageTextObjects: currentPageTextObjects,
            onTextObjectsChanged: onTextObjectsChanged,
            onTextObjectSelectionChanged: onTextObjectSelectionChanged,
            onPlaceTextObject: onPlaceTextObject,
            onShapesChanged: onShapesChanged,
            activeFX: activeFX,
            fxColor: fxColor,
            toolStoreForFade: toolStoreForFade
        )

        // Pinch-in opens page overview.
        let pinchOverview = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinchToOverview(_:))
        )
        pinchOverview.delegate = context.coordinator
        container.addGestureRecognizer(pinchOverview)
        context.coordinator.pinchOverviewGesture = pinchOverview

        // Seed coordinator state so the first updateUIView call does not misfire.
        context.coordinator.onUndoStateChanged = onUndoStateChanged
        context.coordinator.lastZoomResetTrigger = zoomResetTrigger

        // Become first responder so Apple Pencil is ready immediately.
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            let canvasW = canvas.bounds.width
            if canvasW > 0 {
                let targetZoom: CGFloat
                if let saved = self.initialZoomScale {
                    targetZoom = saved
                } else {
                    targetZoom = canvasW / CanvasConstants.pageSize.width
                }
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, targetZoom))
                canvas.setZoomScale(clamped, animated: false)
            }
            canvasPageSignposter.endInterval("CanvasSetup", setupState)
            canvasPageLogger.debug("[\(noteID, privacy: .public)] canvas setup - complete")
        }

        // Play a paper-settle reveal when this canvas represents a newly added page.
        if isNewPage {
            PageTransitionEngine.playNewPageReveal(on: container.layer)
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        context.coordinator.toolStoreRef = toolStoreForFade

        syncPageBackground(context.coordinator, canvas: canvas)
        syncDrawingPolicy(context.coordinator, canvas: canvas)
        syncActiveTool(context.coordinator, canvas: canvas)
        canvas.isUserInteractionEnabled = !isShapeToolActive

        // Sync overlays via shared helper.
        CanvasViewBuilder.syncOverlayCanvases(
            coordinator: context.coordinator,
            canvas: canvas,
            isShapeToolActive: isShapeToolActive,
            activeShapeType: activeShapeType,
            shapeColor: shapeColor,
            shapeWidth: shapeWidth,
            currentPageShapes: currentPageShapes,
            currentPageAttachments: currentPageAttachments,
            attachmentNoteID: attachmentNoteID,
            currentPageWidgets: currentPageWidgets,
            currentPageStickers: currentPageStickers,
            stickerImageProvider: stickerImageProvider,
            isTextToolActive: isTextToolActive,
            currentPageTextObjects: currentPageTextObjects,
            toolStore: toolStoreForFade,
            onAttachmentsChanged: onAttachmentsChanged,
            onAttachmentSelectionChanged: onAttachmentSelectionChanged,
            onWidgetsChanged: onWidgetsChanged,
            onWidgetSelectionChanged: onWidgetSelectionChanged,
            onStickersChanged: onStickersChanged,
            onStickerSelectionChanged: onStickerSelectionChanged,
            onTextObjectsChanged: onTextObjectsChanged,
            onTextObjectSelectionChanged: onTextObjectSelectionChanged,
            onPlaceTextObject: onPlaceTextObject,
            onShapesChanged: onShapesChanged
        )

        // Zoom reset: animate to fit-to-width when the trigger value flips.
        // "Fit to width" is more useful than a fixed 1× scale because it adapts
        // to the current screen size and orientation.
        if context.coordinator.lastZoomResetTrigger != zoomResetTrigger {
            context.coordinator.lastZoomResetTrigger = zoomResetTrigger
            // Dispatch to avoid mutating scroll state mid-layout-pass.
            DispatchQueue.main.async {
                let canvasW = canvas.bounds.width
                let fitZoom = canvasW > 0 ? canvasW / CanvasConstants.pageSize.width : 1.0
                let clamped = max(canvas.minimumZoomScale,
                                  min(canvas.maximumZoomScale, fitZoom))
                canvas.setZoomScale(clamped, animated: true)
                canvasPageLogger.debug("[\(noteID, privacy: .public)] zoom reset to fit-width (\(clamped, format: .fixed(precision: 2))×)")
            }
        }

        // Keep the undo state callback current (closures capture SwiftUI state by value).
        context.coordinator.onUndoStateChanged = onUndoStateChanged

        // Sync effects via shared helper.
        CanvasViewBuilder.syncEffects(
            coordinator: context.coordinator,
            layer: uiView.layer,
            bounds: uiView.bounds,
            pageIndex: pageIndex,
            pageCount: pageCount,
            isMagicModeActive: isMagicModeActive,
            isStudyModeActive: isStudyModeActive,
            activeAmbientScene: activeAmbientScene,
            isAmbientSoundEnabled: isAmbientSoundEnabled,
            activeFX: activeFX,
            fxColor: fxColor,
            toolStore: toolStoreForFade
        )

        // Keep the zoom-changed callback current.
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onPinchToOverview = onPinchToOverview
    }

    // MARK: - updateUIView helpers

    private func syncPageBackground(_ coordinator: Coordinator, canvas: PKCanvasView) {
        guard let bg = coordinator.pageBackground else { return }
        if bg.pageColor != backgroundColor {
            bg.pageColor = backgroundColor
            bg.lineColor = CanvasConstants.rulingLineColor(for: backgroundColor)
        }
        if bg.pageType != pageType {
            bg.pageType = pageType
        }
        coordinator.syncBackgroundWithCanvas(canvas)
    }

    private func syncDrawingPolicy(_ coordinator: Coordinator, canvas: PKCanvasView) {
        guard canvas.drawingPolicy != drawingPolicy else { return }
        canvas.drawingPolicy = drawingPolicy
        // Update touch type filtering to match: pencilOnly → restrict to pencil
        // touches for faster first-touch discrimination, anyInput → allow all.
        if WritingConfig.useTouchTypeFiltering {
            if drawingPolicy == .pencilOnly {
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
        // Reset palm guard when switching modes.
        coordinator.palmGuard.reset()
    }

    private func syncActiveTool(_ coordinator: Coordinator, canvas: PKCanvasView) {
        // Update the active tool from DrawingToolStore — but ONLY when:
        // 1. The user is not mid-stroke (setting tool mid-stroke kills PencilKit's
        //    internal pressure/tilt pipeline, destroying pressure sensitivity).
        // 2. The tool actually changed. We compare a lightweight snapshot of the
        //    tool's identity (type + ink type + color + width) to avoid redundant
        //    assignments that would reset PencilKit's state.
        guard !coordinator.isDrawing else { return }
        let snapshot = ToolSnapshot(currentTool)
        guard coordinator.lastToolSnapshot != snapshot else { return }
        canvas.tool = currentTool
        coordinator.lastToolSnapshot = snapshot

        // ── Interaction feedback for tool switch (AGENT-23) ─────
        if currentTool is PKEraserTool {
            coordinator.interactionFeedback.play(.eraserEngage, on: canvas.layer)
        } else {
            coordinator.interactionFeedback.play(.toolSwitch, on: canvas.layer)
            coordinator.microInteractionEngine.playToolSwitchMorph(on: canvas.layer)
        }
    }

    // MARK: - Forwarding helpers

    /// Forwarded from `CanvasConstants` for call-site compatibility
    /// (used by `CanvasCoordinator+DiffUpdate`).
    static func rulingLineColor(for background: UIColor) -> UIColor {
        CanvasConstants.rulingLineColor(for: background)
    }

    // MARK: - Coordinator

    /// Editor-mode coordinator.
    ///
    /// Inherits all shared drawing lifecycle, object-layer handling, effects,
    /// Apple Pencil support, undo/redo, and background sync from
    /// `CanvasCoordinatorBase`.  The `CanvasPageDiff`-driven `applyDiff`
    /// update path lives in `CanvasCoordinator+DiffUpdate.swift`.
    final class Coordinator: CanvasCoordinatorBase {

        /// Callback forwarded from `CanvasPageView`.
        var onCanvasUndoManagerAvailable: ((UndoManager?) -> Void)?

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void,
            onPinchToOverview: (() -> Void)? = nil
        ) {
            super.init(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
            self.onPinchToOverview = onPinchToOverview
        }
    }
}
