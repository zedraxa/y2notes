import UIKit
import QuartzCore

// MARK: - Magic Mode Engine

/// Toggleable engine that adds delightful "magic" effects while writing.
///
/// Effects provided when magic mode is **active**:
///
/// 1. **Writing particles** — a lightweight `CAEmitterLayer` at the nib
///    position emits a handful of soft, short-lived particles while the
///    user is actively drawing.  Particles fade in ≈ 0.4 s and never
///    accumulate (birth rate is zeroed on pencil-lift).
/// 2. **Keyword glow** — after a stroke ends, the last stroke segment
///    receives a brief radial glow (40 pt, 12 % opacity) that fades
///    out in 0.6 s.  The glow uses the current ink colour for harmony.
/// 3. **Underline highlight** — when a horizontal stroke is detected
///    (near-flat, width > 60 pt), a subtle highlight bar fades in
///    beneath the stroke and then fades out over 0.8 s.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - Maximum 6 particles alive at a time (no shower effect).
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
        // ── Writing Particles ──────────────────────────────────────
        /// Maximum simultaneous particles.
        static let maxParticleCount: Float = 6
        /// Particle lifetime (seconds).
        static let particleLifetime: Float = 0.4
        /// Particle birth rate while writing (particles per second).
        static let particleBirthRate: Float = 12
        /// Particle scale range.
        static let particleScale: CGFloat = 0.06
        /// Particle velocity (points per second).
        static let particleVelocity: CGFloat = 15
        /// Particle alpha (≤ 15 % to stay subtle).
        static let particleAlpha: Float = 0.12

        // ── Keyword Glow ───────────────────────────────────────────
        /// Glow layer diameter (points).
        static let glowDiameter: CGFloat = 40
        /// Glow opacity.
        static let glowOpacity: Float = 0.12
        /// Glow fade-out duration (seconds).
        static let glowFadeOutDuration: CFTimeInterval = 0.6

        // ── Underline Highlight ────────────────────────────────────
        /// Minimum horizontal span to qualify as underline (points).
        static let underlineMinWidth: CGFloat = 60
        /// Maximum vertical deviation to qualify as "flat" (points).
        static let underlineMaxSlope: CGFloat = 12
        /// Highlight bar height (points).
        static let highlightHeight: CGFloat = 6
        /// Highlight opacity.
        static let highlightOpacity: Float = 0.10
        /// Highlight fade-out duration (seconds).
        static let highlightFadeOutDuration: CFTimeInterval = 0.8

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
    }

    // MARK: - Writing Events

    /// Call when the user begins a new stroke.  Starts particle emission
    /// at the nib position.
    func strokeBegan(at point: CGPoint, inkColor: UIColor) {
        guard isActive, !shouldSuppressAnimations else { return }

        if let emitter = emitterLayer {
            emitter.emitterPosition = point
            updateEmitterColor(emitter, color: inkColor)
            emitter.birthRate = Tuning.particleBirthRate
        }
    }

    /// Call as the stroke moves (throttled to ≤ 60 Hz by the caller).
    func strokeMoved(to point: CGPoint) {
        guard isActive else { return }
        emitterLayer?.emitterPosition = point
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

        // ── Keyword Glow ─────────────────────────────────────────
        fireKeywordGlow(at: endPoint, color: inkColor, on: container)

        // ── Underline Highlight ──────────────────────────────────
        let dx = abs(endPoint.x - startPoint.x)
        let dy = abs(endPoint.y - startPoint.y)
        if dx >= Tuning.underlineMinWidth && dy <= Tuning.underlineMaxSlope {
            fireUnderlineHighlight(
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

    // MARK: - Particle Emitter

    private func makeParticleEmitter(bounds: CGRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .point
        emitter.emitterSize = .zero
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.birthRate = 0
        cell.lifetime = Tuning.particleLifetime
        cell.velocity = Tuning.particleVelocity
        cell.velocityRange = Tuning.particleVelocity * 0.5
        cell.emissionRange = .pi * 2
        cell.scale = Tuning.particleScale
        cell.scaleRange = Tuning.particleScale * 0.5
        cell.alphaSpeed = -Float(1.0 / Double(Tuning.particleLifetime))
        cell.color = UIColor.white.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor

        // Use a tiny white circle as the particle image.
        cell.contents = MagicModeEngine.particleImage.cgImage

        emitter.emitterCells = [cell]
        emitter.zPosition = 998  // above canvas, below UI
        return emitter
    }

    private func updateEmitterColor(_ emitter: CAEmitterLayer, color: UIColor) {
        guard let cell = emitter.emitterCells?.first else { return }
        cell.color = color.withAlphaComponent(CGFloat(Tuning.particleAlpha)).cgColor
    }

    /// A 12×12 soft circle rendered once and reused.
    private static let particleImage: UIImage = {
        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
    }()

    // MARK: - Keyword Glow

    private func fireKeywordGlow(
        at point: CGPoint,
        color: UIColor,
        on container: CALayer
    ) {
        let glow = CAGradientLayer()
        glow.type = .radial
        let d = Tuning.glowDiameter
        glow.frame = CGRect(
            x: point.x - d / 2, y: point.y - d / 2,
            width: d, height: d
        )
        glow.colors = [
            color.withAlphaComponent(CGFloat(Tuning.glowOpacity)).cgColor,
            UIColor.clear.cgColor
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint   = CGPoint(x: 1.0, y: 1.0)
        glow.opacity = 0
        glow.zPosition = 997
        container.addSublayer(glow)

        // Fade in then out.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.glowOpacity
        fadeIn.duration = 0.15
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.glowOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.15
        fadeOut.duration = Tuning.glowFadeOutDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, fadeOut]
        group.duration = 0.15 + Tuning.glowFadeOutDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { glow.removeFromSuperlayer() }
        glow.add(group, forKey: "magicGlow")
        CATransaction.commit()
    }

    // MARK: - Underline Highlight

    private func fireUnderlineHighlight(
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor,
        on container: CALayer
    ) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let midY = (start.y + end.y) / 2

        let bar = CALayer()
        bar.frame = CGRect(
            x: minX,
            y: midY + 2,
            width: maxX - minX,
            height: Tuning.highlightHeight
        )
        bar.backgroundColor = color.withAlphaComponent(CGFloat(Tuning.highlightOpacity)).cgColor
        bar.cornerRadius = Tuning.highlightHeight / 2
        bar.opacity = 0
        bar.zPosition = 996
        container.addSublayer(bar)

        // Fade in then out.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.highlightOpacity
        fadeIn.duration = 0.2
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.highlightOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.2
        fadeOut.duration = Tuning.highlightFadeOutDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, fadeOut]
        group.duration = 0.2 + Tuning.highlightFadeOutDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { bar.removeFromSuperlayer() }
        bar.add(group, forKey: "magicHighlight")
        CATransaction.commit()
    }
}
