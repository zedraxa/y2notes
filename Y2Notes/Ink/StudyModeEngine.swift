import UIKit
import QuartzCore

// MARK: - Study Mode Engine

/// Engine that provides subtle, satisfying feedback effects for study-oriented
/// actions: well-formed headings, completed checklists, and timer events.
///
/// Effects provided when study mode is **active**:
///
/// 1. **Heading glow** — when the user writes a heading-like stroke (long,
///    prominent), a brief warm radial glow pulses behind the stroke area
///    and fades over 0.8 s.  This creates a feeling of "locking in" the
///    concept without being distracting.
/// 2. **Checklist completion flash** — when a checklist widget has all
///    items marked complete, a soft green pulse radiates outward from the
///    widget's center and fades in 0.6 s.
/// 3. **Timer soft pulse** — when a study timer completes, a full-canvas
///    gentle brightness pulse (5 % opacity white overlay) fades in and out
///    over 1.2 s — the user feels the transition without being startled.
///
/// **Design guardrails** (anti-neon, anti-distraction):
/// - All colours are soft and derived from the current theme at ≤ 10 % opacity.
/// - No looping animations — every effect is a single one-shot pulse.
/// - No shaders — all effects use plain `CALayer` opacity animations.
/// - Total setup overhead < 0.3 ms (`PerformanceConstraints.studyModeBudgetMs`).
///
/// **Reduce Motion**: all animations are suppressed when
/// `UIAccessibility.isReduceMotionEnabled` is `true`.
///
/// **Default state**: off.  Toggled via `DrawingToolStore.isStudyModeActive`.
final class StudyModeEngine {

    // MARK: - Tuning Constants

    private enum Tuning {
        // ── Heading Glow ───────────────────────────────────────────
        /// Minimum stroke width (points) to consider a heading stroke.
        static let headingMinWidth: CGFloat = 100
        /// Maximum vertical span for a heading (keeps it to a single line).
        static let headingMaxHeight: CGFloat = 60
        /// Glow radius (points).
        static let headingGlowRadius: CGFloat = 60
        /// Glow opacity.
        static let headingGlowOpacity: Float = 0.08
        /// Glow colour — warm amber.
        static let headingGlowColor: UIColor = UIColor(
            red: 1.0, green: 0.88, blue: 0.55, alpha: 1.0
        )
        /// Glow total duration (seconds).
        static let headingGlowDuration: CFTimeInterval = 0.8

        // ── Checklist Completion ───────────────────────────────────
        /// Pulse colour — soft green.
        static let checklistPulseColor: UIColor = UIColor(
            red: 0.35, green: 0.82, blue: 0.50, alpha: 1.0
        )
        /// Pulse initial diameter (points).
        static let checklistPulseStartDiameter: CGFloat = 20
        /// Pulse final diameter (points).
        static let checklistPulseEndDiameter: CGFloat = 80
        /// Pulse opacity.
        static let checklistPulseOpacity: Float = 0.10
        /// Pulse duration (seconds).
        static let checklistPulseDuration: CFTimeInterval = 0.6

        // ── Timer Completion ───────────────────────────────────────
        /// Full-canvas overlay opacity.
        static let timerPulseOpacity: Float = 0.05
        /// Pulse total duration — slow for a calm feel.
        static let timerPulseDuration: CFTimeInterval = 1.2

        // ── General ────────────────────────────────────────────────
        static let reducedMotionDuration: CFTimeInterval = 0.0
    }

    // MARK: - State

    private let reduceMotion: Bool
    private(set) var isActive: Bool = false

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    /// Container layer where overlay effects are added.
    private weak var containerLayer: CALayer?

    init() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
    }

    // MARK: - Computed Helpers

    private var shouldSuppressAnimations: Bool {
        reduceMotion || !effectIntensity.allowsStudyMode
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

    // MARK: - 1. Heading Glow

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
        let r = Tuning.headingGlowRadius

        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = CGRect(
            x: center.x - r, y: center.y - r,
            width: r * 2, height: r * 2
        )
        glow.colors = [
            Tuning.headingGlowColor.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor
        ]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint   = CGPoint(x: 1.0, y: 1.0)
        glow.opacity = 0
        glow.zPosition = 995
        container.addSublayer(glow)

        // Pulse: fade in → hold briefly → fade out.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.headingGlowOpacity
        fadeIn.duration = 0.15
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.headingGlowOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = 0.2
        fadeOut.duration = Tuning.headingGlowDuration - 0.2
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, fadeOut]
        group.duration = Tuning.headingGlowDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { glow.removeFromSuperlayer() }
        glow.add(group, forKey: "studyHeadingGlow")
        CATransaction.commit()
    }

    // MARK: - 2. Checklist Completion

    /// Fire a satisfying green pulse when a checklist widget is fully checked.
    ///
    /// - Parameter center: The centre point of the completed checklist widget.
    func checklistComplete(at center: CGPoint) {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        let startD = Tuning.checklistPulseStartDiameter
        let endD   = Tuning.checklistPulseEndDiameter

        let pulse = CALayer()
        pulse.frame = CGRect(
            x: center.x - startD / 2, y: center.y - startD / 2,
            width: startD, height: startD
        )
        pulse.backgroundColor = Tuning.checklistPulseColor.withAlphaComponent(0.3).cgColor
        pulse.cornerRadius = startD / 2
        pulse.opacity = Tuning.checklistPulseOpacity
        pulse.zPosition = 994
        container.addSublayer(pulse)

        // Scale up while fading out.
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = endD / startD
        scale.duration = Tuning.checklistPulseDuration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Tuning.checklistPulseOpacity
        fade.toValue = 0
        fade.duration = Tuning.checklistPulseDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Tuning.checklistPulseDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { pulse.removeFromSuperlayer() }
        pulse.add(group, forKey: "studyChecklistPulse")
        CATransaction.commit()
    }

    // MARK: - 3. Timer Completion

    /// Fire a gentle full-canvas brightness pulse when a study timer finishes.
    func timerComplete() {
        guard isActive, !shouldSuppressAnimations,
              let container = containerLayer else { return }

        let overlay = CALayer()
        overlay.frame = container.bounds
        overlay.backgroundColor = UIColor.white.cgColor
        overlay.opacity = 0
        overlay.zPosition = 993
        container.addSublayer(overlay)

        let halfDuration = Tuning.timerPulseDuration / 2

        // Fade in.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = Tuning.timerPulseOpacity
        fadeIn.duration = halfDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Fade out.
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Tuning.timerPulseOpacity
        fadeOut.toValue = 0
        fadeOut.beginTime = halfDuration
        fadeOut.duration = halfDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [fadeIn, fadeOut]
        group.duration = Tuning.timerPulseDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { overlay.removeFromSuperlayer() }
        overlay.add(group, forKey: "studyTimerPulse")
        CATransaction.commit()
    }
}
