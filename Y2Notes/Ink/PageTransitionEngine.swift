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

    private let reduceMotion: Bool
    private var isTransitioning: Bool = false

    init() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
    }

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

        if reduceMotion {
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
}
