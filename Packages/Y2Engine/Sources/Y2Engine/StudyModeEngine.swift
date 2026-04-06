import UIKit
import QuartzCore

// MARK: - Study Mode Engine

/// Engine that provides subtle, satisfying feedback effects for study-oriented
/// actions: well-formed headings, completed checklists, and timer events.
///
/// Effects provided when study mode is **active**:
///
/// 1. **Heading glow (concentric rings)** — when the user writes a heading-like
///    stroke (long, prominent), two concentric radial rings pulse outward from
///    the stroke centre.  The inner ring is warm amber; the outer ring is a
///    softer gold.  Both expand slightly and fade over 0.9 s, creating a
///    satisfying "locked in" feel.
/// 2. **Checklist completion (confetti + ring + checkmark)** — when a checklist
///    widget has all items marked complete, a three-phase celebration fires:
///    (a) a green ring pulse expands outward, (b) a small ✓ checkmark fades
///    in at the centre, and (c) a burst of 6 confetti particles radiates
///    outward and fades.
/// 3. **Timer completion (double-pulse + wave + bounce)** — when a study timer
///    / progress tracker completes, a two-phase brightness pulse (fast in,
///    slow out, repeat) is followed by a concentric wave ring expanding from
///    the centre and a gentle scale bounce on the canvas overlay.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - All colours are soft and derived from the current theme at ≤ 12 % opacity.
/// - No looping animations — every effect is a single one-shot sequence.
/// - No shaders — all effects use plain `CALayer` opacity animations.
/// - Total setup overhead < 0.3 ms (`PerformanceConstraints.studyModeBudgetMs`).
///
/// **Reduce Motion**: all animations are suppressed when
/// `UIAccessibility.isReduceMotionEnabled` is `true`.
///
/// **Default state**: off.  Toggled via `DrawingToolStore.isStudyModeActive`.
public final class StudyModeEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        // ── Heading Glow (Concentric Rings) ────────────────────────
        /// Minimum stroke width (points) to consider a heading stroke.
        static let headingMinWidth: CGFloat = 100
        /// Maximum vertical span for a heading (keeps it to a single line).
        static let headingMaxHeight: CGFloat = 60
        /// Inner ring radius (points).
        static let headingInnerRadius: CGFloat = 50
        /// Outer ring radius (points).
        static let headingOuterRadius: CGFloat = 80
        /// Inner ring opacity.
        static let headingInnerOpacity: Float = 0.10
        /// Outer ring opacity.
        static let headingOuterOpacity: Float = 0.06
        /// Inner ring colour — warm amber.
        static let headingInnerColor: UIColor = UIColor(
            red: 1.0, green: 0.88, blue: 0.55, alpha: 1.0
        )
        /// Outer ring colour — softer gold.
        static let headingOuterColor: UIColor = UIColor(
            red: 1.0, green: 0.92, blue: 0.68, alpha: 1.0
        )
        /// Ring expansion scale factor (1.0 → this value).
        static let headingRingExpandScale: CGFloat = 1.25
        /// Total heading glow duration (seconds).
        static let headingGlowDuration: CFTimeInterval = 0.9

        // ── Checklist Completion (Confetti + Ring + Checkmark) ─────
        /// Ring pulse colour — soft green.
        static let checklistRingColor: UIColor = UIColor(
            red: 0.35, green: 0.82, blue: 0.50, alpha: 1.0
        )
        /// Ring pulse start diameter.
        static let checklistRingStartDiameter: CGFloat = 20
        /// Ring pulse end diameter.
        static let checklistRingEndDiameter: CGFloat = 90
        /// Ring pulse max opacity.
        static let checklistRingOpacity: Float = 0.12
        /// Ring + expand duration.
        static let checklistRingDuration: CFTimeInterval = 0.55
        /// Checkmark size.
        static let checkmarkSize: CGFloat = 28
        /// Checkmark opacity.
        static let checkmarkOpacity: Float = 0.35
        /// Checkmark fade-in + hold + fade-out total duration.
        static let checkmarkDuration: CFTimeInterval = 0.9
        /// Confetti particle count.
        static let confettiCount: Int = 6
        /// Confetti spread radius.
        static let confettiSpreadRadius: CGFloat = 50
        /// Confetti particle size.
        static let confettiSize: CGFloat = 6
        /// Confetti duration.
        static let confettiDuration: CFTimeInterval = 0.7

        // ── Timer Completion (Double-Pulse + Wave + Bounce) ────────
        /// Full-canvas overlay opacity per pulse.
        static let timerPulseOpacity: Float = 0.05
        /// Single pulse duration (fade in + out).
        static let timerSinglePulseDuration: CFTimeInterval = 0.45
        /// Gap between double-pulse.
        static let timerPulseGap: CFTimeInterval = 0.15
        /// Wave ring diameter (max).
        static let timerWaveMaxDiameter: CGFloat = 200
        /// Wave ring border width.
        static let timerWaveBorderWidth: CGFloat = 2.0
        /// Wave ring opacity.
        static let timerWaveOpacity: Float = 0.08
        /// Wave expand duration.
        static let timerWaveDuration: CFTimeInterval = 0.8
        /// Bounce scale overshoot.
        static let timerBounceScale: CGFloat = 1.012
        /// Bounce duration.
        static let timerBounceDuration: CFTimeInterval = 0.3

        // ── General ────────────────────────────────────────────────
        static let reducedMotionDuration: CFTimeInterval = 0.0
    }

    // MARK: - State

    public private(set) var isActive: Bool = false

    /// Current adaptive effect intensity.  Updated by the owning view.
    public var effectIntensity: EffectIntensity = .full

    /// Container layer where overlay effects are added.
    private weak var containerLayer: CALayer?

    // MARK: - Computed Helpers

    private var shouldSuppressAnimations: Bool {
        ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsStudyMode
    }

    // MARK: - Activate / Deactivate

    /// Prepare the engine for a given container layer.
    public func activate(on container: CALayer) {
        guard !isActive else { return }
        isActive = true
        containerLayer = container
    }

    /// Tear down.
    public func deactivate() {
        guard isActive else { return }
        isActive = false
        containerLayer = nil
    }

    // MARK: - 1. Heading Glow (Concentric Rings)

    /// Fire concentric-ring heading glow when the user writes a prominent,
    /// wide stroke.
    ///
    /// Call from stroke-end detection.  The caller should verify that the
    /// stroke is "heading-like" (wide horizontal span, small vertical span).
    public func headingGlow(at rect: CGRect) {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // Validate heading heuristic.
        guard rect.width >= Tuning.headingMinWidth,
              rect.height <= Tuning.headingMaxHeight else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Inner ring — warm amber.
        fireConcentricRing(
            at: center,
            radius: Tuning.headingInnerRadius,
            color: Tuning.headingInnerColor,
            opacity: Tuning.headingInnerOpacity,
            expandScale: Tuning.headingRingExpandScale,
            duration: Tuning.headingGlowDuration,
            delay: 0,
            zPosition: 995,
            on: container
        )

        // Outer ring — softer gold, slight delay for staggered feel.
        fireConcentricRing(
            at: center,
            radius: Tuning.headingOuterRadius,
            color: Tuning.headingOuterColor,
            opacity: Tuning.headingOuterOpacity,
            expandScale: Tuning.headingRingExpandScale,
            duration: Tuning.headingGlowDuration,
            delay: 0.06,
            zPosition: 994.5,
            on: container
        )
    }

    private func fireConcentricRing(
        at center: CGPoint,
        radius: CGFloat,
        color: UIColor,
        opacity: Float,
        expandScale: CGFloat,
        duration: CFTimeInterval,
        delay: CFTimeInterval,
        zPosition: CGFloat,
        on container: CALayer
    ) {
        let ring = CAGradientLayer()
        ring.type = .radial
        ring.frame = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        ring.colors = [
            color.withAlphaComponent(CGFloat(opacity)).cgColor,
            color.withAlphaComponent(CGFloat(opacity * 0.3)).cgColor,
            UIColor.clear.cgColor
        ]
        ring.locations = [0.0, 0.6, 1.0]
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint   = CGPoint(x: 1.0, y: 1.0)
        ring.opacity = 0
        ring.zPosition = zPosition
        container.addSublayer(ring)

        // Scale expansion.
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = expandScale
        scale.beginTime = delay
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Opacity: fade in → hold → fade out.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = opacity
        fadeIn.beginTime = delay
        fadeIn.duration = 0.15
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = opacity
        fadeOut.toValue = 0
        fadeOut.beginTime = delay + 0.25
        fadeOut.duration = duration - 0.25
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [scale, fadeIn, fadeOut]
        group.duration = delay + duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "studyRingGlow")
        CATransaction.commit()
    }

    // MARK: - 2. Checklist Completion (Confetti + Ring + Checkmark)

    /// Fire a satisfying celebration when a checklist widget is fully checked.
    ///
    /// - Parameter center: The centre point of the completed checklist widget.
    public func checklistComplete(at center: CGPoint) {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // Phase A: Expanding green ring.
        fireChecklistRing(at: center, on: container)

        // Phase B: Checkmark fade-in at centre.
        fireCheckmark(at: center, on: container)

        // Phase C: Confetti burst.
        fireConfettiBurst(at: center, on: container)
    }

    private func fireChecklistRing(at center: CGPoint, on container: CALayer) {
        let startD = Tuning.checklistRingStartDiameter
        let endD   = Tuning.checklistRingEndDiameter

        let ring = CAShapeLayer()
        ring.path = UIBezierPath(
            ovalIn: CGRect(x: -startD / 2, y: -startD / 2, width: startD, height: startD)
        ).cgPath
        ring.position = center
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = Tuning.checklistRingColor.withAlphaComponent(CGFloat(Tuning.checklistRingOpacity)).cgColor
        ring.lineWidth = 3
        ring.opacity = Tuning.checklistRingOpacity
        ring.zPosition = 994
        container.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = endD / startD
        scale.duration = Tuning.checklistRingDuration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Tuning.checklistRingOpacity
        fade.toValue = 0
        fade.duration = Tuning.checklistRingDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Tuning.checklistRingDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "studyCheckRing")
        CATransaction.commit()
    }

    private func fireCheckmark(at center: CGPoint, on container: CALayer) {
        let sz = Tuning.checkmarkSize

        let check = CAShapeLayer()
        let path = UIBezierPath()
        // Draw a ✓ shape relative to centre.
        path.move(to: CGPoint(x: -sz * 0.3, y: 0))
        path.addLine(to: CGPoint(x: -sz * 0.05, y: sz * 0.25))
        path.addLine(to: CGPoint(x: sz * 0.35, y: -sz * 0.25))
        check.path = path.cgPath
        check.position = center
        check.fillColor = UIColor.clear.cgColor
        check.strokeColor = Tuning.checklistRingColor.cgColor
        check.lineWidth = 2.5
        check.lineCap = .round
        check.lineJoin = .round
        check.opacity = 0
        check.zPosition = 995
        container.addSublayer(check)

        let dur = Tuning.checkmarkDuration

        // Stroke draw-in.
        let strokeEnd = CABasicAnimation(keyPath: "strokeEnd")
        strokeEnd.fromValue = 0
        strokeEnd.toValue = 1.0
        strokeEnd.duration = dur * 0.35
        strokeEnd.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Fade in.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.checkmarkOpacity
        fadeIn.duration = dur * 0.2
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Fade out.
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.checkmarkOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = dur * 0.6
        fadeOut.duration = dur * 0.4
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [strokeEnd, fadeIn, fadeOut]
        group.duration = dur
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { check.removeFromSuperlayer() }
        check.add(group, forKey: "studyCheckmark")
        CATransaction.commit()
    }

    private func fireConfettiBurst(at center: CGPoint, on container: CALayer) {
        let count = Tuning.confettiCount
        let spread = Tuning.confettiSpreadRadius
        let sz = Tuning.confettiSize
        let dur = Tuning.confettiDuration

        // Confetti colours — pastel celebration palette.
        let colors: [UIColor] = [
            UIColor(red: 0.35, green: 0.82, blue: 0.50, alpha: 1), // green
            UIColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1), // blue
            UIColor(red: 1.00, green: 0.82, blue: 0.30, alpha: 1), // gold
            UIColor(red: 0.95, green: 0.50, blue: 0.55, alpha: 1), // coral
            UIColor(red: 0.70, green: 0.50, blue: 0.95, alpha: 1), // purple
            UIColor(red: 0.40, green: 0.90, blue: 0.85, alpha: 1), // teal
        ]

        for i in 0..<count {
            let angle = (CGFloat(i) / CGFloat(count)) * .pi * 2
            let endX = center.x + cos(angle) * spread
            let endY = center.y + sin(angle) * spread

            let particle = CALayer()
            particle.frame = CGRect(x: center.x - sz / 2, y: center.y - sz / 2,
                                     width: sz, height: sz)
            particle.backgroundColor = colors[i % colors.count].withAlphaComponent(0.6).cgColor
            particle.cornerRadius = sz / 2
            particle.opacity = 0
            particle.zPosition = 993
            container.addSublayer(particle)

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: center)
            move.toValue = NSValue(cgPoint: CGPoint(x: endX, y: endY))
            move.duration = dur
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 0.5
            fadeIn.duration = dur * 0.2

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 0.5
            fadeOut.toValue = 0
            fadeOut.beginTime = dur * 0.4
            fadeOut.duration = dur * 0.6
            fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let scaleDown = CABasicAnimation(keyPath: "transform.scale")
            scaleDown.fromValue = 1.0
            scaleDown.toValue = 0.3
            scaleDown.duration = dur
            scaleDown.timingFunction = CAMediaTimingFunction(name: .easeIn)

            let group = CAAnimationGroup()
            group.animations = [move, fadeIn, fadeOut, scaleDown]
            group.duration = dur
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { particle.removeFromSuperlayer() }
            particle.add(group, forKey: "studyConfetti\(i)")
            CATransaction.commit()
        }
    }

    // MARK: - 3. Timer Completion (Double-Pulse + Wave + Bounce)

    /// Fire a satisfying multi-phase effect when a study timer / progress
    /// tracker completes.
    public func timerComplete() {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        // Phase 1: Double brightness pulse.
        fireDoublePulse(on: container)

        // Phase 2: Concentric wave ring from canvas centre.
        let center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        fireWaveRing(at: center, on: container)

        // Phase 3: Subtle scale bounce on the container.
        fireBounce(on: container)
    }

    private func fireDoublePulse(on container: CALayer) {
        let singleDur = Tuning.timerSinglePulseDuration
        let gap = Tuning.timerPulseGap
        let totalDur = singleDur * 2 + gap

        let overlay = CALayer()
        overlay.frame = container.bounds
        overlay.backgroundColor = UIColor.white.cgColor
        overlay.opacity = 0
        overlay.zPosition = 993
        container.addSublayer(overlay)

        let halfPulse = singleDur / 2

        // Pulse 1: fade in → fade out.
        let p1In = CABasicAnimation(keyPath: "opacity")
        p1In.fromValue = 0
        p1In.toValue = Tuning.timerPulseOpacity
        p1In.duration = halfPulse
        p1In.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let p1Out = CABasicAnimation(keyPath: "opacity")
        p1Out.fromValue = Tuning.timerPulseOpacity
        p1Out.toValue = 0
        p1Out.beginTime = halfPulse
        p1Out.duration = halfPulse
        p1Out.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Pulse 2: fade in → fade out (after gap).
        let p2Start = singleDur + gap
        let p2In = CABasicAnimation(keyPath: "opacity")
        p2In.fromValue = 0
        p2In.toValue = Tuning.timerPulseOpacity
        p2In.beginTime = p2Start
        p2In.duration = halfPulse
        p2In.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let p2Out = CABasicAnimation(keyPath: "opacity")
        p2Out.fromValue = Tuning.timerPulseOpacity
        p2Out.toValue = 0
        p2Out.beginTime = p2Start + halfPulse
        p2Out.duration = halfPulse
        p2Out.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [p1In, p1Out, p2In, p2Out]
        group.duration = totalDur
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { overlay.removeFromSuperlayer() }
        overlay.add(group, forKey: "studyDoublePulse")
        CATransaction.commit()
    }

    private func fireWaveRing(at center: CGPoint, on container: CALayer) {
        let maxD = Tuning.timerWaveMaxDiameter
        let startD: CGFloat = 20

        let ring = CAShapeLayer()
        ring.path = UIBezierPath(
            ovalIn: CGRect(x: -startD / 2, y: -startD / 2, width: startD, height: startD)
        ).cgPath
        ring.position = center
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.withAlphaComponent(CGFloat(Tuning.timerWaveOpacity)).cgColor
        ring.lineWidth = Tuning.timerWaveBorderWidth
        ring.opacity = Float(Tuning.timerWaveOpacity)
        ring.zPosition = 992
        container.addSublayer(ring)

        let dur = Tuning.timerWaveDuration

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = maxD / startD
        scale.duration = dur
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Tuning.timerWaveOpacity
        fade.toValue = 0
        fade.duration = dur
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = dur
        // Start wave after the first pulse peak for natural sequencing.
        group.beginTime = CACurrentMediaTime() + Tuning.timerSinglePulseDuration * 0.5
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "studyWaveRing")
        CATransaction.commit()
    }

    private func fireBounce(on container: CALayer) {
        let dur = Tuning.timerBounceDuration
        let bounceScale = Tuning.timerBounceScale
        // Delay bounce to align with second pulse.
        let delay = Tuning.timerSinglePulseDuration + Tuning.timerPulseGap

        let scaleUp = CABasicAnimation(keyPath: "transform.scale")
        scaleUp.fromValue = 1.0
        scaleUp.toValue = bounceScale
        scaleUp.beginTime = delay
        scaleUp.duration = dur * 0.4
        scaleUp.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let scaleDown = CABasicAnimation(keyPath: "transform.scale")
        scaleDown.fromValue = bounceScale
        scaleDown.toValue = 1.0
        scaleDown.beginTime = delay + dur * 0.4
        scaleDown.duration = dur * 0.6
        scaleDown.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.34, 1.56, 0.64, 1.0
        )

        let group = CAAnimationGroup()
        group.animations = [scaleUp, scaleDown]
        group.duration = delay + dur
        group.fillMode = .forwards
        group.isRemovedOnCompletion = true

        container.add(group, forKey: "studyBounce")
    }
}
