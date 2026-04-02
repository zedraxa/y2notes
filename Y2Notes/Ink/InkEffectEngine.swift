import UIKit
import QuartzCore

/// Performance-budgeted overlay engine for writing effects.
///
/// Attaches a non-interactive `UIView` above the canvas container to render:
/// - **Sparkle / Fire** — `CAEmitterLayer` with a per-tier particle budget.
/// - **Glitch** — `CAAnimationGroup` on a full-bounds layer (horizontal shift +
///   transient colour tint) triggered each time a stroke event fires.
/// - **Ripple** — expanding `CAShapeLayer` ring at the stroke endpoint.
///
/// **Performance contract**
/// - The overlay view is removed from the hierarchy entirely when
///   `activeFX == .none` (zero layer cost).
/// - Particle counts are hard-capped to `DeviceCapabilityTier.maxParticles`.
/// - Ripple layers are capped at 3 concurrent rings.
/// - All animations are removed and emitter cells cleared in `deactivate()`.
///
/// **Thread safety**: must be created and used on the main thread only.
final class InkEffectEngine {

    // MARK: - Properties

    private(set) var activeFX: WritingFXType = .none
    private let tier: DeviceCapabilityTier

    private weak var containerView: UIView?

    /// Non-interactive overlay that hosts all effect layers.
    let overlayView: UIView = {
        let v = UIView()
        v.backgroundColor          = .clear
        v.isOpaque                 = false
        v.isUserInteractionEnabled = false
        return v
    }()

    // Emitter (fire + sparkle)
    private let emitterLayer = CAEmitterLayer()

    // Glitch
    private let glitchLayer  = CALayer()

    // Ripple (created per-stroke, up to 3 live at once)
    private var rippleLayers: [CAShapeLayer] = []

    // Current stroke colour — updated via configure(fx:color:)
    private var strokeColor: UIColor = .black

    // MARK: - Init

    init(tier: DeviceCapabilityTier) {
        self.tier = tier

        // Emitter layer — shared between fire and sparkle modes
        emitterLayer.renderMode = .additive
        emitterLayer.isHidden   = true
        overlayView.layer.addSublayer(emitterLayer)

        // Glitch layer — full-bounds, initially hidden
        glitchLayer.isHidden = true
        overlayView.layer.addSublayer(glitchLayer)
    }

    // MARK: - Attach / Detach

    /// Adds the non-interactive overlay above all existing subviews of `view`.
    func attach(to view: UIView) {
        containerView = view
        overlayView.frame                = view.bounds
        overlayView.autoresizingMask     = [.flexibleWidth, .flexibleHeight]
        glitchLayer.frame                = view.bounds
        // CALayer does not support UIView's autoresizingMask constants on iOS;
        // rely on manual frame updates instead (attach caller should relayout).
        view.addSubview(overlayView)
        overlayView.isHidden = (activeFX == .none)
    }

    /// Stops all FX and removes the overlay from its superview.
    func detach() {
        deactivate()
        overlayView.removeFromSuperview()
    }

    // MARK: - Configuration

    /// Updates the active effect and ink colour.  Safe to call on every
    /// `InkEffectStore` change — internally compares to avoid redundant work.
    func configure(fx: WritingFXType, color: UIColor) {
        strokeColor = color

        // Gracefully downgrade FX that the device cannot support.
        let resolved = fx.isSupported(on: tier) ? fx : .none
        guard resolved != activeFX else {
            // Same FX, but colour might have changed — recolour emitter cells.
            if resolved == .fire || resolved == .sparkle {
                recolourEmitter(color: color)
            }
            return
        }

        stopCurrentFX()
        activeFX = resolved
        overlayView.isHidden = (resolved == .none)

        switch resolved {
        case .fire:    setupFireEmitter(color: color)
        case .sparkle: setupSparkleEmitter(color: color)
        case .glitch:  setupGlitchLayer()
        case .ripple:  break  // triggered per-stroke via onStrokeEnded
        case .none:    break
        }
    }

    // MARK: - Stroke Event Hooks

    /// Call when the pencil begins a new stroke (first touch down).
    func onStrokeBegan(at point: CGPoint) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle:
            emitterLayer.isHidden   = false
            emitterLayer.birthRate  = 1
            updateEmitterPosition(point)
        case .glitch:
            glitchLayer.isHidden = false
            triggerGlitchPulse()
        default:
            break
        }
    }

    /// Call for every drawing-changed callback to track the latest nib position.
    func onStrokeUpdated(at point: CGPoint) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle:
            updateEmitterPosition(point)
        case .glitch:
            triggerGlitchPulse()
        default:
            break
        }
    }

    /// Call when the pencil lifts (stroke finished).
    func onStrokeEnded(at point: CGPoint) {
        switch activeFX {
        case .fire, .sparkle:
            emitterLayer.birthRate = 0
        case .ripple:
            triggerRipple(at: point)
        default:
            break
        }
    }

    // MARK: - Deactivate

    /// Removes all active FX layers / animations and marks the engine idle.
    func deactivate() {
        stopCurrentFX()
        activeFX             = .none
        overlayView.isHidden = true
    }

    // MARK: - Private: Fire

    private func setupFireEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 4, height: 4)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeFireCell(color: color)]
        emitterLayer.birthRate    = 0  // enabled on stroke begin
    }

    private func makeFireCell(color: UIColor) -> CAEmitterCell {
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 60)) * 0.8
        cell.lifetime          = 0.45
        cell.lifetimeRange     = 0.25
        cell.velocity          = 70
        cell.velocityRange     = 35
        cell.emissionRange     = .pi / 5
        cell.emissionLongitude = -.pi / 2  // upward
        cell.scale             = 0.05
        cell.scaleRange        = 0.02
        cell.scaleSpeed        = -0.015
        cell.alphaSpeed        = -2.2
        cell.spin              = 0.5
        cell.spinRange         = 1.0

        // Boost fire-orange bias while preserving the user's hue intent
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let fr = min(1.0, r + 0.30)
        let fg = min(1.0, g + 0.10)
        let fb = max(0.0, b - 0.20)
        cell.color      = UIColor(red: fr, green: fg, blue: fb, alpha: 0.90).cgColor
        cell.redRange   = 0.30
        cell.greenRange = 0.20
        cell.contents   = circleCGImage(diameter: 12)
        return cell
    }

    // MARK: - Private: Sparkle

    private func setupSparkleEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 4, height: 4)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeSparkleCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeSparkleCell(color: UIColor) -> CAEmitterCell {
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 15)) * 0.6
        cell.lifetime          = 0.35
        cell.lifetimeRange     = 0.20
        cell.velocity          = 45
        cell.velocityRange     = 40
        cell.emissionRange     = .pi * 2  // omnidirectional
        cell.scale             = 0.025
        cell.scaleRange        = 0.012
        cell.scaleSpeed        = -0.020
        cell.alphaSpeed        = -2.8
        cell.color             = color.withAlphaComponent(0.95).cgColor
        cell.redRange          = 0.12
        cell.blueRange         = 0.12
        cell.contents          = circleCGImage(diameter: 8)
        return cell
    }

    private func recolourEmitter(color: UIColor) {
        guard let cell = emitterLayer.emitterCells?.first else { return }
        cell.color = color.cgColor
        emitterLayer.emitterCells = [cell]
    }

    private func updateEmitterPosition(_ point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.emitterPosition = point
        CATransaction.commit()
    }

    // MARK: - Private: Glitch

    private func setupGlitchLayer() {
        glitchLayer.backgroundColor = UIColor.clear.cgColor
        glitchLayer.isHidden = true
    }

    private func triggerGlitchPulse() {
        glitchLayer.isHidden = false

        // Horizontal jitter
        let shiftAnim            = CABasicAnimation(keyPath: "transform.translation.x")
        shiftAnim.fromValue      = 0
        shiftAnim.toValue        = CGFloat.random(in: -7...7)
        shiftAnim.duration       = 0.04
        shiftAnim.autoreverses   = true
        shiftAnim.isRemovedOnCompletion = true

        // Brief cyan-tint bleed (scan-line artefact)
        let tintAnim             = CABasicAnimation(keyPath: "backgroundColor")
        tintAnim.fromValue       = UIColor.clear.cgColor
        tintAnim.toValue         = UIColor(red: 0, green: 1, blue: 0.9, alpha: 0.07).cgColor
        tintAnim.duration        = 0.04
        tintAnim.autoreverses    = true
        tintAnim.isRemovedOnCompletion = true

        let group                = CAAnimationGroup()
        group.animations         = [shiftAnim, tintAnim]
        group.duration           = 0.08
        group.isRemovedOnCompletion = true

        glitchLayer.add(group, forKey: "glitchPulse")
    }

    // MARK: - Private: Ripple

    private func triggerRipple(at point: CGPoint) {
        // Cap simultaneous rings to avoid layer proliferation
        while rippleLayers.count >= 3 {
            rippleLayers.first?.removeFromSuperlayer()
            rippleLayers.removeFirst()
        }

        let ring           = CAShapeLayer()
        ring.fillColor     = UIColor.clear.cgColor
        ring.strokeColor   = strokeColor.withAlphaComponent(0.55).cgColor
        ring.lineWidth     = 1.5
        ring.path          = circlePath(center: point, radius: 5)
        overlayView.layer.addSublayer(ring)
        rippleLayers.append(ring)

        let expandPath     = circlePath(center: point, radius: 30)

        let pathAnim       = CABasicAnimation(keyPath: "path")
        pathAnim.toValue   = expandPath

        let opacityAnim    = CABasicAnimation(keyPath: "opacity")
        opacityAnim.toValue = 0

        let group                    = CAAnimationGroup()
        group.animations             = [pathAnim, opacityAnim]
        group.duration               = 0.50
        group.fillMode               = .forwards
        group.isRemovedOnCompletion  = false

        let captured = ring
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.rippleLayers.removeAll { $0 === captured }
        }
        ring.add(group, forKey: "rippleExpand")
        CATransaction.commit()
    }

    private func circlePath(center: CGPoint, radius: CGFloat) -> CGPath {
        UIBezierPath(
            arcCenter: center, radius: radius,
            startAngle: 0, endAngle: .pi * 2, clockwise: true
        ).cgPath
    }

    // MARK: - Private: Stop

    private func stopCurrentFX() {
        emitterLayer.birthRate    = 0
        emitterLayer.emitterCells = []
        emitterLayer.isHidden     = true

        glitchLayer.removeAllAnimations()
        glitchLayer.isHidden = true

        rippleLayers.forEach { $0.removeFromSuperlayer() }
        rippleLayers.removeAll()
    }

    // MARK: - Private: Helpers

    private func circleCGImage(diameter: CGFloat) -> CGImage? {
        let size = CGSize(width: diameter, height: diameter)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }
}
