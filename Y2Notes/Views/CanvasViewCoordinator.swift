import UIKit
import PencilKit
import OSLog
import SwiftUI

// MARK: - Performance instrumentation (coordinator)

private let editorLogger = Logger(subsystem: "com.y2notes.app", category: "editor")

enum PinchOverviewGestureTuning {
    /// Require pinch start near baseline zoom.
    /// 1.08 allows minor gesture jitter/zoom drift while still distinguishing
    /// an intentional "overview pinch" from normal zoomed-in navigation.
    static let maxStartZoomScale: CGFloat = 1.08
    /// Minimum pinch-in scale to count as an intentional overview request.
    /// 0.58 was chosen to require a decisive pinch-in and reduce accidental
    /// overview opens during routine zoom adjustments.
    static let triggerScale: CGFloat = 0.58
}

// MARK: - CanvasView.Coordinator

extension CanvasView {

    /// Reader-mode coordinator.
    ///
    /// Inherits all shared drawing lifecycle, object-layer handling, effects,
    /// Apple Pencil support, undo/redo, and background sync from
    /// `CanvasCoordinatorBase`.  Adds the two-finger page-swipe gesture that
    /// is unique to reader mode.
    final class Coordinator: CanvasCoordinatorBase {

        /// Page swipe callback: +1 next, −1 previous.
        let onPageSwipe: ((Int) -> Void)?

        /// Two-finger pan gesture recognizer for interactive page navigation.
        var pagePanGesture: UIPanGestureRecognizer?

        // ── Interactive page-drag state ──────────────────────────────
        private var pageIsDragging = false
        private var pageDragDirection: PageTransitionDirection = .forward

        /// Page-transition animation engine (stub – engine removed in Phase 4).
        let pageTransitionEngine = PageTransitionEngine()

        /// Light haptic feedback played when a page drag commits.
        private let pageTurnImpact: UIImpactFeedbackGenerator = {
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            return g
        }()

        init(
            onDrawingChanged: @escaping (Data) -> Void,
            onSaveRequested: @escaping () -> Void,
            onPageSwipe: ((Int) -> Void)? = nil,
            onPinchToOverview: (() -> Void)? = nil
        ) {
            self.onPageSwipe = onPageSwipe
            super.init(onDrawingChanged: onDrawingChanged, onSaveRequested: onSaveRequested)
            self.onPinchToOverview = onPinchToOverview
        }

        // MARK: - UIGestureRecognizerDelegate (override)

        /// Allows the page-overview pinch AND the page-pan to fire simultaneously
        /// with PKCanvasView's built-in gestures.
        override func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === pagePanGesture { return true }
            return super.gestureRecognizer(gestureRecognizer,
                                           shouldRecognizeSimultaneouslyWith: otherGestureRecognizer)
        }

        // MARK: - Page Gesture Handlers

        /// Tuning constants for the two-finger page-pan gesture recogniser.
        private enum PagePanTuning {
            static let horizontalDominanceRatio: CGFloat = 1.5
            static let minimumLockInDistance: CGFloat = 8
            static let reducedMotionCommitVelocity: CGFloat = 400
        }

        /// Two-finger pan handler for interactive page navigation.
        @objc func handlePagePan(_ gesture: UIPanGestureRecognizer) {
            guard !isDrawing, let view = gesture.view else { return }

            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            let pageWidth = view.bounds.width

            switch gesture.state {
            case .began:
                pageIsDragging = false

            case .changed:
                if !pageIsDragging {
                    guard abs(translation.x) > abs(translation.y) * PagePanTuning.horizontalDominanceRatio,
                          abs(translation.x) > PagePanTuning.minimumLockInDistance
                    else { return }

                    let dir: PageTransitionDirection = translation.x < 0 ? .forward : .backward
                    if dir == .backward && coordinatorPageIndex == 0 { return }

                    if pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                        pageDragDirection = dir
                        pageIsDragging = true
                        pageTransitionEngine.beginInteractiveDrag(
                            on: view, direction: dir, pageWidth: pageWidth
                        )
                    }
                }

                if pageIsDragging {
                    pageTransitionEngine.updateInteractiveDrag(
                        on: view, translation: translation.x, pageWidth: pageWidth
                    )
                }

            case .ended:
                if pageIsDragging {
                    pageIsDragging = false
                    let pageSwitchStart = Date()
                    pageTransitionEngine.finishInteractiveDrag(
                        on: view, velocityX: velocity.x, pageWidth: pageWidth
                    ) { [weak self] committed in
                        guard let self, committed else { return }
                        let pageSwitchDuration = Date().timeIntervalSince(pageSwitchStart) * 1000
                        Task { @MainActor in
                            PerformanceMonitor.shared.recordPageSwitch(durationMs: pageSwitchDuration)
                        }
                        self.flushPendingSave()
                        self.pageTurnImpact.impactOccurred()
                        self.pageTurnImpact.prepare()
                        self.onPageSwipe?(self.pageDragDirection == .forward ? 1 : -1)
                    }
                } else if !pageTransitionEngine.effectIntensity.allowsPageTurnPhysics {
                    guard abs(velocity.x) > PagePanTuning.reducedMotionCommitVelocity,
                          abs(velocity.x) > abs(velocity.y) * PagePanTuning.horizontalDominanceRatio
                    else { return }
                    let dir: PageTransitionDirection = velocity.x < 0 ? .forward : .backward
                    guard !(dir == .backward && coordinatorPageIndex == 0) else { return }
                    let pageSwitchStart = Date()
                    flushPendingSave()
                    let pageSwitchDuration = Date().timeIntervalSince(pageSwitchStart) * 1000
                    Task { @MainActor in
                        PerformanceMonitor.shared.recordPageSwitch(durationMs: pageSwitchDuration)
                    }
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
    }
}
