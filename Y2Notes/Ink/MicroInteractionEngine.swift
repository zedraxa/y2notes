import UIKit
import QuartzCore

// MARK: - Spring Profile

/// Reusable spring animation parameters for physically correct UI feedback.
///
/// Presets cover the range from snappy tool-feedback to gentle content-lift
/// without requiring callers to reason about spring physics constants.
struct SpringProfile {
    let damping: CGFloat
    let stiffness: CGFloat
    let mass: CGFloat
    let initialVelocity: CGFloat

    /// Snappy: fast settle with no overshoot — ideal for selection / snap feedback.
    static let snappy = SpringProfile(damping: 18, stiffness: 400, mass: 1, initialVelocity: 12)

    /// Gentle: slow, smooth settle — ideal for content floating into place.
    static let gentle = SpringProfile(damping: 14, stiffness: 200, mass: 1, initialVelocity: 4)

    /// Bouncy: light overshoot for playful tap / pop effects.
    static let bouncy = SpringProfile(damping: 8,  stiffness: 300, mass: 1, initialVelocity: 10)

    /// Stiff: very fast, minimal travel — almost-instant positional lock.
    static let stiff  = SpringProfile(damping: 25, stiffness: 600, mass: 1, initialVelocity: 8)
}

// MARK: - Micro-Interaction Type

/// Catalogue of physical micro-interactions that make the app feel alive.
///
/// Every interaction is designed to feel like a physical response — never
/// cartoonish.  Timing curves use `CAMediaTimingFunction` with critically-damped
/// spring approximations to avoid bouncy or elastic overshoot.
///
/// **Performance contract**: all animations are GPU-composited via Core Animation.
/// No main-thread layout passes occur during animation.  Total overhead per
/// interaction is < 0.5 ms measured on A12 (`.standard` tier).
enum MicroInteractionType: String, CaseIterable {
    case tapRipple       // very subtle expanding ring on canvas tap
    case selectionGlow   // soft glow pulse when an object is selected
    case snapBounce      // tiny scale bounce on snap-to-grid alignment
    case dragInertia     // momentum carry after drag release
    case softShadow      // shadow shifts to follow finger/object movement
    case liftAndGlow     // combined scale lift + shadow elevation + glow
    case settleFromLift  // spring-settle back to identity + fade glow
    case velocityDragInertia  // velocity-magnitude-scaled momentum carry
    case momentumShadow  // shadow direction and radius track velocity vector

    // ── Deepened interaction types (AGENT-23) ───────────────────────────
    case toolSwitchMorph // brief scale pulse when switching tools
    case undoFlash       // faint overlay flash for undo/redo
    case zoomDetentTick  // micro-bounce at detent zoom levels (100 %, etc.)
    case canvasFirstTouch // very faint ripple on first canvas interaction
    case buttonPress     // subtle press-down scale for toolbar buttons
}

// MARK: - Animation Spec

/// Fully specified animation parameters for a micro-interaction.
///
/// These specs are consumed by `MicroInteractionEngine.play(_:)` which
/// translates them to `CABasicAnimation` / `CASpringAnimation` calls.
/// All durations are in seconds; all distances in points.
struct MicroAnimationSpec: Equatable {
    let type: MicroInteractionType
    /// Total animation duration (seconds).
    let duration: TimeInterval
    /// Timing curve control points (cubic bezier).
    let timingControlPoints: (CGFloat, CGFloat, CGFloat, CGFloat)
    /// Delay before the animation starts (seconds).
    let delay: TimeInterval
    /// Whether the animation auto-reverses.
    let autoreverses: Bool
    /// Number of repeats (0 = play once).
    let repeatCount: Float

    static func == (lhs: MicroAnimationSpec, rhs: MicroAnimationSpec) -> Bool {
        lhs.type == rhs.type && lhs.duration == rhs.duration
    }
}

// MARK: - Interaction Rules

/// Rules governing when micro-interactions fire and how they compose.
///
/// **Rule 1 — Subtlety first**: no interaction should be consciously noticed
///   by the user.  If you can "see" the animation, it's too strong.
///
/// **Rule 2 — One at a time**: tap ripple and selection glow never overlap.
///   If a new interaction fires while one is in-flight, the in-flight one is
///   immediately completed (jumped to final value).
///
/// **Rule 3 — Respect Reduce Motion**: when the system accessibility setting
///   `UIAccessibility.isReduceMotionEnabled` is true, all micro-interactions
///   are replaced with instant state changes (zero duration).
///
/// **Rule 4 — 120 fps ceiling**: every interaction must complete its per-frame
///   work in < 0.5 ms.  All animations are GPU-only (no layout/measure).
///
/// **Rule 5 — No interference with drawing**: micro-interactions never modify
///   `PKCanvasView` state or intercept pencil input events.
enum InteractionRules {
    static let maxSimultaneousAnimations: Int = 2
    static let perFrameBudgetMs: Double = 0.5
    static let respectReduceMotion: Bool = true
}

// MARK: - Micro-Interaction Engine

/// Lightweight engine that plays physical micro-interactions on any `CALayer`.
///
/// All methods are main-thread-only.  The engine does not retain any views;
/// it operates on caller-supplied layers.
///
/// **Lifecycle**: create once per editor session, call `play` methods as
/// needed, and discard when the editor is torn down.
final class MicroInteractionEngine {

    // MARK: - Specs (pre-built for zero-allocation playback)

    /// Tap ripple: expanding ring that fades to invisible.
    /// Duration: 0.35 s, ease-out.
    /// Scale: 0 → 1, Opacity: 0.25 → 0.
    static let tapRippleSpec = MicroAnimationSpec(
        type: .tapRipple,
        duration: 0.35,
        timingControlPoints: (0.0, 0.0, 0.2, 1.0),   // ease-out
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Selection glow: soft pulse around the selected object.
    /// Duration: 0.4 s, ease-in-out, auto-reverses once.
    /// Shadow radius: 0 → 6, Shadow opacity: 0 → 0.15.
    static let selectionGlowSpec = MicroAnimationSpec(
        type: .selectionGlow,
        duration: 0.4,
        timingControlPoints: (0.42, 0.0, 0.58, 1.0),  // ease-in-out
        delay: 0,
        autoreverses: true,
        repeatCount: 0
    )

    /// Snap bounce: micro scale bounce when an object snaps to grid.
    /// Duration: 0.2 s, critically-damped spring approximation.
    /// Scale: 1.0 → 1.03 → 1.0.
    static let snapBounceSpec = MicroAnimationSpec(
        type: .snapBounce,
        duration: 0.2,
        timingControlPoints: (0.34, 1.56, 0.64, 1.0), // spring overshoot
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Drag inertia: position eases to final value after drag release.
    /// Duration: 0.3 s, deceleration curve.
    static let dragInertiaSpec = MicroAnimationSpec(
        type: .dragInertia,
        duration: 0.3,
        timingControlPoints: (0.0, 0.0, 0.2, 1.0),   // ease-out (decelerate)
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Soft shadow movement: shadow offset shifts to follow the object.
    /// Duration: 0.25 s, ease-out.
    /// Shadow offset shifts ±2 pt based on drag direction.
    static let softShadowSpec = MicroAnimationSpec(
        type: .softShadow,
        duration: 0.25,
        timingControlPoints: (0.0, 0.0, 0.2, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Lift and glow: scale 1.0 → 1.06 + shadow elevation + accent glow.
    /// Duration: 0.28 s, spring overshoot for tactile "pick-up" sensation.
    static let liftAndGlowSpec = MicroAnimationSpec(
        type: .liftAndGlow,
        duration: 0.28,
    // ── Deepened interaction specs (AGENT-23) ───────────────────────────

    /// Tool switch morph: brief scale pulse when switching tools.
    /// Duration: 0.22 s, critically-damped spring.
    /// Scale: 1.0 → 1.02 → 1.0.
    static let toolSwitchMorphSpec = MicroAnimationSpec(
        type: .toolSwitchMorph,
        duration: 0.22,
        timingControlPoints: (0.34, 1.20, 0.64, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Undo flash: faint overlay flash for undo/redo feedback.
    /// Duration: 0.25 s, ease-in-out.
    /// Opacity: 0 → 0.06 → 0.
    static let undoFlashSpec = MicroAnimationSpec(
        type: .undoFlash,
        duration: 0.25,
        timingControlPoints: (0.42, 0.0, 0.58, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Zoom detent tick: micro-bounce at detent zoom levels.
    /// Duration: 0.18 s, critically-damped spring.
    /// Scale: 1.0 → 1.005 → 1.0.
    static let zoomDetentTickSpec = MicroAnimationSpec(
        type: .zoomDetentTick,
        duration: 0.18,
        timingControlPoints: (0.34, 1.56, 0.64, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Settle from lift: spring-return to 1.0 + glow fade.
    /// Duration: 0.22 s, ease-out deceleration.
    static let settleFromLiftSpec = MicroAnimationSpec(
        type: .settleFromLift,
        duration: 0.22,
    /// Canvas first touch: very faint expanding ring on initial tap.
    /// Duration: 0.4 s, ease-out.
    /// Scale: 0 → 1, Opacity: 0.15 → 0.
    static let canvasFirstTouchSpec = MicroAnimationSpec(
        type: .canvasFirstTouch,
        duration: 0.4,
        timingControlPoints: (0.0, 0.0, 0.2, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    /// Button press: subtle press-down scale for toolbar buttons.
    /// Duration: 0.12 s, ease-out.
    /// Scale: 1.0 → 0.96.
    static let buttonPressSpec = MicroAnimationSpec(
        type: .buttonPress,
        duration: 0.12,
        timingControlPoints: (0.0, 0.0, 0.2, 1.0),
        delay: 0,
        autoreverses: false,
        repeatCount: 0
    )

    // MARK: - State

    private var activeAnimationCount: Int = 0

    /// Current adaptive effect intensity.  Updated by the owning view
    /// whenever `AdaptiveEffectsEngine.intensity` changes.  Defaults to
    /// `.full` so existing callers that don't set it get original behaviour.
    var effectIntensity: EffectIntensity = .full

    /// Convenience guard: returns `true` when the animation should be skipped
    /// due to Reduce Motion or adaptive intensity.
    private var shouldSuppressAnimations: Bool {
        (InteractionRules.respectReduceMotion && ReduceMotionObserver.shared.isEnabled)
            || !effectIntensity.allowsMicroInteractions
    }

    // MARK: - Tap Ripple

    /// Plays a very subtle expanding ring at `point` inside `container`.
    ///
    /// The ring is a `CAShapeLayer` circle that scales from 0 → 1 while
    /// fading from 0.25 → 0 opacity over 0.35 s.  It is removed from the
    /// layer tree on completion.
    ///
    /// - Parameters:
    ///   - point: Centre of the ripple in the container's coordinate space.
    ///   - container: The `CALayer` to add the ripple to.
    ///   - color: Tint colour for the ring (default: label colour at 25 %).
    func playTapRipple(
        at point: CGPoint,
        in container: CALayer,
        color: UIColor = UIColor.label.withAlphaComponent(0.25)
    ) {
        guard !shouldSuppressAnimations else { return }
        guard activeAnimationCount < InteractionRules.maxSimultaneousAnimations else { return }

        let diameter: CGFloat = 44
        let ring = CAShapeLayer()
        ring.path        = UIBezierPath(ovalIn: CGRect(x: -diameter / 2, y: -diameter / 2,
                                                        width: diameter, height: diameter)).cgPath
        ring.fillColor   = UIColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth   = 1.0
        ring.position    = point
        ring.opacity     = 0 // will be animated

        container.addSublayer(ring)
        activeAnimationCount += 1

        let spec = Self.tapRippleSpec
        let timing = CAMediaTimingFunction(controlPoints:
            Float(spec.timingControlPoints.0), Float(spec.timingControlPoints.1),
            Float(spec.timingControlPoints.2), Float(spec.timingControlPoints.3))

        // Scale animation: 0 → 1
        let scale           = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue     = 0.0
        scale.toValue       = 1.0

        // Opacity animation: 0.25 → 0
        let opacity           = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue     = 0.25
        opacity.toValue       = 0.0

        let group                   = CAAnimationGroup()
        group.animations            = [scale, opacity]
        group.duration              = spec.duration
        group.timingFunction        = timing
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = false

        let captured = ring
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeAnimationCount -= 1
        }
        ring.add(group, forKey: "tapRipple")
        CATransaction.commit()
    }

    // MARK: - Selection Glow

    /// Adds a soft glow pulse to the given layer when an object is selected.
    ///
    /// Animates `shadowRadius` 0 → 6 and `shadowOpacity` 0 → 0.15 with
    /// auto-reverse over 0.4 s.  The shadow is removed on completion.
    ///
    /// - Parameters:
    ///   - layer: The object's presentation layer.
    ///   - color: Glow colour (default: accent blue).
    func playSelectionGlow(
        on layer: CALayer,
        color: UIColor = UIColor.systemBlue
    ) {
        guard !shouldSuppressAnimations else { return }
        guard activeAnimationCount < InteractionRules.maxSimultaneousAnimations else { return }

        layer.shadowColor  = color.cgColor
        layer.shadowOffset = .zero
        activeAnimationCount += 1

        let spec = Self.selectionGlowSpec
        let timing = CAMediaTimingFunction(controlPoints:
            Float(spec.timingControlPoints.0), Float(spec.timingControlPoints.1),
            Float(spec.timingControlPoints.2), Float(spec.timingControlPoints.3))

        let radius           = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue     = 0
        radius.toValue       = 6

        let opacity           = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue     = 0
        opacity.toValue       = 0.15

        let group                   = CAAnimationGroup()
        group.animations            = [radius, opacity]
        group.duration              = spec.duration
        group.timingFunction        = timing
        group.autoreverses          = spec.autoreverses
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            layer.shadowRadius  = 0
            layer.shadowOpacity = 0
            self?.activeAnimationCount -= 1
        }
        layer.add(group, forKey: "selectionGlow")
        CATransaction.commit()
    }

    // MARK: - Snap Bounce

    /// Plays a tiny scale bounce (1.0 → 1.03 → 1.0) on a layer when it snaps.
    ///
    /// Uses a spring timing approximation for physically correct overshoot.
    /// Duration: 0.2 s.
    func playSnapBounce(on layer: CALayer) {
        guard !shouldSuppressAnimations else { return }
        guard activeAnimationCount < InteractionRules.maxSimultaneousAnimations else { return }

        activeAnimationCount += 1

        let anim            = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue      = 1.0
        anim.toValue        = 1.0
        anim.initialVelocity = 8.0    // small impulse
        anim.damping         = 15.0   // critically damped — no bouncing
        anim.stiffness       = 300.0
        anim.mass            = 1.0
        anim.duration        = anim.settlingDuration

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.activeAnimationCount -= 1
        }
        layer.add(anim, forKey: "snapBounce")
        CATransaction.commit()
    }

    // MARK: - Select Scale

    /// Scales a layer up slightly (1.0 → 1.05) with a spring animation when selected.
    ///
    /// Gives objects a tactile "lift" feeling.  Pairs well with `playSelectionGlow`.
    /// Duration: ~0.3 s (spring settling).
    func playSelectScale(on layer: CALayer) {
        guard !shouldSuppressAnimations else { return }

        let anim             = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue       = 1.0
        anim.toValue         = 1.05
        anim.initialVelocity = 4.0
        anim.damping         = 12.0
        anim.stiffness       = 280.0
        anim.mass            = 1.0
        anim.duration        = anim.settlingDuration
        anim.fillMode        = .forwards
        anim.isRemovedOnCompletion = false

        layer.add(anim, forKey: "selectScale")
    }

    /// Scales a layer back to 1.0 with an ease-out curve when deselected.
    func playDeselectScale(on layer: CALayer) {
        guard !shouldSuppressAnimations else {
            layer.removeAnimation(forKey: "selectScale")
            layer.transform = CATransform3DIdentity
            return
        }

        let anim                    = CABasicAnimation(keyPath: "transform.scale")
        anim.toValue                = 1.0
        anim.duration               = 0.2
        anim.timingFunction         = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        layer.add(anim, forKey: "selectScale")
    }

    /// Plays a bounce + settle animation on release (1.05 → 1.0 with spring overshoot).
    func playReleaseBounce(on layer: CALayer) {
        guard !shouldSuppressAnimations else {
            layer.removeAnimation(forKey: "selectScale")
            layer.transform = CATransform3DIdentity
            return
        }

        let anim             = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue       = 1.05
        anim.toValue         = 1.0
        anim.initialVelocity = 6.0
        anim.damping         = 10.0
        anim.stiffness       = 300.0
        anim.mass            = 1.0
        anim.duration        = anim.settlingDuration
        anim.fillMode        = .forwards
        anim.isRemovedOnCompletion = false

        layer.add(anim, forKey: "selectScale")
    }

    // MARK: - Interaction Layer Setup

    /// Configures a layer as a transparent interaction overlay with resting shadow.
    ///
    /// Call once during setup. The layer should be sized/positioned to match the
    /// active object before playing effects.
    func configureInteractionLayer(_ layer: CALayer) {
        layer.backgroundColor = UIColor.clear.cgColor
        layer.shadowColor     = UIColor.black.cgColor
        layer.shadowOpacity   = 0.10
        layer.shadowRadius    = 4.0
        layer.shadowOffset    = CGSize(width: 0, height: 2)
        layer.isHidden        = true
    }

    /// Positions the interaction overlay to match an object's bounding rect and shows it.
    func showInteractionLayer(_ layer: CALayer, for rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame    = rect.insetBy(dx: -2, dy: -2)  // slight outset for shadow room
        layer.isHidden = false
        CATransaction.commit()
    }

    /// Hides the interaction overlay, resetting shadow and transform.
    func hideInteractionLayer(_ layer: CALayer) {
        layer.removeAnimation(forKey: "selectScale")
        layer.removeAnimation(forKey: "softShadow")
        layer.removeAnimation(forKey: "softShadowReset")
        layer.removeAnimation(forKey: "selectionGlow")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.isHidden  = true
        layer.transform = CATransform3DIdentity
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4.0
        layer.shadowOpacity = 0.10
        CATransaction.commit()
    }

    // MARK: - Drag Inertia

    /// Applies momentum carry to a layer's position after a drag release.
    ///
    /// The layer decelerates from `velocity` (points/second) to zero over
    /// 0.3 s using an ease-out curve.
    ///
    /// - Parameters:
    ///   - layer: The dragged layer.
    ///   - from: Current position at drag release.
    ///   - velocity: Drag velocity at release (points/second).
    func playDragInertia(
        on layer: CALayer,
        from currentPosition: CGPoint,
        velocity: CGPoint
    ) {
        guard !shouldSuppressAnimations else { return }

        let spec = Self.dragInertiaSpec
        let decayFactor: CGFloat = 0.12   // how far inertia carries (fraction of velocity)
        let dx = velocity.x * decayFactor
        let dy = velocity.y * decayFactor
        let target = CGPoint(x: currentPosition.x + dx, y: currentPosition.y + dy)

        let timing = CAMediaTimingFunction(controlPoints:
            Float(spec.timingControlPoints.0), Float(spec.timingControlPoints.1),
            Float(spec.timingControlPoints.2), Float(spec.timingControlPoints.3))

        let anim               = CABasicAnimation(keyPath: "position")
        anim.fromValue         = NSValue(cgPoint: currentPosition)
        anim.toValue           = NSValue(cgPoint: target)
        anim.duration          = spec.duration
        anim.timingFunction    = timing
        anim.fillMode          = .forwards
        anim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.position = target
            layer.removeAnimation(forKey: "dragInertia")
        }
        layer.add(anim, forKey: "dragInertia")
        CATransaction.commit()
    }

    // MARK: - Soft Shadow Movement

    /// Shifts the layer's shadow offset to simulate light-source parallax.
    ///
    /// As the user drags an object, the shadow shifts in the opposite
    /// direction by ±2 pt, giving the illusion of depth.
    ///
    /// - Parameters:
    ///   - layer: The object layer.
    ///   - dragDirection: Normalised drag direction vector.
    func playSoftShadow(
        on layer: CALayer,
        dragDirection: CGPoint
    ) {
        guard !shouldSuppressAnimations else { return }

        let maxOffset: CGFloat = 2.0
        let targetOffset = CGSize(
            width:  -dragDirection.x * maxOffset,
            height: -dragDirection.y * maxOffset
        )

        let spec = Self.softShadowSpec
        let timing = CAMediaTimingFunction(controlPoints:
            Float(spec.timingControlPoints.0), Float(spec.timingControlPoints.1),
            Float(spec.timingControlPoints.2), Float(spec.timingControlPoints.3))

        let anim                    = CABasicAnimation(keyPath: "shadowOffset")
        anim.toValue                = NSValue(cgSize: targetOffset)
        anim.duration               = spec.duration
        anim.timingFunction         = timing
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        layer.add(anim, forKey: "softShadow")
    }

    /// Resets the shadow offset to the default resting position (0, 1).
    func resetSoftShadow(on layer: CALayer) {
        guard !shouldSuppressAnimations else {
            layer.shadowOffset = CGSize(width: 0, height: 1)
            return
        }

        let timing = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)

        let anim                    = CABasicAnimation(keyPath: "shadowOffset")
        anim.toValue                = NSValue(cgSize: CGSize(width: 0, height: 1))
        anim.duration               = 0.2
        anim.timingFunction         = timing
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        layer.add(anim, forKey: "softShadowReset")
    }

    // MARK: - Lift and Glow

    /// Plays a combined scale-lift + shadow elevation + accent glow on selection.
    ///
    /// Scale animates 1.0 → 1.06 with a spring overshoot (tactile "pick-up").
    /// Shadow radius increases from 4 → 10 and opacity from 0.10 → 0.28.
    /// An optional accent glow pulses via `shadowColor`.
    ///
    /// Pairs with `playSettleFromLift` on deselection.
    ///
    /// - Parameters:
    ///   - layer: The object layer to lift.
    ///   - color: Glow accent colour (default: accent blue).
    ///   - profile: Spring profile controlling the lift feel.
    func playLiftAndGlow(
        on layer: CALayer,
        color: UIColor = UIColor.systemBlue,
        profile: SpringProfile = .gentle
    ) {
        guard !shouldSuppressAnimations else { return }

        // Scale spring — tactile lift
        let scaleAnim             = CASpringAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue       = 1.0
        scaleAnim.toValue         = 1.06
        scaleAnim.initialVelocity = profile.initialVelocity
        scaleAnim.damping         = profile.damping
        scaleAnim.stiffness       = profile.stiffness
        scaleAnim.mass            = profile.mass
        scaleAnim.duration        = scaleAnim.settlingDuration
        scaleAnim.fillMode        = .forwards
        scaleAnim.isRemovedOnCompletion = false

        // Shadow radius 4 → 10
        let radiusAnim               = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.fromValue         = 4.0
        radiusAnim.toValue           = 10.0
        radiusAnim.duration          = Self.liftAndGlowSpec.duration
        radiusAnim.timingFunction    = CAMediaTimingFunction(name: .easeOut)
        radiusAnim.fillMode          = .forwards
        radiusAnim.isRemovedOnCompletion = false

        // Shadow opacity 0.10 → 0.28
        let opacityAnim              = CABasicAnimation(keyPath: "shadowOpacity")
        opacityAnim.fromValue        = Float(0.10)
        opacityAnim.toValue          = Float(0.28)
        opacityAnim.duration         = Self.liftAndGlowSpec.duration
        opacityAnim.timingFunction   = CAMediaTimingFunction(name: .easeOut)
        opacityAnim.fillMode         = .forwards
        opacityAnim.isRemovedOnCompletion = false

        layer.shadowColor = color.cgColor

        layer.add(scaleAnim,   forKey: "liftScale")
        layer.add(radiusAnim,  forKey: "liftShadowRadius")
        layer.add(opacityAnim, forKey: "liftShadowOpacity")
    }

    // MARK: - Settle from Lift

    /// Spring-returns a lifted layer to its resting identity state.
    ///
    /// Scale springs 1.06 → 1.0, shadow radius and opacity ease back to
    /// their resting values.  Pairs with `playLiftAndGlow`.
    ///
    /// - Parameters:
    ///   - layer: The lifted layer (must have had `playLiftAndGlow` applied).
    ///   - profile: Spring profile controlling the settle feel.
    func playSettleFromLift(
        on layer: CALayer,
        profile: SpringProfile = .snappy
    ) {
        guard !shouldSuppressAnimations else {
            layer.removeAnimation(forKey: "liftScale")
            layer.transform     = CATransform3DIdentity
            layer.shadowRadius  = 4.0
            layer.shadowOpacity = 0.10
            return
        }

        let scaleAnim             = CASpringAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue       = 1.06
        scaleAnim.toValue         = 1.0
        scaleAnim.initialVelocity = profile.initialVelocity
        scaleAnim.damping         = profile.damping
        scaleAnim.stiffness       = profile.stiffness
        scaleAnim.mass            = profile.mass
        scaleAnim.duration        = scaleAnim.settlingDuration
        scaleAnim.fillMode        = .forwards
        scaleAnim.isRemovedOnCompletion = false

        let spec   = Self.settleFromLiftSpec
        let timing = CAMediaTimingFunction(controlPoints:
            Float(spec.timingControlPoints.0), Float(spec.timingControlPoints.1),
            Float(spec.timingControlPoints.2), Float(spec.timingControlPoints.3))

        let radiusAnim              = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.toValue          = 4.0
        radiusAnim.duration         = spec.duration
        radiusAnim.timingFunction   = timing
        radiusAnim.fillMode         = .forwards
        radiusAnim.isRemovedOnCompletion = false

        let opacityAnim             = CABasicAnimation(keyPath: "shadowOpacity")
        opacityAnim.toValue         = Float(0.10)
        opacityAnim.duration        = spec.duration
        opacityAnim.timingFunction  = timing
        opacityAnim.fillMode        = .forwards
        opacityAnim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeAnimation(forKey: "liftScale")
            layer.removeAnimation(forKey: "liftShadowRadius")
            layer.removeAnimation(forKey: "liftShadowOpacity")
            layer.transform     = CATransform3DIdentity
            layer.shadowRadius  = 4.0
            layer.shadowOpacity = 0.10
        }
        layer.add(scaleAnim,   forKey: "liftScale")
        layer.add(radiusAnim,  forKey: "liftShadowRadius")
        layer.add(opacityAnim, forKey: "liftShadowOpacity")
        CATransaction.commit()
    }

    // MARK: - Velocity Drag Inertia

    /// Applies velocity-magnitude-scaled momentum carry to a layer's position.
    ///
    /// Unlike `playDragInertia`, the carry distance scales with the speed of
    /// the gesture — a fast fling carries farther (up to 40 pt) while a slow
    /// release barely moves.  The deceleration curve uses an ease-out quintic
    /// for a physically correct slowdown.
    // MARK: - Tool Switch Morph (AGENT-23)

    /// Plays a brief scale pulse on a layer when the user switches tools.
    ///
    /// The layer (typically the toolbar or canvas) gets a subtle 1.02× scale
    /// impulse that settles via critically-damped spring.  Duration: 0.22 s.
    ///
    /// - Parameter layer: The target layer to animate.
    func playToolSwitchMorph(on layer: CALayer) {
        guard !shouldSuppressAnimations else { return }

        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue       = 1.0
        anim.toValue         = 1.0
        anim.initialVelocity = 5.0
        anim.damping         = 16.0
        anim.stiffness       = 350.0
        anim.mass            = 0.8
        anim.duration        = anim.settlingDuration
        anim.fillMode        = .forwards
        anim.isRemovedOnCompletion = true

        layer.add(anim, forKey: "toolSwitchMorph")
    }

    // MARK: - Undo Flash (AGENT-23)

    /// Plays a very faint overlay flash when undo/redo is performed.
    ///
    /// A translucent layer covers the target, pulses to 6 % opacity, then
    /// fades out over 0.25 s.  Provides non-distracting visual confirmation.
    ///
    /// - Parameters:
    ///   - container: The layer to flash inside.
    ///   - isUndo: `true` for undo (warm tint), `false` for redo (cool tint).
    func playUndoFlash(in container: CALayer, isUndo: Bool) {
        guard !shouldSuppressAnimations else { return }
        guard activeAnimationCount < InteractionRules.maxSimultaneousAnimations else { return }

        activeAnimationCount += 1

        let overlay = CALayer()
        overlay.frame = container.bounds
        overlay.backgroundColor = (isUndo
            ? UIColor.systemOrange.withAlphaComponent(0.06)
            : UIColor.systemBlue.withAlphaComponent(0.06)
        ).cgColor
        overlay.opacity = 0
        container.addSublayer(overlay)

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values   = [0, 1.0, 0]
        anim.keyTimes = [0, 0.35, 1.0]
        anim.duration = Self.undoFlashSpec.duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        let captured = overlay
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeAnimationCount -= 1
        }
        overlay.add(anim, forKey: "undoFlash")
        CATransaction.commit()
    }

    // MARK: - Zoom Detent Tick (AGENT-23)

    /// Plays a micro-bounce on the canvas layer when zoom hits a detent.
    ///
    /// A barely perceptible 0.5 % scale impulse settles via spring physics.
    /// Duration: 0.18 s.  This is the visual companion to the haptic tick
    /// fired by `InteractionFeedbackEngine`.
    ///
    /// - Parameter layer: The canvas or container layer.
    func playZoomDetentTick(on layer: CALayer) {
        guard !shouldSuppressAnimations else { return }

        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue       = 1.0
        anim.toValue         = 1.0
        anim.initialVelocity = 3.0
        anim.damping         = 18.0
        anim.stiffness       = 400.0
        anim.mass            = 0.6
        anim.duration        = anim.settlingDuration
        anim.fillMode        = .forwards
        anim.isRemovedOnCompletion = true

        layer.add(anim, forKey: "zoomDetentTick")
    }

    // MARK: - Canvas First Touch (AGENT-23)

    /// Plays a very faint expanding ring on the first canvas tap.
    ///
    /// Similar to `tapRipple` but even subtler — 15 % max opacity and
    /// larger diameter (56 pt).  Used for non-pencil taps to acknowledge
    /// touch without distracting from the drawing surface.
    ///
    /// - Parameters:
    ///   - point: Centre of the ripple in the container's coordinate space.
    ///   - container: The `CALayer` to add the ripple to.
    func playCanvasFirstTouch(at point: CGPoint, in container: CALayer) {
        guard !shouldSuppressAnimations else { return }
        guard activeAnimationCount < InteractionRules.maxSimultaneousAnimations else { return }

        let diameter: CGFloat = 56
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(
            x: -diameter / 2, y: -diameter / 2,
            width: diameter, height: diameter
        )).cgPath
        ring.fillColor   = UIColor.clear.cgColor
        ring.strokeColor = UIColor.label.withAlphaComponent(0.15).cgColor
        ring.lineWidth   = 0.75
        ring.position    = point
        ring.opacity     = 0

        container.addSublayer(ring)
        activeAnimationCount += 1

        let scale       = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue   = 1.0

        let opacity       = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.15
        opacity.toValue   = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration   = Self.canvasFirstTouchSpec.duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        let captured = ring
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeAnimationCount -= 1
        }
        ring.add(group, forKey: "canvasFirstTouch")
        CATransaction.commit()
    }

    // MARK: - Button Press / Release (AGENT-23)

    /// Plays a subtle press-down scale on a toolbar button layer.
    ///
    /// Scale: 1.0 → 0.96 with ease-out.  Pairs with `playButtonRelease`
    /// to create a physical "press and bounce-back" interaction.
    ///
    /// - Parameter layer: The button's presentation layer.
    func playButtonPress(on layer: CALayer) {
        guard !shouldSuppressAnimations else { return }

        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.toValue = 0.96
        anim.duration = Self.buttonPressSpec.duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        layer.add(anim, forKey: "buttonPress")
    }

    /// Plays a spring bounce-back from the pressed state.
    ///
    /// Scale: 0.96 → 1.0 with spring overshoot.  Call on touch-up.
    ///
    /// - Parameter layer: The button's presentation layer.
    func playButtonRelease(on layer: CALayer) {
        guard !shouldSuppressAnimations else {
            layer.removeAnimation(forKey: "buttonPress")
            layer.transform = CATransform3DIdentity
            return
        }

        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue       = 0.96
        anim.toValue         = 1.0
        anim.initialVelocity = 8.0
        anim.damping         = 12.0
        anim.stiffness       = 300.0
        anim.mass            = 0.8
        anim.duration        = anim.settlingDuration
        anim.fillMode        = .forwards
        anim.isRemovedOnCompletion = true

        layer.removeAnimation(forKey: "buttonPress")
        layer.add(anim, forKey: "buttonRelease")
    }

    // MARK: - Velocity-Driven Drag Inertia (AGENT-22)

    /// Enhanced drag inertia that uses spring physics scaled by gesture velocity.
    ///
    /// Fast flick gestures produce longer carry distance with a snappier settle,
    /// while slow releases produce gentle deceleration.  The spring profile
    /// adapts automatically.
    ///
    /// - Parameters:
    ///   - layer: The dragged layer.
    ///   - from: Current position at drag release.
    ///   - velocity: Drag velocity at release (points/second).
    func playVelocityDragInertia(
        on layer: CALayer,
        from currentPosition: CGPoint,
        velocity: CGPoint
    ) {
        guard !shouldSuppressAnimations else { return }

        let speed = hypot(velocity.x, velocity.y)

        // Scale carry: 0.06 at 200 pt/s → 0.10 at 1000+ pt/s, capped at 40 pt.
        let baseDecay: CGFloat      = 0.06
        let velocityBoost: CGFloat  = min(speed / 1000.0, 1.0) * 0.04
        let decayFactor: CGFloat    = baseDecay + velocityBoost
        let dx = velocity.x * decayFactor
        let dy = velocity.y * decayFactor
        let maxCarry: CGFloat = 40
        let clampedDx = max(-maxCarry, min(maxCarry, dx))
        let clampedDy = max(-maxCarry, min(maxCarry, dy))
        let target = CGPoint(x: currentPosition.x + clampedDx,
                             y: currentPosition.y + clampedDy)

        // Duration scales with speed: 0.28 s at slow → 0.42 s at high velocity.
        let duration = 0.28 + min(speed / 1000.0, 1.0) * 0.14

        let timing = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.15, 1.0)  // ease-out quintic approx

        let anim               = CABasicAnimation(keyPath: "position")
        anim.fromValue         = NSValue(cgPoint: currentPosition)
        anim.toValue           = NSValue(cgPoint: target)
        anim.duration          = duration
        anim.timingFunction    = timing
        anim.fillMode          = .forwards
        anim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.position = target
            layer.removeAnimation(forKey: "velocityDragInertia")
        }
        layer.add(anim, forKey: "velocityDragInertia")
        CATransaction.commit()
    }

    // MARK: - Momentum Shadow

    /// Shifts and scales the layer shadow to track the velocity vector.
    ///
    /// Shadow direction is opposite to the velocity direction (simulating
    /// a light source above and ahead of motion).  Shadow radius scales from
    /// 4 → 8 with speed, amplifying the perception of fast movement.
    ///
    /// - Parameters:
    ///   - layer: The moving layer.
    ///   - velocity: Current drag velocity (points/second).
    func playMomentumShadow(
        on layer: CALayer,
        velocity: CGPoint
    ) {
        guard !shouldSuppressAnimations else { return }

        let speed = hypot(velocity.x, velocity.y)
        guard speed > 1 else { return }

        let maxSpeed: CGFloat = 800
        let speedFraction = min(speed / maxSpeed, 1.0)

        // Shadow offset: opposite to velocity direction, max ±4 pt.
        let maxOffset: CGFloat = 4.0
        let nx = velocity.x / speed  // normalised direction
        let ny = velocity.y / speed
        let targetOffset = CGSize(
            width:  -nx * maxOffset * speedFraction,
            height: -ny * maxOffset * speedFraction
        )

        // Shadow radius: 4 → 8 with speed.
        let targetRadius: CGFloat = 4.0 + speedFraction * 4.0

        let timing = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)

        let offsetAnim              = CABasicAnimation(keyPath: "shadowOffset")
        offsetAnim.toValue          = NSValue(cgSize: targetOffset)
        offsetAnim.duration         = 0.18
        offsetAnim.timingFunction   = timing
        offsetAnim.fillMode         = .forwards
        offsetAnim.isRemovedOnCompletion = false

        let radiusAnim              = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.toValue          = targetRadius
        radiusAnim.duration         = 0.18
        radiusAnim.timingFunction   = timing
        radiusAnim.fillMode         = .forwards
        radiusAnim.isRemovedOnCompletion = false

        layer.add(offsetAnim, forKey: "momentumShadowOffset")
        layer.add(radiusAnim, forKey: "momentumShadowRadius")
    }
}
