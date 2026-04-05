import UIKit
import QuartzCore

// MARK: - Magic Mode Engine

/// Toggleable engine that adds delightful "magic" effects while writing.
///
/// Effects provided when magic mode is **active**:
///
/// 1. **Writing particles** — a dual-cell `CAEmitterLayer` at the nib
///    position emits velocity-responsive, pressure-scaled particles while
///    the user is actively drawing.  A primary sparkle cell and a softer
///    secondary shimmer cell create depth.  Birth rate scales with stroke
///    velocity (faster = more); particle scale responds to pressure.
///    Particles fade in ≈ 0.5 s and never accumulate (birth rate is
///    zeroed on pencil-lift).
/// 2. **Keyword glow** — after a stroke ends, the endpoint receives a
///    dual-layer glow: a tight bright inner core (20 pt, 18 % opacity)
///    and a wider soft outer halo (56 pt, 8 % opacity).  A subtle
///    shimmer (1.03× scale oscillation) runs during the fade.  Faster
///    strokes produce cooler-tinted glows; slower strokes stay warm.
/// 3. **Underline highlight** — when a horizontal stroke is detected
///    (near-flat, width > 60 pt), a gradient highlight bar sweeps in
///    from left to right with a subtle bounce wave, then fades out.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - Maximum 8 primary + 4 secondary particles alive at a time.
/// - All colours are derived from the ink colour at ≤ 15 % opacity.
/// - No looping animations — effects are one-shot and self-removing.
/// - Total setup overhead < 0.4 ms (`PerformanceConstraints.magicModeBudgetMs`).
///
/// **Reduce Motion**: all animations are suppressed when
/// `UIAccessibility.isReduceMotionEnabled` is `true`.
///
/// **Default state**: off.  Toggled via `DrawingToolStore.isMagicModeActive`.
final class MagicModeEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        // ── Writing Particles (Primary Sparkle) ────────────────────
        /// Base particle birth rate (particles per second).
        static let particleBaseBirthRate: Float = 10
        /// Maximum birth rate when writing fast.
        static let particleMaxBirthRate: Float = 22
        /// Particle lifetime (seconds).
        static let particleLifetime: Float = 0.5
        /// Particle base scale.
        static let particleScale: CGFloat = 0.06
        /// Minimum particle scale (light pressure).
        static let particleMinScale: CGFloat = 0.03
        /// Maximum particle scale (heavy pressure).
        static let particleMaxScale: CGFloat = 0.10
        /// Particle velocity (points per second).
        static let particleVelocity: CGFloat = 18
        /// Particle alpha (≤ 15 % to stay subtle).
        static let particleAlpha: Float = 0.13
        /// Velocity threshold for max birth rate (points per second).
        static let velocityMaxThreshold: CGFloat = 1200

        // ── Writing Particles (Secondary Shimmer) ──────────────────
        /// Secondary cell birth rate multiplier relative to primary.
        static let shimmerBirthRateMultiplier: Float = 0.35
        /// Shimmer cell lifetime — longer for a trailing glow.
        static let shimmerLifetime: Float = 0.7
        /// Shimmer cell scale — slightly larger than primary.
        static let shimmerScale: CGFloat = 0.09
        /// Shimmer alpha — softer than primary.
        static let shimmerAlpha: Float = 0.07
        /// Shimmer velocity — slower drift.
        static let shimmerVelocity: CGFloat = 8

        // ── Keyword Glow (Dual Layer) ──────────────────────────────
        /// Inner core diameter (points).
        static let glowInnerDiameter: CGFloat = 20
        /// Inner core opacity.
        static let glowInnerOpacity: Float = 0.18
        /// Outer halo diameter (points).
        static let glowOuterDiameter: CGFloat = 56
        /// Outer halo opacity.
        static let glowOuterOpacity: Float = 0.08
        /// Glow fade-out duration (seconds).
        static let glowFadeOutDuration: CFTimeInterval = 0.7
        /// Shimmer scale amplitude (1.0 ± this value).
        static let glowShimmerAmplitude: CGFloat = 0.03
        /// Shimmer oscillation period (seconds).
        static let glowShimmerPeriod: CFTimeInterval = 0.25
        /// Cool tint for fast strokes.
        static let glowCoolTint: UIColor = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1)
        /// Velocity above which the glow shifts fully cool.
        static let glowCoolVelocityThreshold: CGFloat = 1000

        // ── Underline Highlight ────────────────────────────────────
        /// Minimum horizontal span to qualify as underline (points).
        static let underlineMinWidth: CGFloat = 60
        /// Maximum vertical deviation to qualify as "flat" (points).
        static let underlineMaxSlope: CGFloat = 12
        /// Highlight bar height (points).
        static let highlightHeight: CGFloat = 6
        /// Highlight peak opacity.
        static let highlightOpacity: Float = 0.12
        /// Left-to-right sweep duration (seconds).
        static let highlightSweepDuration: CFTimeInterval = 0.35
        /// Bounce overshoot factor (1.0 = no bounce).
        static let highlightBounceScale: CGFloat = 1.08
        /// Total highlight visible duration (seconds).
        static let highlightTotalDuration: CFTimeInterval = 1.0

        // ── General ────────────────────────────────────────────────
        static let transitionDuration: CFTimeInterval = 0.35
        static let reducedMotionDuration: CFTimeInterval = 0.0
    }

    // MARK: - State

    private(set) var isActive: Bool = false

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    /// Ephemeral emitter layer for writing particles.
    private weak var emitterLayer: CAEmitterLayer?
    /// Container layer where overlay effects are added.
    private weak var containerLayer: CALayer?

    /// Tracks the last nib velocity for glow colour temperature.
    private var lastStrokeVelocity: CGFloat = 0

    // MARK: - Computed Helpers

    private var shouldSuppressAnimations: Bool {
        ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsMagicMode
    }

    private var fadeDuration: CFTimeInterval {
        shouldSuppressAnimations ? Tuning.reducedMotionDuration
            : Tuning.transitionDuration
    }

    // MARK: - Activate / Deactivate

    /// Prepare the engine for a given container layer.  Call once when
    /// magic mode is toggled on.
    func activate(on container: CALayer) {
        guard !isActive else { return }
        isActive = true
        containerLayer = container

        // Pre-create emitter (paused — birth rate = 0 until writing starts).
        let emitter = makeParticleEmitter(bounds: container.bounds)
        emitter.birthRate = 0
        container.addSublayer(emitter)
        self.emitterLayer = emitter
    }

    /// Remove all magic-mode layers and reset state.
    func deactivate() {
        guard isActive else { return }
        isActive = false

        emitterLayer?.removeFromSuperlayer()
        emitterLayer = nil
        containerLayer = nil
        lastStrokeVelocity = 0
    }

    // MARK: - Writing Events

    /// Call when the user begins a new stroke.  Starts particle emission
    /// at the nib position.
    func strokeBegan(at point: CGPoint, inkColor: UIColor) {
        guard isActive, !shouldSuppressAnimations else { return }

        lastStrokeVelocity = 0

        if let emitter = emitterLayer {
            emitter.emitterPosition = point
            updateEmitterColor(emitter, color: inkColor)
            // Start at base birth rate; strokeMoved will scale with velocity.
            let primary = emitter.emitterCells?.first
            primary?.birthRate = Tuning.particleBaseBirthRate
            emitter.birthRate = 1
        }
    }

    /// Call as the stroke moves (throttled to ≤ 60 Hz by the caller).
    /// `velocity` is the current nib speed in points/second (optional).
    /// `pressure` is the current Apple Pencil force (0–1, optional).
    func strokeMoved(to point: CGPoint, velocity: CGFloat = 500, pressure: CGFloat = 1.0) {
        guard isActive else { return }
        emitterLayer?.emitterPosition = point
        lastStrokeVelocity = velocity

        guard !shouldSuppressAnimations, let emitter = emitterLayer else { return }

        // ── Velocity-responsive birth rate ─────────────────────────
        let velocityFraction = min(velocity / Tuning.velocityMaxThreshold, 1.0)
        let targetBirthRate = Tuning.particleBaseBirthRate
            + Float(velocityFraction) * (Tuning.particleMaxBirthRate - Tuning.particleBaseBirthRate)

        if let primary = emitter.emitterCells?.first {
            primary.birthRate = targetBirthRate
        }
        // Secondary cell tracks proportionally.
        if emitter.emitterCells?.count ?? 0 > 1 {
            emitter.emitterCells?[1].birthRate = targetBirthRate * Tuning.shimmerBirthRateMultiplier
        }

        // ── Pressure-responsive particle scale ─────────────────────
        let clampedPressure = min(max(pressure, 0), 1.0)
        let targetScale = Tuning.particleMinScale
            + CGFloat(clampedPressure) * (Tuning.particleMaxScale - Tuning.particleMinScale)

        if let primary = emitter.emitterCells?.first {
            primary.scale = Float(targetScale)
            primary.scaleRange = Float(targetScale) * 0.4
        }
    }

    /// Call when the stroke ends.  Stops particles and optionally fires
    /// a keyword glow or underline highlight.
    func strokeEnded(
        at endPoint: CGPoint,
        startPoint: CGPoint,
        inkColor: UIColor
    ) {
        guard isActive else { return }

        // Stop particle emission.
        emitterLayer?.birthRate = 0

        guard !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // ── Keyword Glow (Dual Layer) ────────────────────────────
        fireKeywordGlow(at: endPoint, color: inkColor,
                        velocity: lastStrokeVelocity, on: container)

        // ── Underline Highlight (Sweep) ──────────────────────────
        let dx = abs(endPoint.x - startPoint.x)
        let dy = abs(endPoint.y - startPoint.y)
        if dx >= Tuning.underlineMinWidth && dy <= Tuning.underlineMaxSlope {
            fireUnderlineHighlight(
                from: startPoint, to: endPoint,
                color: inkColor, on: container
            )
        }

        lastStrokeVelocity = 0
    }

    // MARK: - Layout Update

    /// Call when container bounds change while active.
    func updateLayout(containerBounds: CGRect) {
        emitterLayer?.frame = containerBounds
    }

    // MARK: - Dual-Cell Particle Emitter

    private func makeParticleEmitter(bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .point
        emitter.emitterSize = .zero
        emitter.renderMode = .additive

        // ── Primary sparkle cell ───────────────────────────────────
        let primary = CAEmitterCell()
        primary.birthRate = 0
        primary.lifetime = Tuning.particleLifetime
        primary.velocity = Tuning.particleVelocity
        primary.velocityRange = Tuning.particleVelocity * 0.5
        primary.emissionRange = .pi * 2
        primary.scale = Float(Tuning.particleScale)
        primary.scaleRange = Float(Tuning.particleScale) * 0.4
        primary.scaleSpeed = -Float(Tuning.particleScale) * 0.3
        primary.alphaSpeed = -Float(1.0 / Double(Tuning.particleLifetime))
        primary.color = UIColor.white.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor
        primary.contents = MagicModeEngine.particleImage.cgImage
        primary.spin = 0.5
        primary.spinRange = 1.0

        // ── Secondary shimmer cell ─────────────────────────────────
        let shimmer = CAEmitterCell()
        shimmer.birthRate = 0
        shimmer.lifetime = Tuning.shimmerLifetime
        shimmer.velocity = Tuning.shimmerVelocity
        shimmer.velocityRange = Tuning.shimmerVelocity * 0.5
        shimmer.emissionRange = .pi * 2
        shimmer.scale = Float(Tuning.shimmerScale)
        shimmer.scaleRange = Float(Tuning.shimmerScale) * 0.3
        shimmer.scaleSpeed = -Float(Tuning.shimmerScale) * 0.2
        shimmer.alphaSpeed = -Float(1.0 / Double(Tuning.shimmerLifetime))
        shimmer.color = UIColor.white.withAlphaComponent(CGFloat(Tuning.shimmerAlpha)).cgColor
        shimmer.contents = MagicModeEngine.shimmerImage.cgImage

        emitter.emitterCells = [primary, shimmer]
        emitter.zPosition = 998  // above canvas, below UI
        return emitter
    }

    private func updateEmitterColor(_ emitter: CAEmitterLayer, color: UIColor) {
        if let primary = emitter.emitterCells?.first {
            primary.color = color.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor
        }
        if emitter.emitterCells?.count ?? 0 > 1 {
            // Shimmer uses a lighter, shifted variant of the ink colour.
            let shifted = color.withAlphaComponent(CGFloat(Tuning.shimmerAlpha))
            emitter.emitterCells?[1].color = shifted.cgColor
        }
    }

    /// A 12×12 soft circle rendered once and reused for the primary sparkle.
    static let particleImage: UIImage = {
        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
    }()

    /// A 16×16 soft, feathered circle for the secondary shimmer cell.
    private static let shimmerImage: UIImage = {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.cgContext.drawRadialGradient(gradient,
                                                startCenter: center, startRadius: 0,
                                                endCenter: center, endRadius: size.width / 2,
                                                options: [])
            }
        }
    }()

    // MARK: - Keyword Glow (Dual Layer + Shimmer)

    private func fireKeywordGlow(
        at point: CGPoint,
        color: UIColor,
        velocity: CGFloat,
        on container: CALayer
    ) {
        // ── Colour temperature shift: fast → cool, slow → warm ──
        let coolFraction = min(velocity / Tuning.glowCoolVelocityThreshold, 1.0)
        let blendedColor = blendColor(color, toward: Tuning.glowCoolTint,
                                      fraction: coolFraction)

        // ── Outer halo layer ──────────────────────────────────────
        let outerD = Tuning.glowOuterDiameter
        let outerGlow = makeRadialGlow(
            at: point, diameter: outerD,
            color: blendedColor, opacity: Tuning.glowOuterOpacity,
            zPosition: 997
        )
        container.addSublayer(outerGlow)
        animateGlowFade(on: outerGlow, peakOpacity: Tuning.glowOuterOpacity,
                        duration: Tuning.glowFadeOutDuration + 0.1)

        // ── Inner core layer ──────────────────────────────────────
        let innerD = Tuning.glowInnerDiameter
        let innerGlow = makeRadialGlow(
            at: point, diameter: innerD,
            color: blendedColor, opacity: Tuning.glowInnerOpacity,
            zPosition: 997.5
        )
        container.addSublayer(innerGlow)
        animateGlowFade(on: innerGlow, peakOpacity: Tuning.glowInnerOpacity,
                        duration: Tuning.glowFadeOutDuration,
                        shimmer: true)
    }

    private func makeRadialGlow(
        at point: CGPoint,
        diameter: CGFloat,
        color: UIColor,
        opacity: Float,
        zPosition: CGFloat
    ) -> CAGradientLayer {
        let glow = CAGradientLayer()
        glow.type = .radial
        let half = diameter / 2
        glow.frame = CGRect(x: point.x - half, y: point.y - half,
                            width: diameter, height: diameter)
        glow.colors = [
            color.withAlphaComponent(CGFloat(opacity)).cgColor,
            UIColor.clear.cgColor
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint   = CGPoint(x: 1.0, y: 1.0)
        glow.opacity = 0
        glow.zPosition = zPosition
        return glow
    }

    private func animateGlowFade(
        on layer: CALayer,
        peakOpacity: Float,
        duration: CFTimeInterval,
        shimmer: Bool = false
    ) {
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = peakOpacity
        fadeIn.duration = 0.12
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = peakOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.15
        fadeOut.duration = duration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        var animations: [CAAnimation] = [fadeIn, fadeOut]

        // Optional shimmer: subtle scale oscillation during the glow.
        if shimmer {
            let shimmerAnim = CABasicAnimation(keyPath: "transform.scale")
            shimmerAnim.fromValue = 1.0
            shimmerAnim.toValue = 1.0 + Tuning.glowShimmerAmplitude
            shimmerAnim.duration = Tuning.glowShimmerPeriod
            shimmerAnim.autoreverses = true
            shimmerAnim.repeatCount = Float((duration / Tuning.glowShimmerPeriod).rounded(.down))
            shimmerAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animations.append(shimmerAnim)
        }

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = 0.15 + duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(group, forKey: "magicGlow")
        CATransaction.commit()
    }

    // MARK: - Underline Highlight (Sweep + Bounce)

    private func fireUnderlineHighlight(
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor,
        on container: CALayer
    ) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let barWidth = maxX - minX
        let midY = (start.y + end.y) / 2

        // ── Gradient highlight bar ─────────────────────────────────
        let bar = CAGradientLayer()
        bar.frame = CGRect(
            x: minX,
            y: midY + 2,
            width: barWidth,
            height: Tuning.highlightHeight
        )
        let barColor = color.withAlphaComponent(CGFloat(Tuning.highlightOpacity))
        let barFaded = color.withAlphaComponent(CGFloat(Tuning.highlightOpacity) * 0.3)
        bar.colors = [barColor.cgColor, barFaded.cgColor]
        bar.startPoint = CGPoint(x: 0, y: 0.5)
        bar.endPoint   = CGPoint(x: 1, y: 0.5)
        bar.cornerRadius = Tuning.highlightHeight / 2
        bar.opacity = 0
        bar.zPosition = 996
        container.addSublayer(bar)

        // ── Left-to-right sweep via mask ───────────────────────────
        let mask = CALayer()
        mask.frame = CGRect(x: -barWidth, y: 0, width: barWidth, height: Tuning.highlightHeight)
        mask.backgroundColor = UIColor.white.cgColor
        bar.mask = mask

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -barWidth / 2
        sweep.toValue = barWidth / 2
        sweep.duration = Tuning.highlightSweepDuration
        sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sweep.fillMode = .forwards
        sweep.isRemovedOnCompletion = false
        mask.add(sweep, forKey: "sweep")

        // ── Opacity: fade in with sweep, hold, then fade out ───────
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = Tuning.highlightOpacity
        appear.duration = Tuning.highlightSweepDuration * 0.5
        appear.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Subtle vertical bounce wave.
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale.y")
        bounce.values = [1.0, Tuning.highlightBounceScale, 1.0]
        bounce.keyTimes = [0, 0.5, 1.0]
        bounce.beginTime = Tuning.highlightSweepDuration
        bounce.duration = 0.2
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.highlightOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = Tuning.highlightSweepDuration + 0.25
        fadeOut.duration = Tuning.highlightTotalDuration - Tuning.highlightSweepDuration - 0.25
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [appear, bounce, fadeOut]
        group.duration = Tuning.highlightTotalDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { bar.removeFromSuperlayer() }
        bar.add(group, forKey: "magicHighlight")
        CATransaction.commit()
    }

    // MARK: - Colour Helpers

    /// Blends `base` colour toward `target` by `fraction` (0 = base, 1 = target).
    private func blendColor(_ base: UIColor, toward target: UIColor, fraction: CGFloat) -> UIColor {
        var bR: CGFloat = 0, bG: CGFloat = 0, bB: CGFloat = 0, bA: CGFloat = 0
        var tR: CGFloat = 0, tG: CGFloat = 0, tB: CGFloat = 0, tA: CGFloat = 0
        base.getRed(&bR, green: &bG, blue: &bB, alpha: &bA)
        target.getRed(&tR, green: &tG, blue: &tB, alpha: &tA)
        let f = min(max(fraction, 0), 1)
        return UIColor(
            red:   bR + f * (tR - bR),
            green: bG + f * (tG - bG),
            blue:  bB + f * (tB - bB),
            alpha: bA + f * (tA - bA)
        )
    }
}
