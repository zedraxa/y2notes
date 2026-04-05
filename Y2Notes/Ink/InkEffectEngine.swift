import UIKit
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

    /// Centralised budget and timing constants for the holographic sheen effect.
    ///
    /// The renewed sheen uses a **three-cell** emitter architecture:
    ///   1. **Core diamonds** — small, fast-spinning facets that catch light.
    ///   2. **Prismatic flares** — medium elongated streaks for directional shimmer.
    ///   3. **Dust halo** — large, soft circles that create a broad iridescent aura.
    ///
    /// A radial glow layer tracks the nib for an ambient colour wash.
    private enum SheenTuning {
        // ── Particle budgets ────────────────────────────────────────────
        /// Hard cap on core (bright-diamond) particles before tier scaling.
        static let maxCoreParticles: Int       = 80
        /// Hard cap on prismatic flare particles before tier scaling.
        static let maxFlareParticles: Int      = 35
        /// Hard cap on dust (soft-circle) particles before tier scaling.
        static let maxDustParticles: Int       = 40
        /// Fraction of `maxCoreParticles` emitted per second.
        static let coreBirthFraction: Float    = 0.75
        /// Fraction of `maxFlareParticles` emitted per second.
        static let flareBirthFraction: Float   = 0.60
        /// Fraction of `maxDustParticles` emitted per second.
        static let dustBirthFraction: Float    = 0.65

        // ── Glow geometry ───────────────────────────────────────────────
        /// Diameter of the iridescent radial glow that follows the nib.
        static let glowDiameter: CGFloat       = 72
        /// Duration of the glow fade-out animation when the stroke ends.
        static let glowFadeDuration: Double    = 0.35

        // ── Hue cycling ─────────────────────────────────────────────────
        /// Hue advance per `onStrokeUpdated` call — controls cycle speed.
        static let hueStepPerUpdate: CGFloat   = 0.035
        /// Phase offset applied to the flare cell's hue relative to the core cell.
        static let flareHuePhaseOffset: CGFloat = 0.15
        /// Phase offset applied to the dust cell's hue relative to the core cell,
        /// giving the three-layer iridescent split-hue look.
        static let dustHuePhaseOffset: CGFloat  = 0.33

        // ── Velocity-responsive emission ────────────────────────────────
        /// Multiplier applied to birth rate when nib velocity exceeds the base threshold.
        static let velocityBoostMultiplier: Float = 1.6
        /// Nib speed (points/update) above which the velocity boost kicks in.
        static let velocityBoostThreshold: CGFloat = 4.0
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

    // MARK: Budget tuning

    private enum FireTuning {
        /// Hard cap on fire particles used when computing the per-tier budget.
        /// Keeps fire feeling visually dense regardless of tier ceiling.
        static let maxParticles: Int             = 60
        /// Fraction of the budget emitted by the bright inner core flame.
        static let coreBudgetFraction: Float     = 0.28
        /// Fraction of the budget emitted by the main orange mid-flame body.
        static let midBudgetFraction: Float      = 0.62
        /// Fraction of the budget emitted by rare ember sparks (sum = 1.00).
        static let emberBudgetFraction: Float    = 0.10
        static let glowDiameter: CGFloat         = 80
    }

    private enum SheenTuning {
        static let maxBirthRate                  = 50
        static let coreFraction: Float           = 0.60   // 60% budget → core diamond sparkles
        static let dustFraction: Float           = 0.40   // 40% budget → fine dust circles
        static let glowDiameter: CGFloat         = 44
        static let dustHuePhaseOffset: CGFloat   = 0.20   // complementary hue offset for dust cell
    }

    // Emitter (fire / sparkle / rainbow / snow / dissolve / glow / sheen / blood)
    private let emitterLayer = CAEmitterLayer()

    // Shadow smoke — dedicated layer so it can use normal compositing instead of
    // additive blending.  Additive mode makes dark particles invisible on white paper;
    // normal mode lets semi-transparent grey puffs composite correctly.
    private let shadowEmitterLayer: CAEmitterLayer = {
        let l = CAEmitterLayer()
        l.renderMode = .unordered   // standard compositing — correct grey-on-white appearance
        l.isHidden   = true
        return l
    }()

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

    // Sheen glow — iridescent 3-stop radial gradient that tracks the nib
    private let sheenGlowLayer: CAGradientLayer = {
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

    // MARK: - Init

    init(tier: DeviceCapabilityTier) {
        self.tier = tier

        // Emitter layer — shared between all emitter-based effects except shadow
        emitterLayer.renderMode = .additive
        emitterLayer.isHidden   = true
        overlayView.layer.addSublayer(emitterLayer)

        // Shadow smoke emitter — added on top of the shared emitter so smoke
        // composites over fire/sparkle effects if both were ever active.
        overlayView.layer.addSublayer(shadowEmitterLayer)

        // Glitch layer — full-bounds, initially hidden
        glitchLayer.isHidden = true
        overlayView.layer.addSublayer(glitchLayer)

        // Glow layer — 120×120 radial gradient, initially hidden
        glowLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 120)
        glowLayer.cornerRadius = 60
        glowLayer.isHidden = true
        overlayView.layer.addSublayer(glowLayer)
        // Fire glow layer — 80×80 warm amber aura, initially hidden
        fireGlowLayer.bounds = CGRect(x: 0, y: 0,
                                      width:  FireTuning.glowDiameter,
                                      height: FireTuning.glowDiameter)
        fireGlowLayer.cornerRadius = FireTuning.glowDiameter / 2
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
    }

    /// Keeps the glitch layer frame in sync with the overlay after layout.
    /// Call from `updateUIView` or `layoutSubviews` so the glitch layer
    /// matches the overlay's resolved size.
    func syncLayerFrames() {
        if glitchLayer.frame != overlayView.bounds {
            glitchLayer.frame = overlayView.bounds
        }
        if shadowEmitterLayer.frame != overlayView.bounds {
            shadowEmitterLayer.frame = overlayView.bounds
        }
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
            switch resolved {
            case .fire:
                recolourFireEmitter(color: color)
            case .sparkle, .snow, .dissolve, .rainbow, .blood:
                recolourEmitter(color: color)
            case .shadow:
                recolourShadowEmitter(color: color)
            case .sheen:
                sheenHueOffset = 0  // hue cycles automatically in onStrokeUpdated
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
        case .fire:      setupFireEmitter(color: color)
        case .sparkle:   setupSparkleEmitter(color: color)
        case .glitch:    setupGlitchLayer()
        case .ripple:    break  // triggered per-stroke via onStrokeEnded
        case .rainbow:   setupRainbowEmitter()
        case .snow:      setupSnowEmitter(color: color)
        case .lightning:  break  // triggered per-stroke via onStrokeEnded
        case .dissolve:  setupDissolveEmitter(color: color)
        case .glow:      setupGlowLayer(color: color)
        case .sheen:     setupSheenEmitter(color: color)
        case .shadow:    setupShadowEmitter(color: color)
        case .blood:     setupBloodEmitter(color: color)
        case .none:      break
        }
    }

    // MARK: - Stroke Event Hooks

    /// Call when the pencil begins a new stroke (first touch down).
    func onStrokeBegan(at point: CGPoint) {
        guard activeFX != .none else { return }
        switch activeFX {
        case .fire, .sparkle, .snow, .dissolve, .rainbow, .sheen, .blood:
            emitterLayer.isHidden   = false
            emitterLayer.birthRate  = 1
            updateEmitterPosition(point)
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
        case .shadow:
            shadowEmitterLayer.isHidden  = false
            shadowEmitterLayer.birthRate = 1
            updateShadowEmitterPosition(point)
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
        case .fire, .sparkle, .snow, .dissolve, .blood:
            updateEmitterPosition(point)
            if activeFX == .fire {
                updateFireGlowPosition(point)
            }
        case .shadow:
            updateShadowEmitterPosition(point)
        case .rainbow:
            rainbowHueOffset += 0.02
            if rainbowHueOffset > 1.0 { rainbowHueOffset -= 1.0 }
            recolourEmitter(color: UIColor(hue: rainbowHueOffset, saturation: 0.9, brightness: 1.0, alpha: 0.9))
            updateEmitterPosition(point)
        case .sheen:
            sheenHueOffset += SheenTuning.hueStepPerUpdate
            if sheenHueOffset > 1.0 { sheenHueOffset -= 1.0 }
            recolourSheenEmitter(hue: sheenHueOffset)
            configureSheenGlow(hue: sheenHueOffset)
            // Velocity-responsive birth rate — faster strokes emit more particles.
            if let prev = lastSheenPoint {
                let dx = point.x - prev.x
                let dy = point.y - prev.y
                let speed = sqrt(dx * dx + dy * dy)
                let boost: Float = speed > SheenTuning.velocityBoostThreshold
                    ? SheenTuning.velocityBoostMultiplier : 1.0
                emitterLayer.birthRate = boost
            }
            lastSheenPoint = point
            updateEmitterPosition(point)
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
            emitterLayer.birthRate = 0
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
                // Smooth fade-out of the iridescent glow when the stroke ends.
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
            // Stop emitting; existing puffs/wisps linger naturally until their lifetime expires.
            shadowEmitterLayer.birthRate = 0
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

    // MARK: - Private: Fire (multi-layer physics-driven)

    private func setupFireEmitter(color: UIColor) {
        // Calculate the per-layer budget once so cell fractions correctly sum to ≤ 1×budget.
        let budget = Float(min(tier.maxParticles, FireTuning.maxParticles))
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [
            makeCoreFlameCell(budget: budget),
            makeMidFlameCell(color: color, budget: budget),
            makeFireEmberCell(budget: budget)
        ]
        emitterLayer.birthRate = 0  // enabled on stroke begin
        configureFireGlow(color: color)
    }

    /// Bright yellow-white inner core: the hottest, fastest-rising column.
    private func makeCoreFlameCell(budget: Float) -> CAEmitterCell {
        let physics = ParticlePhysics.fireCorePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = budget * FireTuning.coreBudgetFraction
        cell.lifetime          = 0.28
        cell.lifetimeRange     = 0.12
        cell.velocity          = 95
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity  // strong upward rise
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi / 8          // tight column
        cell.emissionLongitude = -.pi / 2         // straight up
        cell.scale             = 0.040
        cell.scaleRange        = 0.012
        cell.scaleSpeed        = -0.022            // shrinks as it cools
        cell.alphaSpeed        = -3.5              // fades fast — hot core is brief
        cell.spin              = 0.8
        cell.spinRange         = physics.spinRange
        // Pale yellow-white: inner fire colour
        cell.color             = UIColor(red: 1.0, green: 0.96, blue: 0.62, alpha: 0.95).cgColor
        cell.redRange          = 0.04
        cell.greenRange        = 0.06
        cell.contents          = circleCGImage(diameter: 8)
        return cell
    }

    /// Orange mid-flame: main visible body; hue is biased from the user's ink colour.
    private func makeMidFlameCell(color: UIColor, budget: Float) -> CAEmitterCell {
        let physics = ParticlePhysics.firePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = budget * FireTuning.midBudgetFraction
        cell.lifetime          = 0.65
        cell.lifetimeRange     = 0.35
        cell.velocity          = 100
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity  // negative = rise (flames go up)
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi / 4           // wider than core
        cell.emissionLongitude = -.pi / 2
        cell.scale             = 0.14
        cell.scaleRange        = 0.06
        cell.scaleSpeed        = -0.020
        cell.alphaSpeed        = -1.2
        cell.spin              = 0.6
        cell.spinRange         = physics.spinRange
        cell.color             = fireMidFlameColor(from: color).cgColor
        cell.redRange          = 0.16
        cell.greenRange        = 0.18
        cell.contents          = circleCGImage(diameter: 14)
        return cell
    }

    /// Ember sparks: occasional bright orange flecks that scatter and fall.
    private func makeFireEmberCell(budget: Float) -> CAEmitterCell {
        let physics = ParticlePhysics.fireEmberPhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = budget * FireTuning.emberBudgetFraction  // rare
        cell.lifetime          = 0.75
        cell.lifetimeRange     = 0.30
        cell.velocity          = 60
        cell.velocityRange     = CGFloat(physics.turbulence)
        cell.yAcceleration     = physics.gravity  // positive = downward after initial rise
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 0.9        // wide scatter
        cell.emissionLongitude = -.pi / 2
        cell.scale             = 0.018
        cell.scaleRange        = 0.010
        cell.scaleSpeed        = -0.008
        cell.alphaSpeed        = -1.3
        cell.spin              = 2.2
        cell.spinRange         = physics.spinRange
        // Vivid deep-orange ember — independent of user colour
        cell.color             = UIColor(red: 1.0, green: 0.50, blue: 0.04, alpha: 0.95).cgColor
        cell.redRange          = 0.08
        cell.greenRange        = 0.20
        cell.contents          = circleCGImage(diameter: 6)
        return cell
    }

    // MARK: - Private: Sparkle (physics-driven)

    private func setupSparkleEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeSparkleCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeSparkleCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.sparklePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 30)) * 0.6
        cell.lifetime          = 0.60
        cell.lifetimeRange     = 0.30
        cell.velocity          = 80
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2  // omnidirectional
        cell.scale             = 0.08
        cell.scaleRange        = 0.04
        cell.scaleSpeed        = -0.025
        cell.alphaSpeed        = -1.4
        cell.spin              = 1.0
        cell.spinRange         = physics.spinRange
        cell.color             = color.withAlphaComponent(0.95).cgColor
        cell.redRange          = 0.12
        cell.blueRange         = 0.12
        cell.contents          = circleCGImage(diameter: 20)
        return cell
    }

    // MARK: - Private: Rainbow (hue-cycling emitter)

    private func setupRainbowEmitter() {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        emitterLayer.isHidden     = false
        rainbowHueOffset = 0
        emitterLayer.emitterCells = [makeRainbowCell()]
        emitterLayer.birthRate    = 0
    }

    private func makeRainbowCell() -> CAEmitterCell {
        let physics = ParticlePhysics.rainbowPhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 45)) * 0.7
        cell.lifetime          = 0.90
        cell.lifetimeRange     = 0.40
        cell.velocity          = 60
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.09
        cell.scaleRange        = 0.04
        cell.scaleSpeed        = -0.015
        cell.alphaSpeed        = -0.8
        cell.spin              = 0.3
        cell.spinRange         = physics.spinRange
        // Start with red — hue will cycle via recolourEmitter on each update
        cell.color             = UIColor(hue: 0, saturation: 0.9, brightness: 1.0, alpha: 0.85).cgColor
        cell.redRange          = 0.15
        cell.greenRange        = 0.15
        cell.blueRange         = 0.15
        cell.contents          = circleCGImage(diameter: 22)
        return cell
    }

    // MARK: - Private: Snow (physics-driven falling particles)

    private func setupSnowEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 35, height: 8)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeSnowCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeSnowCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.snowPhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 35)) * 0.5
        cell.lifetime          = 1.8
        cell.lifetimeRange     = 0.7
        cell.velocity          = 28
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity  // gentle descent
        cell.xAcceleration     = physics.wind               // sideways drift
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.06
        cell.scaleRange        = 0.04
        cell.scaleSpeed        = -0.006
        cell.alphaSpeed        = -0.45
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
        cell.contents          = snowflakeCGImage(diameter: 24)
        return cell
    }

    // MARK: - Private: Dissolve (chaotic disintegration particles)

    private func setupDissolveEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 14, height: 14)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeDissolveCell(color: color)]
        emitterLayer.birthRate    = 0
    }

    private func makeDissolveCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.dissolvePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 55)) * 0.7
        cell.lifetime          = 0.80
        cell.lifetimeRange     = 0.40
        cell.velocity          = 85
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity  // crumble downward
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.06
        cell.scaleRange        = 0.035
        cell.scaleSpeed        = -0.040   // shrink as they disintegrate
        cell.alphaSpeed        = -1.0
        cell.spin              = 1.5
        cell.spinRange         = physics.spinRange
        cell.color             = color.withAlphaComponent(0.80).cgColor
        cell.redRange          = 0.10
        cell.greenRange        = 0.10
        cell.contents          = squareCGImage(size: 14)
        return cell
    }

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

    private func recolourEmitter(color: UIColor) {
        guard let cell = emitterLayer.emitterCells?.first else { return }
        cell.color = color.cgColor
        emitterLayer.emitterCells = [cell]
    }

    /// Updates only the mid-flame cell colour on fire ink-colour change,
    /// preserving the fixed core (yellow-white) and ember (deep orange) colours.
    private func recolourFireEmitter(color: UIColor) {
        guard var cells = emitterLayer.emitterCells, cells.count >= 3 else { return }
        // Cell index 1 = mid flame (the only cell that uses user colour)
        cells[1].color = fireMidFlameColor(from: color).cgColor
        emitterLayer.emitterCells = cells
        configureFireGlow(color: color)
    }

    /// Derives the mid-flame particle colour: user hue strongly biased toward fire orange-red.
    private func fireMidFlameColor(from color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return UIColor(
            red:   min(1.0, r * 0.35 + 0.72),
            green: min(1.0, g * 0.25 + 0.22),
            blue:  max(0.0, b * 0.08),
            alpha: 0.90
        )
    }

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
        emitterLayer.birthRate    = 0
        emitterLayer.emitterCells = []
        emitterLayer.isHidden     = true

        shadowEmitterLayer.birthRate    = 0
        shadowEmitterLayer.emitterCells = []
        shadowEmitterLayer.isHidden     = true

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

        sheenGlowLayer.removeAllAnimations()
        sheenGlowLayer.isHidden = true
        sheenGlowLayer.opacity  = 1

        rippleLayers.forEach { $0.removeFromSuperlayer() }
        rippleLayers.removeAll()

        lightningLayers.forEach { $0.removeFromSuperlayer() }
        lightningLayers.removeAll()

        rainbowHueOffset = 0
        sheenHueOffset   = 0
        lastSheenPoint   = nil
    }

    // MARK: - Private: Sheen (holographic iridescent shimmer)

    private func setupSheenEmitter(color: UIColor) {
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 10, height: 10)
        emitterLayer.isHidden     = false
        sheenHueOffset   = 0
        lastSheenPoint   = nil
        emitterLayer.emitterCells = [
            makeSheenCoreCell(color: color),
            makeSheenFlareCell(color: color),
            makeSheenDustCell(),
        ]
        emitterLayer.birthRate = 0
        configureSheenGlow(hue: sheenHueOffset)
    }

    /// Core cell: fast-spinning diamonds that cluster tightly around the nib
    /// for a dense glittering nucleus.
    private func makeSheenCoreCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.sheenCorePhysics
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, SheenTuning.maxCoreParticles)) * SheenTuning.coreBirthFraction
        cell.lifetime          = 0.90
        cell.lifetimeRange     = 0.35
        cell.velocity          = 85
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2  // omnidirectional shimmer
        cell.scale             = 0.11
        cell.scaleRange        = 0.05
        cell.scaleSpeed        = -0.025
        cell.alphaSpeed        = -0.85
        cell.spin              = 2.5
        cell.spinRange         = physics.spinRange
        cell.color             = color.cgColor
        cell.redRange          = 0.60
        cell.greenRange        = 0.60
        cell.blueRange         = 0.60
        cell.contents          = diamondCGImage(size: 24)
        return cell
    }

    /// Flare cell: medium elongated streaks that add directional prismatic shimmer
    /// between the tight core and the broad dust halo.
    private func makeSheenFlareCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.sheenFlarePhysics
        let flareColor = UIColor(hue: SheenTuning.flareHuePhaseOffset,
                                 saturation: 0.90, brightness: 1.0, alpha: 0.80)
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, SheenTuning.maxFlareParticles)) * SheenTuning.flareBirthFraction
        cell.lifetime          = 0.65
        cell.lifetimeRange     = 0.20
        cell.velocity          = 55
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.07
        cell.scaleRange        = 0.03
        cell.scaleSpeed        = -0.030
        cell.alphaSpeed        = -1.1
        cell.spin              = 3.5
        cell.spinRange         = physics.spinRange
        cell.color             = flareColor.cgColor
        cell.redRange          = 0.50
        cell.greenRange        = 0.50
        cell.blueRange         = 0.50
        cell.contents          = diamondCGImage(size: 16)
        return cell
    }

    /// Dust cell: large, slow soft circles that fan out into a broad iridescent halo.
    private func makeSheenDustCell() -> CAEmitterCell {
        let physics = ParticlePhysics.sheenDustPhysics
        // Initialise at the dust-phase-offset hue so it immediately contrasts with core.
        let dustColor = UIColor(hue: SheenTuning.dustHuePhaseOffset,
                                saturation: 0.75, brightness: 1.0, alpha: 0.55)
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, SheenTuning.maxDustParticles)) * SheenTuning.dustBirthFraction
        cell.lifetime          = 0.95
        cell.lifetimeRange     = 0.30
        cell.velocity          = 38
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.045
        cell.scaleRange        = 0.020
        cell.scaleSpeed        = -0.012
        cell.alphaSpeed        = -0.90
        cell.spin              = 1.2
        cell.spinRange         = physics.spinRange
        cell.color             = dustColor.cgColor
        cell.redRange          = 0.50
        cell.greenRange        = 0.50
        cell.blueRange         = 0.50
        cell.contents          = circleCGImage(diameter: 14)
        return cell
    }

    /// Updates all three sheen cells to the current hue cycle, maintaining phase offsets
    /// between core, flare, and dust layers for a rich split-hue iridescent look.
    private func recolourSheenEmitter(hue: CGFloat) {
        guard var cells = emitterLayer.emitterCells, cells.count >= 3 else { return }
        cells[0].color = UIColor(hue: hue,
                                 saturation: 1.0, brightness: 1.0, alpha: 0.90).cgColor
        let flareHue   = fmod(hue + SheenTuning.flareHuePhaseOffset, 1.0)
        cells[1].color = UIColor(hue: flareHue,
                                 saturation: 0.90, brightness: 1.0, alpha: 0.80).cgColor
        let dustHue    = fmod(hue + SheenTuning.dustHuePhaseOffset, 1.0)
        cells[2].color = UIColor(hue: dustHue,
                                 saturation: 0.75, brightness: 1.0, alpha: 0.60).cgColor
        emitterLayer.emitterCells = cells
    }

    /// Recolours the sheen glow layer with a four-stop iridescent gradient derived
    /// from `hue`.  The stops cycle through distinct hues to simulate the
    /// wavelength-dependent colour shift of real holographic material.
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


    // MARK: - Private: Shadow (billowing smoke cloud behind strokes)
    //
    // Design goals:
    //   • Looks like real smoke — large grey puffs that rise and expand, plus fine
    //     erratic wisps that disperse laterally.
    //   • Uses `shadowEmitterLayer` (renderMode .unordered) so semi-transparent grey
    //     particles composite correctly on white paper.  The shared emitterLayer uses
    //     additive blending which makes dark particles invisible on light backgrounds.
    //   • Two-cell system: primary billowing puffs + secondary wispy tendrils.
    //   • Particles survive after pen lifts (birthRate→0) and drift away naturally.

    private func setupShadowEmitter(color: UIColor) {
        shadowEmitterLayer.emitterShape = .point
        shadowEmitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        shadowEmitterLayer.emitterCells = [
            makeShadowPuffCell(color: color),
            makeShadowWispCell(color: color)
        ]
        shadowEmitterLayer.birthRate = 0   // enabled on stroke begin
        shadowEmitterLayer.isHidden  = false
    }


    /// Large, slow, billowing primary smoke puffs.
    private func makeShadowPuffCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.shadowPhysics
        let cell               = CAEmitterCell()
        // Budget: simultaneous particles ≈ birthRate × lifetime.  Reserve 60% of the
        // tier's budget for puffs so the combined total (puffs + wisps) stays ≤ maxParticles.
        //   birthRate = maxParticles × 0.60 / lifetime  →  simultaneous ≈ maxParticles × 0.60
        let puffLifetime: Float = 1.40
        cell.birthRate         = Float(tier.maxParticles) * 0.60 / puffLifetime
        cell.lifetime          = puffLifetime
        cell.lifetimeRange     = 0.45
        cell.velocity          = 18               // slow initial drift
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence) * 0.55
        cell.yAcceleration     = physics.effectiveGravity  // negative = gentle upward float
        cell.xAcceleration     = physics.wind              // lateral spread
        cell.emissionRange     = .pi * 2          // omnidirectional — smoke billows in all directions
        cell.scale             = 0.20             // start as a large, visible puff
        cell.scaleRange        = 0.08
        cell.scaleSpeed        = 0.022            // expands as it rises — realistic smoke expansion
        // Fade rate derived from starting alpha and lifetime:
        //   alphaSpeed = -startAlpha / puffLifetime ≈ -0.40 / 1.40 ≈ −0.286
        //   Rounded to −0.29 so the particle is nearly transparent exactly at lifetime.
        cell.alphaSpeed        = -0.29
        cell.spin              = 0.5
        cell.spinRange         = physics.spinRange

        // Colour: mid-grey with a subtle cool tint and a hint of the user's ink colour.
        // Normal blend mode means these are truly grey on white paper (not invisible).
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let pr = 0.30 + r * 0.12
        let pg = 0.30 + g * 0.12
        let pb = 0.34 + b * 0.10   // slight cool/blue tint — classic smoke hue
        cell.color    = UIColor(red: pr, green: pg, blue: pb, alpha: 0.40).cgColor
        cell.contents = smokeCloudCGImage(diameter: 36)
        return cell
    }

    /// Small, fast, erratic secondary wisps that give smoke its tendrilly character.
    private func makeShadowWispCell(color: UIColor) -> CAEmitterCell {
        let physics = ParticlePhysics.shadowWispPhysics
        let cell               = CAEmitterCell()
        // Reserve the remaining 40% of the tier budget for wisps.
        //   birthRate = maxParticles × 0.40 / lifetime  →  simultaneous ≈ maxParticles × 0.40
        // Combined with puffs (60%) the total simultaneous count ≈ maxParticles × 1.0.
        let wispLifetime: Float = 0.75
        cell.birthRate         = Float(tier.maxParticles) * 0.40 / wispLifetime
        cell.lifetime          = wispLifetime
        cell.lifetimeRange     = 0.30
        cell.velocity          = 30               // faster initial burst
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi * 2
        cell.scale             = 0.07
        cell.scaleRange        = 0.03
        cell.scaleSpeed        = 0.018            // wisps also expand slightly
        // Fade rate: -startAlpha / wispLifetime ≈ -0.25 / 0.75 ≈ −0.333 → −0.34
        cell.alphaSpeed        = -0.34
        cell.spin              = 1.0
        cell.spinRange         = physics.spinRange

        // Slightly lighter than the main puffs so they feel like wispy tendrils.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let wr = 0.42 + r * 0.10
        let wg = 0.42 + g * 0.10
        let wb = 0.46 + b * 0.08
        cell.color    = UIColor(red: wr, green: wg, blue: wb, alpha: 0.25).cgColor
        cell.contents = smokeCloudCGImage(diameter: 16)
        return cell
    }

    private func updateShadowEmitterPosition(_ point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowEmitterLayer.emitterPosition = point
        CATransaction.commit()
    }

    /// Recolours both shadow cells in-place without disrupting birth rates.
    private func recolourShadowEmitter(color: UIColor) {
        guard var cells = shadowEmitterLayer.emitterCells, cells.count >= 2 else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let pr = 0.30 + r * 0.12
        let pg = 0.30 + g * 0.12
        let pb = 0.34 + b * 0.10
        cells[0].color = UIColor(red: pr, green: pg, blue: pb, alpha: 0.40).cgColor
        let wr = 0.42 + r * 0.10
        let wg = 0.42 + g * 0.10
        let wb = 0.46 + b * 0.08
        cells[1].color = UIColor(red: wr, green: wg, blue: wb, alpha: 0.25).cgColor
        shadowEmitterLayer.emitterCells = cells
    }

    // MARK: - Private: Blood (viscous crimson drips)

    private func setupBloodEmitter(color: UIColor) {
        let physics = ParticlePhysics.bloodPhysics
        emitterLayer.emitterShape = .point
        emitterLayer.emitterSize  = CGSize(width: 8, height: 8)
        emitterLayer.isHidden     = false
        emitterLayer.emitterCells = [makeBloodCell(physics: physics)]
        emitterLayer.birthRate    = 0
    }

    private func makeBloodCell(physics: ParticlePhysics) -> CAEmitterCell {
        let cell               = CAEmitterCell()
        cell.birthRate         = Float(min(tier.maxParticles, 45)) * 0.5
        cell.lifetime          = 1.0
        cell.lifetimeRange     = 0.35
        cell.velocity          = 45
        cell.velocityRange     = CGFloat(physics.effectiveTurbulence)
        cell.yAcceleration     = physics.effectiveGravity   // heavy downward pull
        cell.xAcceleration     = physics.wind
        cell.emissionRange     = .pi / 6            // mostly downward splatter
        cell.emissionLongitude = .pi / 2            // emitting downward
        cell.scale             = 0.12
        cell.scaleRange        = 0.06
        cell.scaleSpeed        = -0.015
        cell.alphaSpeed        = -0.8
        cell.spin              = 0
        cell.spinRange         = physics.spinRange
        // Deep crimson — not user-customisable for maximum horror effect
        cell.color      = UIColor(red: 0.55, green: 0.02, blue: 0.02, alpha: 0.92).cgColor
        cell.redRange   = 0.15
        cell.contents   = dropCGImage(size: 22)
        return cell
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

    /// Soft-edged smoke cloud bitmap: white at the centre fading to transparent at the
    /// perimeter.  This feathered gradient makes overlapping puffs blend smoothly,
    /// giving the emitter system a volumetric, cloud-like appearance.
    private func smokeCloudCGImage(diameter: CGFloat) -> CGImage? {
        let size   = CGSize(width: diameter, height: diameter)
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let radius = diameter / 2
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx       = ctx.cgContext
            let colorSpace  = CGColorSpaceCreateDeviceRGB()
            // Radial gradient: opaque white at the centre → fully transparent at the edge.
            // When CAEmitterCell tints this white image with cell.color, the soft edge
            // blends naturally with neighbouring particles and the page background.
            let colors: [CGFloat] = [
                1.0, 1.0, 1.0, 0.90,   // centre: near-opaque white
                1.0, 1.0, 1.0, 0.40,   // mid-point: partial opacity for soft shoulder
                1.0, 1.0, 1.0, 0.00    // edge: fully transparent
            ]
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            if let gradient = CGGradient(
                colorSpace: colorSpace,
                colorComponents: colors,
                locations: locations,
                count: 3
            ) {
                cgCtx.drawRadialGradient(
                    gradient,
                    startCenter: center, startRadius: 0,
                    endCenter:   center, endRadius:   radius,
                    options:     []
                )
            }
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

    /// Diamond (rotated square) bitmap for the sheen effect — gives an iridescent sparkle shape.
    private func diamondCGImage(size: CGFloat) -> CGImage? {
        let sz = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: sz)
        return renderer.image { ctx in
            let cx = size / 2, cy = size / 2, r = size / 2 - 0.5
            let path = UIBezierPath()
            path.move(to:    CGPoint(x: cx,     y: cy - r))  // top
            path.addLine(to: CGPoint(x: cx + r, y: cy))       // right
            path.addLine(to: CGPoint(x: cx,     y: cy + r))  // bottom
            path.addLine(to: CGPoint(x: cx - r, y: cy))       // left
            path.close()
            UIColor.white.setFill()
            path.fill()
        }.cgImage
    }

    /// Teardrop bitmap for the blood effect — simulates a heavy falling drop.
    private func dropCGImage(size: CGFloat) -> CGImage? {
        let sz = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: sz)
        return renderer.image { _ in
            let cx = size / 2
            let path = UIBezierPath()
            // Round bottom half — arc from right (angle 0) counterclockwise to left (angle π)
            path.addArc(
                withCenter: CGPoint(x: cx, y: size * 0.65),
                radius: size * 0.32,
                startAngle: 0,
                endAngle: .pi,
                clockwise: false
            )
            // Pointed tip: quad curve from the arc's end point (left) up to a peak and back to the right
            path.addQuadCurve(to: CGPoint(x: cx + size * 0.32, y: size * 0.65),
                              controlPoint: CGPoint(x: cx, y: 0))
            path.close()
            UIColor.white.setFill()
            path.fill()
        }.cgImage
    }
}
