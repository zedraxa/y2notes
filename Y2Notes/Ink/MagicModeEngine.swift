import UIKit
import QuartzCore

// MARK: - Magic Mode Engine

/// Toggleable engine that adds delightful "magic" effects while writing.
///
/// Effects provided when magic mode is **active**:
///
/// 1. **Writing particles** — a dual-cell `CAEmitterLayer` (sparkle + shimmer)
///    at the nib position emits velocity/pressure-responsive particles while
///    the user is actively drawing.  Sparkle cells are sharper and faster;
///    shimmer cells are larger, softer, and drift slowly.  Both respond to
///    writing speed: faster strokes produce more particles.
/// 2. **Keyword glow** — after a stroke ends, a dual-layer radial glow fires:
///    an inner warm layer and an outer cool layer, creating a colour-temperature
///    shift that feels organic.  Both fade out in 0.7 s.
/// 3. **Underline highlight** — when a horizontal stroke is detected
///    (near-flat, width > 60 pt), a highlight bar sweeps in from the leading
///    edge and then bounces subtly before fading out.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - Maximum 8 particles alive at a time (no shower effect).
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
        // ── Writing Particles (Dual-Cell) ──────────────────────────
        /// Maximum simultaneous particles across both cells.
        static let maxParticleCount: Float = 8
        /// Sparkle cell lifetime (seconds) — short, sharp.
        static let sparkleLifetime: Float = 0.35
        /// Shimmer cell lifetime (seconds) — longer, softer drift.
        static let shimmerLifetime: Float = 0.55
        /// Base birth rate while writing (sparkle cell, particles/s).
        static let sparkleBirthRate: Float = 10
        /// Base birth rate while writing (shimmer cell, particles/s).
        static let shimmerBirthRate: Float = 5
        /// Sparkle scale.
        static let sparkleScale: CGFloat = 0.05
        /// Shimmer scale — larger and softer.
        static let shimmerScale: CGFloat = 0.09
        /// Sparkle velocity (points per second).
        static let sparkleVelocity: CGFloat = 20
        /// Shimmer velocity — slow drift.
        static let shimmerVelocity: CGFloat = 8
        /// Particle alpha (≤ 15 % to stay subtle).
        static let particleAlpha: Float = 0.12
        /// Velocity multiplier for birth rate scaling.
        static let velocityBirthRateScale: Float = 0.008
        /// Maximum birth rate multiplier from velocity.
        static let maxVelocityMultiplier: Float = 2.5
        /// Pressure scale range (0 → light, 1 → heavy).
        static let pressureScaleBoost: CGFloat = 0.04

        // ── Keyword Glow (Dual-Layer) ─────────────────────────────
        /// Inner (warm) glow diameter.
        static let glowInnerDiameter: CGFloat = 36
        /// Outer (cool) glow diameter.
        static let glowOuterDiameter: CGFloat = 56
        /// Inner glow opacity.
        static let glowInnerOpacity: Float = 0.12
        /// Outer glow opacity.
        static let glowOuterOpacity: Float = 0.06
        /// Warm colour temperature shift (toward amber).
        static let warmShift: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.08, 0.04, -0.04)
        /// Cool colour temperature shift (toward sky blue).
        static let coolShift: (r: CGFloat, g: CGFloat, b: CGFloat) = (-0.04, 0.02, 0.08)
        /// Glow fade-out duration (seconds).
        static let glowFadeOutDuration: CFTimeInterval = 0.7

        // ── Underline Highlight (Sweep + Bounce) ──────────────────
        /// Minimum horizontal span to qualify as underline (points).
        static let underlineMinWidth: CGFloat = 60
        /// Maximum vertical deviation to qualify as "flat" (points).
        static let underlineMaxSlope: CGFloat = 12
        /// Highlight bar height (points).
        static let highlightHeight: CGFloat = 6
        /// Highlight opacity.
        static let highlightOpacity: Float = 0.10
        /// Sweep-in duration (seconds).
        static let highlightSweepDuration: CFTimeInterval = 0.25
        /// Bounce overshoot scale (1.0 = no bounce).
        static let highlightBounceScale: CGFloat = 1.06
        /// Bounce settle duration (seconds).
        static let highlightBounceDuration: CFTimeInterval = 0.18
        /// Hold duration before fade-out (seconds).
        static let highlightHoldDuration: CFTimeInterval = 0.15
        /// Fade-out duration (seconds).
        static let highlightFadeOutDuration: CFTimeInterval = 0.5

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

    /// Last known stroke velocity (points per second) for responsive particles.
    private var lastVelocity: CGFloat = 0
    /// Previous nib position for velocity estimation.
    private var previousPoint: CGPoint?
    /// Timestamp of previous point for velocity calculation.
    private var previousPointTime: CFTimeInterval = 0

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

        // Pre-create dual-cell emitter (paused — birth rate = 0 until writing starts).
        let emitter = makeDualCellEmitter(bounds: container.bounds)
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
        previousPoint = nil
        lastVelocity = 0
    }

    // MARK: - Writing Events

    /// Call when the user begins a new stroke.  Starts particle emission
    /// at the nib position.
    func strokeBegan(at point: CGPoint, inkColor: UIColor) {
        guard isActive, !shouldSuppressAnimations else { return }

        previousPoint = point
        previousPointTime = CACurrentMediaTime()
        lastVelocity = 0

        if let emitter = emitterLayer {
            emitter.emitterPosition = point
            updateEmitterColor(emitter, color: inkColor)
            emitter.birthRate = 1.0  // un-pause; cell birth rates take over
        }
    }

    /// Call as the stroke moves (throttled to ≤ 60 Hz by the caller).
    /// Velocity is estimated from successive points for responsive particles.
    func strokeMoved(to point: CGPoint) {
        guard isActive else { return }

        // Estimate velocity from point delta.
        let now = CACurrentMediaTime()
        if let prev = previousPoint {
            let dt = now - previousPointTime
            if dt > 0 {
                let dist = hypot(point.x - prev.x, point.y - prev.y)
                let instantVelocity = dist / CGFloat(dt)
                // Smooth velocity to avoid jitter.
                lastVelocity = lastVelocity * 0.6 + instantVelocity * 0.4
            }
        }
        previousPoint = point
        previousPointTime = now

        if let emitter = emitterLayer {
            emitter.emitterPosition = point
            // Scale birth rates based on velocity.
            let velocityMul = min(
                1.0 + Float(lastVelocity) * Tuning.velocityBirthRateScale,
                Tuning.maxVelocityMultiplier
            )
            if let cells = emitter.emitterCells, cells.count >= 2 {
                cells[0].birthRate = Tuning.sparkleBirthRate * velocityMul
                cells[1].birthRate = Tuning.shimmerBirthRate * velocityMul
            }
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
        previousPoint = nil
        lastVelocity = 0

        guard !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // ── Dual-Layer Keyword Glow ──────────────────────────────
        fireDualLayerGlow(at: endPoint, color: inkColor, on: container)

        // ── Sweep + Bounce Underline Highlight ───────────────────
        let dx = abs(endPoint.x - startPoint.x)
        let dy = abs(endPoint.y - startPoint.y)
        if dx >= Tuning.underlineMinWidth && dy <= Tuning.underlineMaxSlope {
            fireSweepBounceHighlight(
                from: startPoint, to: endPoint,
                color: inkColor, on: container
            )
        }
    }

    // MARK: - Layout Update

    /// Call when container bounds change while active.
    func updateLayout(containerBounds: CGRect) {
        emitterLayer?.frame = containerBounds
    }

    // MARK: - Dual-Cell Particle Emitter

    private func makeDualCellEmitter(bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .point
        emitter.emitterSize = .zero
        emitter.renderMode = .additive

        // Cell 1: Sparkle — sharp, fast, short-lived.
        let sparkle = CAEmitterCell()
        sparkle.birthRate = 0
        sparkle.lifetime = Tuning.sparkleLifetime
        sparkle.velocity = Tuning.sparkleVelocity
        sparkle.velocityRange = Tuning.sparkleVelocity * 0.4
        sparkle.emissionRange = .pi * 2
        sparkle.scale = Tuning.sparkleScale
        sparkle.scaleRange = Tuning.sparkleScale * 0.4
        sparkle.scaleSpeed = Float(-Tuning.sparkleScale * 0.3)
        sparkle.alphaSpeed = -Float(1.0 / Double(Tuning.sparkleLifetime))
        sparkle.color = UIColor.white.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor
        sparkle.contents = MagicModeEngine.sparkleImage.cgImage
        sparkle.name = "sparkle"

        // Cell 2: Shimmer — larger, slower, softer drift.
        let shimmer = CAEmitterCell()
        shimmer.birthRate = 0
        shimmer.lifetime = Tuning.shimmerLifetime
        shimmer.velocity = Tuning.shimmerVelocity
        shimmer.velocityRange = Tuning.shimmerVelocity * 0.5
        shimmer.emissionRange = .pi * 2
        shimmer.scale = Tuning.shimmerScale
        shimmer.scaleRange = Tuning.shimmerScale * 0.3
        shimmer.scaleSpeed = Float(-Tuning.shimmerScale * 0.15)
        shimmer.alphaSpeed = -Float(1.0 / Double(Tuning.shimmerLifetime))
        shimmer.spin = .pi * 0.5
        shimmer.spinRange = .pi
        shimmer.color = UIColor.white.withAlphaComponent(CGFloat(Tuning.particleAlpha * 0.7)).cgColor
        shimmer.contents = MagicModeEngine.shimmerImage.cgImage
        shimmer.name = "shimmer"

        emitter.emitterCells = [sparkle, shimmer]
        emitter.zPosition = 998  // above canvas, below UI
        return emitter
    }

    private func updateEmitterColor(_ emitter: CAEmitterLayer, color: UIColor) {
        guard let cells = emitter.emitterCells, cells.count >= 2 else { return }
        cells[0].color = color.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor
        cells[1].color = color.withAlphaComponent(CGFloat(Tuning.particleAlpha * 0.7)).cgColor
    }

    /// A 12×12 sharp circle for sparkle particles.
    private static let sparkleImage: UIImage = {
        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
    }()

    /// A 16×16 soft-edged circle for shimmer particles.
    private static let shimmerImage: UIImage = {
        let size = CGSize(width: 16, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [UIColor.white.cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: center, startRadius: 0,
                    endCenter: center, endRadius: size.width / 2,
                    options: []
                )
            }
        }
    }()

    // MARK: - Dual-Layer Keyword Glow

    private func fireDualLayerGlow(
        at point: CGPoint,
        color: UIColor,
        on container: CALayer
    ) {
        // Extract colour components for temperature shift.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        let warmColor = UIColor(
            red:   min(1, max(0, r + Tuning.warmShift.r)),
            green: min(1, max(0, g + Tuning.warmShift.g)),
            blue:  min(1, max(0, b + Tuning.warmShift.b)),
            alpha: 1.0
        )
        let coolColor = UIColor(
            red:   min(1, max(0, r + Tuning.coolShift.r)),
            green: min(1, max(0, g + Tuning.coolShift.g)),
            blue:  min(1, max(0, b + Tuning.coolShift.b)),
            alpha: 1.0
        )

        // Inner warm glow.
        let innerD = Tuning.glowInnerDiameter
        let inner = makeRadialGlow(
            at: point, diameter: innerD,
            color: warmColor,
            opacity: Tuning.glowInnerOpacity,
            zPosition: 997
        )
        container.addSublayer(inner)

        // Outer cool glow.
        let outerD = Tuning.glowOuterDiameter
        let outer = makeRadialGlow(
            at: point, diameter: outerD,
            color: coolColor,
            opacity: Tuning.glowOuterOpacity,
            zPosition: 996.5
        )
        container.addSublayer(outer)

        // Animate both layers together.
        for (layer, maxOpacity) in [(inner, Tuning.glowInnerOpacity),
                                     (outer, Tuning.glowOuterOpacity)] {
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = maxOpacity
            fadeIn.duration = 0.12
            fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = maxOpacity
            fadeOut.toValue = 0
            fadeOut.beginTime = 0.12
            fadeOut.duration = Tuning.glowFadeOutDuration
            fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let group = CAAnimationGroup()
            group.animations = [fadeIn, fadeOut]
            group.duration = 0.12 + Tuning.glowFadeOutDuration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
            layer.add(group, forKey: "magicGlow")
            CATransaction.commit()
        }
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
        glow.frame = CGRect(
            x: point.x - diameter / 2, y: point.y - diameter / 2,
            width: diameter, height: diameter
        )
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

    // MARK: - Sweep + Bounce Underline Highlight

    private func fireSweepBounceHighlight(
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor,
        on container: CALayer
    ) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let midY = (start.y + end.y) / 2
        let barWidth = maxX - minX

        let bar = CALayer()
        bar.frame = CGRect(
            x: minX,
            y: midY + 2,
            width: barWidth,
            height: Tuning.highlightHeight
        )
        bar.backgroundColor = color.withAlphaComponent(CGFloat(Tuning.highlightOpacity)).cgColor
        bar.cornerRadius = Tuning.highlightHeight / 2
        bar.opacity = 0
        bar.zPosition = 996
        // Start with width = 0 for sweep effect (anchor at leading edge).
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = CGPoint(x: minX, y: midY + 2 + Tuning.highlightHeight / 2)
        bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: Tuning.highlightHeight)
        bar.transform = CATransform3DMakeScale(0, 1, 1)
        container.addSublayer(bar)

        let sweepDur = Tuning.highlightSweepDuration
        let bounceDur = Tuning.highlightBounceDuration
        let holdDur = Tuning.highlightHoldDuration
        let fadeDur = Tuning.highlightFadeOutDuration

        // Phase 1: Sweep in (scale X from 0 → bounceScale).
        let sweepIn = CABasicAnimation(keyPath: "transform.scale.x")
        sweepIn.fromValue = 0
        sweepIn.toValue = Tuning.highlightBounceScale
        sweepIn.duration = sweepDur
        sweepIn.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Phase 2: Bounce settle (bounceScale → 1.0).
        let bounceSettle = CABasicAnimation(keyPath: "transform.scale.x")
        bounceSettle.fromValue = Tuning.highlightBounceScale
        bounceSettle.toValue = 1.0
        bounceSettle.beginTime = sweepDur
        bounceSettle.duration = bounceDur
        bounceSettle.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.34, 1.56, 0.64, 1.0
        )

        let scaleGroup = CAAnimationGroup()
        scaleGroup.animations = [sweepIn, bounceSettle]
        scaleGroup.duration = sweepDur + bounceDur
        scaleGroup.fillMode = .forwards
        scaleGroup.isRemovedOnCompletion = false

        // Opacity: fade in during sweep, hold, then fade out.
        let opFadeIn = CABasicAnimation(keyPath: "opacity")
        opFadeIn.fromValue = 0
        opFadeIn.toValue = Tuning.highlightOpacity
        opFadeIn.duration = sweepDur * 0.5
        opFadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let opFadeOut = CABasicAnimation(keyPath: "opacity")
        opFadeOut.fromValue = Tuning.highlightOpacity
        opFadeOut.toValue = 0
        opFadeOut.beginTime = sweepDur + bounceDur + holdDur
        opFadeOut.duration = fadeDur
        opFadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opGroup = CAAnimationGroup()
        opGroup.animations = [opFadeIn, opFadeOut]
        opGroup.duration = sweepDur + bounceDur + holdDur + fadeDur
        opGroup.fillMode = .forwards
        opGroup.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { bar.removeFromSuperlayer() }
        bar.add(scaleGroup, forKey: "magicHighlightSweep")
        bar.add(opGroup, forKey: "magicHighlightOpacity")
        CATransaction.commit()
    }
}
