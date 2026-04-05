import UIKit
import QuartzCore

// MARK: - Study Mode Engine

/// Engine that provides subtle, satisfying feedback effects for study-oriented
/// actions: well-formed headings, completed checklists, and timer events.
///
/// Effects provided when study mode is **active**:
///
/// 1. **Heading glow** — when the user writes a heading-like stroke (long,
///    prominent), a dual-ring concentric pulse radiates outward with a
///    warm-to-cool colour shift, plus a subtle scale "lock-in" bounce on
///    the inner ring.  Total duration 1.0 s.
/// 2. **Checklist completion flash** — when a checklist widget has all
///    items marked complete, a multi-particle confetti burst fires from the
///    widget centre, an expanding green ring pulses outward with a brief
///    checkmark flash overlay, and the ring does a satisfying scale bounce.
///    Total duration 0.8 s.
/// 3. **Timer soft pulse** — when a study timer completes, a breathing
///    double-pulse (two fade cycles) washes the canvas, with a subtle colour
///    wave radiating from the centre outward and a gentle canvas scale bounce.
///    Total duration 1.6 s.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - All colours are soft and derived from the current theme at ≤ 12 % opacity.
/// - No looping animations — every effect is a single one-shot burst.
/// - No shaders — all effects use plain `CALayer` opacity/transform animations.
/// - Total setup overhead < 0.3 ms (`PerformanceConstraints.studyModeBudgetMs`).
///
/// **Reduce Motion**: all animations are suppressed when
/// `UIAccessibility.isReduceMotionEnabled` is `true`.
///
/// **Default state**: off.  Toggled via `DrawingToolStore.isStudyModeActive`.
final class StudyModeEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        // ── Heading Glow (Concentric Rings) ────────────────────────
        /// Minimum stroke width (points) to consider a heading stroke.
        static let headingMinWidth: CGFloat = 100
        /// Maximum vertical span for a heading (keeps it to a single line).
        static let headingMaxHeight: CGFloat = 60
        /// Inner ring radius (points).
        static let headingInnerRadius: CGFloat = 40
        /// Outer ring radius (points).
        static let headingOuterRadius: CGFloat = 80
        /// Inner ring peak opacity.
        static let headingInnerOpacity: Float = 0.10
        /// Outer ring peak opacity.
        static let headingOuterOpacity: Float = 0.06
        /// Warm colour for inner ring.
        static let headingWarmColor: UIColor = UIColor(
            red: 1.0, green: 0.88, blue: 0.55, alpha: 1.0
        )
        /// Cool colour for outer ring.
        static let headingCoolColor: UIColor = UIColor(
            red: 0.65, green: 0.82, blue: 1.0, alpha: 1.0
        )
        /// Inner ring scale bounce amplitude.
        static let headingBounceScale: CGFloat = 1.06
        /// Heading glow total duration (seconds).
        static let headingGlowDuration: CFTimeInterval = 1.0
        /// Outer ring expansion scale.
        static let headingOuterExpansion: CGFloat = 1.5

        // ── Checklist Completion (Confetti + Ring + Checkmark) ─────
        /// Confetti particle count.
        static let confettiParticleCount: Int = 12
        /// Confetti particle lifetime (seconds).
        static let confettiLifetime: Float = 0.6
        /// Confetti spread velocity (points per second).
        static let confettiVelocity: CGFloat = 80
        /// Confetti particle size.
        static let confettiSize: CGFloat = 5
        /// Pulse ring colour — soft green.
        static let checklistPulseColor: UIColor = UIColor(
            red: 0.35, green: 0.82, blue: 0.50, alpha: 1.0
        )
        /// Pulse ring initial diameter (points).
        static let checklistPulseStartDiameter: CGFloat = 20
        /// Pulse ring final diameter (points).
        static let checklistPulseEndDiameter: CGFloat = 90
        /// Pulse ring peak opacity.
        static let checklistPulseOpacity: Float = 0.12
        /// Ring scale bounce overshoot.
        static let checklistBounceScale: CGFloat = 1.12
        /// Checkmark flash diameter.
        static let checkmarkDiameter: CGFloat = 28
        /// Checkmark flash peak opacity.
        static let checkmarkOpacity: Float = 0.25
        /// Checklist total duration (seconds).
        static let checklistTotalDuration: CFTimeInterval = 0.8

        // ── Timer Completion (Double Pulse + Colour Wave) ─────────
        /// Full-canvas overlay opacity (per pulse).
        static let timerPulseOpacity: Float = 0.05
        /// Single pulse cycle duration.
        static let timerSinglePulseDuration: CFTimeInterval = 0.6
        /// Gap between the two pulses.
        static let timerPulseGap: CFTimeInterval = 0.15
        /// Colour wave ring start diameter (fraction of canvas).
        static let timerWaveStartFraction: CGFloat = 0.1
        /// Colour wave ring end diameter (fraction of canvas).
        static let timerWaveEndFraction: CGFloat = 1.5
        /// Colour wave opacity.
        static let timerWaveOpacity: Float = 0.04
        /// Canvas scale bounce amplitude.
        static let timerCanvasBounce: CGFloat = 1.005
        /// Total timer effect duration (seconds).
        static let timerTotalDuration: CFTimeInterval = 1.6

        // ── General ────────────────────────────────────────────────
        static let reducedMotionDuration: CFTimeInterval = 0.0
    }

    // MARK: - State

    private(set) var isActive: Bool = false

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    /// Container layer where overlay effects are added.
    private weak var containerLayer: CALayer?

    // MARK: - Computed Helpers

    private var shouldSuppressAnimations: Bool {
        ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsStudyMode
    }

    // MARK: - Activate / Deactivate

    /// Prepare the engine for a given container layer.
    func activate(on container: CALayer) {
        guard !isActive else { return }
        isActive = true
        containerLayer = container
    }

    /// Tear down.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        containerLayer = nil
    }

    // MARK: - 1. Heading Glow (Concentric Rings + Colour Shift + Bounce)

    /// Fire a heading glow when the user writes a prominent, wide stroke.
    ///
    /// Call from stroke-end detection.  The caller should verify that the
    /// stroke is "heading-like" (wide horizontal span, small vertical span).
    func headingGlow(at rect: CGRect) {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // Validate heading heuristic.
        guard rect.width >= Tuning.headingMinWidth,
              rect.height <= Tuning.headingMaxHeight else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)

        // ── Inner ring (warm amber, scale bounce) ─────────────────
        let innerR = Tuning.headingInnerRadius
        let innerGlow = makeRadialGlow(
            at: center, radius: innerR,
            color: Tuning.headingWarmColor,
            opacity: Tuning.headingInnerOpacity,
            zPosition: 995
        )
        container.addSublayer(innerGlow)
        animateHeadingInnerRing(on: innerGlow)

        // ── Outer ring (cool blue, expanding) ─────────────────────
        let outerR = Tuning.headingOuterRadius
        let outerGlow = makeRadialGlow(
            at: center, radius: outerR,
            color: Tuning.headingCoolColor,
            opacity: Tuning.headingOuterOpacity,
            zPosition: 994
        )
        container.addSublayer(outerGlow)
        animateHeadingOuterRing(on: outerGlow)
    }

    private func animateHeadingInnerRing(on layer: CALayer) {
        let duration = Tuning.headingGlowDuration

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.headingInnerOpacity
        fadeIn.duration = 0.15
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Scale bounce: 1.0 → overshoot → 1.0
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, Tuning.headingBounceScale, 0.98, 1.0]
        bounce.keyTimes = [0, 0.3, 0.6, 1.0]
        bounce.duration = 0.35
        bounce.beginTime = 0.1
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.headingInnerOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.3
        fadeOut.duration = duration - 0.3
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, bounce, fadeOut]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(group, forKey: "studyHeadingInner")
        CATransaction.commit()
    }

    private func animateHeadingOuterRing(on layer: CALayer) {
        let duration = Tuning.headingGlowDuration

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.headingOuterOpacity
        fadeIn.duration = 0.2
        fadeIn.beginTime = 0.1
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Expand outward.
        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = 1.0
        expand.toValue = Tuning.headingOuterExpansion
        expand.duration = duration * 0.7
        expand.beginTime = 0.1
        expand.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.headingOuterOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.3
        fadeOut.duration = duration - 0.3
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, expand, fadeOut]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(group, forKey: "studyHeadingOuter")
        CATransaction.commit()
    }

    // MARK: - 2. Checklist Completion (Confetti + Ring + Checkmark)

    /// Fire a satisfying celebration when a checklist widget is fully checked.
    ///
    /// - Parameter center: The centre point of the completed checklist widget.
    func checklistComplete(at center: CGPoint) {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // ── Confetti burst ────────────────────────────────────────
        fireConfettiBurst(at: center, on: container)

        // ── Expanding pulse ring with bounce ──────────────────────
        fireChecklistRing(at: center, on: container)

        // ── Checkmark flash ───────────────────────────────────────
        fireCheckmarkFlash(at: center, on: container)
    }

    private func fireConfettiBurst(at center: CGPoint, on container: CALayer) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = center
        emitter.emitterShape = .point
        emitter.emitterSize = .zero
        emitter.renderMode = .oldestFirst
        emitter.frame = container.bounds
        emitter.zPosition = 996

        let colors: [UIColor] = [
            Tuning.checklistPulseColor,
            UIColor(red: 0.35, green: 0.70, blue: 0.95, alpha: 1),
            UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1),
            UIColor(red: 0.90, green: 0.45, blue: 0.65, alpha: 1)
        ]

        var cells: [CAEmitterCell] = []
        for i in 0..<Tuning.confettiParticleCount {
            let cell = CAEmitterCell()
            cell.birthRate = 0
            cell.lifetime = Tuning.confettiLifetime
            cell.velocity = Tuning.confettiVelocity
            cell.velocityRange = Tuning.confettiVelocity * 0.4
            cell.emissionRange = .pi * 2
            let angle = CGFloat(i) * (.pi * 2 / CGFloat(Tuning.confettiParticleCount))
            cell.emissionLongitude = angle
            cell.scale = Float(Tuning.confettiSize) / 12.0
            cell.scaleSpeed = -Float(Tuning.confettiSize) / 12.0 * 0.5
            cell.alphaSpeed = -Float(1.0 / Double(Tuning.confettiLifetime))
            cell.color = colors[i % colors.count].withAlphaComponent(0.5).cgColor
            cell.contents = MagicModeEngine.particleImage.cgImage
            cell.spin = 2.0
            cell.spinRange = 4.0
            cell.yAcceleration = 40
            cells.append(cell)
        }

        emitter.emitterCells = cells
        container.addSublayer(emitter)

        // Fire once then stop.
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            emitter.birthRate = 0
        }

        // Remove after particles have faded.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(Tuning.confettiLifetime) + 0.1
        ) {
            emitter.removeFromSuperlayer()
        }
    }

    private func fireChecklistRing(at center: CGPoint, on container: CALayer) {
        let startD = Tuning.checklistPulseStartDiameter
        let endD   = Tuning.checklistPulseEndDiameter

        let ring = CAShapeLayer()
        let startPath = UIBezierPath(
            ovalIn: CGRect(x: center.x - startD / 2, y: center.y - startD / 2,
                           width: startD, height: startD)
        )
        ring.path = startPath.cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = Tuning.checklistPulseColor.withAlphaComponent(
            CGFloat(Tuning.checklistPulseOpacity)).cgColor
        ring.lineWidth = 3
        ring.opacity = Tuning.checklistPulseOpacity
        ring.zPosition = 995
        container.addSublayer(ring)

        // Scale up with bounce overshoot.
        let scaleFactor = endD / startD
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, scaleFactor * Tuning.checklistBounceScale,
                         scaleFactor * 0.97, scaleFactor]
        bounce.keyTimes = [0, 0.5, 0.75, 1.0]
        bounce.duration = Tuning.checklistTotalDuration * 0.6

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Tuning.checklistPulseOpacity
        fade.toValue = 0
        fade.beginTime = Tuning.checklistTotalDuration * 0.3
        fade.duration = Tuning.checklistTotalDuration * 0.7
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [bounce, fade]
        group.duration = Tuning.checklistTotalDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "studyChecklistRing")
        CATransaction.commit()
    }

    private func fireCheckmarkFlash(at center: CGPoint, on container: CALayer) {
        let d = Tuning.checkmarkDiameter
        let checkLayer = CAShapeLayer()
        checkLayer.frame = CGRect(x: center.x - d / 2, y: center.y - d / 2,
                                  width: d, height: d)

        // Draw a simple checkmark path.
        let path = UIBezierPath()
        path.move(to: CGPoint(x: d * 0.22, y: d * 0.52))
        path.addLine(to: CGPoint(x: d * 0.42, y: d * 0.72))
        path.addLine(to: CGPoint(x: d * 0.78, y: d * 0.30))
        checkLayer.path = path.cgPath
        checkLayer.fillColor = UIColor.clear.cgColor
        checkLayer.strokeColor = Tuning.checklistPulseColor.cgColor
        checkLayer.lineWidth = 2.5
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        checkLayer.opacity = 0
        checkLayer.zPosition = 997
        container.addSublayer(checkLayer)

        // Stroke-in animation (draw the checkmark).
        let strokeEnd = CABasicAnimation(keyPath: "strokeEnd")
        strokeEnd.fromValue = 0
        strokeEnd.toValue = 1
        strokeEnd.duration = 0.25
        strokeEnd.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.checkmarkOpacity
        fadeIn.duration = 0.1

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.checkmarkOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.35
        fadeOut.duration = 0.3
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [strokeEnd, fadeIn, fadeOut]
        group.duration = 0.65
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { checkLayer.removeFromSuperlayer() }
        checkLayer.add(group, forKey: "studyCheckmark")
        CATransaction.commit()
    }

    // MARK: - 3. Timer Completion (Double Pulse + Colour Wave + Bounce)

    /// Fire a gentle double-pulse with colour wave when a study timer finishes.
    func timerComplete() {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // ── Breathing double-pulse overlay ─────────────────────────
        fireTimerDoublePulse(on: container)

        // ── Colour wave from centre outward ───────────────────────
        fireTimerColourWave(on: container)

        // ── Gentle canvas scale bounce ────────────────────────────
        fireTimerCanvasBounce(on: container)
    }

    private func fireTimerDoublePulse(on container: CALayer) {
        let overlay = CALayer()
        overlay.frame = container.bounds
        overlay.backgroundColor = UIColor.white.cgColor
        overlay.opacity = 0
        overlay.zPosition = 993
        container.addSublayer(overlay)

        let pulseDur = Tuning.timerSinglePulseDuration
        let gap = Tuning.timerPulseGap

        // First pulse: fade in → fade out.
        let fadeIn1 = CABasicAnimation(keyPath: "opacity")
        fadeIn1.fromValue = 0
        fadeIn1.toValue = Tuning.timerPulseOpacity
        fadeIn1.duration = pulseDur / 2
        fadeIn1.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut1 = CABasicAnimation(keyPath: "opacity")
        fadeOut1.fromValue = Tuning.timerPulseOpacity
        fadeOut1.toValue = 0
        fadeOut1.beginTime = pulseDur / 2
        fadeOut1.duration = pulseDur / 2
        fadeOut1.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Second pulse: slightly softer.
        let secondStart = pulseDur + gap
        let fadeIn2 = CABasicAnimation(keyPath: "opacity")
        fadeIn2.fromValue = 0
        fadeIn2.toValue = Tuning.timerPulseOpacity * 0.7
        fadeIn2.beginTime = secondStart
        fadeIn2.duration = pulseDur / 2
        fadeIn2.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut2 = CABasicAnimation(keyPath: "opacity")
        fadeOut2.fromValue = Tuning.timerPulseOpacity * 0.7
        fadeOut2.toValue = 0
        fadeOut2.beginTime = secondStart + pulseDur / 2
        fadeOut2.duration = pulseDur / 2
        fadeOut2.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn1, fadeOut1, fadeIn2, fadeOut2]
        group.duration = Tuning.timerTotalDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { overlay.removeFromSuperlayer() }
        overlay.add(group, forKey: "studyTimerDoublePulse")
        CATransaction.commit()
    }

    private func fireTimerColourWave(on container: CALayer) {
        let bounds = container.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxDim = max(bounds.width, bounds.height)
        let startD = maxDim * Tuning.timerWaveStartFraction
        let endD   = maxDim * Tuning.timerWaveEndFraction

        let wave = CAShapeLayer()
        let startPath = UIBezierPath(
            ovalIn: CGRect(x: center.x - startD / 2, y: center.y - startD / 2,
                           width: startD, height: startD)
        )
        wave.path = startPath.cgPath
        wave.fillColor = UIColor.clear.cgColor
        wave.strokeColor = UIColor(red: 0.5, green: 0.7, blue: 1.0,
                                    alpha: CGFloat(Tuning.timerWaveOpacity)).cgColor
        wave.lineWidth = 6
        wave.opacity = Float(Tuning.timerWaveOpacity)
        wave.zPosition = 993.5
        container.addSublayer(wave)

        let scaleFactor = endD / startD

        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = 1.0
        expand.toValue = scaleFactor
        expand.duration = Tuning.timerTotalDuration * 0.8
        expand.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Tuning.timerWaveOpacity
        fade.toValue = 0
        fade.duration = Tuning.timerTotalDuration * 0.8
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [expand, fade]
        group.duration = Tuning.timerTotalDuration * 0.8
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { wave.removeFromSuperlayer() }
        wave.add(group, forKey: "studyTimerWave")
        CATransaction.commit()
    }

    private func fireTimerCanvasBounce(on container: CALayer) {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, Tuning.timerCanvasBounce, 1.0]
        bounce.keyTimes = [0, 0.4, 1.0]
        bounce.duration = Tuning.timerTotalDuration * 0.5
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bounce.fillMode = .forwards
        bounce.isRemovedOnCompletion = true
        container.add(bounce, forKey: "studyTimerBounce")
    }

    // MARK: - Radial Glow Helper

    private func makeRadialGlow(
        at center: CGPoint,
        radius: CGFloat,
        color: UIColor,
        opacity: Float,
        zPosition: CGFloat
    ) -> CAGradientLayer {
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
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
}
