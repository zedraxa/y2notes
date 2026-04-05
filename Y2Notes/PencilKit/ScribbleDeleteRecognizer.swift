import UIKit

// MARK: - ScribbleDeleteRecognizer

/// Passive gesture recognizer that detects a "scratch-to-delete" pencil gesture —
/// a rapid back-and-forth horizontal motion drawn over existing ink — without
/// preventing PencilKit from drawing.  When the pattern is confirmed,
/// `onScratchDetected` is called with the bounding rectangle of the gesture in
/// the recognizer's view coordinate space.
///
/// ## Disambiguation from handwriting
/// Five independent gates ensure normal handwriting is never mistaken for a scratch:
///
/// 1. **Direction reversals** — the pencil must change horizontal direction
///    ≥ ``Tuning/minReversals`` times (filters individual letters such as "m", "w", "z").
/// 2. **Horizontal span** — bounding-box width must exceed ``Tuning/minHorizontalSpan``
///    (filters tiny stray marks).
/// 3. **Aspect ratio** — width ÷ height must exceed ``Tuning/minAspectRatio``,
///    guaranteeing predominantly horizontal motion (filters tall or round letterforms).
/// 4. **Velocity** — average drawing speed must exceed ``Tuning/minVelocity`` pt/s
///    (filters slow, deliberate handwriting strokes).
/// 5. **Path length** — total pencil travel must exceed ``Tuning/minPathLength`` pt
///    (filters short flicks or accidental edge contacts).
///
/// ## Passive design
/// The recognizer is *always* passive:
/// - Never transitions to `.began` / `.changed` / `.ended`; always ends in `.failed`.
/// - Does not cancel or prevent any other gesture recognizer.
/// - Processes only Apple Pencil touches (`UITouch.TouchType.pencil`); finger
///   touches are ignored completely.
/// - `cancelsTouchesInView`, `delaysTouchesBegan`, and `delaysTouchesEnded` are all
///   `false` to guarantee zero interference with PencilKit's own recognizer.
final class ScribbleDeleteRecognizer: UIGestureRecognizer {

    // MARK: Callback

    /// Called on the main thread immediately after a scratch gesture is confirmed.
    ///
    /// - Parameter rect: Bounding rectangle of the gesture in the recognizer's
    ///   `view` coordinate space (viewport / scroll-view bounds coordinates).
    var onScratchDetected: ((CGRect) -> Void)?

    // MARK: Tuning

    /// Detection thresholds.  All constants are deliberately conservative to
    /// minimise false positives against fast handwriting.
    enum Tuning {
        /// Minimum number of horizontal direction reversals required.
        /// A value of 4 requires a motion pattern of at least ←→←→← or →←→←→,
        /// which is difficult to produce unintentionally while writing.
        static let minReversals: Int = 4

        /// Minimum bounding-box width (pt) of the gesture.
        static let minHorizontalSpan: CGFloat = 45

        /// Minimum width-to-height ratio of the bounding box.
        /// Ensures motion is predominantly horizontal.
        static let minAspectRatio: CGFloat = 2.2

        /// Minimum total path length (pt) of the pencil tip during the gesture.
        static let minPathLength: CGFloat = 90

        /// Maximum allowed gesture duration in seconds.
        /// Prevents very slow back-and-forth motions (e.g. careful erasing with
        /// an inking tool) from being misclassified.
        static let maxDuration: TimeInterval = 2.5

        /// Minimum average pencil speed in points per second.
        /// Scratch gestures are inherently fast; slow deliberate strokes are excluded.
        static let minVelocity: CGFloat = 200

        /// Minimum horizontal displacement from the last accepted reversal point
        /// before a new direction change is counted.  Filters high-frequency tremor
        /// noise and tiny wobbles at the apex of each back-and-forth pass.
        static let reversalMinAdvance: CGFloat = 12
    }

    // MARK: Private state

    private var collectedPoints: [CGPoint] = []
    private var startTimestamp: TimeInterval = 0
    private var endTimestamp: TimeInterval = 0

    // MARK: Initialiser

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Never delay or cancel touches — let PKCanvasView receive everything
        // simultaneously so the user's ink is drawn in real time.
        cancelsTouchesInView = false
        delaysTouchesBegan   = false
        delaysTouchesEnded   = false
    }

    // MARK: Passive conflict resolution

    override func canPrevent(_ preventedRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    // MARK: Touch collection

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        collectedPoints.removeAll(keepingCapacity: true)
        guard let touch = touches.first, touch.type == .pencil else { return }
        startTimestamp = touch.timestamp
        endTimestamp   = touch.timestamp
        collectedPoints.append(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        // Collect coalesced touches for maximum spatial accuracy — coalesced
        // touches are the full-rate Apple Pencil samples that UIKit batches into
        // a single delivery for efficiency.
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for t in coalesced {
            collectedPoints.append(t.location(in: view))
        }
        endTimestamp = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, touch.type == .pencil {
            endTimestamp = touch.timestamp
            collectedPoints.append(touch.location(in: view))
        }
        // Analyse synchronously while the data is still fresh, then transition
        // to .failed so the recognizer resets for the next touch sequence.
        if let scratchRect = analyzeForScratch() {
            onScratchDetected?(scratchRect)
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        collectedPoints.removeAll(keepingCapacity: true)
        state = .failed
    }

    // MARK: Scratch detection

    /// Analyses ``collectedPoints`` and returns the bounding rectangle of the
    /// gesture if all five detection gates pass; returns `nil` otherwise.
    private func analyzeForScratch() -> CGRect? {
        let pts = collectedPoints
        // Need at least a few samples to compute reliable statistics.
        guard pts.count >= 6 else { return nil }

        // ── Gate 1 + 3: Bounding box, horizontal span, aspect ratio ──────────
        var minX = pts[0].x, maxX = pts[0].x
        var minY = pts[0].y, maxY = pts[0].y
        for p in pts {
            if p.x < minX { minX = p.x }; if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }; if p.y > maxY { maxY = p.y }
        }
        let width  = maxX - minX
        let height = maxY - minY

        guard width >= Tuning.minHorizontalSpan else { return nil }

        // Guard against zero height to avoid division-by-zero on perfectly
        // flat strokes; treat them as infinitely horizontal (always pass).
        let aspect = width / max(height, 1)
        guard aspect >= Tuning.minAspectRatio else { return nil }

        // ── Gate 4: Path length ───────────────────────────────────────────────
        var pathLength: CGFloat = 0
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i-1].x
            let dy = pts[i].y - pts[i-1].y
            pathLength += (dx * dx + dy * dy).squareRoot()
        }
        guard pathLength >= Tuning.minPathLength else { return nil }

        // ── Gate 5: Duration and average velocity ─────────────────────────────
        let duration = endTimestamp - startTimestamp
        // A zero-duration stroke (single-tap sample) cannot be a scratch.
        guard duration > 0, duration <= Tuning.maxDuration else { return nil }

        let velocity = pathLength / CGFloat(duration)
        guard velocity >= Tuning.minVelocity else { return nil }

        // ── Gate 2: Direction-reversal count ──────────────────────────────────
        guard countHorizontalReversals(in: pts) >= Tuning.minReversals else { return nil }

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Returns the number of times the horizontal movement direction reverses
    /// in `points`, ignoring oscillations smaller than `Tuning.reversalMinAdvance`.
    ///
    /// The noise filter works by recording the x-position at the last accepted
    /// reversal and requiring the pencil to travel at least `reversalMinAdvance`
    /// points in the new direction before the change is counted.  This eliminates
    /// high-frequency tremor and the tiny overshoot that occurs at each apex.
    private func countHorizontalReversals(in points: [CGPoint]) -> Int {
        var reversals     = 0
        var direction     = 0  // +1 = moving right, -1 = moving left, 0 = undecided
        var lastReversalX = points[0].x

        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            // Ignore sub-pixel jitter — touches at the exact same x are neutral.
            guard abs(dx) > 0.3 else { continue }

            let newDir = dx > 0 ? 1 : -1

            if direction == 0 {
                // First discernible horizontal movement: establish initial direction.
                direction = newDir
            } else if newDir != direction {
                // Candidate reversal — only accept if horizontal advance since the
                // last accepted reversal exceeds the noise floor.
                let advance = abs(points[i].x - lastReversalX)
                if advance >= Tuning.reversalMinAdvance {
                    reversals    += 1
                    direction     = newDir
                    lastReversalX = points[i].x
                }
            }
        }
        return reversals
    }
}
