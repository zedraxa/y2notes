import UIKit
import QuartzCore

// MARK: - Focus Mode Engine

/// Lightweight engine that applies subtle ambient effects to increase
/// writing immersion and reduce distraction.
///
/// Effects applied when focus mode is **active**:
///
/// 1. **Background dimming** — a semi-transparent dark overlay behind
///    the canvas dims surrounding chrome, pulling attention inward.
/// 2. **Vignette** — a radial gradient that gently darkens the edges of
///    the page, mimicking the natural fall-off of a desk lamp.
/// 3. **Reduced UI opacity** — toolbar and navigation elements become
///    more transparent (driven by `DrawingToolStore.toolbarOpacity`).
/// 4. **Soft paper glow** — a warm, very subtle inner glow on the
///    canvas layer that makes the page feel like real lit paper.
///
/// **Performance contract**: all effects are GPU-composited via Core
/// Animation.  No main-thread layout passes.  Total setup overhead
/// is < 0.3 ms (within `PerformanceConstraints.focusModeBudgetMs`).
///
/// **Reduce Motion**: when `UIAccessibility.isReduceMotionEnabled` is
/// `true`, transitions are instantaneous (no fade animation).
///
/// **Lifecycle**: create once per editor session.  Call `activate` /
/// `deactivate` as the user toggles focus mode.  Discard when the
/// editor is torn down.
final class FocusModeEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        /// Duration for the enter/exit crossfade (seconds).
        static let transitionDuration: CFTimeInterval = 0.35

        /// Reduced-motion instant transition duration.
        static let reducedMotionDuration: CFTimeInterval = 0.0

        // ── Background Dimming ─────────────────────────────────
        /// Opacity of the background dim overlay.  Should be barely
        /// perceptible — a hint, not a curtain.
        static let dimOverlayOpacity: Float = 0.12

        // ── Vignette ───────────────────────────────────────────
        /// Opacity of the radial vignette gradient.
        static let vignetteOpacity: Float = 0.18

        /// Fraction of the shorter dimension used as the clear zone.
        /// 0.45 means the center 45 % is fully clear.
        static let vignetteClearRadius: CGFloat = 0.45

        // ── Paper Glow ─────────────────────────────────────────
        /// Shadow radius for the warm inner glow.
        static let paperGlowRadius: CGFloat = 24.0
        /// Opacity of the glow shadow.
        static let paperGlowOpacity: Float = 0.08
        /// Warm off-white colour for the glow.
        static let paperGlowColor: UIColor = UIColor(
            red: 1.0, green: 0.97, blue: 0.90, alpha: 1.0
        )

        // ── UI Dimming ─────────────────────────────────────────
        /// Toolbar opacity when focus mode is active.
        static let focusToolbarOpacity: Double = 0.35
        /// Normal toolbar opacity.
        static let normalToolbarOpacity: Double = 1.0
    }

    // MARK: - State

    private let reduceMotion: Bool
    private(set) var isActive: Bool = false

    /// Ephemeral layers managed by the engine — removed on `deactivate`.
    private weak var dimLayer: CALayer?
    private weak var vignetteLayer: CAGradientLayer?

    init() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
    }

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    // MARK: - Transition Duration

    private var fadeDuration: CFTimeInterval {
        reduceMotion ? Tuning.reducedMotionDuration
        : (effectIntensity.allowsFocusModeOverlays ? Tuning.transitionDuration
           : Tuning.reducedMotionDuration)
    }

    // MARK: - Activate

    /// Activates focus mode on the given container layer.
    ///
    /// - Parameters:
    ///   - container: The root layer of the editor view (e.g. the canvas
    ///     superview's layer).  Dim and vignette sublayers are added here.
    ///   - canvasLayer: The `PKCanvasView`'s layer.  A warm inner glow is
    ///     applied to it.
    ///   - toolStore: The store whose `toolbarOpacity` is reduced.
    func activate(
        on container: CALayer,
        canvasLayer: CALayer,
        toolStore: DrawingToolStore
    ) {
        guard !isActive else { return }
        isActive = true

        let bounds = container.bounds

        // ── 1. Background dim overlay ───────────────────────────────────
        let dim = CALayer()
        dim.frame = bounds
        dim.backgroundColor = UIColor.black.cgColor
        dim.opacity = 0
        dim.zPosition = -1  // behind canvas content but inside container
        container.addSublayer(dim)
        self.dimLayer = dim

        animateOpacity(of: dim, to: Tuning.dimOverlayOpacity)

        // ── 2. Vignette (radial gradient) ───────────────────────────────
        let vignette = makeVignetteLayer(bounds: bounds)
        vignette.opacity = 0
        vignette.zPosition = 999  // in front — overlay effect
        container.addSublayer(vignette)
        self.vignetteLayer = vignette

        animateOpacity(of: vignette, to: Tuning.vignetteOpacity)

        // ── 3. Paper glow on canvas ─────────────────────────────────────
        applyPaperGlow(to: canvasLayer, fadeIn: true)

        // ── 4. Reduce toolbar opacity ───────────────────────────────────
        toolStore.toolbarOpacity = Tuning.focusToolbarOpacity
    }

    // MARK: - Deactivate

    /// Deactivates focus mode, removing all ambient layers.
    func deactivate(
        canvasLayer: CALayer,
        toolStore: DrawingToolStore
    ) {
        guard isActive else { return }
        isActive = false

        // Fade out and remove dim
        if let dim = dimLayer {
            animateOpacity(of: dim, to: 0) {
                dim.removeFromSuperlayer()
            }
        }

        // Fade out and remove vignette
        if let vignette = vignetteLayer {
            animateOpacity(of: vignette, to: 0) {
                vignette.removeFromSuperlayer()
            }
        }

        // Remove paper glow
        removePaperGlow(from: canvasLayer)

        // Restore toolbar opacity
        toolStore.toolbarOpacity = Tuning.normalToolbarOpacity
    }

    // MARK: - Layout Update

    /// Call when the container bounds change (e.g. rotation) while focus
    /// mode is active, so overlays resize correctly.
    func updateLayout(containerBounds: CGRect) {
        dimLayer?.frame = containerBounds
        if let vignette = vignetteLayer {
            vignette.frame = containerBounds
            updateVignetteGradient(vignette, bounds: containerBounds)
        }
    }

    // MARK: - Vignette Layer Factory

    private func makeVignetteLayer(bounds: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.frame = bounds
        updateVignetteGradient(layer, bounds: bounds)
        return layer
    }

    private func updateVignetteGradient(
        _ layer: CAGradientLayer,
        bounds: CGRect
    ) {
        let clear = UIColor.clear.cgColor
        let dark  = UIColor.black.cgColor

        layer.colors    = [clear, clear, dark]
        layer.locations = [
            0.0,
            NSNumber(value: Double(Tuning.vignetteClearRadius)),
            1.0
        ]

        // Radial gradient: center out.
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint   = CGPoint(x: 1.0, y: 1.0)
    }

    // MARK: - Paper Glow

    private func applyPaperGlow(to layer: CALayer, fadeIn: Bool) {
        layer.shadowColor  = Tuning.paperGlowColor.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = Tuning.paperGlowRadius

        if fadeIn {
            let anim                    = CABasicAnimation(keyPath: "shadowOpacity")
            anim.fromValue              = 0
            anim.toValue                = Tuning.paperGlowOpacity
            anim.duration               = fadeDuration
            anim.timingFunction         = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode               = .forwards
            anim.isRemovedOnCompletion  = false
            layer.add(anim, forKey: "focusPaperGlow")
        } else {
            layer.shadowOpacity = Tuning.paperGlowOpacity
        }
    }

    private func removePaperGlow(from layer: CALayer) {
        let anim                    = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue              = Tuning.paperGlowOpacity
        anim.toValue                = 0
        anim.duration               = fadeDuration
        anim.timingFunction         = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.shadowOpacity = 0
            layer.shadowRadius  = 0
            layer.removeAnimation(forKey: "focusPaperGlow")
            layer.removeAnimation(forKey: "focusPaperGlowOut")
        }
        layer.add(anim, forKey: "focusPaperGlowOut")
        CATransaction.commit()
    }

    // MARK: - Opacity Animation Helper

    private func animateOpacity(
        of layer: CALayer,
        to target: Float,
        completion: (() -> Void)? = nil
    ) {
        let anim                    = CABasicAnimation(keyPath: "opacity")
        anim.fromValue              = layer.opacity
        anim.toValue                = target
        anim.duration               = fadeDuration
        anim.timingFunction         = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode               = .forwards
        anim.isRemovedOnCompletion  = false

        if let completion = completion {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            layer.add(anim, forKey: nil)
            CATransaction.commit()
        } else {
            layer.add(anim, forKey: nil)
        }
    }
}
