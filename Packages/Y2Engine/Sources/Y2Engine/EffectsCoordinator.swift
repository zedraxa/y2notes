import UIKit
import Combine
import Y2Core

// MARK: - Canvas Event

/// Typed description of a single canvas lifecycle moment.
///
/// `EffectsCoordinator.dispatch(_:inkEffectEngine:)` accepts a `CanvasEvent`
/// and fans it out to every interested engine in one call, replacing the
/// previous pattern of calling three separate engine methods from
/// `NoteEditorView.Coordinator`.
///
/// **Coordinate space**: all `CGPoint` and `CGRect` values are in **viewport**
/// coordinates (the canvas view's own bounds space), matching what each engine
/// expects for overlay positioning.
public enum CanvasEvent {
    /// The user's pencil just touched the canvas.  The nib position is
    /// approximate (bounds midpoint) because the stroke is not committed yet.
    case strokeBegan(at: CGPoint, inkColor: UIColor)

    /// A live stroke update — called for every new `PKStrokePoint` appended.
    /// `pressure` is `PKStrokePoint.force` (0–1 normalised).
    /// `velocity` is the instantaneous inter-point speed in points/second.
    case strokeUpdated(at: CGPoint, pressure: CGFloat, velocity: CGFloat)

    /// The pencil lifted.  The last committed stroke's geometry is provided.
    /// `headingBounds` is the stroke's `renderBounds` converted to viewport
    /// space; used by `StudyModeEngine` for heading-glow detection.
    case strokeEnded(at: CGPoint, start: CGPoint, inkColor: UIColor, headingBounds: CGRect)
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
public struct SensoryContext {

    // MARK: Writing Rhythm

    /// Qualitative writing rhythm derived from smoothed velocity.
    public enum WritingRhythm: Equatable {
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
    public private(set) var smoothedVelocity: CGFloat = 0

    /// Current writing rhythm derived from `smoothedVelocity`.
    public private(set) var rhythm: WritingRhythm = .still

    // MARK: Update

    private static let smoothingAlpha: CGFloat = 0.25

    public mutating func update(velocity: CGFloat) {
        smoothedVelocity = Self.smoothingAlpha * velocity
                         + (1 - Self.smoothingAlpha) * smoothedVelocity
        rhythm = WritingRhythm(velocity: smoothedVelocity)
    }

    /// Call when the pencil lifts — decays velocity toward zero so that the
    /// rhythm eventually returns to `.still` after a writing pause.
    public mutating func decay() {
        smoothedVelocity *= 0.5
        rhythm = WritingRhythm(velocity: smoothedVelocity)
    }
}

// MARK: - Effects Coordinator

/// Central mediator that owns all effect engines and dispatches canvas events.
///
/// `EffectsCoordinator` provides two services:
///
/// 1. **Intensity distribution** — `AdaptiveEffectsEngine.intensity` is
///    propagated to every sub-engine automatically via Combine.
///
/// 2. **Event dispatch** — `dispatch(_:inkEffectEngine:)` accepts a typed
///    `CanvasEvent` and routes it to every engine that cares, replacing the
///    previous pattern of making three separate engine calls from
///    `NoteEditorView.Coordinator` for every stroke lifecycle event.
///
/// **Usage:**
/// ```swift
/// let effects = EffectsCoordinator()
///
/// // Stroke lifecycle (replaces 3 separate engine calls):
/// effects.dispatch(.strokeBegan(at: pt, inkColor: color), inkEffectEngine: engine)
/// effects.dispatch(.strokeUpdated(at: pt, pressure: p, velocity: v), inkEffectEngine: engine)
/// effects.dispatch(.strokeEnded(at: end, start: start, inkColor: color,
///                               headingBounds: bounds), inkEffectEngine: engine)
///
/// // Mode activation:
/// effects.setMagicMode(active: true, on: canvasView.layer)
/// effects.setStudyMode(active: true, on: canvasView.layer)
///
/// // Notebook complexity signals:
/// effects.adaptiveEngine.pageCount = pageCount
/// effects.adaptiveEngine.currentPageStrokeCount = strokeCount
/// ```
@MainActor
public final class EffectsCoordinator {

    // MARK: - Engines

    /// Evaluates context signals and publishes the current `EffectIntensity`.
    public let adaptiveEngine = AdaptiveEffectsEngine()

    /// Physical page-turn effects.
    public let pageTransitionEngine = PageTransitionEngine()

    /// Background dim / vignette when focus mode is active.
    public let focusModeEngine = FocusModeEngine()

    /// Ambient mood scenes (rain, lo-fi, night grain).
    public let ambientEngine = AmbientEnvironmentEngine()

    /// Writing particles, keyword glow, underline highlights.
    public let magicModeEngine = MagicModeEngine()

    /// Heading recognition glow, checklist pulse, timer overlay.
    public let studyModeEngine = StudyModeEngine()

    /// Core + advanced writing effects (glow pen, neon ink, ink trail, gradient ink).
    public let writingEffectsPipeline = WritingEffectsPipeline()

    /// Physical micro-interactions (tap ripple, selection glow, snap bounce, etc.).
    public let microInteractionEngine = MicroInteractionEngine()

    /// Visual feedback for snap/alignment events.
    public let snapAlignEffectEngine = SnapAlignEffectEngine()

    /// Centralized haptic + visual feedback for UI interactions.
    public let interactionFeedbackEngine = InteractionFeedbackEngine()

    // MARK: - Sensory Context

    /// Live snapshot of the user's current writing dynamics.
    ///
    /// Updated automatically by `dispatch(_:)` on every `.strokeUpdated` and
    /// decayed on `.strokeEnded`.  Engines may query this to modulate their
    /// output for a coherent, context-aware sensory experience.
    public private(set) var sensoryContext: SensoryContext = SensoryContext()

    // MARK: - Private

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    public init() {
        // Automatically distribute intensity to all sub-engines when it changes.
        adaptiveEngine.$intensity
            .receive(on: RunLoop.main)
            .sink { [weak self] intensity in
                self?.distribute(intensity: intensity)
            }
            .store(in: &cancellables)
    }

    // MARK: - Intensity Distribution

    /// Propagates `intensity` to all engines owned by this coordinator.
    ///
    /// Also call with optional canvas view references to update their
    /// internal snap/micro engines.
    public func distribute(
        intensity: EffectIntensity,
        shapeCanvas: (any EffectIntensityReceiver)? = nil,
        attachmentCanvas: (any EffectIntensityReceiver)? = nil,
        widgetCanvas: (any EffectIntensityReceiver)? = nil,
        stickerCanvas: (any EffectIntensityReceiver)? = nil
    ) {
        pageTransitionEngine.effectIntensity = intensity
        focusModeEngine.effectIntensity = intensity
        ambientEngine.effectIntensity = intensity
        magicModeEngine.effectIntensity = intensity
        studyModeEngine.effectIntensity = intensity
        writingEffectsPipeline.effectIntensity = intensity
        microInteractionEngine.effectIntensity = intensity
        snapAlignEffectEngine.effectIntensity = intensity
        interactionFeedbackEngine.effectIntensity = intensity
        shapeCanvas?.effectIntensity = intensity
        attachmentCanvas?.effectIntensity = intensity
        widgetCanvas?.effectIntensity = intensity
        stickerCanvas?.effectIntensity = intensity
    }

    // MARK: - Mode Lifecycle

    /// Activates or deactivates magic mode on the given canvas layer.
    public func setMagicMode(active: Bool, on layer: CALayer) {
        if active, !magicModeEngine.isActive {
            magicModeEngine.activate(on: layer)
        } else if !active, magicModeEngine.isActive {
            magicModeEngine.deactivate()
        }
    }

    /// Activates or deactivates study mode on the given canvas layer.
    public func setStudyMode(active: Bool, on layer: CALayer) {
        if active, !studyModeEngine.isActive {
            studyModeEngine.activate(on: layer)
        } else if !active, studyModeEngine.isActive {
            studyModeEngine.deactivate()
        }
    }

    // MARK: - Canvas Event Dispatch

    /// Single intake point for all stroke lifecycle events.
    ///
    /// Replaces the previous pattern of calling three separate engine methods
    /// from `NoteEditorView.Coordinator` on every stroke event.  The coordinator
    /// fans the event out to every interested engine and updates `sensoryContext`.
    ///
    /// - Parameters:
    ///   - event: The typed canvas event.
    ///   - inkEffectEngine: The optional per-session `InkEffectEngine` (not owned
    ///     by this coordinator because it requires a `DeviceCapabilityTier` at
    ///     init time and is created by the editor coordinator).
    public func dispatch(_ event: CanvasEvent, inkEffectEngine: InkEffectEngine? = nil) {
        switch event {

        case .strokeBegan(let at, let inkColor):
            inkEffectEngine?.onStrokeBegan(at: at)
            writingEffectsPipeline.onStrokeBegan(at: at)
            if magicModeEngine.isActive {
                magicModeEngine.strokeBegan(at: at, inkColor: inkColor)
            }

        case .strokeUpdated(let at, let pressure, let velocity):
            inkEffectEngine?.onStrokeUpdated(at: at)
            writingEffectsPipeline.onStrokeUpdated(at: at, pressure: pressure, velocity: velocity)
            if magicModeEngine.isActive {
                magicModeEngine.strokeMoved(to: at)
            }
            sensoryContext.update(velocity: velocity)

        case .strokeEnded(let at, let start, let inkColor, let headingBounds):
            inkEffectEngine?.onStrokeEnded(at: at)
            writingEffectsPipeline.onStrokeEnded()
            if magicModeEngine.isActive {
                magicModeEngine.strokeEnded(at: at, startPoint: start, inkColor: inkColor)
            }
            if studyModeEngine.isActive {
                studyModeEngine.headingGlow(at: headingBounds)
            }
            sensoryContext.decay()
        }
    }

    // MARK: - Layout Sync

    /// Forwards a layout update to all active, layout-sensitive engines.
    public func updateLayout(containerBounds: CGRect) {
        if magicModeEngine.isActive {
            magicModeEngine.updateLayout(containerBounds: containerBounds)
        }
        if ambientEngine.activeScene != nil {
            ambientEngine.updateLayout(containerBounds: containerBounds)
        }
        if focusModeEngine.isActive {
            focusModeEngine.updateLayout(containerBounds: containerBounds)
        }
    }
}

// MARK: - Effect Intensity Receiver

/// Describes a canvas view that accepts an `EffectIntensity` update.
///
/// All four canvas overlay views (`ShapeCanvasView`, `AttachmentCanvasView`,
/// `WidgetCanvasView`, `StickerCanvasView`) satisfy this protocol through
/// their existing `effectIntensity` property.
public protocol EffectIntensityReceiver: AnyObject {
    public var effectIntensity: EffectIntensity { get set }
}
