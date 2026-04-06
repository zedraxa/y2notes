import UIKit
import Metal
import QuartzCore

    /// Performance-budgeted overlay engine for writing effects with 2D physics.
///
/// Attaches a non-interactive `UIView` above the canvas container to render:
/// - **Sparkle / Fire / Rainbow / Snow / Dissolve / Glow / Sheen / Shadow / Blood** —
///   `CAEmitterLayer` with physics-informed parameters and per-tier particle budget.
///   **Fire** uses three emitter cells — bright yellow-white core, orange mid-flame,
///   and rare ember sparks — plus a dedicated warm amber `CAGradientLayer` glow aura
///   that follows the nib while writing and fades on pencil-lift.
/// - **Glitch** — `CAAnimationGroup` on a full-bounds layer (horizontal shift +
///   transient colour tint) triggered each time a stroke event fires.
/// - **Ripple** — expanding `CAShapeLayer` ring at the stroke endpoint.
/// - **Lightning** — branching electric bolt `CAShapeLayer` at stroke end.
///
/// **New interactive effects (AGENT-21)**
/// - **Sheen** — Holographic iridescent shimmer; hue cycles rapidly as you write,
///   creating a colour-shifting rainbow sheen that follows the nib exactly.
/// - **Shadow** — Dark translucent smoke particles billow and sink behind strokes,
///   giving ink a cinematic depth and weight.
/// - **Blood** — Heavy crimson drops fall from the nib as you write, creating a
///   visceral horror ink experience.  Particles obey high-gravity physics so they
///   quickly fall off-screen below the stroke.
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

    // MARK: - SheenTuning

    /// Glow geometry, timing, and hue-cycling constants for the holographic sheen effect.
    /// The Metal particle renderer handles particle budgets independently.
    private enum SheenTuning {
        // ── Glow geometry ───────────────────────────────────────────────
        /// Diameter of the iridescent radial glow that follows the nib.
        static let glowDiameter: CGFloat       = 72
        /// Duration of the glow fade-out animation when the stroke ends.
        static let glowFadeDuration: Double    = 0.35

        // ── Hue cycling (CAGradientLayer glow only) ─────────────────────
        /// Hue advance per `onStrokeUpdated` call — controls cycle speed.
        static let hueStepPerUpdate: CGFloat   = 0.035
        /// Phase offset applied to the flare colour's hue relative to the core.
        static let flareHuePhaseOffset: CGFloat = 0.15
        /// Phase offset applied to the dust colour's hue relative to the core.
        static let dustHuePhaseOffset: CGFloat  = 0.33
    }

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

    // Metal GPU particle renderer — replaces CAEmitterLayer for all emitter-based effects.
    // Nil only if the device somehow lacks Metal support (unreachable on iOS 17+).
    private var metalRenderer: MetalParticleRenderer?

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

    // Sheen iridescent glow — multi-stop radial gradient that cycles hue with the nib
    private let sheenGlowLayer: CAGradientLayer = {
        let g = CAGradientLayer()
        g.type       = .radial
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint   = CGPoint(x: 1.0, y: 1.0)
        g.isHidden   = true
        return g
    }()

    // Fire glow — warm amber radial aura that follows the nib while writing with fire
    private let fireGlowLayer: CAGradientLayer = {
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

    // Sheen hue offset — advances faster than rainbow for rapid colour cycling
    private var sheenHueOffset: CGFloat = 0

    // Last recorded nib position for sheen velocity calculation
    private var lastSheenPoint: CGPoint?

    // Current stroke colour — updated via configure(fx:color:)
    private var strokeColor: UIColor = .black

    // Generation counter used to cancel pending end-of-stroke burst timers
    // if a new stroke begins before the timer fires.
    private var strokeEndGeneration: Int = 0

    // MARK: - Init

    init(tier: DeviceCapabilityTier) {
        self.tier = tier

        // Glitch layer — full-bounds, initially hidden
        glitchLayer.isHidden = true
        overlayView.layer.addSublayer(glitchLayer)

        // Glow layer — 120×120 radial gradient, initially hidden
        glowLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 120)
        glowLayer.cornerRadius = 60
        glowLayer.isHidden = true
        overlayView.layer.addSublayer(glowLayer)
        // Fire glow layer — 80×80 warm amber aura, initially hidden
        fireGlowLayer.bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
        fireGlowLayer.cornerRadius = 40
        fireGlowLayer.isHidden = true
        overlayView.layer.addSublayer(fireGlowLayer)

        // Sheen glow layer — iridescent radial gradient, initially hidden
        let sd = SheenTuning.glowDiameter
        sheenGlowLayer.bounds       = CGRect(x: 0, y: 0, width: sd, height: sd)
        sheenGlowLayer.cornerRadius = sd / 2
        sheenGlowLayer.isHidden     = true
        overlayView.layer.addSublayer(sheenGlowLayer)
    }

    /// Adds the non-interactive overlay above all existing subviews of `view`.
    ///
    /// Uses Auto Layout constraints instead of `autoresizingMask` so the overlay
    /// correctly fills the container even when the container's initial bounds are
    /// `.zero` (common when called from `makeUIView` before SwiftUI layout).
    func attach(to view: UIView) {
        containerView = view
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        overlayView.isHidden = (activeFX == .none)

        // Create the Metal particle renderer now that the overlay is in the hierarchy.
        metalRenderer = MetalParticleRenderer(overlayLayer: overlayView.layer)
    }

    /// Keeps layer frames in sync with the overlay after layout.
    /// Call from `updateUIView` or `layoutSubviews`.
    func syncLayerFrames() {
        let bounds = overlayView.bounds
        if glitchLayer.frame != bounds {
            glitchLayer.frame = bounds
        }
        metalRenderer?.syncFrame(to: bounds)
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
            // Same FX, same effect — only the colour changed.
            // Update the Metal renderer's color mode so new particles use the updated colour.
            switch resolved {
            case .fire:
                metalRenderer?.updateColorMode(.firePalette(inkTint: color.simd4))
            case .sparkle, .dissolve, .blood:
                metalRenderer?.updateColorMode(.solid(color.simd4))
            case .snow:
                metalRenderer?.updateColorMode(.solid(snowColor(from: color).simd4))
            case .sheen:
                sheenHueOffset = 0
                configureSheenGlow(hue: sheenHueOffset)
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
        case .fire:
            metalRenderer?.configure(preset: .fire,
                                     colorMode: .firePalette(inkTint: color.simd4))
            metalRenderer?.start()
            configureFireGlow(color: color)
        case .sparkle:
            metalRenderer?.configure(preset: .sparkle, colorMode: .solid(color.simd4))
            metalRenderer?.start()
        case .rainbow:
            metalRenderer?.configure(preset: .rainbow,
                                     colorMode: .cyclingHue(saturation: 0.90, brightness: 1.0, alpha: 0.85))
            metalRenderer?.start()
        case .snow:
            metalRenderer?.configure(preset: .snow,
                                     colorMode: .solid(snowColor(from: color).simd4))
            metalRenderer?.start()
        case .dissolve:
            metalRenderer?.configure(preset: .dissolve, colorMode: .solid(color.simd4))
            metalRenderer?.start()
        case .sheen:
            sheenHueOffset = 0
            metalRenderer?.configure(preset: .sheen,
                                     colorMode: .cyclingHue(saturation: 1.0, brightness: 1.0, alpha: 0.88))
            metalRenderer?.start()
            configureSheenGlow(hue: sheenHueOffset)
        case .shadow:
            metalRenderer?.configure(preset: .shadow, colorMode: .shadow)
            metalRenderer?.start()
        case .blood:
            metalRenderer?.configure(preset: .blood, colorMode: .blood)
            metalRenderer?.start()
        case .glitch:    setupGlitchLayer()
        case .ripple:    break   // triggered per-stroke via onStrokeEnded
        case .lightning: break   // triggered per-stroke via onStrokeEnded
        case .glow:      setupGlowLayer(color: color)
        case .none:      break
        }
    }

    // MARK: - Stroke Event Hooks

    /// Call when the pencil begins a new stroke (first touch down).
    func onStrokeBegan(at point: CGPoint) {
        guard activeFX != .none else { return }
        // Cancel any pending end-of-stroke burst timer from the previous stroke.
        strokeEndGeneration += 1
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve, .rainbow, .sheen, .blood, .shadow:
            metalRenderer?.emitterPosition      = point
            metalRenderer?.birthRateMultiplier  = 1.0
            if activeFX == .fire {
                fireGlowLayer.isHidden = false
                updateFireGlowPosition(point)
            }
            if activeFX == .sheen {
                sheenGlowLayer.removeAllAnimations()
                sheenGlowLayer.opacity  = 1
                sheenGlowLayer.isHidden = false
                lastSheenPoint = point
                updateSheenGlowPosition(point)
            }
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
    ///
    /// - Parameters:
    ///   - point: Current nib position in viewport coordinates.
    ///   - pressure: Normalised Apple Pencil force (0–1+). Modulates particle spawn rate.
    ///   - velocity: Instantaneous tip speed in points/second.
    func onStrokeUpdated(at point: CGPoint, pressure: CGFloat = 1.0, velocity: CGFloat = 500) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve, .blood:
            // Pressure → Metal birth rate multiplier: light touch = fewer particles.
            metalRenderer?.birthRateMultiplier = Float(max(0.3, min(1.5, pressure)))
            metalRenderer?.emitterPosition     = point
            if activeFX == .fire {
                updateFireGlowPosition(point)
            }
        case .shadow:
            metalRenderer?.birthRateMultiplier = Float(max(0.3, min(1.5, pressure)))
            metalRenderer?.emitterPosition     = point
        case .rainbow:
            // Color cycling is handled inside MetalParticleRenderer (.cyclingHue mode picks
            // a random hue per spawn); just update position and rate here.
            metalRenderer?.birthRateMultiplier = Float(max(0.3, min(1.5, pressure)))
            metalRenderer?.emitterPosition     = point
        case .sheen:
            // Advance the sheen glow hue (the CAGradientLayer ambient aura).
            sheenHueOffset += SheenTuning.hueStepPerUpdate
            if sheenHueOffset > 1.0 { sheenHueOffset -= 1.0 }
            configureSheenGlow(hue: sheenHueOffset)
            metalRenderer?.birthRateMultiplier = Float(max(0.3, min(1.5, pressure)))
            metalRenderer?.emitterPosition     = point
            lastSheenPoint = point
            updateSheenGlowPosition(point)
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
        case .fire, .sparkle, .snow, .dissolve, .rainbow, .sheen, .blood:
            // End-of-stroke burst: triple the birth rate for 80 ms so particles
            // scatter from the final nib position before fading out naturally.
            metalRenderer?.birthRateMultiplier = 3.0
            strokeEndGeneration += 1
            let gen = strokeEndGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.strokeEndGeneration == gen else { return }
                self.metalRenderer?.birthRateMultiplier = 0
            }
            if activeFX == .fire {
                let fadeAnim                   = CABasicAnimation(keyPath: "opacity")
                fadeAnim.fromValue             = Float(1)
                fadeAnim.toValue               = Float(0)
                fadeAnim.duration              = 0.35
                fadeAnim.fillMode              = .forwards
                fadeAnim.isRemovedOnCompletion = false
                let glow = fireGlowLayer
                CATransaction.begin()
                CATransaction.setCompletionBlock {
                    glow.isHidden = true
                    glow.opacity  = 1
                    glow.removeAnimation(forKey: "fireGlowFade")
                }
                fireGlowLayer.add(fadeAnim, forKey: "fireGlowFade")
                CATransaction.commit()
            }
            if activeFX == .sheen {
                let fadeAnim                   = CABasicAnimation(keyPath: "opacity")
                fadeAnim.fromValue             = Float(1)
                fadeAnim.toValue               = Float(0)
                fadeAnim.duration              = SheenTuning.glowFadeDuration
                fadeAnim.fillMode              = .forwards
                fadeAnim.isRemovedOnCompletion = false
                let glow = sheenGlowLayer
                CATransaction.begin()
                CATransaction.setCompletionBlock {
                    glow.isHidden = true
                    glow.opacity  = 1
                    glow.removeAnimation(forKey: "sheenGlowFade")
                }
                sheenGlowLayer.add(fadeAnim, forKey: "sheenGlowFade")
                CATransaction.commit()
                lastSheenPoint = nil
            }
        case .shadow:
            // Stop emitting; existing puffs linger naturally until their Metal lifetime expires.
            metalRenderer?.birthRateMultiplier = 0
        case .ripple:
            triggerRipple(at: point)
        case .lightning:
            triggerLightning(at: point)
        case .glow:
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

    // MARK: - Private: Glow (soft luminous aura)
    // MARK: - Private: Glow (soft luminous aura)

    private func setupGlowLayer(color: UIColor) {
        configureGlowColor(color)
        glowLayer.isHidden = true  // shown on stroke begin
        glowLayer.opacity = 1
    }

    private func configureGlowColor(_ color: UIColor) {
        let glowColor = color.withAlphaComponent(0.75)
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

    // MARK: - Private: Fire glow helpers (still used with Metal renderer)

    /// Derives the fire glow ambient colour: user hue biased toward warm amber.
    private func fireGlowAmbientColor(from color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return UIColor(
            red:   min(1.0, r * 0.25 + 0.88),
            green: min(1.0, g * 0.20 + 0.32),
            blue:  max(0.0, b * 0.06),
            alpha: 0.32
        )
    }

    /// Configures the fire glow gradient colours from the user's ink colour.
    private func configureFireGlow(color: UIColor) {
        let glowColor = fireGlowAmbientColor(from: color)
        fireGlowLayer.colors = [glowColor.cgColor, UIColor.clear.cgColor]
        fireGlowLayer.locations = [0.0, 1.0]
    }

    private func updateFireGlowPosition(_ point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fireGlowLayer.position = point
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
        shiftAnim.toValue        = CGFloat.random(in: -18...18)
        shiftAnim.duration       = 0.04
        shiftAnim.autoreverses   = true
        shiftAnim.isRemovedOnCompletion = true

        // Brief cyan-tint bleed (scan-line artefact)
        let tintAnim             = CABasicAnimation(keyPath: "backgroundColor")
        tintAnim.fromValue       = UIColor.clear.cgColor
        tintAnim.toValue         = UIColor(red: 0, green: 1, blue: 0.9, alpha: 0.20).cgColor
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
        ring.lineWidth     = 3.5
        ring.path          = circlePath(center: point, radius: 12)
        overlayView.layer.addSublayer(ring)
        rippleLayers.append(ring)

        let expandPath     = circlePath(center: point, radius: 60)

        let pathAnim       = CABasicAnimation(keyPath: "path")
        pathAnim.toValue   = expandPath

        let opacityAnim    = CABasicAnimation(keyPath: "opacity")
        opacityAnim.toValue = 0

        let group                    = CAAnimationGroup()
        group.animations             = [pathAnim, opacityAnim]
        group.duration               = 0.70
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
        // Stop Metal particle emission immediately.
        metalRenderer?.birthRateMultiplier = 0
        // Keep the display link running so existing particles fade out naturally.
        // `metalRenderer?.stop()` would kill them immediately — not desired here.

        glitchLayer.removeAllAnimations()
        glitchLayer.isHidden = true

        glowLayer.removeAllAnimations()
        glowLayer.isHidden = true

        sheenGlowLayer.removeAllAnimations()
        sheenGlowLayer.isHidden = true
        sheenGlowLayer.opacity  = 1

        fireGlowLayer.removeAllAnimations()
        fireGlowLayer.isHidden = true
        fireGlowLayer.opacity  = 1

        rippleLayers.forEach { $0.removeFromSuperlayer() }
        rippleLayers.removeAll()

        lightningLayers.forEach { $0.removeFromSuperlayer() }
        lightningLayers.removeAll()

        rainbowHueOffset = 0
        sheenHueOffset   = 0
        lastSheenPoint   = nil
    }

    // MARK: - Private: Sheen glow helpers

    /// Recolours the sheen glow gradient with a four-stop iridescent colour sweep.
    private func configureSheenGlow(hue: CGFloat) {
        let c0 = UIColor(hue: hue,
                         saturation: 0.90, brightness: 1.0, alpha: 0.40).cgColor
        let c1 = UIColor(hue: fmod(hue + SheenTuning.flareHuePhaseOffset, 1.0),
                         saturation: 0.85, brightness: 1.0, alpha: 0.25).cgColor
        let c2 = UIColor(hue: fmod(hue + SheenTuning.dustHuePhaseOffset, 1.0),
                         saturation: 0.80, brightness: 1.0, alpha: 0.10).cgColor
        let c3 = UIColor(hue: fmod(hue + 0.50, 1.0),
                         saturation: 0.70, brightness: 1.0, alpha: 0.00).cgColor
        sheenGlowLayer.colors    = [c0, c1, c2, c3]
        sheenGlowLayer.locations = [0.0, 0.30, 0.65, 1.0]
    }

    private func updateSheenGlowPosition(_ point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheenGlowLayer.position = point
        CATransaction.commit()
    }

    // MARK: - Private: Snow colour helper

    /// Derives a snow particle colour: white biased toward the user's ink hue.
    private func snowColor(from color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return UIColor(
            red:   min(1.0, 0.70 + r * 0.30),
            green: min(1.0, 0.70 + g * 0.30),
            blue:  min(1.0, 0.70 + b * 0.30),
            alpha: 0.85
        )
    }
}
