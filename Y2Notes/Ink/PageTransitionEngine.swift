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

    // MARK: - Interactive Drag Tuning

    private enum InteractiveTuning {
        /// Fraction of page width that must be covered for the drag to commit.
        static let commitThreshold: CGFloat = 0.38
        /// Pan velocity (points/second) that counts as a committed swipe
        /// even when the drag hasn't crossed `commitThreshold`.
        static let commitVelocity: CGFloat = 400
        /// Damping ratio used for the commit spring animation.
        static let commitDamping: CGFloat = 0.82
        /// Damping ratio used for the cancel (spring-back) animation.
        static let cancelDamping: CGFloat = 0.70
        /// Duration cap for the spring snap animation (seconds).
        static let maxSnapDuration: TimeInterval = 0.48
        /// Translation multiplier when dragging in the wrong direction
        /// (rubber-band resistance).
        static let rubberBandFactor: CGFloat = 0.22
    }

    // MARK: - State

    private var isTransitioning: Bool = false

    // ── Interactive drag state ───────────────────────────────────────────────
    private var interactiveShadowLayer: CAGradientLayer?
    private var interactiveBendLayer: CAGradientLayer?
    private var interactiveDirection: PageTransitionDirection = .forward

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    // MARK: - Public API

    // MARK: - Velocity-Driven Tuning

    private enum VelocityTuning {
        /// Gesture velocity below which no speed scaling is applied.
        static let minVelocity: CGFloat = 200
        /// Gesture velocity at which maximum speed scaling is reached.
        static let maxVelocity: CGFloat = 1200
        /// Minimum duration multiplier at peak velocity (shortens the animation).
        static let minDurationScale: CGFloat = 0.70
        /// Extra slide fraction added at peak velocity for a "flung" feel.
        static let maxSlideFractionBoost: CGFloat = 0.08
    }

    // MARK: - Interactive (Pan-Gesture) Drag

    /// Prepares the engine for a live finger-tracked page drag.
    // MARK: New-page reveal

    /// Plays a "paper settle" reveal animation on a freshly created page layer.
    ///
    /// The effect simulates a blank sheet of paper being placed on the desk:
    /// - The layer slides gently upward from 10 pts below its resting position.
    /// - It scales from 0.98 → 1.0 with a spring bounce.
    /// - It fades from 0 → 1 over the first portion of the animation.
    ///
    /// Under **Reduce Motion** the reveal is a simple 0.15 s cross-fade.
    ///
    /// - Parameter layer: The container `CALayer` for the new page canvas.
    static func playNewPageReveal(on layer: CALayer) {
        if ReduceMotionObserver.shared.isEnabled {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue   = 1.0
            fade.duration  = 0.15
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.fillMode  = .backwards
            layer.add(fade, forKey: "newPageReveal")
            return
        }

        // Spring parameters tuned for a light, crisp paper-settle feel.
        let mass:              CGFloat = 0.9
        let stiffness:         CGFloat = 300
        let damping:           CGFloat = 24
        /// Initial scale of the new-page layer — just below full size so the spring
        /// overshoots slightly, mimicking a sheet of paper settling on a desk.
        let paperSettleInitialScale: CGFloat = 0.985

        // Slide up from +10 pts below
        let slide = CASpringAnimation(keyPath: "transform.translation.y")
        slide.fromValue         = 10.0
        slide.toValue           = 0.0
        slide.mass              = mass
        slide.stiffness         = stiffness
        slide.damping           = damping
        slide.initialVelocity   = 0
        slide.fillMode          = .backwards
        slide.isRemovedOnCompletion = true

        // Scale from paperSettleInitialScale → 1.0
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue         = paperSettleInitialScale
        scale.toValue           = 1.0
        scale.mass              = mass
        scale.stiffness         = stiffness
        scale.damping           = damping
        scale.initialVelocity   = 0
        scale.fillMode          = .backwards
        scale.isRemovedOnCompletion = true

        // Fade in over 0.20 s
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue          = 0.0
        fade.toValue            = 1.0
        fade.duration           = 0.20
        fade.timingFunction     = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode           = .backwards
        fade.isRemovedOnCompletion = true

        layer.add(slide, forKey: "newPageSlide")
        layer.add(scale, forKey: "newPageScale")
        layer.add(fade,  forKey: "newPageFade")
    }

    /// Plays a physical page transition on the given container layer.
    ///
    /// Call once when a two-finger pan gesture is recognised and its horizontal
    /// direction has been determined.  Attaches edge-shadow and bend-highlight
    /// sublayers to `view.layer` at opacity 0; they fade in as the drag proceeds.
    ///
    /// - Parameters:
    ///   - view: The UIView whose `transform` will be modified during the drag.
    ///   - direction: The page-turn direction for this drag.
    ///   - pageWidth: Visible width of the page, used to position decoration layers.
    func beginInteractiveDrag(
        on view: UIView,
        direction: PageTransitionDirection,
        pageWidth: CGFloat
    ) {
        guard !isTransitioning else { return }
        isTransitioning = true
        interactiveDirection = direction

        if ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsPageTurnPhysics {
            playReducedMotionTransition(on: layer, completion: completion)
            return
        }

        // Edge shadow
        let shadow = makeEdgeShadow(height: height, direction: direction)
        let shadowX: CGFloat = direction == .forward ? layer.bounds.width : 0
        shadow.position = CGPoint(x: shadowX, y: height / 2)
        shadow.opacity = 0
        layer.addSublayer(shadow)
        interactiveShadowLayer = shadow

        // Bend highlight
        let bend = makeBendHighlight(height: height, direction: direction)
        let bendX: CGFloat = direction == .forward ? 0 : layer.bounds.width
        bend.position = CGPoint(x: bendX, y: height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)
        interactiveBendLayer = bend
    }

    /// Updates the visual position of the page as the finger moves.
    ///
    /// Call on every `.changed` event from the pan gesture recognizer.
    /// Applies the translation to `view.transform` without animation so the
    /// page follows the finger exactly.  Shadow and bend opacity scale with
    /// drag progress.  Wrong-direction drags apply rubber-band resistance.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - translation: Horizontal finger translation in points (from `gesture.translation(in:)`).
    ///   - pageWidth: Visible page width.
    func updateInteractiveDrag(
        on view: UIView,
        translation: CGFloat,
        pageWidth: CGFloat
    ) {
        // Determine whether the drag is in the natural direction.
        let isNaturalDirection: Bool
        if interactiveDirection == .forward {
            isNaturalDirection = translation <= 0
        } else {
            isNaturalDirection = translation >= 0
        }

        // Apply rubber-band resistance for wrong-direction drags.
        let effectiveTranslation: CGFloat
        if isNaturalDirection {
            effectiveTranslation = translation
        } else {
            effectiveTranslation = translation * InteractiveTuning.rubberBandFactor
        }

        // Clamp to one full page width so the page can't fly too far off screen.
        let clampedTranslation = max(-pageWidth, min(pageWidth, effectiveTranslation))

        // Apply transform directly (no implicit animation) — we're outside any
        // animation block so setting view.transform is instant.
        view.transform = CGAffineTransform(translationX: clampedTranslation, y: 0)

        // Scale decoration opacity with drag progress.
        let progress = Float(min(abs(clampedTranslation) / pageWidth, 1.0))
        interactiveShadowLayer?.opacity = progress * Tuning.edgeShadowOpacity
        interactiveBendLayer?.opacity   = progress * Tuning.bendHighlightOpacity
    }

    /// Snaps the dragged page to its final position using spring physics.
    ///
    /// Decides whether the drag committed (page change) or cancelled (page
    /// returns to its origin) based on the current offset and release velocity.
    /// The `completion` closure is called on the main thread after the spring
    /// settles; `committed` is `true` when the page should actually change.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - velocityX: Horizontal velocity at release (from `gesture.velocity(in:).x`).
    ///   - pageWidth: Visible page width.
    ///   - completion: Called when the animation finishes. `committed` is `true` if
    ///     the drag exceeded the threshold and the page should change.
    func finishInteractiveDrag(
        on view: UIView,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        completion: @escaping (_ committed: Bool) -> Void
    ) {
        guard isTransitioning else {
            completion(false)
            return
        }

        let currentTranslation = view.transform.tx

        // Determine commit/cancel.
        let droppedPastThreshold: Bool
        let velocitySufficient: Bool
        if interactiveDirection == .forward {
            droppedPastThreshold = currentTranslation < -(pageWidth * InteractiveTuning.commitThreshold)
            velocitySufficient   = velocityX < -InteractiveTuning.commitVelocity
        } else {
            droppedPastThreshold = currentTranslation > pageWidth * InteractiveTuning.commitThreshold
            velocitySufficient   = velocityX > InteractiveTuning.commitVelocity
        }
        let committed = droppedPastThreshold || velocitySufficient

        // Target: commit → page fully off-screen; cancel → back to identity.
        let targetTranslation: CGFloat
        if committed {
            targetTranslation = interactiveDirection == .forward ? -pageWidth : pageWidth
        } else {
            targetTranslation = 0
        }

        // Normalised initial velocity for the spring (distance per second).
        let distance = abs(targetTranslation - currentTranslation)
        let normalizedVelocity = distance > 0 ? abs(velocityX) / distance : 0

        let dampingRatio = committed
            ? InteractiveTuning.commitDamping
            : InteractiveTuning.cancelDamping

        let shadowRef = interactiveShadowLayer
        let bendRef   = interactiveBendLayer

        UIView.animate(
            withDuration: InteractiveTuning.maxSnapDuration,
            delay: 0,
            usingSpringWithDamping: dampingRatio,
            initialSpringVelocity: normalizedVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            view.transform = targetTranslation == 0
                ? .identity
                : CGAffineTransform(translationX: targetTranslation, y: 0)
            shadowRef?.opacity = 0
            bendRef?.opacity   = 0
        } completion: { [weak self] _ in
            shadowRef?.removeFromSuperlayer()
            bendRef?.removeFromSuperlayer()
            if self?.interactiveShadowLayer === shadowRef { self?.interactiveShadowLayer = nil }
            if self?.interactiveBendLayer === bendRef     { self?.interactiveBendLayer   = nil }
            self?.isTransitioning = false
            completion(committed)
        }
    }

    /// Immediately springs the page back to its origin without committing.
    ///
    /// Call when the pan gesture is `.cancelled` or `.failed`.
    func cancelInteractiveDrag(on view: UIView, completion: @escaping () -> Void) {
        finishInteractiveDrag(on: view, velocityX: 0, pageWidth: view.bounds.width) { _ in
            completion()
        }
    }

    // MARK: - Interactive (Pan-Gesture) Drag

    /// Prepares the engine for a live finger-tracked page drag.
    ///
    /// Call once when a two-finger pan gesture is recognised and its horizontal
    /// direction has been determined.  Attaches edge-shadow and bend-highlight
    /// sublayers to `view.layer` at opacity 0; they fade in as the drag proceeds.
    ///
    /// - Parameters:
    ///   - view: The UIView whose `transform` will be modified during the drag.
    ///   - direction: The page-turn direction for this drag.
    ///   - pageWidth: Visible width of the page, used to position decoration layers.
    func beginInteractiveDrag(
        on view: UIView,
        direction: PageTransitionDirection,
        pageWidth: CGFloat
    ) {
        guard !isTransitioning else { return }
        isTransitioning = true
        interactiveDirection = direction

        let layer = view.layer
        let height = layer.bounds.height

        // Edge shadow
        let shadow = makeEdgeShadow(height: height, direction: direction)
        let shadowX: CGFloat = direction == .forward ? layer.bounds.width : 0
        shadow.position = CGPoint(x: shadowX, y: height / 2)
        shadow.opacity = 0
        layer.addSublayer(shadow)
        interactiveShadowLayer = shadow

        // Bend highlight
        let bend = makeBendHighlight(height: height, direction: direction)
        let bendX: CGFloat = direction == .forward ? 0 : layer.bounds.width
        bend.position = CGPoint(x: bendX, y: height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)
        interactiveBendLayer = bend
    }

    /// Updates the visual position of the page as the finger moves.
    ///
    /// Call on every `.changed` event from the pan gesture recognizer.
    /// Applies the translation to `view.transform` without animation so the
    /// page follows the finger exactly.  Shadow and bend opacity scale with
    /// drag progress.  Wrong-direction drags apply rubber-band resistance.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - translation: Horizontal finger translation in points (from `gesture.translation(in:)`).
    ///   - pageWidth: Visible page width.
    func updateInteractiveDrag(
        on view: UIView,
        translation: CGFloat,
        pageWidth: CGFloat
    ) {
        // Determine whether the drag is in the natural direction.
        let isNaturalDirection: Bool
        if interactiveDirection == .forward {
            isNaturalDirection = translation <= 0
        } else {
            isNaturalDirection = translation >= 0
        }

        // Apply rubber-band resistance for wrong-direction drags.
        let effectiveTranslation: CGFloat
        if isNaturalDirection {
            effectiveTranslation = translation
        } else {
            effectiveTranslation = translation * InteractiveTuning.rubberBandFactor
        }

        // Clamp to one full page width so the page can't fly too far off screen.
        let clampedTranslation = max(-pageWidth, min(pageWidth, effectiveTranslation))

        // Apply transform directly (no implicit animation) — we're outside any
        // animation block so setting view.transform is instant.
        view.transform = CGAffineTransform(translationX: clampedTranslation, y: 0)

        // Scale decoration opacity with drag progress.
        let progress = Float(min(abs(clampedTranslation) / pageWidth, 1.0))
        interactiveShadowLayer?.opacity = progress * Tuning.edgeShadowOpacity
        interactiveBendLayer?.opacity   = progress * Tuning.bendHighlightOpacity
    }

    /// Snaps the dragged page to its final position using spring physics.
    ///
    /// Decides whether the drag committed (page change) or cancelled (page
    /// returns to its origin) based on the current offset and release velocity.
    /// The `completion` closure is called on the main thread after the spring
    /// settles; `committed` is `true` when the page should actually change.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - velocityX: Horizontal velocity at release (from `gesture.velocity(in:).x`).
    ///   - pageWidth: Visible page width.
    ///   - completion: Called when the animation finishes. `committed` is `true` if
    ///     the drag exceeded the threshold and the page should change.
    func finishInteractiveDrag(
        on view: UIView,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        completion: @escaping (_ committed: Bool) -> Void
    ) {
        guard isTransitioning else {
            completion(false)
            return
        }

        let currentTranslation = view.transform.tx

        // Determine commit/cancel.
        let droppedPastThreshold: Bool
        let velocitySufficient: Bool
        if interactiveDirection == .forward {
            droppedPastThreshold = currentTranslation < -(pageWidth * InteractiveTuning.commitThreshold)
            velocitySufficient   = velocityX < -InteractiveTuning.commitVelocity
        } else {
            droppedPastThreshold = currentTranslation > pageWidth * InteractiveTuning.commitThreshold
            velocitySufficient   = velocityX > InteractiveTuning.commitVelocity
        }
        let committed = droppedPastThreshold || velocitySufficient

        // Target: commit → page fully off-screen; cancel → back to identity.
        let targetTranslation: CGFloat
        if committed {
            targetTranslation = interactiveDirection == .forward ? -pageWidth : pageWidth
        } else {
            targetTranslation = 0
        }

        // Normalised initial velocity for the spring (distance per second).
        let distance = abs(targetTranslation - currentTranslation)
        let normalizedVelocity = distance > 0 ? abs(velocityX) / distance : 0

        let dampingRatio = committed
            ? InteractiveTuning.commitDamping
            : InteractiveTuning.cancelDamping

        let shadowRef = interactiveShadowLayer
        let bendRef   = interactiveBendLayer

        UIView.animate(
            withDuration: InteractiveTuning.maxSnapDuration,
            delay: 0,
            usingSpringWithDamping: dampingRatio,
            initialSpringVelocity: normalizedVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            view.transform = targetTranslation == 0
                ? .identity
                : CGAffineTransform(translationX: targetTranslation, y: 0)
            shadowRef?.opacity = 0
            bendRef?.opacity   = 0
        } completion: { [weak self] _ in
            shadowRef?.removeFromSuperlayer()
            bendRef?.removeFromSuperlayer()
            if self?.interactiveShadowLayer === shadowRef { self?.interactiveShadowLayer = nil }
            if self?.interactiveBendLayer === bendRef     { self?.interactiveBendLayer   = nil }
            self?.isTransitioning = false
            completion(committed)
        }
    }

    /// Immediately springs the page back to its origin without committing.
    ///
    /// Call when the pan gesture is `.cancelled` or `.failed`.
    func cancelInteractiveDrag(on view: UIView, completion: @escaping () -> Void) {
        finishInteractiveDrag(on: view, velocityX: 0, pageWidth: view.bounds.width) { _ in
            completion()
        }
    }

    // MARK: - Interactive (Pan-Gesture) Drag

    /// Prepares the engine for a live finger-tracked page drag.
    ///
    /// Call once when a two-finger pan gesture is recognised and its horizontal
    /// direction has been determined.  Attaches edge-shadow and bend-highlight
    /// sublayers to `view.layer` at opacity 0; they fade in as the drag proceeds.
    ///
    /// - Parameters:
    ///   - view: The UIView whose `transform` will be modified during the drag.
    ///   - direction: The page-turn direction for this drag.
    ///   - pageWidth: Visible width of the page, used to position decoration layers.
    func beginInteractiveDrag(
        on view: UIView,
        direction: PageTransitionDirection,
        pageWidth: CGFloat
    ) {
        guard !isTransitioning else { return }
        isTransitioning = true
        interactiveDirection = direction

        let layer = view.layer
        let height = layer.bounds.height

        // Edge shadow
        let shadow = makeEdgeShadow(height: height, direction: direction)
        let shadowX: CGFloat = direction == .forward ? layer.bounds.width : 0
        shadow.position = CGPoint(x: shadowX, y: height / 2)
        shadow.opacity = 0
        layer.addSublayer(shadow)
        interactiveShadowLayer = shadow

        // Bend highlight
        let bend = makeBendHighlight(height: height, direction: direction)
        let bendX: CGFloat = direction == .forward ? 0 : layer.bounds.width
        bend.position = CGPoint(x: bendX, y: height / 2)
        bend.opacity = 0
        layer.addSublayer(bend)
        interactiveBendLayer = bend
    }

    /// Updates the visual position of the page as the finger moves.
    ///
    /// Call on every `.changed` event from the pan gesture recognizer.
    /// Applies the translation to `view.transform` without animation so the
    /// page follows the finger exactly.  Shadow and bend opacity scale with
    /// drag progress.  Wrong-direction drags apply rubber-band resistance.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - translation: Horizontal finger translation in points (from `gesture.translation(in:)`).
    ///   - pageWidth: Visible page width.
    func updateInteractiveDrag(
        on view: UIView,
        translation: CGFloat,
        pageWidth: CGFloat
    ) {
        // Determine whether the drag is in the natural direction.
        let isNaturalDirection: Bool
        if interactiveDirection == .forward {
            isNaturalDirection = translation <= 0
        } else {
            isNaturalDirection = translation >= 0
        }

        // Apply rubber-band resistance for wrong-direction drags.
        let effectiveTranslation: CGFloat
        if isNaturalDirection {
            effectiveTranslation = translation
        } else {
            effectiveTranslation = translation * InteractiveTuning.rubberBandFactor
        }

        // Clamp to one full page width so the page can't fly too far off screen.
        let clampedTranslation = max(-pageWidth, min(pageWidth, effectiveTranslation))

        // Apply transform directly (no implicit animation) — we're outside any
        // animation block so setting view.transform is instant.
        view.transform = CGAffineTransform(translationX: clampedTranslation, y: 0)

        // Scale decoration opacity with drag progress.
        let progress = Float(min(abs(clampedTranslation) / pageWidth, 1.0))
        interactiveShadowLayer?.opacity = progress * Tuning.edgeShadowOpacity
        interactiveBendLayer?.opacity   = progress * Tuning.bendHighlightOpacity
    }

    /// Snaps the dragged page to its final position using spring physics.
    ///
    /// Decides whether the drag committed (page change) or cancelled (page
    /// returns to its origin) based on the current offset and release velocity.
    /// The `completion` closure is called on the main thread after the spring
    /// settles; `committed` is `true` when the page should actually change.
    ///
    /// - Parameters:
    ///   - view: The view passed to `beginInteractiveDrag`.
    ///   - velocityX: Horizontal velocity at release (from `gesture.velocity(in:).x`).
    ///   - pageWidth: Visible page width.
    ///   - completion: Called when the animation finishes. `committed` is `true` if
    ///     the drag exceeded the threshold and the page should change.
    func finishInteractiveDrag(
        on view: UIView,
        velocityX: CGFloat,
        pageWidth: CGFloat,
        completion: @escaping (_ committed: Bool) -> Void
    ) {
        guard isTransitioning else {
            completion(false)
            return
        }

        let currentTranslation = view.transform.tx

        // Determine commit/cancel.
        let droppedPastThreshold: Bool
        let velocitySufficient: Bool
        if interactiveDirection == .forward {
            droppedPastThreshold = currentTranslation < -(pageWidth * InteractiveTuning.commitThreshold)
            velocitySufficient   = velocityX < -InteractiveTuning.commitVelocity
        } else {
            droppedPastThreshold = currentTranslation > pageWidth * InteractiveTuning.commitThreshold
            velocitySufficient   = velocityX > InteractiveTuning.commitVelocity
        }
        let committed = droppedPastThreshold || velocitySufficient

        // Target: commit → page fully off-screen; cancel → back to identity.
        let targetTranslation: CGFloat
        if committed {
            targetTranslation = interactiveDirection == .forward ? -pageWidth : pageWidth
        } else {
            targetTranslation = 0
        }

        // Normalised initial velocity for the spring (distance per second).
        let distance = abs(targetTranslation - currentTranslation)
        let normalizedVelocity = distance > 0 ? abs(velocityX) / distance : 0

        let dampingRatio = committed
            ? InteractiveTuning.commitDamping
            : InteractiveTuning.cancelDamping

        let shadowRef = interactiveShadowLayer
        let bendRef   = interactiveBendLayer

        UIView.animate(
            withDuration: InteractiveTuning.maxSnapDuration,
            delay: 0,
            usingSpringWithDamping: dampingRatio,
            initialSpringVelocity: normalizedVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            view.transform = targetTranslation == 0
                ? .identity
                : CGAffineTransform(translationX: targetTranslation, y: 0)
            shadowRef?.opacity = 0
            bendRef?.opacity   = 0
        } completion: { [weak self] _ in
            shadowRef?.removeFromSuperlayer()
            bendRef?.removeFromSuperlayer()
            if self?.interactiveShadowLayer === shadowRef { self?.interactiveShadowLayer = nil }
            if self?.interactiveBendLayer === bendRef     { self?.interactiveBendLayer   = nil }
            self?.isTransitioning = false
            completion(committed)
        }
    }

    /// Immediately springs the page back to its origin without committing.
    ///
    /// Call when the pan gesture is `.cancelled` or `.failed`.
    func cancelInteractiveDrag(on view: UIView, completion: @escaping () -> Void) {
        finishInteractiveDrag(on: view, velocityX: 0, pageWidth: view.bounds.width) { _ in
            completion()
        }
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

        // Position offset — translation is already signed to match the
        // drag direction so the page follows the finger directly.
        let offsetX = translation * Tuning.slideFraction
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
