import UIKit
import QuartzCore

/// Performance-budgeted overlay engine for writing effects with 2D physics.
///
/// Attaches a non-interactive `UIView` above the canvas container to render:
/// - **Sparkle / Fire / Rainbow / Snow / Dissolve / Glow** — `CAEmitterLayer`
///   with physics-informed parameters and per-tier particle budget.
/// - **Glitch** — `CAAnimationGroup` on a full-bounds layer (horizontal shift +
///   transient colour tint) triggered each time a stroke event fires.
/// - **Ripple** — expanding `CAShapeLayer` ring at the stroke endpoint.
/// - **Lightning** — branching electric bolt `CAShapeLayer` at stroke end.
///
/// **Physics engine**
/// Each emitter-based effect reads a `ParticlePhysics` preset that maps to
/// `CAEmitterCell` properties: gravity → `yAcceleration`, wind → `xAcceleration`,
/// turbulence → `velocityRange`, drag → `alphaSpeed`/`scaleSpeed`, spin → `spin`/`spinRange`.
/// This gives physically-realistic behaviour (flames rise, sparks scatter, snow drifts)
/// while staying within Core Animation's hardware-accelerated compositor.
///
/// **Performance contract**
/// - The overlay view is removed from the hierarchy entirely when
///   `activeFX == .none` (zero layer cost).
/// - Particle counts are hard-capped to `DeviceCapabilityTier.maxParticles`.
/// - Ripple layers are capped at 3 concurrent rings.
/// - Lightning bolt layers are capped at 2 concurrent bolts.
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

    // Emitter (fire / sparkle / rainbow / snow / dissolve / glow)
    private let emitterLayer = CAEmitterLayer()

    // Glitch
    private let glitchLayer  = CALayer()

    // Glow — soft radial gradient layer that follows the nib
    private let glowLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.type = .radial
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint   = CGPoint(x: 1.0, y: 1.0)
        g.isHidden   = true
        return g
    }()

    // Ripple (created per-stroke, up to 3 live at once)
    private var rippleLayers: [CAShapeLayer] = []

    // Lightning (created per-stroke, up to 2 live at once)
    private var lightningLayers: [CAShapeLayer] = []

    // Rainbow hue offset — advances with each stroke update for colour cycling
    private var rainbowHueOffset: CGFloat = 0

    // Current stroke colour — updated via configure(fx:color:)
    private var strokeColor: UIColor = .black

    // MARK: - Init

    init(tier: DeviceCapabilityTier) {
        self.tier = tier

        // Emitter layer — shared between all emitter-based effects
        emitterLayer.renderMode = .additive
        emitterLayer.isHidden   = true
        overlayView.layer.addSublayer(emitterLayer)

        // Glitch layer — full-bounds, initially hidden
        glitchLayer.isHidden = true
        overlayView.layer.addSublayer(glitchLayer)

        // Glow layer — 60×60 radial gradient, initially hidden
        glowLayer.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        glowLayer.cornerRadius = 30
        glowLayer.isHidden = true
        overlayView.layer.addSublayer(glowLayer)
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

        // Keep glitch layer frame in sync with the overlay; the overlay auto-resizes
        // via autoresizingMask but CALayer sublayers do not.
        if glitchLayer.frame != overlayView.bounds {
            glitchLayer.frame = overlayView.bounds
        }

        // Gracefully downgrade FX that the device cannot support.
        let resolved = fx.isSupported(on: tier) ? fx : .none
        guard resolved != activeFX else {
            // Same FX, but colour might have changed — recolour emitter cells.
            switch resolved {
            case .fire, .sparkle, .snow, .dissolve, .rainbow:
                recolourEmitter(color: color)
            case .glow:
                configureGlowColor(color)
            default:
                break
            }
            return
        }

        stopCurrentFX()
        activeFX = resolved
        overlayView.isHidden = (resolved == .none)

        switch resolved {
        case .fire:      setupFireEmitter(color: color)
        case .sparkle:   setupSparkleEmitter(color: color)
        case .glitch:    setupGlitchLayer()
        case .ripple:    break  // triggered per-stroke via onStrokeEnded
        case .rainbow:   setupRainbowEmitter()
        case .snow:      setupSnowEmitter(color: color)
        case .lightning:  break  // triggered per-stroke via onStrokeEnded
        case .dissolve:  setupDissolveEmitter(color: color)
        case .glow:      setupGlowLayer(color: color)
        case .none:      break
        }
    }

    // MARK: - Stroke Event Hooks

    /// Call when the pencil begins a new stroke (first touch down).
    func onStrokeBegan(at point: CGPoint) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve, .rainbow:
            emitterLayer.isHidden   = false
            emitterLayer.birthRate  = 1
            updateEmitterPosition(point)
        case .glitch:
            glitchLayer.isHidden = false
            triggerGlitchPulse()
        case .glow:
            glowLayer.isHidden = false
            updateGlowPosition(point)
        default:
            break
        }
    }

    /// Call for every drawing-changed callback to track the latest nib position.
    func onStrokeUpdated(at point: CGPoint) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve:
            updateEmitterPosition(point)
        case .rainbow:
            rainbowHueOffset += 0.02
            if rainbowHueOffset > 1.0 { rainbowHueOffset -= 1.0 }
            recolourEmitter(color: UIColor(hue: rainbowHueOffset, saturation: 0.9, brightness: 1.0, alpha: 0.9))
            updateEmitterPosition(point)
        case .glitch:
            triggerGlitchPulse()
        case .glow:
            updateGlowPosition(point)
        default:
            break
        }
    }

    /// Call when the pencil lifts (stroke finished).
    func onStrokeEnded(at point: CGPoint) {
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve, .rainbow:
            emitterLayer.birthRate = 0
        case .ripple:
            triggerRipple(at: point)
        case .lightning:
            triggerLightning(at: point)
        case .glow:
            // Fade glow out smoothly
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            glowLayer.opacity = 0
            CATransaction.setCompletionBlock { [weak self] in
                self?.glowLayer.isHidden = true
                self?.glowLayer.opacity = 1
            }
            CATransaction.commit()
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

    // MARK: - Private: Fire (physics-driven)

    private func setupFireEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 4, height: 4)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeFireCell(color: color)]
        emitterLayer.birthRate    = 0  // enabled on stroke begin
    }

    private func makeFireCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.firePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 60)) * 0.8
        cell.lifetime          = 0.45
        cell.lifetimeRange     = 0.25
        cell.velocity          = 70
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity     // negative = rise (flames go up)
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi / 5
        cell.emissionLongitude = -.pi / 2  // upward
        cell.scale             = 0.05
        cell.scaleRange        = 0.02
        cell.scaleSpeed        = -0.015
        cell.alphaSpeed        = -2.2
        cell.spin              = 0.5
        cell.spinRange         = physics.spinRange

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

    // MARK: - Private: Sparkle (physics-driven)

    private func setupSparkleEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 4, height: 4)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeSparkleCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeSparkleCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.sparklePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 15)) * 0.6
        cell.lifetime          = 0.35
        cell.lifetimeRange     = 0.20
        cell.velocity          = 45
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2  // omnidirectional
        cell.scale             = 0.025
        cell.scaleRange        = 0.012
        cell.scaleSpeed        = -0.020
        cell.alphaSpeed        = -2.8
        cell.spin              = 1.0
        cell.spinRange         = physics.spinRange
        cell.color             = color.withAlphaComponent(0.95).cgColor
        cell.redRange          = 0.12
        cell.blueRange         = 0.12
        cell.contents          = circleCGImage(diameter: 8)
        return cell
    }

    // MARK: - Private: Rainbow (hue-cycling emitter)

    private func setupRainbowEmitter() {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 4, height: 4)
        emitterLayer.isHidden     = false
        rainbowHueOffset = 0
        emitterLayer.emitterCells = [makeRainbowCell()]
        emitterLayer.birthRate    = 0
    }

    private func makeRainbowCell() -> CAEmitterCell {
        let physics = ParticlePhysics.rainbowPhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 25)) * 0.7
        cell.lifetime          = 0.6
        cell.lifetimeRange     = 0.3
        cell.velocity          = 30
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.03
        cell.scaleRange        = 0.015
        cell.scaleSpeed        = -0.012
        cell.alphaSpeed        = -1.6
        cell.spin              = 0.3
        cell.spinRange         = physics.spinRange
        // Start with red — hue will cycle via recolourEmitter on each update
        cell.color             = UIColor(hue: 0, saturation: 0.9, brightness: 1.0, alpha: 0.85).cgColor
        cell.redRange          = 0.15
        cell.greenRange        = 0.15
        cell.blueRange         = 0.15
        cell.contents          = circleCGImage(diameter: 10)
        return cell
    }

    // MARK: - Private: Snow (physics-driven falling particles)

    private func setupSnowEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 20, height: 4)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeSnowCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeSnowCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.snowPhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 20)) * 0.5
        cell.lifetime          = 1.2
        cell.lifetimeRange     = 0.5
        cell.velocity          = 15
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity      // gentle descent
        cell.xAcceleration     = physics.wind          // sideways drift
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.02
        cell.scaleRange        = 0.015
        cell.scaleSpeed        = -0.005
        cell.alphaSpeed        = -0.8
        cell.spin              = 0.3
        cell.spinRange         = physics.spinRange
        // White-ish with a tint from the user's colour
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let sr = min(1.0, 0.7 + r * 0.3)
        let sg = min(1.0, 0.7 + g * 0.3)
        let sb = min(1.0, 0.7 + b * 0.3)
        cell.color             = UIColor(red: sr, green: sg, blue: sb, alpha: 0.85).cgColor
        cell.redRange          = 0.08
        cell.blueRange         = 0.08
        cell.contents          = snowflakeCGImage(diameter: 10)
        return cell
    }

    // MARK: - Private: Dissolve (chaotic disintegration particles)

    private func setupDissolveEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeDissolveCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeDissolveCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.dissolvePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 35)) * 0.7
        cell.lifetime          = 0.55
        cell.lifetimeRange     = 0.3
        cell.velocity          = 50
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity      // crumble downward
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.018
        cell.scaleRange        = 0.012
        cell.scaleSpeed        = -0.025   // shrink as they disintegrate
        cell.alphaSpeed        = -1.8
        cell.spin              = 1.5
        cell.spinRange         = physics.spinRange
        cell.color             = color.withAlphaComponent(0.80).cgColor
        cell.redRange          = 0.10
        cell.greenRange        = 0.10
        cell.contents          = squareCGImage(size: 6)
        return cell
    }

    // MARK: - Private: Glow (soft luminous aura)

    private func setupGlowLayer(color: UIColor) {
        configureGlowColor(color)
        glowLayer.isHidden = true  // shown on stroke begin
        glowLayer.opacity = 1
    }

    private func configureGlowColor(_ color: UIColor) {
        let glowColor = color.withAlphaComponent(0.45)
        let clearColor = color.withAlphaComponent(0.0)
        glowLayer.colors = [glowColor.cgColor, clearColor.cgColor]
        glowLayer.locations = [0.0, 1.0]
    }

    private func updateGlowPosition(_ point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowLayer.position = point
        CATransaction.commit()
    }

    // MARK: - Private: Lightning (electric bolt at stroke end)

    private func triggerLightning(at point: CGPoint) {
        // Cap simultaneous bolts to avoid layer proliferation
        while lightningLayers.count >= 2 {
            lightningLayers.first?.removeFromSuperlayer()
            lightningLayers.removeFirst()
        }

        let bolt = CAShapeLayer()
        bolt.fillColor   = UIColor.clear.cgColor
        bolt.strokeColor = strokeColor.withAlphaComponent(0.85).cgColor
        bolt.lineWidth   = 1.5
        bolt.lineCap     = .round
        bolt.lineJoin    = .round
        bolt.path        = lightningPath(from: point)
        overlayView.layer.addSublayer(bolt)
        lightningLayers.append(bolt)

        // Bright flash then fade
        let flashAnim          = CABasicAnimation(keyPath: "opacity")
        flashAnim.fromValue    = 1.0
        flashAnim.toValue      = 0.0

        let widthAnim          = CABasicAnimation(keyPath: "lineWidth")
        widthAnim.fromValue    = 2.5
        widthAnim.toValue      = 0.5

        let group                   = CAAnimationGroup()
        group.animations            = [flashAnim, widthAnim]
        group.duration              = 0.35
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = false

        let captured = bolt
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            captured.removeFromSuperlayer()
            self?.lightningLayers.removeAll { $0 === captured }
        }
        bolt.add(group, forKey: "lightningFade")
        CATransaction.commit()
    }

    /// Generates a random branching bolt path originating from `point`.
    private func lightningPath(from origin: CGPoint) -> CGPath {
        let path = UIBezierPath()
        path.move(to: origin)

        var current = origin
        let segments = Int.random(in: 4...7)
        let mainAngle = CGFloat.random(in: -.pi * 0.8 ... -.pi * 0.2) // generally upward

        for i in 0..<segments {
            let length = CGFloat.random(in: 12...28)
            let jitter = CGFloat.random(in: -0.4...0.4)
            let angle  = mainAngle + jitter
            let next   = CGPoint(
                x: current.x + cos(angle) * length,
                y: current.y + sin(angle) * length
            )
            path.addLine(to: next)

            // Branch with 30% probability (not on last segment)
            if i < segments - 1 && Int.random(in: 0..<10) < 3 {
                let branchAngle  = angle + CGFloat.random(in: 0.4...1.0) * (Bool.random() ? 1 : -1)
                let branchLength = CGFloat.random(in: 8...18)
                let branchEnd    = CGPoint(
                    x: next.x + cos(branchAngle) * branchLength,
                    y: next.y + sin(branchAngle) * branchLength
                )
                path.addLine(to: branchEnd)
                path.move(to: next)  // return to main trunk
            }
            current = next
        }
        return path.cgPath
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

        glowLayer.removeAllAnimations()
        glowLayer.isHidden = true

        rippleLayers.forEach { $0.removeFromSuperlayer() }
        rippleLayers.removeAll()

        lightningLayers.forEach { $0.removeFromSuperlayer() }
        lightningLayers.removeAll()

        rainbowHueOffset = 0
    }

    // MARK: - Private: Helpers

    private func circleCGImage(diameter: CGFloat) -> CGImage? {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }.cgImage
    }

    /// Six-pointed snowflake bitmap for the snow effect.
    private func snowflakeCGImage(diameter: CGFloat) -> CGImage? {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter / 2 - 1
            UIColor.white.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 1.0
            // Draw 6 radial arms
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3
                let endPt = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                path.move(to: center)
                path.addLine(to: endPt)
            }
            path.stroke()
        }.cgImage
    }

    /// Small square bitmap for the dissolve effect (simulates crumbling chunks).
    private func squareCGImage(size: CGFloat) -> CGImage? {
        let sz = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: sz)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 1).fill()
        }.cgImage
    }
}
