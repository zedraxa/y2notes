// swiftlint:disable file_length type_body_length
import UIKit
import PencilKit
import OSLog
import SwiftUI

private let baseLogger = Logger(subsystem: "com.y2notes.app", category: "canvas.coordinator")
private let baseSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "canvas.coordinator.perf")

// MARK: - CanvasCoordinatorBase

/// Shared base class for both `CanvasView.Coordinator` (reader mode) and
/// `CanvasPageView.Coordinator` (editor mode).
///
/// ## Motivation
/// Before this refactor the two coordinators duplicated ~70% of their code:
/// drawing lifecycle, object-layer handlers, effects wiring, Apple Pencil
/// support, undo/redo, background-sync, hold-to-straighten, scratch-to-delete,
/// and haptic feedback.  `CanvasCoordinatorBase` extracts all of that into a
/// single class that both coordinators inherit from.
///
/// ## Subclass Responsibilities
/// - `CanvasView.Coordinator`:  adds the two-finger page-swipe gesture.
/// - `CanvasPageView.Coordinator`: adds infinite-canvas dynamic expansion.
class CanvasCoordinatorBase: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - Drawing Callbacks

    let onDrawingChanged: (Data) -> Void
    let onSaveRequested: () -> Void

    // MARK: - Canvas References

    weak var canvas: PKCanvasView?
    weak var shapeOverlay: ShapeOverlayView?
    /// Page ruling / background view placed behind the canvas.
    weak var pageBackground: PageBackgroundView?
    /// PDF page image rendered behind the canvas (book-like feel).
    weak var pdfBackgroundView: UIImageView?
    /// Updated by updateUIView to always hold the freshest closure.
    var onUndoStateChanged: ((Bool, Bool) -> Void)?
    /// Tracks the last zoom-reset trigger seen so we only react to flips.
    var lastZoomResetTrigger: Bool = false
    /// Debounce timer for drawing saves.
    private var debounceTimer: Timer?
    /// Tracks the last drawing data that was propagated to the store.
    /// Prevents the feedback loop: stroke → onDrawingChanged → noteStore
    /// → SwiftUI re-eval → canvasViewDrawingDidChange → duplicate dispatch.
    var lastPropagatedDrawingData: Data?

    // MARK: - Apple Pencil Support

    var pencilCoordinator: PencilInteractionCoordinator?
    /// Passive gesture recognizer that feeds real-time pencil positions
    /// to the effects engines at the hardware's native touch rate.
    var nibTracker: PencilNibTrackerGestureRecognizer?
    var hoverOverlay: PencilHoverOverlayView?
    var eraserCursorOverlay: EraserCursorOverlay?
    /// Passive gesture recognizer that detects scratch-to-delete gestures.
    var scratchDeleteRecognizer: ScribbleDeleteRecognizer?
    weak var canvasRef: PKCanvasView?

    // MARK: - Effects

    /// Ink effect engine that renders fire/sparkle/glitch/ripple overlays.
    var effectEngine: InkEffectEngine?

    /// Central coordinator that owns and wires all effect sub-engines.
    let effects = EffectsCoordinator()

    // Convenience accessors forwarded to the coordinator.
    var pageTransitionEngine: PageTransitionEngine { effects.pageTransitionEngine }
    var adaptiveEffectsEngine: AdaptiveEffectsEngine { effects.adaptiveEngine }
    var writingPipeline: WritingEffectsPipeline    { effects.writingEffectsPipeline }
    var microInteractionEngine: MicroInteractionEngine { effects.microInteractionEngine }
    var snapAlignEffectEngine: SnapAlignEffectEngine { effects.snapAlignEffectEngine }
    var interactionFeedback: InteractionFeedbackEngine { effects.interactionFeedbackEngine }

    // MARK: - Object Layer Overlays

    /// Shape objects canvas for the current page.
    weak var shapeCanvas: ShapeCanvasView?
    private var shapeDebounceTimer: Timer?
    var onShapesChanged: (([ShapeInstance]) -> Void)?

    /// Attachment canvas overlay for the current page.
    weak var attachmentCanvas: AttachmentCanvasView?
    private var attachmentDebounceTimer: Timer?
    var onAttachmentsChanged: (([AttachmentObject]) -> Void)?
    var onAttachmentSelectionChanged: ((UUID?) -> Void)?

    /// Widget canvas overlay for the current page.
    weak var widgetCanvas: WidgetCanvasView?
    private var widgetDebounceTimer: Timer?
    var onWidgetsChanged: (([NoteWidget]) -> Void)?
    var onWidgetSelectionChanged: ((UUID?) -> Void)?

    /// Sticker canvas overlay for the current page.
    weak var stickerCanvas: StickerCanvasView?
    private var stickerDebounceTimer: Timer?
    var onStickersChanged: (([StickerInstance]) -> Void)?
    var onStickerSelectionChanged: ((UUID?) -> Void)?

    /// Text object canvas overlay for the current page.
    weak var textCanvas: TextCanvasView?
    private var textDebounceTimer: Timer?
    var onTextObjectsChanged: (([TextObject]) -> Void)?
    var onTextObjectSelectionChanged: ((UUID?) -> Void)?
    var onPlaceTextObject: ((CGPoint) -> Void)?
    var onTextObjectTransformed: ((TextObject) -> Void)?

    // MARK: - Toolbar & Drawing State

    /// Weak reference to the drawing tool store for toolbar auto-fade.
    weak var toolStoreRef: DrawingToolStore?

    /// Task that schedules the toolbar fade after a delay of active drawing.
    private var fadeTask: Task<Void, Never>?

    /// Pinch gesture recognizer for page overview.
    var pinchOverviewGesture: UIPinchGestureRecognizer?
    /// Pinch-to-overview callback.
    var onPinchToOverview: (() -> Void)?

    /// Minimum scale observed during the current pinch-to-overview gesture.
    private var pinchOverviewMinScale: CGFloat = 1.0
    /// Whether the pinch began near baseline zoom.
    private var pinchOverviewStartedNearBaseZoom = false

    /// Identity token for the currently bound page content.
    var boundPageToken: String?
    /// Signature of the currently rendered PDF background layer.
    var pdfBackgroundToken: String?

    /// Current zero-based page index, kept in sync by `updateUIView`.
    var coordinatorPageIndex: Int = 0
    /// Total page count, kept in sync by `updateUIView`.
    var coordinatorPageCount: Int = 1

    /// True while the user is actively drawing a stroke. Used to prevent
    /// `updateUIView` from overwriting `canvas.tool` mid-stroke, which
    /// would reset PencilKit's internal pressure/tilt pipeline.
    private(set) var isDrawing = false

    /// Tracks the last PKTool identity set on the canvas so updateUIView
    /// skips redundant assignments that would reset PencilKit's state.
    var lastToolSnapshot: ToolSnapshot?

    /// Stable base width captured from the tool when a fountain-pen stroke
    /// begins. Used for barrel-roll modulation so the feedback loop does
    /// not shift the reference width on every micro-movement.
    var barrelRollBaseWidth: CGFloat?

    /// The last active inking tool before switching to the eraser.
    private var previousInkingTool: PKTool?

    /// Zoom scale captured when a stroke begins.
    private var strokeStartZoomScale: CGFloat?

    /// Timer that re-enables zoom/scroll gestures after a short delay.
    private var postStrokeZoomUnlockTimer: Timer?

    /// Timer that fires when the user holds the pen still after drawing.
    private var holdToStraightenTimer: Timer?

    /// True while `straightenLastStroke` is replacing the canvas drawing.
    private var isStraightening = false

    /// Tracks Apple Pencil contact timing for palm rejection in `.anyInput` mode.
    let palmGuard = PalmGuardState()

    /// Tracks stroke count and data size for performance warnings.
    let strokeMonitor = StrokePerformanceMonitor()

    // KVO observers that keep the page background in sync with canvas
    // scroll offset and zoom scale.
    private var contentOffsetObservation: NSKeyValueObservation?
    private var zoomScaleObservation: NSKeyValueObservation?

    /// Tracks whether the last zoom update landed on a detent.
    private var wasOnZoomDetent: Bool = false

    // Pre-prepared haptic generator for double-tap pencil delete feedback.
    private let deletionImpactGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    /// Called when the scroll view's zoom scale changes.
    var onZoomChanged: ((CGFloat) -> Void)?

    // MARK: - Init / Deinit

    init(
        onDrawingChanged: @escaping (Data) -> Void,
        onSaveRequested: @escaping () -> Void
    ) {
        self.onDrawingChanged = onDrawingChanged
        self.onSaveRequested  = onSaveRequested
    }

    deinit {
        flushPendingSave()
        postStrokeZoomUnlockTimer?.invalidate()
        shapeDebounceTimer?.invalidate()
        attachmentDebounceTimer?.invalidate()
        widgetDebounceTimer?.invalidate()
        stickerDebounceTimer?.invalidate()
        textDebounceTimer?.invalidate()
        contentOffsetObservation?.invalidate()
        zoomScaleObservation?.invalidate()
    }

    // MARK: - Subclass Hooks

    /// Set by subclasses to skip `canvasViewDrawingDidChange` during
    /// programmatic drawing mutations (e.g. infinite-canvas expansion shift).
    var suppressDrawingChangeHandler = false

    /// Called after the standard `canvasViewDrawingDidChange` processing.
    /// Subclasses can override to add behaviour like infinite-canvas expansion.
    /// The default implementation does nothing.
    func didProcessDrawingChange(in canvasView: PKCanvasView, data: Data) {
        // No-op — overridden by CanvasPageView.Coordinator for infinite canvas.
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow the overview pinch to fire simultaneously with canvas zoom/pan.
        if gestureRecognizer === pinchOverviewGesture {
            guard let canvas else { return false }
            return otherGestureRecognizer === canvas.pinchGestureRecognizer
                || otherGestureRecognizer === canvas.panGestureRecognizer
        }
        return false
    }

    // MARK: - Pinch-to-Overview

    @objc func handlePinchToOverview(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchOverviewMinScale = gesture.scale
            pinchOverviewStartedNearBaseZoom =
                (canvas?.zoomScale ?? 1.0) <= PinchOverviewGestureTuning.maxStartZoomScale
        case .changed:
            pinchOverviewMinScale = min(pinchOverviewMinScale, gesture.scale)
        case .ended, .cancelled:
            if pinchOverviewStartedNearBaseZoom,
               pinchOverviewMinScale < PinchOverviewGestureTuning.triggerScale {
                onPinchToOverview?()
            }
            pinchOverviewMinScale = 1.0
            pinchOverviewStartedNearBaseZoom = false
        default:
            break
        }
    }

    // MARK: - Drawing Lifecycle

    /// Converts a PKDrawing content-space point to the viewport/overlay
    /// coordinate space so that ink-effect particles render at the correct
    /// on-screen position regardless of zoom/scroll state.
    func viewportPoint(from contentPoint: CGPoint, in canvasView: PKCanvasView) -> CGPoint {
        let z = canvasView.zoomScale
        let o = canvasView.contentOffset
        return CGPoint(
            x: contentPoint.x * z - o.x,
            y: contentPoint.y * z - o.y
        )
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = true
        postStrokeZoomUnlockTimer?.invalidate()
        postStrokeZoomUnlockTimer = nil
        holdToStraightenTimer?.invalidate()
        holdToStraightenTimer = nil

        if WritingConfig.lockZoomDuringWriting {
            strokeStartZoomScale = canvasView.zoomScale
            canvasView.pinchGestureRecognizer?.isEnabled = false
            canvasView.isScrollEnabled = false
        }

        if let inkTool = canvasView.tool as? PKInkingTool {
            barrelRollBaseWidth = inkTool.width
        }

        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(WritingConfig.toolbarFadeDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFadedOpacity
            }
        }
        attachmentCanvas?.renderingPaused = true
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = false
        holdToStraightenTimer?.invalidate()
        holdToStraightenTimer = nil

        if barrelRollBaseWidth != nil {
            lastToolSnapshot = nil
        }
        barrelRollBaseWidth = nil

        if WritingConfig.lockZoomDuringWriting {
            let savedZoom = strokeStartZoomScale
            postStrokeZoomUnlockTimer?.invalidate()
            postStrokeZoomUnlockTimer = Timer.scheduledTimer(
                withTimeInterval: WritingConfig.postStrokeZoomLockDelay,
                repeats: false
            ) { [weak self, weak canvasView] _ in
                guard let self, !self.isDrawing, let canvas = canvasView else { return }
                if let savedZoom, abs(canvas.zoomScale - savedZoom) > WritingConfig.zoomDriftTolerance {
                    canvas.setZoomScale(savedZoom, animated: true)
                }
                canvas.pinchGestureRecognizer?.isEnabled = true
                canvas.isScrollEnabled = true
            }
            strokeStartZoomScale = nil
        }

        palmGuard.pencilStrokeEnded()

        Task { @MainActor [weak self] in
            self?.adaptiveEffectsEngine.reportStrokePause()
        }

        // Dispatch stroke-ended through the effects coordinator.
        let fallbackPt = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
        if let lastStroke = canvasView.drawing.strokes.last {
            let path = lastStroke.path
            let endPt = path.last.map {
                viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
            } ?? fallbackPt
            let startPt = path.first.map {
                viewportPoint(from: CGPoint(x: $0.location.x, y: $0.location.y), in: canvasView)
            } ?? endPt
            let bbox = lastStroke.renderBounds
            let vpOrigin = viewportPoint(from: bbox.origin, in: canvasView)
            let vpMax = viewportPoint(from: CGPoint(x: bbox.maxX, y: bbox.maxY), in: canvasView)
            let headingBounds = CGRect(
                x: vpOrigin.x, y: vpOrigin.y,
                width: vpMax.x - vpOrigin.x, height: vpMax.y - vpOrigin.y
            )
            let strokeEndColor = (canvasView.tool as? PKInkingTool)?.color ?? .label
            effects.dispatch(
                .strokeEnded(at: endPt, start: startPt,
                             inkColor: strokeEndColor, headingBounds: headingBounds),
                inkEffectEngine: effectEngine
            )
        } else {
            effects.dispatch(
                .strokeEnded(at: fallbackPt, start: fallbackPt,
                             inkColor: .label, headingBounds: .zero),
                inkEffectEngine: effectEngine
            )
        }

        fadeTask?.cancel()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(WritingConfig.toolbarRestoreDelay))
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFullOpacity
            }
        }

        if canvasView.tool is PKLassoTool {
            markLassoSelectionActive()
        } else {
            updateSelectionState(for: canvasView)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            self?.attachmentCanvas?.renderingPaused = false
            self?.attachmentCanvas?.setNeedsDisplay()
        }
    }

    // MARK: - Selection State

    func updateSelectionState(for canvasView: PKCanvasView) {
        let isLasso = canvasView.tool is PKLassoTool
        if !isLasso && toolStoreRef?.hasActiveSelection == true {
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = false
                }
            }
        }
    }

    func markLassoSelectionActive() {
        guard toolStoreRef?.hasActiveSelection != true else { return }
        Task { @MainActor [weak self] in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self?.toolStoreRef?.hasActiveSelection = true
            }
        }
    }

    func clearSelectionState() {
        guard toolStoreRef?.hasActiveSelection != false else { return }
        Task { @MainActor [weak self] in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self?.toolStoreRef?.hasActiveSelection = false
            }
        }
    }

    // MARK: - Shape Object Handlers

    func handleShapesChanged(_ shapes: [ShapeInstance]) {
        shapeDebounceTimer?.invalidate()
        shapeDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: ShapeConstants.saveDebounce,
            repeats: false
        ) { [weak self] _ in
            self?.onShapesChanged?(shapes)
        }
    }

    func handleShapeSelectionChanged(_ shapeID: UUID?) {
        Task { @MainActor [weak self] in
            self?.toolStoreRef?.activeShapeSelection = shapeID
        }
    }

    // MARK: - Attachment Coordination

    func handleAttachmentTransformed(_ attachment: AttachmentObject) {
        guard var attachments = attachmentCanvas?.attachments else { return }
        if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
            attachments[idx] = attachment
        }
        handleAttachmentsChanged(attachments)
    }

    func handleAttachmentsChanged(_ attachments: [AttachmentObject]) {
        attachmentDebounceTimer?.invalidate()
        attachmentDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: AttachmentConstants.saveDebounce,
            repeats: false
        ) { [weak self] _ in
            self?.onAttachmentsChanged?(attachments)
        }
    }

    // MARK: - Widget Coordinator

    func handleWidgetTransformed(_ widget: NoteWidget) {
        guard var widgets = widgetCanvas?.widgets else { return }
        if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
            widgets[idx] = widget
        }
        handleWidgetsChanged(widgets)
    }

    func handleWidgetsChanged(_ widgets: [NoteWidget]) {
        widgetDebounceTimer?.invalidate()
        widgetDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: WidgetConstants.saveDebounce,
            repeats: false
        ) { [weak self] _ in
            self?.onWidgetsChanged?(widgets)
        }
    }

    // MARK: - Sticker Coordinator

    func handleStickerTransformed(_ sticker: StickerInstance) {
        guard let stickerCanvas = stickerCanvas else { return }
        if let idx = stickerCanvas.stickers.firstIndex(where: { $0.id == sticker.id }) {
            stickerCanvas.stickers[idx] = sticker
        }
        handleStickersChanged(stickerCanvas.stickers)
    }

    func handleStickerDeleted(_ stickerID: UUID) {
        guard let stickerCanvas = stickerCanvas else { return }
        stickerCanvas.stickers.removeAll(where: { $0.id == stickerID })
        handleStickersChanged(stickerCanvas.stickers)
    }

    func handleStickerSelectionChanged(_ stickerID: UUID?) {
        onStickerSelectionChanged?(stickerID)
    }

    func handleStickersChanged(_ stickers: [StickerInstance]) {
        stickerDebounceTimer?.invalidate()
        stickerDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: StickerConstants.saveDebounce,
            repeats: false
        ) { [weak self] _ in
            self?.onStickersChanged?(stickers)
        }
    }

    // MARK: - Text Object Coordinator

    func handleTextObjectTransformed(_ textObject: TextObject) {
        guard var textObjects = textCanvas?.textObjects else { return }
        if let idx = textObjects.firstIndex(where: { $0.id == textObject.id }) {
            textObjects[idx] = textObject
        }
        handleTextObjectsChanged(textObjects)
    }

    func handleTextObjectsChanged(_ textObjects: [TextObject]) {
        textDebounceTimer?.invalidate()
        textDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: TextObjectConstants.saveDebounce,
            repeats: false
        ) { [weak self] _ in
            self?.onTextObjectsChanged?(textObjects)
        }
    }

    // MARK: - Double-Tap Pencil Delete

    func deleteLastStroke() {
        guard let canvas = canvasRef else { return }
        let strokes = Array(canvas.drawing.strokes)
        guard !strokes.isEmpty else { return }

        let oldDrawing = canvas.drawing
        let newDrawing = PKDrawing(strokes: Array(strokes.dropLast()))

        canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
            cv.drawing = oldDrawing
        }
        canvas.undoManager?.setActionName(
            NSLocalizedString("Delete Stroke", comment: "Undo action name for pencil double-tap delete")
        )

        canvas.drawing = newDrawing

        deletionImpactGenerator.impactOccurred()
        deletionImpactGenerator.prepare()
    }

    // MARK: - Scratch-to-Delete

    func deleteScratchStrokes(in viewportRect: CGRect) {
        guard let canvas = canvasRef else { return }

        let contentRect = self.contentRect(from: viewportRect, in: canvas)
        let hitRect = contentRect.insetBy(dx: -10, dy: -10)

        let allStrokes = Array(canvas.drawing.strokes)
        let remaining = allStrokes.filter { !$0.renderBounds.intersects(hitRect) }

        guard remaining.count < allStrokes.count else { return }

        let oldDrawing = canvas.drawing
        let newDrawing = PKDrawing(strokes: remaining)

        canvas.undoManager?.registerUndo(withTarget: canvas) { cv in
            cv.drawing = oldDrawing
        }
        canvas.undoManager?.setActionName(
            NSLocalizedString("Editor.ScratchDelete.UndoAction",
                              comment: "Undo action name for scribble-to-delete")
        )

        canvas.drawing = newDrawing

        let deletedCount = allStrokes.count - remaining.count
        deletionImpactGenerator.impactOccurred()
        if deletedCount > 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.deletionImpactGenerator.impactOccurred()
            }
        }
        deletionImpactGenerator.prepare()
    }

    /// Converts a viewport rectangle to content-space coordinates.
    func contentRect(from viewportRect: CGRect, in canvasView: PKCanvasView) -> CGRect {
        let z = canvasView.zoomScale
        let o = canvasView.contentOffset
        let origin = CGPoint(
            x: (viewportRect.minX + o.x) / z,
            y: (viewportRect.minY + o.y) / z
        )
        let size = CGSize(
            width: viewportRect.width / z,
            height: viewportRect.height / z
        )
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Drawing Change Handler

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Subclass can set this to skip programmatic drawing mutations.
        guard !suppressDrawingChangeHandler else { return }

        baseSignposter.emitEvent("DrawingChanged")

        let data = canvasView.drawing.dataRepresentation()

        guard data != lastPropagatedDrawingData else { return }
        lastPropagatedDrawingData = data

        onDrawingChanged(data)

        // Subclass hook for post-processing (e.g. infinite canvas expansion).
        didProcessDrawingChange(in: canvasView, data: data)

        let um = canvasView.undoManager
        onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

        clearSelectionState()

        let strokeCount = canvasView.drawing.strokes.count
        Task { @MainActor [weak self] in
            self?.strokeMonitor.update(strokeCount: strokeCount, dataSize: data.count)
            self?.adaptiveEffectsEngine.currentPageStrokeCount = strokeCount
            self?.adaptiveEffectsEngine.reportStrokeChange()
        }

        if isDrawing, !isStraightening, canvasView.tool is PKInkingTool {
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = Timer.scheduledTimer(
                withTimeInterval: WritingConfig.holdToStraightenDelay,
                repeats: false
            ) { [weak self, weak canvasView] _ in
                guard let self, self.isDrawing, let canvasView else { return }
                self.holdToStraightenTimer = nil
                self.straightenLastStroke(in: canvasView)
            }
        }

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: WritingConfig.saveDebounceInterval, repeats: false) { [weak self] _ in
            baseSignposter.emitEvent("DrawingSaved")
            self?.onSaveRequested()
        }
    }

    /// Immediately cancels the pending debounce timer and triggers a
    /// synchronous save.
    func flushPendingSave() {
        guard debounceTimer != nil else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        onSaveRequested()
    }

    /// Rebinds the coordinator/canvas to a new logical page without
    /// recreating `PKCanvasView`.
    func bindPageIfNeeded(
        pageToken: String,
        drawingData: Data,
        canvas: PKCanvasView
    ) {
        guard boundPageToken != pageToken else { return }

        flushPendingSave()
        boundPageToken = pageToken

        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        lastPropagatedDrawingData = drawing.dataRepresentation()
        // Suppress the drawing-change handler while programmatically loading
        // the new page's drawing to avoid a redundant round-trip to SwiftUI.
        suppressDrawingChangeHandler = true
        canvas.drawing = drawing
        suppressDrawingChangeHandler = false

        let um = canvas.undoManager
        onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)
        clearSelectionState()
    }

    // MARK: - Hold-to-Straighten

    private func straightenLastStroke(in canvasView: PKCanvasView) {
        let drawing = canvasView.drawing
        let strokes = Array(drawing.strokes)
        guard !strokes.isEmpty else { return }
        let strokeIndex = strokes.count - 1
        let stroke = strokes[strokeIndex]
        let path = stroke.path
        guard path.count >= 2,
              let firstPoint = path.first,
              let lastPoint = path.last else { return }

        let dx = lastPoint.location.x - firstPoint.location.x
        let dy = lastPoint.location.y - firstPoint.location.y
        let length = sqrt(dx * dx + dy * dy)
        guard length >= WritingConfig.holdToStraightenMinLength else { return }

        let pointCount = max(3, min(path.count, WritingConfig.holdToStraightenMaxPoints))
        let straightPoints: [PKStrokePoint] = (0 ..< pointCount).map { i in
            let t = CGFloat(i) / CGFloat(pointCount - 1)
            let loc = CGPoint(
                x: firstPoint.location.x + t * dx,
                y: firstPoint.location.y + t * dy
            )
            let origIdx = min(Int(t * CGFloat(path.count - 1) + 0.5), path.count - 1)
            let orig = path[origIdx]
            return PKStrokePoint(
                location: loc,
                timeOffset: firstPoint.timeOffset + t * (lastPoint.timeOffset - firstPoint.timeOffset),
                size: orig.size,
                opacity: orig.opacity,
                force: orig.force,
                azimuth: orig.azimuth,
                altitude: orig.altitude
            )
        }

        let straightPath = PKStrokePath(controlPoints: straightPoints, creationDate: path.creationDate)
        let straightStroke = PKStroke(ink: stroke.ink, path: straightPath,
                                      transform: stroke.transform, mask: stroke.mask)

        var newStrokes = strokes
        newStrokes[strokeIndex] = straightStroke
        let newDrawing = PKDrawing(strokes: newStrokes)

        let oldDrawing = drawing
        isStraightening = true
        canvasView.undoManager?.registerUndo(withTarget: canvasView) { cv in
            cv.drawing = oldDrawing
        }
        canvasView.undoManager?.setActionName(
            NSLocalizedString("Editor.StraightenLine", comment: "Undo action name for hold-to-straighten")
        )
        canvasView.drawing = newDrawing
        isStraightening = false

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        haptic.impactOccurred()
    }

    // MARK: - Canvas Scroll / Zoom → Background Sync

    /// Start observing the canvas's contentOffset and zoomScale via KVO so
    /// the page background (ruling) follows zoom and scroll.
    func observeCanvasScroll(_ canvas: PKCanvasView) {
        contentOffsetObservation = canvas.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            self?.syncBackgroundWithCanvas(sv)
        }
        zoomScaleObservation = canvas.observe(\.zoomScale, options: [.new]) { [weak self] sv, _ in
            self?.syncBackgroundWithCanvas(sv)
            self?.centerContentDuringZoom(sv)
        }
    }

    /// Positions and scales the page background to match the canvas content.
    func syncBackgroundWithCanvas(_ scrollView: UIScrollView) {
        guard let bg = pageBackground else { return }
        let z = scrollView.zoomScale
        let o = scrollView.contentOffset
        let pw = bg.bounds.width
        let ph = bg.bounds.height
        let tx = -o.x + pw * (z - 1) / 2
        let ty = -o.y + ph * (z - 1) / 2

        let xform = CGAffineTransform(scaleX: z, y: z)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bg.transform = xform
        pdfBackgroundView?.transform = xform
        shapeCanvas?.transform = xform
        attachmentCanvas?.transform = xform
        widgetCanvas?.transform = xform
        stickerCanvas?.transform = xform
        textCanvas?.transform = xform
        CATransaction.commit()
    }

    // MARK: - UIScrollViewDelegate (zoom centering)

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContentDuringZoom(scrollView)
        adaptiveEffectsEngine.zoomScale = scrollView.zoomScale
        interactionFeedback.updateZoom(scrollView.zoomScale, on: scrollView.layer)
        let onDetent = InteractionFeedbackEngine.zoomDetents.first(where: {
            abs(scrollView.zoomScale - $0) < InteractionFeedbackEngine.detentTolerance
        }) != nil
        if onDetent && !wasOnZoomDetent {
            microInteractionEngine.playZoomDetentTick(on: scrollView.layer)
        }
        wasOnZoomDetent = onDetent
        onZoomChanged?(scrollView.zoomScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomChanged?(scrollView.zoomScale)
    }

    /// Adjusts content insets so the page stays centered when zoomed out.
    private func centerContentDuringZoom(_ scrollView: UIScrollView) {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let xInset = max(0, (boundsSize.width - contentSize.width) / 2)
        let yInset = max(0, (boundsSize.height - contentSize.height) / 2)

        scrollView.contentInset = UIEdgeInsets(
            top: yInset, left: xInset,
            bottom: yInset, right: xInset
        )

        syncBackgroundWithCanvas(scrollView)
    }
}

// MARK: - PencilActionDelegate

extension CanvasCoordinatorBase: PencilActionDelegate {

    func pencilDidRequestSwitchToEraser() {
        guard let canvas = canvasRef else { return }
        if !(canvas.tool is PKEraserTool) {
            previousInkingTool = canvas.tool
        }
        canvas.tool = toolStoreRef?.makeEraserTool() ?? {
            if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: EraserSubType.standard.defaultWidth)
            }
            return PKEraserTool(.bitmap)
        }()
        interactionFeedback.play(.eraserEngage, on: canvas.layer)
    }

    func pencilDidRequestSwitchToPreviousTool() {
        guard let canvas = canvasRef else { return }
        if let previous = previousInkingTool {
            canvas.tool = previous
            previousInkingTool = nil
        } else {
            canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        }
        interactionFeedback.play(.eraserDisengage, on: canvas.layer)
    }

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        guard let canvas = canvasRef,
              let window = canvas.window else { return }
        let windowPoint = canvas.convert(anchorPoint, to: window)
        ContextualPencilPaletteView.show(
            at: windowPoint,
            in: window,
            canvas: canvas,
            eraserType: toolStoreRef?.eraserSubType.eraserMode.pkEraserType ?? .vector
        )
    }

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.undo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: true)
        }
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.redo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: false)
        }
    }

    func pencilDidRequestDeleteLastStroke() {
        deleteLastStroke()
    }

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        let isErasing = canvasRef?.tool is PKEraserTool
        if isErasing {
            let sub = toolStoreRef?.eraserSubType ?? .standard
            let width = toolStoreRef?.eraserWidth ?? sub.defaultWidth
            eraserCursorOverlay?.update(position: position, subType: sub, eraserWidth: width)
            hoverOverlay?.update(position: nil, altitude: altitude, azimuth: azimuth)
        } else {
            if let ts = toolStoreRef {
                let personality = ts.activePersonality
                let info = HoverToolInfo(
                    tool: ts.activeTool,
                    color: ts.activeColor,
                    width: CGFloat(ts.activeWidth),
                    opacity: CGFloat(ts.activeOpacity),
                    widthMultiplier: CGFloat(personality?.widthMultiplier ?? 1.0),
                    showsAzimuthLine: personality?.usesTiltShading == true
                                   || personality?.usesBarrelRoll == true,
                    eraserMode: ts.eraserMode
                )
                hoverOverlay?.configure(with: info)
            }
            hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
            eraserCursorOverlay?.update(position: nil, subType: .standard, eraserWidth: 0)
        }
    }

    func pencilBarrelRollChanged(angle: CGFloat) {
        guard #available(iOS 17.5, *), let canvas = canvasRef else { return }
        guard let inkTool = canvas.tool as? PKInkingTool,
              inkTool.inkType == .fountainPen else { return }
        guard let baseWidth = barrelRollBaseWidth else { return }
        guard isDrawing else { return }

        let rollFactor = (cos(angle) + 1) / 2
        let minWidth = max(baseWidth * 0.3, 1.0)
        let maxWidth = baseWidth * 1.8
        let targetWidth = minWidth + rollFactor * (maxWidth - minWidth)
        let clampedWidth = min(max(targetWidth, 1), 20)

        let currentWidth = inkTool.width
        if abs(clampedWidth - currentWidth) > 0.8 {
            canvas.tool = PKInkingTool(.fountainPen, color: inkTool.color, width: clampedWidth)
        }
    }
}

// MARK: - Canvas UIView Builder

/// Helper that creates and wires all the subviews of the canvas container.
/// Used by both `CanvasView.makeUIView` and `CanvasPageView.makeUIView` to
/// eliminate the ~200 lines of duplicated overlay setup code.
@MainActor
enum CanvasViewBuilder {

    /// Builds all overlay subviews (attachment, widget, sticker, text, shape
    /// canvases, hover/eraser overlays, pencil coordinator, nib tracker,
    /// scratch recognizer, effects engine) and wires them to the coordinator.
    ///
    /// Call this from `makeUIView` after the PKCanvasView and shape overlay
    /// have been added to the container.
    // swiftlint:disable:next function_parameter_count
    static func buildOverlays(
        in container: UIView,
        canvas: PKCanvasView,
        coordinator: CanvasCoordinatorBase,
        currentPageShapes: [ShapeInstance],
        isShapeToolActive: Bool,
        currentPageAttachments: [AttachmentObject],
        attachmentNoteID: UUID,
        onAttachmentsChanged: (([AttachmentObject]) -> Void)?,
        onAttachmentSelectionChanged: ((UUID?) -> Void)?,
        currentPageWidgets: [NoteWidget],
        onWidgetsChanged: (([NoteWidget]) -> Void)?,
        onWidgetSelectionChanged: ((UUID?) -> Void)?,
        currentPageStickers: [StickerInstance],
        onStickersChanged: (([StickerInstance]) -> Void)?,
        onStickerSelectionChanged: ((UUID?) -> Void)?,
        stickerImageProvider: ((String) -> UIImage?)?,
        isTextToolActive: Bool,
        currentPageTextObjects: [TextObject],
        onTextObjectsChanged: (([TextObject]) -> Void)?,
        onTextObjectSelectionChanged: ((UUID?) -> Void)?,
        onPlaceTextObject: ((CGPoint) -> Void)?,
        onShapesChanged: (([ShapeInstance]) -> Void)?,
        activeFX: WritingFXType,
        fxColor: UIColor,
        toolStoreForFade: DrawingToolStore?
    ) {
        // ── Attachment canvas ────────────────────────────────────────
        let attachCanvas = AttachmentCanvasView(frame: .zero)
        attachCanvas.translatesAutoresizingMaskIntoConstraints = false
        attachCanvas.noteID = attachmentNoteID
        attachCanvas.attachments = currentPageAttachments
        attachCanvas.onSelectionChanged = { attachmentID in
            coordinator.onAttachmentSelectionChanged?(attachmentID)
        }
        attachCanvas.onAttachmentTransformed = { attachment in
            coordinator.handleAttachmentTransformed(attachment)
        }
        attachCanvas.onAttachmentsChanged = { attachments in
            coordinator.handleAttachmentsChanged(attachments)
        }
        coordinator.onAttachmentsChanged = onAttachmentsChanged
        coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged
        container.addSubview(attachCanvas)
        NSLayoutConstraint.activate([
            attachCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            attachCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            attachCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            attachCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.attachmentCanvas = attachCanvas

        // ── Widget canvas ────────────────────────────────────────────
        let widgetCanvas = WidgetCanvasView(frame: .zero)
        widgetCanvas.translatesAutoresizingMaskIntoConstraints = false
        widgetCanvas.widgets = currentPageWidgets
        widgetCanvas.onSelectionChanged = { widgetID in
            coordinator.onWidgetSelectionChanged?(widgetID)
        }
        widgetCanvas.onWidgetTransformed = { widget in
            coordinator.handleWidgetTransformed(widget)
        }
        widgetCanvas.onWidgetsChanged = { widgets in
            coordinator.handleWidgetsChanged(widgets)
        }
        coordinator.onWidgetsChanged = onWidgetsChanged
        coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged
        container.addSubview(widgetCanvas)
        NSLayoutConstraint.activate([
            widgetCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            widgetCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            widgetCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            widgetCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.widgetCanvas = widgetCanvas

        // ── Sticker canvas ───────────────────────────────────────────
        let stickerCanvas = StickerCanvasView(frame: .zero)
        stickerCanvas.translatesAutoresizingMaskIntoConstraints = false
        stickerCanvas.stickers = currentPageStickers
        stickerCanvas.imageProvider = stickerImageProvider
        stickerCanvas.onStickerTransformed = { sticker in
            coordinator.handleStickerTransformed(sticker)
        }
        stickerCanvas.onStickerDeleted = { stickerID in
            coordinator.handleStickerDeleted(stickerID)
        }
        stickerCanvas.onSelectionChanged = { stickerID in
            coordinator.handleStickerSelectionChanged(stickerID)
        }
        coordinator.onStickersChanged = onStickersChanged
        coordinator.onStickerSelectionChanged = onStickerSelectionChanged
        container.addSubview(stickerCanvas)
        NSLayoutConstraint.activate([
            stickerCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            stickerCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stickerCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stickerCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.stickerCanvas = stickerCanvas

        // ── Text object canvas ───────────────────────────────────────
        let textCanvas = TextCanvasView(frame: .zero)
        textCanvas.translatesAutoresizingMaskIntoConstraints = false
        textCanvas.isTextToolActive = isTextToolActive
        textCanvas.textObjects = currentPageTextObjects
        textCanvas.onSelectionChanged = { textObjectID in
            coordinator.onTextObjectSelectionChanged?(textObjectID)
        }
        textCanvas.onTextObjectsChanged = { textObjects in
            coordinator.handleTextObjectsChanged(textObjects)
        }
        textCanvas.onPlaceTextObject = { point in
            coordinator.onPlaceTextObject?(point)
        }
        textCanvas.onTextObjectTransformed = { textObject in
            coordinator.handleTextObjectTransformed(textObject)
        }
        coordinator.onTextObjectsChanged = onTextObjectsChanged
        coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        coordinator.onPlaceTextObject = onPlaceTextObject
        container.addSubview(textCanvas)
        NSLayoutConstraint.activate([
            textCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            textCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.textCanvas = textCanvas

        // ── Shape object canvas ──────────────────────────────────────
        let shapeCanvas = ShapeCanvasView(frame: .zero)
        shapeCanvas.translatesAutoresizingMaskIntoConstraints = false
        shapeCanvas.shapes = currentPageShapes
        shapeCanvas.isShapeToolActive = isShapeToolActive
        shapeCanvas.onShapesChanged = { [weak shapeCanvas] shapes in
            guard let shapeCanvas else { return }
            coordinator.handleShapesChanged(shapes)
            shapeCanvas.shapes = shapes
        }
        shapeCanvas.onSelectionChanged = { shapeID in
            coordinator.handleShapeSelectionChanged(shapeID)
        }
        coordinator.onShapesChanged = onShapesChanged
        container.addSubview(shapeCanvas)
        NSLayoutConstraint.activate([
            shapeCanvas.topAnchor.constraint(equalTo: container.topAnchor),
            shapeCanvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shapeCanvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shapeCanvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.shapeCanvas = shapeCanvas

        // ── Hover overlay ────────────────────────────────────────────
        let hoverOverlay = PencilHoverOverlayView(frame: .zero)
        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        hoverOverlay.isUserInteractionEnabled = false
        canvas.addSubview(hoverOverlay)
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: canvas.topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        coordinator.hoverOverlay = hoverOverlay

        // ── Eraser cursor overlay ────────────────────────────────────
        let eraserCursor = EraserCursorOverlay(frame: .zero)
        eraserCursor.translatesAutoresizingMaskIntoConstraints = false
        eraserCursor.isUserInteractionEnabled = false
        canvas.addSubview(eraserCursor)
        NSLayoutConstraint.activate([
            eraserCursor.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            eraserCursor.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            eraserCursor.topAnchor.constraint(equalTo: canvas.topAnchor),
            eraserCursor.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        coordinator.eraserCursorOverlay = eraserCursor

        // ── Apple Pencil interaction coordinator ─────────────────────
        let pencilCoordinator = PencilInteractionCoordinator()
        pencilCoordinator.delegate = coordinator
        pencilCoordinator.attach(to: canvas)
        coordinator.pencilCoordinator = pencilCoordinator
        coordinator.canvasRef = canvas

        // ── Real-time nib tracker for effects ────────────────────────
        let nibTracker = PencilNibTrackerGestureRecognizer()
        nibTracker.onNibBegan = { [weak coordinator] location in
            MainActor.assumeIsolated {
                guard let coordinator else { return }
                guard coordinator.canvasRef?.tool is PKInkingTool else { return }
                let inkColor = (coordinator.canvasRef?.tool as? PKInkingTool)?.color ?? .label
                coordinator.effects.dispatch(
                    .strokeBegan(at: location, inkColor: inkColor),
                    inkEffectEngine: coordinator.effectEngine
                )
            }
        }
        nibTracker.onNibMoved = { [weak coordinator] location, force, velocity in
            MainActor.assumeIsolated {
                guard let coordinator else { return }
                guard coordinator.canvasRef?.tool is PKInkingTool else { return }
                coordinator.effects.dispatch(
                    .strokeUpdated(at: location, pressure: force, velocity: velocity),
                    inkEffectEngine: coordinator.effectEngine
                )
            }
        }
        canvas.addGestureRecognizer(nibTracker)
        coordinator.nibTracker = nibTracker

        // ── Scratch-to-delete gesture recognizer ─────────────────────
        let scratchRecognizer = ScribbleDeleteRecognizer()
        scratchRecognizer.onScratchDetected = { [weak coordinator] viewportRect in
            DispatchQueue.main.async {
                coordinator?.deleteScratchStrokes(in: viewportRect)
            }
        }
        canvas.addGestureRecognizer(scratchRecognizer)
        coordinator.scratchDeleteRecognizer = scratchRecognizer

        // Pre-warm haptic generators.
        coordinator.interactionFeedback.prepareAll()

        // ── Ink effect engine ────────────────────────────────────────
        let engine = InkEffectEngine(tier: DeviceCapabilityTier.current)
        engine.configure(fx: activeFX, color: fxColor)
        engine.attach(to: container)
        coordinator.effectEngine = engine

        // ── Writing Effects Pipeline ─────────────────────────────────
        coordinator.writingPipeline.attach(to: container)
        coordinator.writingPipeline.configure(
            config: toolStoreForFade?.writingEffectConfig ?? .default,
            color: toolStoreForFade?.activeColor ?? .black
        )
    }

    /// Syncs overlay canvases with the current representable properties.
    /// Used by both `CanvasView.updateUIView` and `CanvasPageView.updateUIView`.
    // swiftlint:disable:next function_parameter_count
    static func syncOverlayCanvases(
        coordinator: CanvasCoordinatorBase,
        canvas: PKCanvasView,
        isShapeToolActive: Bool,
        activeShapeType: ShapeType,
        shapeColor: UIColor,
        shapeWidth: Double,
        currentPageShapes: [ShapeInstance],
        currentPageAttachments: [AttachmentObject],
        attachmentNoteID: UUID,
        currentPageWidgets: [NoteWidget],
        currentPageStickers: [StickerInstance],
        stickerImageProvider: ((String) -> UIImage?)?,
        isTextToolActive: Bool,
        currentPageTextObjects: [TextObject],
        toolStore: DrawingToolStore?,
        onAttachmentsChanged: (([AttachmentObject]) -> Void)?,
        onAttachmentSelectionChanged: ((UUID?) -> Void)?,
        onWidgetsChanged: (([NoteWidget]) -> Void)?,
        onWidgetSelectionChanged: ((UUID?) -> Void)?,
        onStickersChanged: (([StickerInstance]) -> Void)?,
        onStickerSelectionChanged: ((UUID?) -> Void)?,
        onTextObjectsChanged: (([TextObject]) -> Void)?,
        onTextObjectSelectionChanged: ((UUID?) -> Void)?,
        onPlaceTextObject: ((CGPoint) -> Void)?,
        onShapesChanged: (([ShapeInstance]) -> Void)?
    ) {
        if let overlay = coordinator.shapeOverlay {
            overlay.isHidden = !isShapeToolActive
            overlay.shapeType = activeShapeType
            overlay.strokeColor = shapeColor
            overlay.strokeWidth = CGFloat(shapeWidth)
        }
        if let shapeCanvas = coordinator.shapeCanvas {
            shapeCanvas.isShapeToolActive = isShapeToolActive
            shapeCanvas.shapes = currentPageShapes
            shapeCanvas.selectedShapeID = toolStore?.activeShapeSelection
        }
        if let attachCanvas = coordinator.attachmentCanvas {
            attachCanvas.attachments = currentPageAttachments
            attachCanvas.noteID = attachmentNoteID
            attachCanvas.selectedAttachmentID = toolStore?.activeAttachmentSelection
            attachCanvas.zoomScale = canvas.zoomScale
        }
        coordinator.onAttachmentsChanged = onAttachmentsChanged
        coordinator.onAttachmentSelectionChanged = onAttachmentSelectionChanged

        if let widgetCanvas = coordinator.widgetCanvas {
            widgetCanvas.widgets = currentPageWidgets
            widgetCanvas.selectedWidgetID = toolStore?.activeWidgetSelection
        }
        coordinator.onWidgetsChanged = onWidgetsChanged
        coordinator.onWidgetSelectionChanged = onWidgetSelectionChanged

        if let stickerCanvas = coordinator.stickerCanvas {
            stickerCanvas.stickers = currentPageStickers
            stickerCanvas.imageProvider = stickerImageProvider
            stickerCanvas.selectedStickerID = toolStore?.activeStickerSelection
        }
        coordinator.onStickersChanged = onStickersChanged
        coordinator.onStickerSelectionChanged = onStickerSelectionChanged

        if let textCanvas = coordinator.textCanvas {
            textCanvas.isTextToolActive = isTextToolActive
            textCanvas.textObjects = currentPageTextObjects
            textCanvas.selectedTextObjectID = toolStore?.activeTextObjectSelection
        }
        coordinator.onTextObjectsChanged = onTextObjectsChanged
        coordinator.onTextObjectSelectionChanged = onTextObjectSelectionChanged
        coordinator.onPlaceTextObject = onPlaceTextObject
    }

    /// Syncs effects engines with current state.
    static func syncEffects(
        coordinator: CanvasCoordinatorBase,
        layer: CALayer,
        bounds: CGRect,
        pageIndex: Int,
        pageCount: Int,
        activeFX: WritingFXType,
        fxColor: UIColor,
        toolStore: DrawingToolStore?
    ) {
        coordinator.coordinatorPageIndex = pageIndex
        coordinator.coordinatorPageCount = pageCount

        coordinator.adaptiveEffectsEngine.pageCount = pageCount
        let intensity = coordinator.adaptiveEffectsEngine.intensity
        coordinator.effects.distribute(
            intensity: intensity,
            shapeCanvas: coordinator.shapeCanvas,
            attachmentCanvas: coordinator.attachmentCanvas,
            widgetCanvas: coordinator.widgetCanvas,
            stickerCanvas: coordinator.stickerCanvas
        )

        coordinator.effects.updateLayout(containerBounds: bounds)

        if let engine = coordinator.effectEngine {
            engine.syncLayerFrames()
            engine.configure(fx: activeFX, color: fxColor)
        }

        coordinator.writingPipeline.configure(
            config: toolStore?.writingEffectConfig ?? .default,
            color: toolStore?.activeColor ?? .black
        )
    }
}
// swiftlint:enable file_length type_body_length
