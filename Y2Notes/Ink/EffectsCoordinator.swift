import UIKit

// MARK: - Canvas Event

/// Typed description of a single canvas lifecycle moment.
///
/// `EffectsCoordinator.dispatch(_:inkEffectEngine:)` accepts a `CanvasEvent`
/// and fans it out to every interested engine in one call.
///
/// **Coordinate space**: all `CGPoint` values are in **viewport**
/// coordinates (the canvas view's own bounds space), matching what each engine
/// expects for overlay positioning.
enum CanvasEvent {
    /// The user's pencil just touched the canvas.  The nib position is
    /// approximate (bounds midpoint) because the stroke is not committed yet.
    case strokeBegan(at: CGPoint, inkColor: UIColor)

    /// A live stroke update — called for every new `PKStrokePoint` appended.
    /// `pressure` is `PKStrokePoint.force` (0–1 normalised).
    /// `velocity` is the instantaneous inter-point speed in points/second.
    case strokeUpdated(at: CGPoint, pressure: CGFloat, velocity: CGFloat)

    /// The pencil lifted.  The last committed stroke's geometry is provided.
    case strokeEnded(at: CGPoint, start: CGPoint, inkColor: UIColor)
}

// MARK: - Sensory Context

/// Lightweight value that tracks the user's current writing dynamics.
///
/// Updated automatically by `EffectsCoordinator.dispatch(_:)` on every
/// `.strokeUpdated` event.  Engines can read `coordinator.sensoryContext`
/// to modulate their output — for example, emitting more energetic particles
/// during fast dynamic writing and soft glow during deliberate strokes.
///
/// **Thread safety**: mutated exclusively on the main thread inside the
/// `@MainActor`-isolated `EffectsCoordinator`.
struct SensoryContext {

    // MARK: Writing Rhythm

    /// Qualitative writing rhythm derived from smoothed velocity.
    enum WritingRhythm: Equatable {
        case still        // pen not moving   (< 80 pts/s)
        case deliberate   // careful, slow    (80 – 300 pts/s)
        case moderate     // normal handwriting (300 – 700 pts/s)
        case dynamic      // fast, energetic  (> 700 pts/s)

        fileprivate init(velocity v: CGFloat) {
            switch v {
            case ..<80:   self = .still
            case ..<300:  self = .deliberate
            case ..<700:  self = .moderate
            default:      self = .dynamic
            }
        }
    }

    // MARK: State

    /// Exponentially smoothed stroke velocity (points/second).
    private(set) var smoothedVelocity: CGFloat = 0

    /// Current writing rhythm derived from `smoothedVelocity`.
    private(set) var rhythm: WritingRhythm = .still

    // MARK: Update

    private static let smoothingAlpha: CGFloat = 0.25

    mutating func update(velocity: CGFloat) {
        smoothedVelocity = Self.smoothingAlpha * velocity
                         + (1 - Self.smoothingAlpha) * smoothedVelocity
        rhythm = WritingRhythm(velocity: smoothedVelocity)
    }

    /// Call when the pencil lifts — decays velocity toward zero so that the
    /// rhythm eventually returns to `.still` after a writing pause.
    mutating func decay() {
        smoothedVelocity *= 0.5
        rhythm = WritingRhythm(velocity: smoothedVelocity)
    }
}

// MARK: - Effects Coordinator

/// Central mediator that owns all effect engines and dispatches canvas events.
///
/// `EffectsCoordinator` provides event dispatch — `dispatch(_:inkEffectEngine:)`
/// accepts a typed `CanvasEvent` and routes it to every engine that cares.
///
/// **Usage:**
/// ```swift
/// let effects = EffectsCoordinator()
///
/// // Stroke lifecycle:
/// effects.dispatch(.strokeBegan(at: pt, inkColor: color), inkEffectEngine: engine)
/// effects.dispatch(.strokeUpdated(at: pt, pressure: p, velocity: v), inkEffectEngine: engine)
/// effects.dispatch(.strokeEnded(at: end, start: start, inkColor: color), inkEffectEngine: engine)
/// ```
@MainActor
final class EffectsCoordinator {

    // MARK: - Engines

    /// Physical page-turn effects.
    let pageTransitionEngine = PageTransitionEngine()

    /// Core writing effects (fire, sparkle).
    let writingEffectsPipeline = WritingEffectsPipeline()

    /// Physical micro-interactions (tap ripple, selection glow, snap bounce, etc.).
    let microInteractionEngine = MicroInteractionEngine()

    /// Visual feedback for snap/alignment events.
    let snapAlignEffectEngine = SnapAlignEffectEngine()

    /// Centralized haptic + visual feedback for UI interactions.
    let interactionFeedbackEngine = InteractionFeedbackEngine()

    // MARK: - Sensory Context

    /// Live snapshot of the user's current writing dynamics.
    ///
    /// Updated automatically by `dispatch(_:)` on every `.strokeUpdated` and
    /// decayed on `.strokeEnded`.  Engines may query this to modulate their
    /// output for a coherent, context-aware sensory experience.
    private(set) var sensoryContext: SensoryContext = SensoryContext()

    // MARK: - Layout Distribution

    /// Updates layout for canvas overlays.
    func distribute(
        shapeCanvas: UIView? = nil,
        attachmentCanvas: UIView? = nil,
        widgetCanvas: UIView? = nil,
        stickerCanvas: UIView? = nil
    ) {
        // Currently just a placeholder for future canvas-specific updates
    }

    // MARK: - Canvas Event Dispatch

    /// Single intake point for all stroke lifecycle events.
    ///
    /// The coordinator fans the event out to interested engines and updates
    /// `sensoryContext` for dynamic effect modulation.
    ///
    /// - Parameters:
    ///   - event: The typed canvas event.
    ///   - inkEffectEngine: The optional per-session `InkEffectEngine`.
    func dispatch(_ event: CanvasEvent, inkEffectEngine: InkEffectEngine? = nil) {
        switch event {

        case .strokeBegan(let at, _):
            inkEffectEngine?.onStrokeBegan(at: at)
            writingEffectsPipeline.onStrokeBegan(at: at)

        case .strokeUpdated(let at, let pressure, let velocity):
            inkEffectEngine?.onStrokeUpdated(at: at, pressure: pressure, velocity: velocity)
            writingEffectsPipeline.onStrokeUpdated(at: at, pressure: pressure, velocity: velocity)
            sensoryContext.update(velocity: velocity)

        case .strokeEnded(let at, _, _):
            inkEffectEngine?.onStrokeEnded(at: at)
            writingEffectsPipeline.onStrokeEnded()
            sensoryContext.decay()
        }
    }

    // MARK: - Layout Sync

    /// Forwards a layout update to layout-sensitive engines.
    func updateLayout(containerBounds: CGRect) {
        // Currently minimal - engines handle their own layout if needed
    }
}
