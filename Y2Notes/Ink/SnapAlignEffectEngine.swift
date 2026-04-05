import UIKit
import QuartzCore

// MARK: - Snap & Align Effect Type

/// Visual feedback effects triggered when objects snap or align on canvas.
///
/// Each effect is tuned for subtle, physical feedback — never cartoonish.
/// All animations are GPU-composited via Core Animation; no main-thread
/// layout passes occur during animation.
///
/// **Performance contract**: total overhead per effect is < 0.5 ms
/// (within `PerformanceConstraints.microInteractionBudgetMs`).
enum SnapAlignEffectType: String, CaseIterable {
    /// Brief glow around a sticker when it snaps to a guide.
    /// Radius pulses from 0 → 4 pt with 0.12 opacity over 0.25 s.
    case snapGlow

    /// Thin alignment line that flashes when a shape aligns with another.
    /// 1-pt hairline fades in at 0.3 opacity and out over 0.3 s.
    case lineGuideFlash

    /// Micro-haptic pulse when an object reaches perfect alignment on
    /// both axes simultaneously.  No visual — haptic only.
    case perfectAlignmentPulse
}

// MARK: - Snap & Align Effect Engine

/// Lightweight engine that plays snap/alignment feedback on any `CALayer`.
///
/// All methods are main-thread-only.  The engine does not retain views;
/// it operates on caller-supplied layers and a shared container layer for
/// guide lines.
///
/// Respects `UIAccessibility.isReduceMotionEnabled`.  When active, visual
/// effects are skipped but haptic feedback still fires (it's non-visual).
///
/// **Lifecycle**: create once per editor session alongside
/// `MicroInteractionEngine`, call effect methods as needed, and discard
/// when the editor is torn down.
final class SnapAlignEffectEngine {

    // MARK: - Constants

    /// Snap glow: shadow radius 0 → 4, shadow opacity 0 → 0.12, duration 0.25 s.
    private enum SnapGlowConstants {
        static let maxShadowRadius: CGFloat = 4.0
        static let maxShadowOpacity: Float = 0.12
        static let duration: CFTimeInterval = 0.25
    }

    /// Line guide flash: 1-pt hairline, opacity 0 → 0.3 → 0, duration 0.3 s.
    private enum GuideFlashConstants {
        static let lineWidth: CGFloat = 1.0
        static let maxOpacity: Float = 0.3
        static let duration: CFTimeInterval = 0.3
    }

    /// Haptic style for perfect-alignment pulse.
    private enum HapticConstants {
        static let style: UIImpactFeedbackGenerator.FeedbackStyle = .light
    }

    // MARK: - State

    private var activeEffectCount: Int = 0

    /// Maximum simultaneous snap/align effects (mirrors `InteractionRules`).
    private static let maxSimultaneousEffects: Int = 2

    /// Pre-allocated haptic generator for zero-latency feedback.
    private let hapticGenerator: UIImpactFeedbackGenerator

    /// Tracks whether the previous frame was already perfectly aligned
    /// to avoid repeated haptic pulses during sustained alignment.
    private var isPerfectlyAligned: Bool = false

    // MARK: - Init

    init() {
        hapticGenerator = UIImpactFeedbackGenerator(style: HapticConstants.style)
        hapticGenerator.prepare()
    }

    /// Current adaptive effect intensity.  Updated by the owning view.
    var effectIntensity: EffectIntensity = .full

    // MARK: - Snap Glow (Sticker Alignment)

    /// Plays a brief, subtle glow around a layer when it snaps to a guide.
    ///
    /// Shadow radius animates 0 → 4 pt, shadow opacity 0 → 0.12, then
    /// auto-reverses.  Total duration: 0.25 s.  The layer's existing shadow
    /// state is restored on completion.
    ///
    /// - Parameters:
    ///   - layer: The snapped object's layer.
    ///   - color: Glow colour (default: system accent).
    func playSnapGlow(
        on layer: CALayer,
        color: UIColor = UIColor.systemBlue.withAlphaComponent(0.6)
    ) {
        guard !ReduceMotionObserver.shared.isEnabled, effectIntensity.allowsSnapAlignVisuals else { return }
        guard activeEffectCount < Self.maxSimultaneousEffects else { return }

        let previousShadowColor   = layer.shadowColor
        let previousShadowRadius  = layer.shadowRadius
        let previousShadowOpacity = layer.shadowOpacity
        let previousShadowOffset  = layer.shadowOffset

        layer.shadowColor  = color.cgColor
        layer.shadowOffset = .zero
        activeEffectCount += 1

        let timing = CAMediaTimingFunction(controlPoints: 0.42, 0.0, 0.58, 1.0) // ease-in-out

        let radius       = CABasicAnimation(keyPath: "shadowRadius")
        radius.fromValue = 0
        radius.toValue   = SnapGlowConstants.maxShadowRadius

        let opacity       = CABasicAnimation(keyPath: "shadowOpacity")
        opacity.fromValue = 0
        opacity.toValue   = SnapGlowConstants.maxShadowOpacity

        let group                   = CAAnimationGroup()
        group.animations            = [radius, opacity]
        group.duration              = SnapGlowConstants.duration
        group.timingFunction        = timing
        group.autoreverses          = true
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            layer.shadowColor   = previousShadowColor
            layer.shadowRadius  = previousShadowRadius
            layer.shadowOpacity = previousShadowOpacity
            layer.shadowOffset  = previousShadowOffset
            self?.activeEffectCount -= 1
        }
        layer.add(group, forKey: "snapGlow")
        CATransaction.commit()
    }

    // MARK: - Line Guide Flash (Shape Alignment)

    /// Flashes a thin alignment guide line inside a container layer.
    ///
    /// The line appears at full position immediately and fades from
    /// 0.3 → 0 opacity over 0.3 s, then is removed from the layer tree.
    ///
    /// - Parameters:
    ///   - from: Start point of the guide line.
    ///   - to: End point of the guide line.
    ///   - container: The parent layer to add the guide line to.
    ///   - color: Line colour (default: system red at 50 %).
    func playLineGuideFlash(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        in container: CALayer,
        color: UIColor = UIColor.systemRed.withAlphaComponent(0.5)
    ) {
        guard !ReduceMotionObserver.shared.isEnabled, effectIntensity.allowsSnapAlignVisuals else { return }
        guard activeEffectCount < Self.maxSimultaneousEffects else { return }

        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)

        let line = CAShapeLayer()
        line.path        = path.cgPath
        line.strokeColor = color.cgColor
        line.fillColor   = UIColor.clear.cgColor
        line.lineWidth   = GuideFlashConstants.lineWidth
        line.lineDashPattern = [4, 4] // subtle dash pattern
        line.opacity     = 0

        container.addSublayer(line)
        activeEffectCount += 1

        let timing = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0) // ease-out

        let fadeIn       = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue   = GuideFlashConstants.maxOpacity
        fadeIn.duration  = GuideFlashConstants.duration * 0.3 // fast appearance

        let fadeOut           = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue     = GuideFlashConstants.maxOpacity
        fadeOut.toValue       = 0
        fadeOut.beginTime     = GuideFlashConstants.duration * 0.3
        fadeOut.duration      = GuideFlashConstants.duration * 0.7

        let group                   = CAAnimationGroup()
        group.animations            = [fadeIn, fadeOut]
        group.duration              = GuideFlashConstants.duration
        group.timingFunction        = timing
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = false

        let captured = line
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.activeEffectCount -= 1
        }
        line.add(group, forKey: "guideFlash")
        CATransaction.commit()
    }

    // MARK: - Perfect Alignment Pulse (Haptic)

    /// Fires a micro-haptic pulse when an object is perfectly aligned on
    /// both axes simultaneously.
    ///
    /// This is edge-triggered: it fires once when perfect alignment is first
    /// achieved and does not re-fire until alignment is broken and re-achieved.
    ///
    /// Haptic feedback is not affected by Reduce Motion (it's non-visual).
    ///
    /// - Parameter isAligned: Whether the object is currently perfectly
    ///   aligned on both X and Y axes.
    func updatePerfectAlignment(isAligned: Bool) {
        if isAligned && !isPerfectlyAligned {
            hapticGenerator.impactOccurred(intensity: 0.5) // subtle
            isPerfectlyAligned = true
        } else if !isAligned {
            isPerfectlyAligned = false
        }
    }

    /// Prepares the haptic generator for imminent use (call at drag start).
    func prepareHaptics() {
        hapticGenerator.prepare()
    }

    // MARK: - Convenience — Combined Snap Feedback

    /// Plays the appropriate snap feedback for a snap event.
    ///
    /// Combines the visual glow with alignment state tracking. Call this
    /// from the canvas view's pan-changed handler when a snap is detected.
    ///
    /// - Parameters:
    ///   - layer: The snapped object's layer.
    ///   - snappedX: Whether the object snapped on the X axis.
    ///   - snappedY: Whether the object snapped on the Y axis.
    ///   - color: Optional glow colour override.
    func playSnapFeedback(
        on layer: CALayer,
        snappedX: Bool,
        snappedY: Bool,
        color: UIColor = UIColor.systemBlue.withAlphaComponent(0.6)
    ) {
        guard snappedX || snappedY else {
            updatePerfectAlignment(isAligned: false)
            return
        }

        playSnapGlow(on: layer, color: color)
        updatePerfectAlignment(isAligned: snappedX && snappedY)
    }
}
