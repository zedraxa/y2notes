import UIKit
import QuartzCore

// MARK: - Page Transition Direction

/// Direction of a page transition.
enum PageTransitionDirection {
    case forward   // swipe left → next page
    case backward  // swipe right → previous page

    /// Sign multiplier for horizontal offsets (+1 forward, −1 backward).
    var sign: CGFloat { self == .forward ? 1.0 : -1.0 }
}

// MARK: - Page Transition Engine

/// Lightweight engine that plays physical page-turn effects on `CALayer`s.
///
/// Effects convey the physicality of a paper page:
///
/// 1. **Inertia-based slide** — the outgoing page decelerates naturally
///    with an ease-out curve, never arriving at a hard stop.
/// 2. **Slight resistance** — a subtle horizontal scale compression at the
///    leading edge suggests the page resists the finger before yielding.
/// 3. **Edge shadow** — a thin gradient shadow appears on the transition
///    edge, simulating the shadow cast by a lifted page corner.
/// 4. **Soft page-bend illusion** — a faint vertical gradient overlay on
///    the incoming page mimics the curvature of paper uncurling.
///
/// **Performance contract**: all animations are GPU-composited via
/// Core Animation.  No main-thread layout passes occur.  Total setup
/// overhead is < 0.4 ms (within `PerformanceConstraints.pageTransitionBudgetMs`).
///
/// **Reduce Motion**: when `UIAccessibility.isReduceMotionEnabled` is `true`,
/// the page change is instantaneous (cross-fade over 0.12 s) with no slide
/// or bend effects.
///
/// **Lifecycle**: create once per editor session; call
/// `playTransition(on:direction:pageWidth:completion:)` from the page-swipe
/// handler.  Discard when the editor is torn down.
final class PageTransitionEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        /// Total transition duration (seconds).  Short enough to feel instant,
        /// long enough for the eye to register the physical cues.
        static let duration: CFTimeInterval = 0.32

        /// Reduced-motion cross-fade duration.
        static let reducedMotionDuration: CFTimeInterval = 0.12

        /// Fraction of `pageWidth` the outgoing page slides off-screen.
        /// 0.35 means it slides 35 % of the width — enough to clear the
        /// view without feeling like it flew away.
        static let slideFraction: CGFloat = 0.35

        /// Resistance scale factor applied to the leading edge.
        /// 0.97 = 3 % horizontal compression — barely visible, but felt.
        static let resistanceScaleX: CGFloat = 0.97

        // ── Edge Shadow ─────────────────────────────────────
        /// Shadow width in points.
        static let edgeShadowWidth: CGFloat = 12.0
        /// Peak shadow opacity.
        static let edgeShadowOpacity: Float = 0.18

        // ── Page Bend ───────────────────────────────────────
        /// Width of the bend highlight gradient on the incoming page.
        static let bendHighlightWidth: CGFloat = 40.0
        /// Peak bend highlight opacity.
        static let bendHighlightOpacity: Float = 0.07
    }

    // MARK: - State

    private var isTransitioning: Bool = false

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    // MARK: - Public API

    /// Plays a physical page transition on the given container layer.
    ///
    /// The engine creates ephemeral sublayers for the shadow and bend
    /// effects, animates them together with `position` / `transform`
    /// changes on the container, and removes all artifacts on completion.
    ///
    /// - Parameters:
    ///   - layer: The container `CALayer` whose contents represent the
    ///     current page.  The layer is returned to its original state on
    ///     completion.
    ///   - direction: `.forward` (next page) or `.backward` (previous page).
    ///   - pageWidth: The visible width of the page, used to compute slide
    ///     distance and shadow placement.
    ///   - completion: Called on the main thread when the transition finishes.
    func playTransition(
        on layer: CALayer,
        direction: PageTransitionDirection,
        pageWidth: CGFloat,
        completion: @escaping () -> Void
    ) {
        // Prevent overlapping transitions.
        guard !isTransitioning else {
            completion()
            return
        }
        isTransitioning = true

        if ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsPageTurnPhysics {
            playReducedMotionTransition(on: layer, completion: completion)
            return
        }

        let slideDistance = pageWidth * Tuning.slideFraction * direction.sign
        let originalPosition = layer.position

        // ── 1. Edge shadow sublayer ──────────────────────────────────────
        let shadow = makeEdgeShadow(
            height: layer.bounds.height,
            direction: direction
        )
        let shadowX: CGFloat = direction == .forward
            ? layer.bounds.width                   // right edge
            : 0                                     // left edge
        shadow.position = CGPoint(x: shadowX, y: layer.bounds.height / 2)
        layer.addSublayer(shadow)

        // ── 2. Page-bend highlight sublayer ──────────────────────────────
        let bend = makeBendHighlight(
            height: layer.bounds.height,
            direction: direction
        )
        let bendX: CGFloat = direction == .forward
            ? 0                                     // left edge of incoming
            : layer.bounds.width                    // right edge of incoming
        bend.position = CGPoint(x: bendX, y: layer.bounds.height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)

        // ── Timing functions ─────────────────────────────────────────────
        // Decelerate (ease-out): fast start, gentle stop — feels like inertia.
        let easeOut = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.25, 1.0)

        // ── 3. Slide animation (inertia-based) ──────────────────────────
        let slide                   = CABasicAnimation(keyPath: "position.x")
        slide.fromValue             = originalPosition.x
        slide.toValue               = originalPosition.x - slideDistance
        slide.duration              = Tuning.duration
        slide.timingFunction        = easeOut
        slide.fillMode              = .forwards
        slide.isRemovedOnCompletion = false

        // ── 4. Resistance transform (slight horizontal compression) ─────
        let resist                   = CABasicAnimation(keyPath: "transform")
        let resistTransform = CATransform3DMakeScale(
            Tuning.resistanceScaleX, 1.0, 1.0
        )
        resist.fromValue             = NSValue(caTransform3D: CATransform3DIdentity)
        resist.toValue               = NSValue(caTransform3D: resistTransform)
        resist.duration              = Tuning.duration * 0.5       // first half
        resist.autoreverses          = true                         // snaps back
        resist.timingFunction        = easeOut
        resist.fillMode              = .forwards
        resist.isRemovedOnCompletion = false

        // ── 5. Edge shadow fade in → out ────────────────────────────────
        let shadowFade               = CAKeyframeAnimation(keyPath: "opacity")
        shadowFade.values            = [0.0, Tuning.edgeShadowOpacity, 0.0]
        shadowFade.keyTimes          = [0.0, 0.4, 1.0]
        shadowFade.duration          = Tuning.duration
        shadowFade.timingFunction    = easeOut
        shadowFade.fillMode          = .forwards
        shadowFade.isRemovedOnCompletion = false

        // ── 6. Bend highlight fade in → out ─────────────────────────────
        let bendFade                 = CAKeyframeAnimation(keyPath: "opacity")
        bendFade.values              = [0.0, Tuning.bendHighlightOpacity, 0.0]
        bendFade.keyTimes            = [0.0, 0.35, 1.0]
        bendFade.duration            = Tuning.duration
        bendFade.timingFunction      = easeOut
        bendFade.fillMode            = .forwards
        bendFade.isRemovedOnCompletion = false

        // ── Commit all animations atomically ────────────────────────────
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Restore layer to original state.
            layer.position  = originalPosition
            layer.transform = CATransform3DIdentity
            layer.removeAnimation(forKey: "pageSlide")
            layer.removeAnimation(forKey: "pageResist")
            shadow.removeFromSuperlayer()
            bend.removeFromSuperlayer()
            self?.isTransitioning = false
            completion()
        }

        layer.add(slide, forKey: "pageSlide")
        layer.add(resist, forKey: "pageResist")
        shadow.add(shadowFade, forKey: "shadowFade")
        bend.add(bendFade, forKey: "bendFade")

        CATransaction.commit()
    }

    // MARK: - Reduced Motion Fallback

    private func playReducedMotionTransition(
        on layer: CALayer,
        completion: @escaping () -> Void
    ) {
        let fade                   = CABasicAnimation(keyPath: "opacity")
        fade.fromValue             = 1.0
        fade.toValue               = 0.85
        fade.duration              = Tuning.reducedMotionDuration
        fade.autoreverses          = true
        fade.timingFunction        = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.fillMode              = .forwards
        fade.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isTransitioning = false
            completion()
        }
        layer.add(fade, forKey: "reducedMotionFade")
        CATransaction.commit()
    }

    // MARK: - Shadow & Bend Layer Factories

    /// Creates a thin vertical gradient that simulates the shadow cast by
    /// a lifted page edge.
    private func makeEdgeShadow(
        height: CGFloat,
        direction: PageTransitionDirection
    ) -> CAGradientLayer {
        let shadow = CAGradientLayer()
        shadow.bounds = CGRect(
            x: 0, y: 0,
            width: Tuning.edgeShadowWidth,
            height: height
        )
        shadow.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let clear = UIColor.clear.cgColor
        let dark  = UIColor.black.withAlphaComponent(0.25).cgColor

        // Gradient goes from dark → clear in the slide direction.
        if direction == .forward {
            shadow.colors     = [dark, clear]
            shadow.startPoint = CGPoint(x: 0, y: 0.5)
            shadow.endPoint   = CGPoint(x: 1, y: 0.5)
        } else {
            shadow.colors     = [clear, dark]
            shadow.startPoint = CGPoint(x: 0, y: 0.5)
            shadow.endPoint   = CGPoint(x: 1, y: 0.5)
        }

        shadow.opacity = 0
        return shadow
    }

    /// Creates a faint vertical highlight strip that simulates paper
    /// bending as the incoming page unfurls.
    private func makeBendHighlight(
        height: CGFloat,
        direction: PageTransitionDirection
    ) -> CAGradientLayer {
        let bend = CAGradientLayer()
        bend.bounds = CGRect(
            x: 0, y: 0,
            width: Tuning.bendHighlightWidth,
            height: height
        )
        bend.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let clear = UIColor.clear.cgColor
        let white = UIColor.white.withAlphaComponent(0.15).cgColor

        if direction == .forward {
            bend.colors     = [white, clear]
            bend.startPoint = CGPoint(x: 0, y: 0.5)
            bend.endPoint   = CGPoint(x: 1, y: 0.5)
        } else {
            bend.colors     = [clear, white]
            bend.startPoint = CGPoint(x: 0, y: 0.5)
            bend.endPoint   = CGPoint(x: 1, y: 0.5)
        }

        bend.opacity = 0
        return bend
    }

    // MARK: - Velocity-Driven Transition (AGENT-22)

    /// Tuning for gesture-velocity-dependent page transitions.
    ///
    /// Faster swipes produce shorter, more energetic transitions with
    /// increased slide distance and deeper shadow.  Slow deliberate swipes
    /// give the user time to see the full page-turn physics.
    private enum VelocityTuning {
        /// Minimum allowed transition duration (seconds) — prevents glitch-fast turns.
        static let minDuration: CFTimeInterval = 0.18
        /// Maximum allowed transition duration (seconds) — prevents sluggish turns.
        static let maxDuration: CFTimeInterval = 0.45
        /// Swipe velocity (points/s) at which duration reaches `minDuration`.
        static let fastVelocity: CGFloat = 2000.0
        /// Swipe velocity (points/s) at which duration is `maxDuration` (slow deliberate swipe).
        static let slowVelocity: CGFloat = 200.0

        /// Minimum slide fraction of page width at slow velocity.
        static let minSlideFraction: CGFloat = 0.25
        /// Maximum slide fraction of page width at fast velocity.
        static let maxSlideFraction: CGFloat = 0.55

        /// Maximum shadow opacity boost at fast velocity.
        static let fastShadowOpacity: Float = 0.30
        /// Shadow spread boost at fast velocity.
        static let fastShadowWidth: CGFloat = 20.0
    }

    /// Plays a velocity-responsive page transition with deeper physical cues.
    ///
    /// The transition dynamically adjusts based on the swipe gesture velocity:
    /// - **Fast swipes** → shorter duration, larger slide distance, deeper shadow
    /// - **Slow swipes** → longer duration, smaller slide, gentler shadow
    ///
    /// Additionally adds a subtle 3D perspective rotation that creates a
    /// page-curl illusion (up to 4° rotation around the Y axis).
    ///
    /// - Parameters:
    ///   - layer: The page container layer.
    ///   - direction: `.forward` or `.backward`.
    ///   - pageWidth: Visible width of the page.
    ///   - velocity: Horizontal swipe velocity in points/second (absolute value used).
    ///   - completion: Called on the main thread when the transition finishes.
    func playVelocityTransition(
        on layer: CALayer,
        direction: PageTransitionDirection,
        pageWidth: CGFloat,
        velocity: CGFloat,
        completion: @escaping () -> Void
    ) {
        guard !isTransitioning else {
            completion()
            return
        }
        isTransitioning = true

        if ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsPageTurnPhysics {
            playReducedMotionTransition(on: layer, completion: completion)
            return
        }

        let absV = abs(velocity)
        // Map velocity to 0…1 normalised speed factor
        let velocityT = min(max((absV - VelocityTuning.slowVelocity)
            / (VelocityTuning.fastVelocity - VelocityTuning.slowVelocity), 0), 1)

        // Derive dynamic parameters from velocity
        let duration = VelocityTuning.maxDuration
            - velocityT * (VelocityTuning.maxDuration - VelocityTuning.minDuration)
        let slideFraction = VelocityTuning.minSlideFraction
            + velocityT * (VelocityTuning.maxSlideFraction - VelocityTuning.minSlideFraction)
        let shadowOpacity = Tuning.edgeShadowOpacity
            + Float(velocityT) * (VelocityTuning.fastShadowOpacity - Tuning.edgeShadowOpacity)
        let shadowWidth = Tuning.edgeShadowWidth
            + velocityT * (VelocityTuning.fastShadowWidth - Tuning.edgeShadowWidth)

        let slideDistance = pageWidth * slideFraction * direction.sign
        let originalPosition = layer.position

        // ── Edge shadow (velocity-scaled) ────────────────────────────────
        let shadow = makeVelocityShadow(
            height: layer.bounds.height,
            width: shadowWidth,
            direction: direction
        )
        let shadowX: CGFloat = direction == .forward
            ? layer.bounds.width : 0
        shadow.position = CGPoint(x: shadowX, y: layer.bounds.height / 2)
        layer.addSublayer(shadow)

        // ── Page-bend highlight ──────────────────────────────────────────
        let bend = makeBendHighlight(height: layer.bounds.height, direction: direction)
        let bendX: CGFloat = direction == .forward ? 0 : layer.bounds.width
        bend.position = CGPoint(x: bendX, y: layer.bounds.height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)

        let easeOut = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.25, 1.0)

        // ── Slide animation ──────────────────────────────────────────────
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue             = originalPosition.x
        slide.toValue               = originalPosition.x - slideDistance
        slide.duration              = duration
        slide.timingFunction        = easeOut
        slide.fillMode              = .forwards
        slide.isRemovedOnCompletion = false

        // ── Resistance transform ─────────────────────────────────────────
        let resist = CABasicAnimation(keyPath: "transform")
        let resistScale = Tuning.resistanceScaleX - velocityT * 0.02 // more resistance at speed
        let resistTransform = CATransform3DMakeScale(resistScale, 1.0, 1.0)
        resist.fromValue             = NSValue(caTransform3D: CATransform3DIdentity)
        resist.toValue               = NSValue(caTransform3D: resistTransform)
        resist.duration              = duration * 0.5
        resist.autoreverses          = true
        resist.timingFunction        = easeOut
        resist.fillMode              = .forwards
        resist.isRemovedOnCompletion = false

        // ── 3D perspective curl (AGENT-22) ───────────────────────────────
        // Subtle Y-axis rotation proportional to velocity — creates a
        // page-curl illusion.  Maximum 4° at full speed.
        let maxAngle = velocityT * (.pi / 45)  // ~4° at max velocity
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 800.0  // subtle perspective projection
        let curlTransform = CATransform3DRotate(perspective, maxAngle * direction.sign, 0, 1, 0)

        let curl = CABasicAnimation(keyPath: "transform")
        curl.fromValue             = NSValue(caTransform3D: CATransform3DIdentity)
        curl.toValue               = NSValue(caTransform3D: curlTransform)
        curl.duration              = duration * 0.6
        curl.autoreverses          = true
        curl.timingFunction        = easeOut
        curl.fillMode              = .forwards
        curl.isRemovedOnCompletion = false

        // ── Shadow fade ──────────────────────────────────────────────────
        let shadowFade = CAKeyframeAnimation(keyPath: "opacity")
        shadowFade.values            = [0.0, shadowOpacity, 0.0]
        shadowFade.keyTimes          = [0.0, 0.4, 1.0]
        shadowFade.duration          = duration
        shadowFade.timingFunction    = easeOut
        shadowFade.fillMode          = .forwards
        shadowFade.isRemovedOnCompletion = false

        // ── Bend highlight fade ──────────────────────────────────────────
        let bendFade = CAKeyframeAnimation(keyPath: "opacity")
        let bendPeak = Tuning.bendHighlightOpacity + Float(velocityT) * 0.04
        bendFade.values              = [0.0, bendPeak, 0.0]
        bendFade.keyTimes            = [0.0, 0.35, 1.0]
        bendFade.duration            = duration
        bendFade.timingFunction      = easeOut
        bendFade.fillMode            = .forwards
        bendFade.isRemovedOnCompletion = false

        // ── Commit ───────────────────────────────────────────────────────
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            layer.position  = originalPosition
            layer.transform = CATransform3DIdentity
            layer.removeAnimation(forKey: "pageSlide")
            layer.removeAnimation(forKey: "pageResist")
            layer.removeAnimation(forKey: "pageCurl")
            shadow.removeFromSuperlayer()
            bend.removeFromSuperlayer()
            self?.isTransitioning = false
            completion()
        }

        layer.add(slide, forKey: "pageSlide")
        layer.add(resist, forKey: "pageResist")
        layer.add(curl, forKey: "pageCurl")
        shadow.add(shadowFade, forKey: "shadowFade")
        bend.add(bendFade, forKey: "bendFade")

        CATransaction.commit()
    }

    /// Creates a velocity-scaled edge shadow with variable width.
    private func makeVelocityShadow(
        height: CGFloat,
        width: CGFloat,
        direction: PageTransitionDirection
    ) -> CAGradientLayer {
        let shadow = CAGradientLayer()
        shadow.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        shadow.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let clear = UIColor.clear.cgColor
        let dark  = UIColor.black.withAlphaComponent(0.30).cgColor

        if direction == .forward {
            shadow.colors     = [dark, clear]
            shadow.startPoint = CGPoint(x: 0, y: 0.5)
            shadow.endPoint   = CGPoint(x: 1, y: 0.5)
        } else {
            shadow.colors     = [clear, dark]
            shadow.startPoint = CGPoint(x: 0, y: 0.5)
            shadow.endPoint   = CGPoint(x: 1, y: 0.5)
        }

        shadow.opacity = 0
        return shadow
    }

    // MARK: - Interactive Page Drag (AGENT-22)

    /// Tuning for interactive drag-to-turn gestures.
    private enum InteractiveTuning {
        /// Fraction of page width required to commit the transition.
        static let commitThreshold: CGFloat = 0.30
        /// Spring damping for the finish/cancel snap-back animation.
        static let springDamping: CGFloat = 0.85
        /// Spring response for the finish/cancel animation (seconds).
        static let springResponse: TimeInterval = 0.35
        /// Maximum shadow opacity during interactive drag.
        static let dragShadowOpacity: Float = 0.22
        /// Maximum 3D rotation angle during interactive drag (radians).
        static let dragMaxRotation: CGFloat = .pi / 30  // ~6°
    }

    /// State tracking for an in-progress interactive drag.
    private var interactiveState: InteractiveDragState?

    /// Captures the state of an interactive drag-to-turn gesture.
    private struct InteractiveDragState {
        let direction: PageTransitionDirection
        let pageWidth: CGFloat
        let originalPosition: CGPoint
        let shadowLayer: CAGradientLayer
        let bendLayer: CAGradientLayer
        var progress: CGFloat = 0 // 0…1
    }

    /// Begins an interactive page drag.
    ///
    /// Creates the shadow and bend layers and stores the initial state.
    /// Call `updateInteractiveDrag(translation:)` as the gesture updates.
    ///
    /// - Parameters:
    ///   - layer: The page container layer.
    ///   - direction: `.forward` or `.backward`.
    ///   - pageWidth: The visible width of the page.
    func beginInteractiveDrag(
        on layer: CALayer,
        direction: PageTransitionDirection,
        pageWidth: CGFloat
    ) {
        guard interactiveState == nil, !isTransitioning else { return }
        if ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsPageTurnPhysics { return }

        let shadow = makeEdgeShadow(height: layer.bounds.height, direction: direction)
        let shadowX: CGFloat = direction == .forward ? layer.bounds.width : 0
        shadow.position = CGPoint(x: shadowX, y: layer.bounds.height / 2)
        layer.addSublayer(shadow)

        let bend = makeBendHighlight(height: layer.bounds.height, direction: direction)
        let bendX: CGFloat = direction == .forward ? 0 : layer.bounds.width
        bend.position = CGPoint(x: bendX, y: layer.bounds.height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)

        interactiveState = InteractiveDragState(
            direction: direction,
            pageWidth: pageWidth,
            originalPosition: layer.position,
            shadowLayer: shadow,
            bendLayer: bend
        )
    }

    /// Updates the interactive drag with the current gesture translation.
    ///
    /// Applies position offset, shadow opacity, bend highlight, and 3D
    /// perspective rotation proportional to the drag progress.
    ///
    /// - Parameters:
    ///   - layer: The page container layer.
    ///   - translation: Horizontal translation in points.
    func updateInteractiveDrag(on layer: CALayer, translation: CGFloat) {
        guard var state = interactiveState else { return }

        let rawProgress = abs(translation) / state.pageWidth
        let progress = min(max(rawProgress, 0), 1)
        state.progress = progress
        interactiveState = state

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Position offset
        let offsetX = -translation * Tuning.slideFraction * state.direction.sign
        layer.position = CGPoint(
            x: state.originalPosition.x + offsetX,
            y: state.originalPosition.y
        )

        // Shadow opacity proportional to progress
        state.shadowLayer.opacity = Float(progress) * InteractiveTuning.dragShadowOpacity

        // Bend highlight proportional to progress
        state.bendLayer.opacity = Float(progress) * Tuning.bendHighlightOpacity

        // 3D perspective rotation proportional to progress
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 800.0
        let angle = progress * InteractiveTuning.dragMaxRotation * state.direction.sign
        layer.transform = CATransform3DRotate(perspective, angle, 0, 1, 0)

        CATransaction.commit()
    }

    /// Finishes the interactive drag, committing or cancelling based on progress.
    ///
    /// If the drag exceeded `InteractiveTuning.commitThreshold`, the transition
    /// completes with a spring animation.  Otherwise it snaps back.
    ///
    /// - Parameters:
    ///   - layer: The page container layer.
    ///   - velocity: Horizontal velocity at gesture end (points/s).
    ///   - onCommit: Called if the page turn is committed.
    ///   - onCancel: Called if the page turn is cancelled.
    func finishInteractiveDrag(
        on layer: CALayer,
        velocity: CGFloat,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let state = interactiveState else { return }

        // Velocity boost: if the user flings quickly, commit even at low progress
        let velocityBoost = abs(velocity) > 800 ? CGFloat(0.2) : 0
        let shouldCommit = state.progress + velocityBoost >= InteractiveTuning.commitThreshold

        if shouldCommit {
            animateInteractiveCommit(on: layer, state: state, completion: onCommit)
        } else {
            animateInteractiveCancel(on: layer, state: state, completion: onCancel)
        }
    }

    /// Cancels the interactive drag, snapping back to the original position.
    ///
    /// - Parameters:
    ///   - layer: The page container layer.
    ///   - completion: Called when the cancel animation completes.
    func cancelInteractiveDrag(on layer: CALayer, completion: @escaping () -> Void) {
        guard let state = interactiveState else {
            completion()
            return
        }
        animateInteractiveCancel(on: layer, state: state, completion: completion)
    }

    // MARK: - Interactive Animation Helpers

    private func animateInteractiveCommit(
        on layer: CALayer,
        state: InteractiveDragState,
        completion: @escaping () -> Void
    ) {
        let slideTarget = state.originalPosition.x
            - state.pageWidth * Tuning.slideFraction * state.direction.sign

        UIView.animate(
            withDuration: InteractiveTuning.springResponse,
            delay: 0,
            usingSpringWithDamping: InteractiveTuning.springDamping,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            layer.position  = CGPoint(x: slideTarget, y: state.originalPosition.y)
            state.shadowLayer.opacity = 0
            state.bendLayer.opacity   = 0
            layer.transform = CATransform3DIdentity
        } completion: { [weak self] _ in
            layer.position  = state.originalPosition
            layer.transform = CATransform3DIdentity
            state.shadowLayer.removeFromSuperlayer()
            state.bendLayer.removeFromSuperlayer()
            self?.interactiveState = nil
            self?.isTransitioning = false
            completion()
        }
    }

    private func animateInteractiveCancel(
        on layer: CALayer,
        state: InteractiveDragState,
        completion: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: InteractiveTuning.springResponse,
            delay: 0,
            usingSpringWithDamping: InteractiveTuning.springDamping,
            initialSpringVelocity: 0.3,
            options: .curveEaseOut
        ) {
            layer.position  = state.originalPosition
            layer.transform = CATransform3DIdentity
            state.shadowLayer.opacity = 0
            state.bendLayer.opacity   = 0
        } completion: { [weak self] _ in
            state.shadowLayer.removeFromSuperlayer()
            state.bendLayer.removeFromSuperlayer()
            self?.interactiveState = nil
            self?.isTransitioning = false
            completion()
        }
    }
}
