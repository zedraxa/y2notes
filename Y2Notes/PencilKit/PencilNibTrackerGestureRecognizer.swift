import UIKit

// MARK: - PencilNibTrackerGestureRecognizer

/// A passive gesture recognizer that tracks Apple Pencil contact positions at
/// the hardware's full touch-delivery rate (up to 240Hz on ProMotion iPads).
///
/// **Purpose**: update ink-effect emitter and glow layer positions in real time
/// while the user draws, instead of waiting for `canvasViewDrawingDidChange`
/// which only fires when PencilKit commits batched stroke-point data.
///
/// **Passivity guarantee**: `cancelsTouchesInView = false` and
/// `delaysTouchesBegan/Ended = false` mean PencilKit's drawing recognizer
/// receives every touch event unmodified.
///
/// **Usage:**
/// ```swift
/// let tracker = PencilNibTrackerGestureRecognizer()
/// tracker.onNibMoved = { [weak effects] location, force, velocity in
///     guard isDrawing, tool is PKInkingTool else { return }
///     effects?.dispatch(.strokeUpdated(at: location,
///                                      pressure: force,
///                                      velocity: velocity))
/// }
/// canvasView.addGestureRecognizer(tracker)
/// ```
final class PencilNibTrackerGestureRecognizer: UIGestureRecognizer {

    // MARK: - Callback

    /// Called on the main thread when the pencil first contacts the screen.
    ///
    /// - Parameters:
    ///   - location: First pencil contact location in the recognizer's view space.
    var onNibBegan: ((_ location: CGPoint) -> Void)?

    /// Called on the main thread for every pencil `touchesMoved` event.
    ///
    /// - Parameters:
    ///   - location:  Current pencil tip location in the gesture recognizer's
    ///                view coordinate space (PKCanvasView bounds space).
    ///   - force:     Normalized applied force (0–1+ scale; `UITouch.maximumPossibleForce`
    ///                is the ceiling on supported hardware; falls back to 1.0 when
    ///                force is not available).
    ///   - velocity:  Instantaneous tip speed in points per second, computed from
    ///                consecutive touch positions and timestamps.
    var onNibMoved: ((_ location: CGPoint, _ force: CGFloat, _ velocity: CGFloat) -> Void)?

    // MARK: - Private State

    private var prevLocation:  CGPoint      = .zero
    private var prevTimestamp: TimeInterval = 0

    // MARK: - Init

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        configure()
    }

    private func configure() {
        // Never cancel or delay touches going to PencilKit's own recognizer.
        cancelsTouchesInView  = false
        delaysTouchesBegan    = false
        delaysTouchesEnded    = false
        // Only respond to Apple Pencil contacts, not finger touches.
        allowedTouchTypes = [UITouch.TouchType.pencil.rawValue as NSNumber]
    }

    // MARK: - Touch Forwarding

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let pencil = firstPencilTouch(in: touches) {
            prevLocation  = pencil.location(in: view)
            prevTimestamp = pencil.timestamp
            state = .began
            onNibBegan?(prevLocation)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let pencil = firstPencilTouch(in: touches) else { return }

        let location  = pencil.location(in: view)
        let force     = pencil.force > 0 ? pencil.force : 1.0
        let dt        = pencil.timestamp - prevTimestamp
        let velocity: CGFloat
        if dt > 0 {
            let dx = location.x - prevLocation.x
            let dy = location.y - prevLocation.y
            velocity = sqrt(dx * dx + dy * dy) / CGFloat(dt)
        } else {
            // Fallback when two consecutive events share the same timestamp.
            // 500 pt/s is a moderate writing speed — roughly mid-range for
            // deliberate handwriting, independent of VelocityThicknessParams.
            velocity = 500
        }
        prevLocation  = location
        prevTimestamp = pencil.timestamp

        state = .changed
        onNibMoved?(location, force, velocity)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    // MARK: - Helpers

    private func firstPencilTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .pencil }
    }
}
