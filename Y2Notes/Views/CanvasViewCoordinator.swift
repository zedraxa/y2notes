import UIKit
import PencilKit
import OSLog
import SwiftUI

// MARK: - Performance instrumentation (coordinator)

private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")
private let editorSignposter = OSSignposter(subsystem: "com.y2notes.app", category: "editor.perf")

// MARK: - CanvasView.Coordinator

extension CanvasView {

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let onDrawingChanged: (Data) -> Void
        let onSaveRequested: () -> Void
        /// Page swipe callback: +1 next, −1 previous.
        let onPageSwipe: ((Int) -> Void)?
        /// Pinch-to-overview callback.
        let onPinchToOverview: (() -> Void)?
        weak var canvas: PKCanvasView?
        weak var shapeOverlay: ShapeOverlayView?
        /// Page ruling / background view placed behind the canvas.
        weak var pageBackground: PageBackgroundView?
        /// PDF page image rendered behind the canvas (book-like feel).
        weak var pdfBackgroundView: UIImageView?
        /// Updated by updateUIView to always hold the freshest closure.
        var onUndoStateChanged: ((Bool, Bool) -> Void)?
        /// Called once when the canvas undo manager is available, so the parent
        /// view can call undo/redo directly without relying on the environment.
        var onCanvasUndoManagerAvailable: ((UndoManager?) -> Void)?
        /// Guards one-time delivery of the undo manager reference.
        private var didDeliverUndoManager = false
        /// Tracks the last zoom-reset trigger seen so we only react to flips.
        var lastZoomResetTrigger: Bool = false
        private var debounceTimer: Timer?

        // Apple Pencil support
        var pencilCoordinator: PencilInteractionCoordinator?
        /// Passive gesture recognizer that feeds real-time pencil positions
        /// to the effects engines at the hardware's native touch rate.
        var nibTracker: PencilNibTrackerGestureRecognizer?
        var hoverOverlay: PencilHoverOverlayView?
        var eraserCursorOverlay: EraserCursorOverlay?
        /// Passive gesture recognizer that detects scratch-to-delete gestures.
        var scratchDeleteRecognizer: ScribbleDeleteRecognizer?
        weak var canvasRef: PKCanvasView?

        /// Ink effect engine that renders fire/sparkle/glitch/ripple overlays.
        var effectEngine: InkEffectEngine?

        /// Central coordinator that owns and wires all effect sub-engines.
        let effects = EffectsCoordinator()

        // Convenience accessors forwarded to the coordinator.
        var pageTransitionEngine: PageTransitionEngine { effects.pageTransitionEngine }
        var focusModeEngine: FocusModeEngine           { effects.focusModeEngine }
        var ambientEngine: AmbientEnvironmentEngine    { effects.ambientEngine }
        var magicModeEngine: MagicModeEngine           { effects.magicModeEngine }
        var studyModeEngine: StudyModeEngine           { effects.studyModeEngine }
        var adaptiveEffectsEngine: AdaptiveEffectsEngine { effects.adaptiveEngine }
        var writingPipeline: WritingEffectsPipeline    { effects.writingEffectsPipeline }
        var microInteractionEngine: MicroInteractionEngine { effects.microInteractionEngine }
        var snapAlignEffectEngine: SnapAlignEffectEngine { effects.snapAlignEffectEngine }
        var interactionFeedback: InteractionFeedbackEngine { effects.interactionFeedbackEngine }


        /// Shape objects canvas for the current page.
        weak var shapeCanvas: ShapeCanvasView?

        /// Debounce timer for persisting shape changes.
        private var shapeDebounceTimer: Timer?

        /// Callback to persist shape changes.
        var onShapesChanged: (([ShapeInstance]) -> Void)?

        /// Attachment canvas overlay for the current page.
        weak var attachmentCanvas: AttachmentCanvasView?

        /// Debounce timer for persisting attachment changes.
        private var attachmentDebounceTimer: Timer?

        /// Callback to persist attachment changes.
        var onAttachmentsChanged: (([AttachmentObject]) -> Void)?

        /// Callback when attachment selection changes.
        var onAttachmentSelectionChanged: ((UUID?) -> Void)?

        /// Widget canvas overlay for the current page.
        weak var widgetCanvas: WidgetCanvasView?

        /// Debounce timer for persisting widget changes.
        private var widgetDebounceTimer: Timer?

        /// Callback to persist widget changes.
        var onWidgetsChanged: (([NoteWidget]) -> Void)?

        /// Callback when widget selection changes.
        var onWidgetSelectionChanged: ((UUID?) -> Void)?

        /// Sticker canvas overlay for the current page.
        weak var stickerCanvas: StickerCanvasView?

        /// Debounce timer for persisting sticker changes.
        private var stickerDebounceTimer: Timer?

        /// Callback to persist sticker changes.
        var onStickersChanged: (([StickerInstance]) -> Void)?

        /// Callback when sticker selection changes.
        var onStickerSelectionChanged: ((UUID?) -> Void)?

        /// Text object canvas overlay for the current page.
        weak var textCanvas: TextCanvasView?

        /// Debounce timer for persisting text object changes.
        private var textDebounceTimer: Timer?

        /// Callback to persist text object changes.
        var onTextObjectsChanged: (([TextObject]) -> Void)?

        /// Callback when text object selection changes.
        var onTextObjectSelectionChanged: ((UUID?) -> Void)?

        /// Called when the user taps empty space with the text tool active.
        var onPlaceTextObject: ((CGPoint) -> Void)?

        /// Callback to propagate text object transform to the view.
        var onTextObjectTransformed: ((TextObject) -> Void)?

        /// Weak reference to the drawing tool store for toolbar auto-fade.
        weak var toolStoreRef: DrawingToolStore?

        /// Task that schedules the toolbar fade after a delay of active drawing.
        private var fadeTask: Task<Void, Never>?

        /// Pinch gesture recognizer for page overview.
        var pinchOverviewGesture: UIPinchGestureRecognizer?

        /// Two-finger pan gesture recognizer for interactive page navigation.
        var pagePanGesture: UIPanGestureRecognizer?

        /// Minimum scale observed during the current pinch-to-overview gesture.
        /// Tracked during `.changed` because `numberOfTouches` is zero at `.ended`.
        private var pinchOverviewMinScale: CGFloat = 1.0

        // ── Interactive page-drag state ──────────────────────────────────────────
        /// True while a two-finger horizontal pan is being tracked for page navigation.
        private var pageIsDragging = false
        /// Direction locked in at the start of the current page drag.
        private var pageDragDirection: PageTransitionDirection = .forward
        /// Current zero-based page index, kept in sync by `updateUIView`.
        var coordinatorPageIndex: Int = 0
        /// Total page count, kept in sync by `updateUIView`.
        var coordinatorPageCount: Int = 1

        /// Light haptic feedback played when a page drag commits.
        private let pageTurnImpact: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            return g
        }()

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
        /// Used to restore the tool when the user double-taps "switch to previous".
        private var previousInkingTool: PKTool?

        /// Zoom scale captured when a stroke begins. When `WritingConfig.lockZoomDuringWriting`
        /// is enabled, the canvas zoom is pinned to this value during active writing to
        /// prevent accidental zoom drift from multi-touch interference.
        private var strokeStartZoomScale: CGFloat?

        /// Timer that re-enables zoom/scroll gestures after a short delay following
        /// the end of a stroke. Prevents accidental zoom when lifting the hand
        /// between quick successive strokes.
        private var postStrokeZoomUnlockTimer: Timer?

        /// Timer that fires when the user holds the pen still after drawing a stroke,
        /// triggering automatic straightening of the last stroke into a clean line.
        private var holdToStraightenTimer: Timer?

        /// True while `straightenLastStroke` is replacing the canvas drawing so
        /// `canvasViewDrawingDidChange` does not restart `holdToStraightenTimer`
        /// on the programmatic change.
        private var isStraightening = false

        /// Tracks Apple Pencil contact timing for palm rejection in `.anyInput` mode.
        let palmGuard = PalmGuardState()

        /// Tracks stroke count and data size for performance warnings.
        let strokeMonitor = StrokePerformanceMonitor()

        // KVO observers that keep the page background in sync with canvas
        // scroll offset and zoom scale. Invalidated automatically on dealloc.
        private var contentOffsetObservation: NSKeyValueObservation?
        private var zoomScaleObservation: NSKeyValueObservation?

        /// Tracks whether the last zoom update landed on a detent, so the
        /// visual micro-bounce fires only on the leading edge (entry, not hold).
        private var wasOnZoomDetent: Bool = false

        // Pre-prepared haptic generator for double-tap pencil delete feedback.
        // Preparing eagerly avoids the latency spike that would occur if the
        // generator were created and prepared on the first deletion event.
        private let deletionImpactGenerator: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            return g
        }()

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void,
            onPageSwipe: ((Int) -> Void)? = nil,
            onPinchToOverview: (() -> Void)? = nil
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onSaveRequested  = onSaveRequested
            self.onPageSwipe      = onPageSwipe
            self.onPinchToOverview = onPinchToOverview
        }

        deinit {
            // Flush any pending drawing save so strokes are never silently
            // dropped when the coordinator deallocates (e.g. on page change).
            flushPendingSave()
            // Invalidate remaining timers.
            postStrokeZoomUnlockTimer?.invalidate()
            shapeDebounceTimer?.invalidate()
            attachmentDebounceTimer?.invalidate()
            // KVO observations are invalidated automatically by
            // NSKeyValueObservation.deinit, but nil them for clarity.
            contentOffsetObservation?.invalidate()
            zoomScaleObservation?.invalidate()
        }

        // MARK: - Page gesture handlers

        /// Tuning constants for the two-finger page-pan gesture recogniser.
        private enum PagePanTuning {
            /// Minimum horizontal-to-vertical ratio required before the gesture
            /// is locked in as a horizontal page drag.
            static let horizontalDominanceRatio: CGFloat = 1.5
            /// Minimum horizontal displacement (points) before direction is
            /// locked in — prevents accidental page turns on tiny movements.
            static let minimumLockInDistance: CGFloat = 8
            /// Minimum horizontal release velocity (points/second) for a
            /// reduce-motion fast-swipe to commit a page change.
            static let reducedMotionCommitVelocity: CGFloat = 400
        }

        /// Two-finger pan handler for interactive page navigation.
        ///
        /// The page follows the finger in real-time.  Direction is determined on
        /// the first update where horizontal motion clearly dominates vertical.
        /// Backward drags are blocked when already on the first page to prevent
        /// the container from flying off-screen with no state change to recover it.
        ///
        /// `onPageSwipe` is only called inside the snap-completion callback so
        /// SwiftUI rebuilds the page content *after* the outgoing page has
        /// finished its animation — eliminating the visual conflict that occurred
        /// when state and CA animation changed simultaneously.
        @objc func handlePagePan(_ gesture: UIPanGestureRecognizer) {
            guard !isDrawing, let view = gesture.view else { return }

            let translation = gesture.translation(in: view)
            let velocity    = gesture.velocity(in: view)
            let pageWidth   = view.bounds.width

            switch gesture.state {
            case .began:
                // Direction and drag start are deferred until the first `.changed`
                // event that shows clear horizontal dominance.
                pageIsDragging = false

            case .changed:
                if !pageIsDragging {
                    // Wait until horizontal motion clearly dominates vertical.
                    guard abs(translation.x) > abs(translation.y) * PagePanTuning.horizontalDominanceRatio,
                          abs(translation.x) > PagePanTuning.minimumLockInDistance
                    else { return }

                    let dir: PageTransitionDirection = translation.x < 0 ? .forward : .backward

                    // Block backward drag on the very first page: there's nothing to
                    // return to, and committing would leave the container off-screen.
                    if dir == .backward && coordinatorPageIndex == 0 { return }

                    // Reduce-motion: fall through to the simpler cross-fade path.
                    if pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                        pageDragDirection = dir
                        pageIsDragging    = true
                        pageTransitionEngine.beginInteractiveDrag(
                            on: view,
                            direction: dir,
                            pageWidth: pageWidth
                        )
                    }
                }

                if pageIsDragging {
                    pageTransitionEngine.updateInteractiveDrag(
                        on: view,
                        translation: translation.x,
                        pageWidth: pageWidth
                    )
                }

            case .ended:
                if pageIsDragging {
                    // Normal mode: spring-snap the interactive drag to completion
                    // or back to origin.
                    pageIsDragging = false

                    pageTransitionEngine.finishInteractiveDrag(
                        on: view,
                        velocityX: velocity.x,
                        pageWidth: pageWidth
                    ) { [weak self] committed in
                        guard let self, committed else { return }
                        // Flush any pending drawing save so strokes are
                        // persisted before the page transition replaces
                        // the canvas content.
                        self.flushPendingSave()
                        self.pageTurnImpact.impactOccurred()
                        self.pageTurnImpact.prepare()
                        self.onPageSwipe?(self.pageDragDirection == .forward ? 1 : -1)
                    }
                } else if !pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                    // Reduce-motion / low-intensity fallback: treat a fast, clearly
                    // horizontal release as a swipe and change page immediately.
                    guard abs(velocity.x) > PagePanTuning.reducedMotionCommitVelocity,
                          abs(velocity.x) > abs(velocity.y) * PagePanTuning.horizontalDominanceRatio
                    else { return }
                    let dir: PageTransitionDirection = velocity.x < 0 ? .forward : .backward
                    guard !(dir == .backward && coordinatorPageIndex == 0) else { return }
                    flushPendingSave()
                    onPageSwipe?(dir == .forward ? 1 : -1)
                }

            case .cancelled, .failed:
                guard pageIsDragging else { return }
                pageIsDragging = false
                pageTransitionEngine.cancelInteractiveDrag(on: view) {}

            default:
                break
            }
        }

        /// Pinch-in handler for page overview.
        @objc func handlePinchToOverview(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchOverviewMinScale = gesture.scale
            case .changed:
                pinchOverviewMinScale = min(pinchOverviewMinScale, gesture.scale)
            case .ended, .cancelled:
                // Trigger overview only when:
                // 1. The gesture reached a very small scale (fingers came close together).
                // 2. The gesture velocity is negative (fingers still moving inward at release).
                // This prevents normal zoom-out from accidentally triggering the overview.
                let isDeepPinch = pinchOverviewMinScale < 0.35
                let isClosingAtEnd = gesture.velocity < 0
                if isDeepPinch && isClosingAtEnd {
                    onPinchToOverview?()
                }
                pinchOverviewMinScale = 1.0
            default:
                break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        /// Allows the page-overview pinch and the page-pan to fire simultaneously
        /// with PKCanvasView's built-in gestures.  The page-pan handler uses a
        /// horizontal-dominance check to distinguish page turns from canvas scroll.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === pinchOverviewGesture
                || gestureRecognizer === pagePanGesture
        }

        // MARK: - Drawing lifecycle (protects pressure/tilt pipeline)

        /// Converts a PKDrawing content-space point to the viewport/overlay
        /// coordinate space so that ink-effect particles render at the correct
        /// on-screen position regardless of zoom/scroll state.
        private func viewportPoint(from contentPoint: CGPoint, in canvasView: PKCanvasView) -> CGPoint {
            let z = canvasView.zoomScale
            let o = canvasView.contentOffset
            return CGPoint(
                x: contentPoint.x * z - o.x,
                y: contentPoint.y * z - o.y
            )
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = true
            // Cancel any pending zoom-unlock timer from a previous stroke so
            // rapid successive strokes keep zoom locked continuously.
            postStrokeZoomUnlockTimer?.invalidate()
            postStrokeZoomUnlockTimer = nil

            // Cancel any pending hold-to-straighten from the previous stroke.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil

            // Lock zoom during writing to prevent accidental zoom drift from
            // multi-touch interference (e.g. palm resting on screen).
            if WritingConfig.lockZoomDuringWriting {
                strokeStartZoomScale = canvasView.zoomScale
                canvasView.pinchGestureRecognizer?.isEnabled = false
                canvasView.isScrollEnabled = false
            }

            // Capture base width for barrel-roll modulation at stroke start.
            if let inkTool = canvasView.tool as? PKInkingTool {
                barrelRollBaseWidth = inkTool.width
            }
            // NOTE: .strokeBegan is dispatched by PencilNibTrackerGestureRecognizer
            // with the actual first-contact position.  No dispatch needed here.
            // Auto-fade toolbar using config constants
            fadeTask?.cancel()
            fadeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarFadeDelay))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFadedOpacity
                }
            }
            // Pause attachment rendering during active strokes for zero lag.
            attachmentCanvas?.renderingPaused = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
            // Pen lifted — discard any pending hold-to-straighten.
            holdToStraightenTimer?.invalidate()
            holdToStraightenTimer = nil
            // If barrel-roll modulated the fountain-pen width during this stroke,
            // the canvas tool is left at the modulated (drifted) width.
            // Invalidate lastToolSnapshot so updateUIView resets canvas.tool to
            // the canonical width from DrawingToolStore before the next stroke,
            // preventing a compounding feedback loop where each stroke starts
            // wider than the last.
            if barrelRollBaseWidth != nil {
                lastToolSnapshot = nil
            }
            barrelRollBaseWidth = nil

            // Re-enable zoom and scroll after a short delay to prevent
            // accidental zoom when lifting the hand between rapid successive
            // strokes.  Guard `isDrawing` in the callback to handle the rare
            // case where a new stroke begins before the timer fires.
            if WritingConfig.lockZoomDuringWriting {
                postStrokeZoomUnlockTimer?.invalidate()
                postStrokeZoomUnlockTimer = Timer.scheduledTimer(
                    withTimeInterval: WritingConfig.postStrokeZoomLockDelay,
                    repeats: false
                ) { [weak self, weak canvasView] _ in
                    guard let self, !self.isDrawing else { return }
                    canvasView?.pinchGestureRecognizer?.isEnabled = true
                    canvasView?.isScrollEnabled = true
                }
                strokeStartZoomScale = nil
            }

            // Record pencil end time for palm guard (finger rejection window).
            palmGuard.pencilStrokeEnded()

            // Signal stroke pause to the adaptive effects engine so it can
            // decay the smoothed writing rate and potentially restore effects.
            Task { @MainActor [weak self] in
                self?.adaptiveEffectsEngine.reportStrokePause()
            }

            // Dispatch stroke-ended through the effects coordinator (single stroke read).
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
                let vpMax    = viewportPoint(from: CGPoint(x: bbox.maxX, y: bbox.maxY), in: canvasView)
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
            // Restore toolbar opacity after drawing ends using config constants
            fadeTask?.cancel()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(WritingConfig.toolbarRestoreDelay))
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.toolStoreRef?.toolbarOpacity = WritingConfig.toolbarFullOpacity
                }
            }
            // Detect lasso selection state. When the user finishes a lasso gesture
            // the canvas holds an internal selection. We set hasActiveSelection so
            // the floating toolbar morphs to show selection actions.
            if canvasView.tool is PKLassoTool {
                markLassoSelectionActive()
            } else {
                updateSelectionState(for: canvasView)
            }
            // Resume attachment rendering after a short delay (matches toolbar restore timing).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.3))
                self?.attachmentCanvas?.renderingPaused = false
                self?.attachmentCanvas?.setNeedsDisplay()
            }
        }

        /// Updates `toolStore.hasActiveSelection` based on whether the canvas
        /// currently holds a lasso selection. Called after tool-end events and
        /// drawing changes to keep the toolbar in sync.
        ///
        /// Detection: when the lasso tool finishes a gesture, PencilKit holds an
        /// internal selection. We track this via a simple flag that is set when
        /// `canvasViewDidEndUsingTool` fires while a PKLassoTool is active, and
        /// cleared when the drawing changes (selection committed) or the tool
        /// switches away from lasso.
        func updateSelectionState(for canvasView: PKCanvasView) {
            let isLasso = canvasView.tool is PKLassoTool
            // Only set true when lasso tool just finished a gesture (likely selected
            // something). Reset when drawing changes or tool switches.
            if !isLasso && toolStoreRef?.hasActiveSelection == true {
                Task { @MainActor [weak self] in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        self?.toolStoreRef?.hasActiveSelection = false
                    }
                }
            }
        }

        /// Marks that the lasso tool completed a selection gesture.
        /// Called from `canvasViewDidEndUsingTool` when the active tool is a lasso.
        func markLassoSelectionActive() {
            guard toolStoreRef?.hasActiveSelection != true else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = true
                }
            }
        }

        /// Clears the selection state (e.g. after the drawing changes, meaning
        /// the selection was committed or the canvas was otherwise modified).
        func clearSelectionState() {
            guard toolStoreRef?.hasActiveSelection != false else { return }
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    self?.toolStoreRef?.hasActiveSelection = false
                }
            }
        }

        // MARK: - Shape Object Handlers

        /// Called when the shape canvas reports changes to shape objects.
        func handleShapesChanged(_ shapes: [ShapeInstance]) {
            shapeDebounceTimer?.invalidate()
            shapeDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: ShapeConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onShapesChanged?(shapes)
            }
        }

        /// Called when shape selection changes.
        func handleShapeSelectionChanged(_ shapeID: UUID?) {
            Task { @MainActor [weak self] in
                self?.toolStoreRef?.activeShapeSelection = shapeID
            }
        }

        // MARK: - Attachment Coordination

        /// Called when an attachment is moved or resized.
        func handleAttachmentTransformed(_ attachment: AttachmentObject) {
            guard var attachments = attachmentCanvas?.attachments else { return }
            if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                attachments[idx] = attachment
            }
            handleAttachmentsChanged(attachments)
        }

        /// Debounced persistence for attachment changes.
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

        /// Debounced persistence for widget changes.
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

        func handleStickersChanged(_ stickers: [StickerInstance]) {
            stickerDebounceTimer?.invalidate()
            stickerDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: StickerConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onStickersChanged?(stickers)
            }
        }

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

        // MARK: - Text Object Coordinator

        /// Called when a text object is moved, resized, or rotated.
        func handleTextObjectTransformed(_ textObject: TextObject) {
            guard var textObjects = textCanvas?.textObjects else { return }
            if let idx = textObjects.firstIndex(where: { $0.id == textObject.id }) {
                textObjects[idx] = textObject
            }
            handleTextObjectsChanged(textObjects)
        }

        /// Debounced persistence for text object changes.
        func handleTextObjectsChanged(_ textObjects: [TextObject]) {
            textDebounceTimer?.invalidate()
            textDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: TextObjectConstants.saveDebounce,
                repeats: false
            ) { [weak self] _ in
                self?.onTextObjectsChanged?(textObjects)
            }
        }

        // MARK: - Double-tap pencil to delete last stroke

        /// Removes the most recently drawn stroke from the canvas.
        /// Called when the user double-taps Apple Pencil.  Registered with the
        /// canvas's own `UndoManager` so it can be reversed with undo.
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

        // MARK: - Scratch-to-delete

        /// Removes every PKStroke whose render bounds intersect the scratch region
        /// described by `viewportRect` (in the canvas scroll-view's bounds coordinates).
        ///
        /// This is called by ``ScribbleDeleteRecognizer`` after it confirms that the
        /// user drew a rapid back-and-forth scratch gesture.  Because the scratch was
        /// drawn with the active inking tool it becomes a regular PKStroke — that
        /// stroke's render bounds lie within `viewportRect`, so it is included in the
        /// set of strokes to remove alongside any pre-existing strokes it overlaps.
        ///
        /// The operation is registered with the canvas's `UndoManager` so it can be
        /// reversed with a standard Undo gesture or Cmd-Z.
        func deleteScratchStrokes(in viewportRect: CGRect) {
            guard let canvas = canvasRef else { return }

            // Expand the hit region slightly to account for stroke width — strokes
            // are compared by their render bounds, which already includes the ink
            // radius, but a small inset guards against sub-pixel rounding gaps.
            let contentRect = self.contentRect(from: viewportRect, in: canvas)
            let hitRect     = contentRect.insetBy(dx: -10, dy: -10)

            let allStrokes = Array(canvas.drawing.strokes)
            let remaining  = allStrokes.filter { !$0.renderBounds.intersects(hitRect) }

            // Nothing to delete — either the scratch was over empty space or the
            // detection fired erroneously.  Bail early without touching undo stack.
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

            // Scale haptic weight with the number of strokes removed: a single
            // scratch stroke that erases only itself gets a normal impact, while
            // removing several strokes at once gets a heavier double-impact.
            let deletedCount = allStrokes.count - remaining.count
            deletionImpactGenerator.impactOccurred()
            if deletedCount > 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.deletionImpactGenerator.impactOccurred()
                }
            }
            deletionImpactGenerator.prepare()
        }

        /// Converts a rectangle from the canvas scroll-view's **viewport** (bounds)
        /// coordinate space into the PKDrawing **content** coordinate space.
        ///
        /// PKStroke.renderBounds lives in content space; gesture touch locations are
        /// reported in the scroll-view's bounds space.  The mapping is:
        ///
        ///     contentPoint.x = (viewportPoint.x + contentOffset.x) / zoomScale
        ///
        /// which is the inverse of `viewportPoint(from:in:)` defined nearby.
        private func contentRect(from viewportRect: CGRect, in canvasView: PKCanvasView) -> CGRect {
            let z = canvasView.zoomScale
            let o = canvasView.contentOffset
            let origin = CGPoint(
                x: (viewportRect.minX + o.x) / z,
                y: (viewportRect.minY + o.y) / z
            )
            let size = CGSize(
                width:  viewportRect.width  / z,
                height: viewportRect.height / z
            )
            return CGRect(origin: origin, size: size)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            editorSignposter.emitEvent("DrawingChanged")

            let data = canvasView.drawing.dataRepresentation()
            onDrawingChanged(data)

            // NOTE: effect position updates are driven by PencilNibTrackerGestureRecognizer
            // at the hardware's native touch rate.  No position dispatch is needed here.

            // Report undo/redo availability directly from the canvas's undo manager.
            // PKCanvasView inherits UIResponder.undoManager which traverses the responder
            // chain — the same manager PencilKit registers stroke actions against.
            let um = canvasView.undoManager
            onUndoStateChanged?(um?.canUndo ?? false, um?.canRedo ?? false)

            // Deliver the canvas undo manager reference once so the parent view
            // can call undo/redo directly (the SwiftUI environment undo manager
            // may differ from the PKCanvasView's responder-chain undo manager).
            if !didDeliverUndoManager, let um {
                didDeliverUndoManager = true
                onCanvasUndoManagerAvailable?(um)
            }

            // Drawing changed — selection was committed (paste, delete, move, etc.)
            // so clear the selection state to collapse the selection toolbar.
            clearSelectionState()

            // Update stroke performance monitor for warning thresholds.
            let strokeCount = canvasView.drawing.strokes.count
            Task { @MainActor [weak self] in
                self?.strokeMonitor.update(strokeCount: strokeCount, dataSize: data.count)
                self?.adaptiveEffectsEngine.currentPageStrokeCount = strokeCount
                self?.adaptiveEffectsEngine.reportStrokeChange()
            }

            // Hold-to-straighten: restart the timer on every new drawing change
            // while the pen is still down. If drawing stops changing (user holds
            // the pen still), the timer fires and replaces the last stroke with a
            // clean straight line between its start and end points.
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

            // Debounce disk writes using config constant.
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: WritingConfig.saveDebounceInterval, repeats: false) { [weak self] _ in
                editorSignposter.emitEvent("DrawingSaved")
                self?.onSaveRequested()
            }
        }

        /// Immediately cancels the pending debounce timer and triggers a
        /// synchronous save.  Called before page transitions so strokes
        /// drawn just before a swipe are never silently dropped.
        func flushPendingSave() {
            guard debounceTimer != nil else { return }
            debounceTimer?.invalidate()
            debounceTimer = nil
            onSaveRequested()
        }

        // MARK: - Canvas scroll / zoom → background sync
        // MARK: - Hold-to-Straighten

        /// Replaces the last stroke in `canvasView.drawing` with a clean straight
        /// line from its first point to its last point, preserving the original
        /// ink colour, tool type, and per-point pressure/tilt attributes.
        ///
        /// Called by `holdToStraightenTimer` when the user holds the pen still
        /// after drawing without lifting it. The replacement is registered with
        /// the canvas's own `UndoManager` so it can be reversed with undo.
        private func straightenLastStroke(in canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            let strokes = Array(drawing.strokes)
            guard !strokes.isEmpty else { return }
            let strokeIndex = strokes.count - 1
            let stroke = strokes[strokeIndex]
            let path = stroke.path
            guard path.count >= 2,
                  let firstPoint = path.first,
                  let lastPoint  = path.last else { return }

            let dx = lastPoint.location.x - firstPoint.location.x
            let dy = lastPoint.location.y - firstPoint.location.y
            let length = sqrt(dx * dx + dy * dy)
            guard length >= WritingConfig.holdToStraightenMinLength else { return }

            // Build a straight-line path by mapping original point attributes
            // (size, force, tilt) onto evenly-spaced locations along the new line.
            // This preserves pressure dynamics while straightening the geometry.
            let pointCount = max(3, min(path.count, WritingConfig.holdToStraightenMaxPoints))
            let straightPoints: [PKStrokePoint] = (0 ..< pointCount).map { i in
                let t = CGFloat(i) / CGFloat(pointCount - 1)
                let loc = CGPoint(
                    x: firstPoint.location.x + t * dx,
                    y: firstPoint.location.y + t * dy
                )
                // +0.5 performs nearest-neighbour rounding when mapping the
                // straight-line position t back to an original path index.
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

            let straightPath   = PKStrokePath(controlPoints: straightPoints, creationDate: path.creationDate)
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
        ///
        /// The background view sits in the container (same coordinate space as
        /// the canvas viewport). To make it visually overlay the canvas content:
        ///
        /// - **Scale** by `zoomScale` so ruling lines scale with drawing strokes.
        /// - **Translate** to compensate for `contentOffset` so the background
        ///   pans with the content.
        ///
        /// The math: a content point `(px, py)` appears in the viewport at
        /// `(px * z − o.x, py * z − o.y)`. The view's transform is applied
        /// around its center, so we derive `tx`/`ty` to make the visual frame
        /// origin land at `(−o.x, −o.y)`.
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
            // Keep object overlay canvases (shapes, attachments, widgets)
            // in sync with the PencilKit canvas zoom/scroll so objects
            // rendered in page-local coordinates don't drift from ink.
            shapeCanvas?.transform = xform
            attachmentCanvas?.transform = xform
            widgetCanvas?.transform = xform
            CATransaction.commit()
        }

        // MARK: - UIScrollViewDelegate (zoom centering)

        /// Centers the canvas content when zoomed out below 1× so the page
        /// stays centered on screen rather than pinning to the top-left corner.
        /// Also called from the zoomScale KVO observer so the centering logic
        /// fires reliably even when PKCanvasView does not forward
        /// `UIScrollViewDelegate` callbacks.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentDuringZoom(scrollView)
            adaptiveEffectsEngine.zoomScale = scrollView.zoomScale
            // Zoom detent haptic + visual feedback (AGENT-23).
            interactionFeedback.updateZoom(scrollView.zoomScale, on: scrollView.layer)
            // Micro-bounce visual tick on detent entry (short-circuits on first match).
            let onDetent = InteractionFeedbackEngine.zoomDetents.first(where: { abs(scrollView.zoomScale - $0) < InteractionFeedbackEngine.detentTolerance }) != nil
            if onDetent && !wasOnZoomDetent {
                microInteractionEngine.playZoomDetentTick(on: scrollView.layer)
            }
            wasOnZoomDetent = onDetent
        }

        /// Adjusts content insets so the page stays centered when the scaled
        /// content is smaller than the viewport.
        private func centerContentDuringZoom(_ scrollView: UIScrollView) {
            let boundsSize  = scrollView.bounds.size
            let contentSize = scrollView.contentSize

            // Horizontal centering: when scaled content is narrower than viewport
            let xInset = max(0, (boundsSize.width  - contentSize.width)  / 2)
            // Vertical centering: when scaled content is shorter than viewport
            let yInset = max(0, (boundsSize.height - contentSize.height) / 2)

            scrollView.contentInset = UIEdgeInsets(
                top: yInset, left: xInset,
                bottom: yInset, right: xInset
            )

            syncBackgroundWithCanvas(scrollView)
        }
    }
}

// MARK: - PencilActionDelegate

extension CanvasView.Coordinator: PencilActionDelegate {

    // MARK: Tool switching

    func pencilDidRequestSwitchToEraser() {
        guard let canvas = canvasRef else { return }
        if !(canvas.tool is PKEraserTool) {
            // Remember current inking tool before switching to eraser.
            previousInkingTool = canvas.tool
        }
        canvas.tool = toolStoreRef?.makeEraserTool() ?? {
            if #available(iOS 16.4, *) {
                return PKEraserTool(.bitmap, width: EraserSubType.standard.defaultWidth)
            }
            return PKEraserTool(.bitmap)
        }()
        // Interaction feedback for eraser engage (AGENT-23).
        interactionFeedback.play(.eraserEngage, on: canvas.layer)
    }

    func pencilDidRequestSwitchToPreviousTool() {
        guard let canvas = canvasRef else { return }
        if let previous = previousInkingTool {
            canvas.tool = previous
            previousInkingTool = nil
        } else {
            // No previous tool recorded — toggle from eraser to default pen.
            canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        }
        // Interaction feedback for eraser disengage (AGENT-23).
        interactionFeedback.play(.eraserDisengage, on: canvas.layer)
    }

    // MARK: Contextual palette

    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint) {
        guard let canvas = canvasRef,
              let window = canvas.window else { return }
        // Convert from canvas coordinates to window coordinates.
        let windowPoint = canvas.convert(anchorPoint, to: window)
        let ts = toolStoreRef
        ContextualPencilPaletteView.show(
            at: windowPoint,
            in: window,
            canvas: canvas,
            eraserType: toolStoreRef?.eraserSubType.eraserMode.pkEraserType ?? .vector,
            onToolSelected: { [weak ts] pkTool in
                guard let ts else { return }
                if pkTool is PKEraserTool {
                    ts.activeTool = .eraser
                } else if let ink = pkTool as? PKInkingTool {
                    // Sync tool type.
                    switch ink.inkType {
                    case .pen:         ts.activeTool = .pen
                    case .pencil:      ts.activeTool = .pencil
                    case .marker:      ts.activeTool = .highlighter
                    case .fountainPen: ts.activeTool = .fountainPen
                    default:           break
                    }
                    // Sync color so the floating toolbar reflects the palette's choice.
                    ts.activeColor = ink.color
                }
            }
        )
    }

    // MARK: Undo / redo

    func pencilDidRequestUndo() {
        canvasRef?.undoManager?.undo()
        // Interaction feedback for undo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.undo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: true)
        }
    }

    func pencilDidRequestRedo() {
        canvasRef?.undoManager?.redo()
        // Interaction feedback for redo (AGENT-23).
        if let layer = canvasRef?.layer {
            interactionFeedback.play(.redo, on: layer)
            microInteractionEngine.playUndoFlash(in: layer, isUndo: false)
        }
    }

    // MARK: Double-tap delete

    func pencilDidRequestDeleteLastStroke() {
        deleteLastStroke()
    }

    // MARK: Hover preview

    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat) {
        let isErasing = canvasRef?.tool is PKEraserTool
        if isErasing {
            // Show sized eraser ring; hide ghost-nib overlay.
            let sub   = toolStoreRef?.eraserSubType ?? .standard
            let width = toolStoreRef?.eraserWidth   ?? sub.defaultWidth
            eraserCursorOverlay?.update(position: position, subType: sub, eraserWidth: width)
            hoverOverlay?.update(position: nil, altitude: altitude, azimuth: azimuth)
        } else {
            // Sync the ghost-nib appearance with the current tool state on every hover
            // event.  This is cheap and ensures the nib reflects a colour/width change
            // made while the pencil was already hovering.
            if let ts = toolStoreRef {
                let personality = ts.activePersonality
                let info = HoverToolInfo(
                    tool: ts.activeTool,
                    color: ts.activeColor,
                    width: CGFloat(ts.activeWidth),
                    opacity: CGFloat(ts.activeOpacity),
                    widthMultiplier: CGFloat(personality?.widthMultiplier ?? 1.0),
                    showsAzimuthLine: personality?.usesTiltShading == true
                                   || personality?.usesBarrelRoll  == true,
                    eraserMode: ts.eraserMode
                )
                hoverOverlay?.configure(with: info)
            }
            // Show ghost-nib; hide eraser ring.
            hoverOverlay?.update(position: position, altitude: altitude, azimuth: azimuth)
            eraserCursorOverlay?.update(position: nil, subType: .standard, eraserWidth: 0)
        }
    }

    // MARK: Barrel-roll fountain pen (Apple Pencil Pro, iOS 17.5+)

    func pencilBarrelRollChanged(angle: CGFloat) {
        guard #available(iOS 17.5, *), let canvas = canvasRef else { return }
        guard let inkTool = canvas.tool as? PKInkingTool,
              inkTool.inkType == .fountainPen else { return }

        // Use the stable base width captured at stroke start (not the current
        // tool width, which drifts if we've already modulated once).
        guard let baseWidth = barrelRollBaseWidth else { return }

        // Don't modulate while between strokes — let PencilKit keep its
        // native barrel-roll behaviour for the initial stroke setup.
        guard isDrawing else { return }

        // Map barrel-roll angle to a width variation that mimics a calligraphic nib:
        // • Roll  0 (neutral)       → base width
        // • Roll ±π/2 (edge-on)     → ~30 % of base width (thin stroke)
        // • Roll  π  (flipped)      → base width again (symmetrical)
        let rollFactor   = (cos(angle) + 1) / 2            // 0.0 … 1.0
        let minWidth     = max(baseWidth * 0.3, 1.0)
        let maxWidth     = baseWidth * 1.8
        let targetWidth  = minWidth + rollFactor * (maxWidth - minWidth)
        let clampedWidth = min(max(targetWidth, 1), 20)    // sane bounds

        // Only update when the change is visually meaningful to avoid
        // rebuilding PKInkingTool on every micro-movement.
        let currentWidth = inkTool.width
        if abs(clampedWidth - currentWidth) > 0.8 {
            canvas.tool = PKInkingTool(.fountainPen, color: inkTool.color, width: clampedWidth)
        }
    }
}
