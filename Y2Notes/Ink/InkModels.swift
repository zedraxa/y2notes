import Foundation
import UIKit
import PencilKit

// MARK: - Device Capability Tier

/// Classifies the iPad's processing capability to set appropriate FX budgets.
///
/// Detection uses `ProcessInfo` memory and processor count as a conservative
/// proxy for GPU generation.  When in doubt the tier is rounded *down* so FX
/// are never forced on devices that cannot sustain them at 60 fps.
///
/// **Graceful degradation contract**
/// - `.basic`    → no overlay FX created at all (zero cost)
/// - `.standard` → sparkle + ripple only (lightweight CAEmitter / CAShape)
/// - `.pro`      → fire + glitch + all standard FX
/// - `.ultra`    → all FX at full particle budget
enum DeviceCapabilityTier: Int, Codable, Comparable {
    case basic    = 0   // A10 / iPad 7th gen and earlier
    case standard = 1   // A12 / iPad 8–9, mini 5
    case pro      = 2   // A14+ / iPad Air 4–5, iPad Pro (A12X–M1)
    case ultra    = 3   // M2+ / iPad Pro 12.9 5th gen and later

    static func < (lhs: DeviceCapabilityTier, rhs: DeviceCapabilityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Detects the tier from available memory and processor count.
    ///
    /// Thresholds are set generously so that fire / glitch / blood effects are
    /// available on all iPads from ~2018 onward (A12+).  Devices with less than
    /// 2 GB RAM (iPad 6th gen / A10) are the only ones held to `.basic`.
    static var current: DeviceCapabilityTier {
        let memory = ProcessInfo.processInfo.physicalMemory
        let cores  = ProcessInfo.processInfo.processorCount
        if memory >= 8_589_934_592 && cores >= 8 { return .ultra    }  // 8 GB+ / 8+ cores  (M2+ iPad Pro)
        if memory >= 3_221_225_472              { return .pro       }  // 3 GB+              (A12+, iPad Air 3+, mini 5+)
        if memory >= 2_147_483_648              { return .standard  }  // 2 GB+              (A10, iPad 7th gen)
        return .basic
    }

    /// Hard cap on simultaneous emitter particles.  The engine clamps birth rates
    /// to this value at runtime so the GPU stays within budget.
    var maxParticles: Int {
        switch self {
        case .basic:    return 0
        case .standard: return 30
        case .pro:      return 50
        case .ultra:    return 80
        }
    }

    /// Fire and glitch require real-time additive blending that older GPUs cannot
    /// sustain without dropping below 60 fps.
    var supportsRealtimeFX: Bool { self >= .pro }

    /// Whether *any* overlay FX should be created (avoids even allocating layers on .basic).
    var supportsAnyFX: Bool { self >= .standard }
}

// MARK: - Ink Family

/// High-level character families.  Each maps to a curated set of built-in
/// `InkPreset` values in `InkFamilyRegistry`.
enum InkFamily: String, CaseIterable, Codable, Identifiable {
    case standard    // everyday pen / pencil writing
    case metallic    // gold, silver, copper — optional shimmer overlay
    case neon        // bright emissive colours — optional sparkle overlay
    case watercolor  // soft, wet, translucent washes
    case fire        // flame-particle trailing effect
    case glitch      // digital artefact / scan-line distortion
    case phantom     // near-invisible ink that is revealed by contrast or tilt
    case sheen       // holographic / iridescent colour-shifting ink
    case shadow      // dark smoky ink with trailing shadow particles
    case blood       // deep crimson ink with dripping horror particles

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:   return "Standard"
        case .metallic:   return "Metallic"
        case .neon:       return "Neon"
        case .watercolor: return "Watercolour"
        case .fire:       return "Fire"
        case .glitch:     return "Glitch"
        case .phantom:    return "Phantom"
        case .sheen:      return "Sheen"
        case .shadow:     return "Shadow"
        case .blood:      return "Blood"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:   return "pencil"
        case .metallic:   return "sparkles"
        case .neon:       return "light.max"
        case .watercolor: return "paintpalette"
        case .fire:       return "flame.fill"
        case .glitch:     return "waveform.path.ecg"
        case .phantom:    return "eye.slash"
        case .sheen:      return "sun.dust.fill"
        case .shadow:     return "smoke.fill"
        case .blood:      return "drop.fill"
        }
    }
}

// MARK: - Ink Material Traits

/// Physical properties that describe how an ink behaves on paper.
///
/// These traits influence:
/// 1. Which `PKInkingTool.InkType` is selected (`isDry` → `.pencil`,
///    high `wetness` → `.fountainPen` on iOS 17+).
/// 2. Which overlay FX are visually appropriate.
/// 3. Future texture-rendering agents can read `granularity` to modulate
///    paper grain simulation.
struct InkMaterialTraits: Codable, Equatable {
    /// Dry inks feel grainy / fibrous (maps to the `.pencil` ink type).
    var isDry: Bool
    /// 0 = bone-dry, 1 = very wet.  High values → fountain-pen variable width.
    var wetness: Double
    /// 0 = matte, 1 = full metallic sheen.  Values > 0.3 suggest a shimmer overlay.
    var sheenAmount: Double
    /// Stroke width variation factor — influences the look of fountain-pen ink.
    var viscosity: Double
    /// Paper texture interaction: 0 = ultra-smooth / 1 = rough.
    /// Reserved for a future texture-renderer agent.
    var granularity: Double

    // MARK: Named presets

    static let standard   = InkMaterialTraits(isDry: false, wetness: 0.2,
                                               sheenAmount: 0.0, viscosity: 0.5, granularity: 0.1)
    static let dry        = InkMaterialTraits(isDry: true,  wetness: 0.0,
                                               sheenAmount: 0.0, viscosity: 0.2, granularity: 0.6)
    static let wet        = InkMaterialTraits(isDry: false, wetness: 0.8,
                                               sheenAmount: 0.0, viscosity: 0.8, granularity: 0.05)
    static let metallic   = InkMaterialTraits(isDry: false, wetness: 0.3,
                                               sheenAmount: 0.9, viscosity: 0.5, granularity: 0.02)
    static let watercolor = InkMaterialTraits(isDry: false, wetness: 0.9,
                                               sheenAmount: 0.0, viscosity: 0.9, granularity: 0.3)
}

// MARK: - Writing FX Type

/// Optional real-time writing effect rendered in a non-interactive overlay above
/// the PKCanvasView.
///
/// **`.none` has zero runtime cost** — no overlay view or CALayer is created when
/// the active FX is `.none`.  This means the base note-taking path is completely
/// unaffected by the FX system.
enum WritingFXType: String, CaseIterable, Codable, Identifiable {
    case none      // no effect; always available on all devices
    case sparkle   // brief bright sparks on stroke (standard+ tier)
    case fire      // flame particles trailing the nib (pro+ tier)
    case glitch    // digital scan-line / colour-shift artefacts (pro+ tier)
    case ripple    // expanding ring at stroke end (standard+ tier)
    case rainbow   // multi-hue trail following the nib (standard+ tier)
    case snow      // falling snowflake particles (standard+ tier)
    case lightning // electric bolt branching from stroke end (pro+ tier)
    case dissolve  // particles crumbling away from the stroke (pro+ tier)
    case glow      // soft luminous aura around the nib (standard+ tier)
    case sheen     // iridescent holographic shimmer following the nib (standard+ tier)
    case shadow    // dark smoke particles trailing behind the stroke (standard+ tier)
    case blood     // viscous dripping crimson particles (pro+ tier)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "None"
        case .sparkle:   return "Sparkle"
        case .fire:      return "Fire"
        case .glitch:    return "Glitch"
        case .ripple:    return "Ripple"
        case .rainbow:   return "Rainbow"
        case .snow:      return "Snow"
        case .lightning: return "Lightning"
        case .dissolve:  return "Dissolve"
        case .glow:      return "Glow"
        case .sheen:     return "Sheen"
        case .shadow:    return "Shadow"
        case .blood:     return "Blood"
        }
    }

    var systemImage: String {
        switch self {
        case .none:      return "slash.circle"
        case .sparkle:   return "sparkles"
        case .fire:      return "flame.fill"
        case .glitch:    return "waveform.path.ecg"
        case .ripple:    return "circle.dashed"
        case .rainbow:   return "rainbow"
        case .snow:      return "snowflake"
        case .lightning: return "bolt.fill"
        case .dissolve:  return "aqi.medium"
        case .glow:      return "light.max"
        case .sheen:     return "sun.dust.fill"
        case .shadow:    return "smoke.fill"
        case .blood:     return "drop.fill"
        }
    }

    /// Minimum device tier required for this effect.
    ///
    /// All emitter-based effects (including fire, glitch, blood) run on `.standard`
    /// and above.  Only `.basic` devices (pre-2018 iPads with < 2 GB RAM) are excluded.
    /// The engine's per-tier `maxParticles` cap ensures older hardware stays at 60 fps.
    var minimumTier: DeviceCapabilityTier {
        switch self {
        case .none:                                   return .basic
        case .sparkle, .ripple, .rainbow,
             .snow, .glow, .sheen, .shadow,
             .fire, .glitch, .lightning,
             .dissolve, .blood:                       return .standard
        }
    }

    func isSupported(on tier: DeviceCapabilityTier) -> Bool {
        tier >= minimumTier
    }
}

// MARK: - Particle Physics

/// Lightweight 2D physics parameters for particle behaviour.
///
/// The `InkEffectEngine` reads these to drive physically-realistic motion.
/// Each field maps directly to a `CAEmitterCell` property or informs the
/// engine's emitter-setup logic.
///
/// **Extended physics model (AGENT-22)**
/// In addition to the original gravity/wind/turbulence/drag model, the
/// struct now carries five additional parameters that deepen the physical
/// simulation without requiring custom per-frame stepping:
///
/// | Parameter | Mapped to | Effect |
/// |-----------|-----------|--------|
/// | `mass` | `gravity × mass` | Heavier particles fall faster |
/// | `attractorStrength` | `CAEmitterLayer.emitterSize` modulation | Inward/outward drift |
/// | `noiseFrequency` | Turbulence seed refresh rate | Organic variation speed |
/// | `noiseAmplitude` | `velocityRange` addend | Strength of organic scatter |
/// | `velocitySpawnSpread` | `emissionRange` addend | Nib speed widens emission cone |
struct ParticlePhysics: Equatable {
    /// Downward acceleration (points/s²).  Positive = pull toward bottom.
    var gravity: CGFloat = 0
    /// Horizontal drift acceleration (points/s²).
    var wind: CGFloat = 0
    /// Random per-frame velocity perturbation range (points/s).
    var turbulence: CGFloat = 0
    /// Velocity multiplier per second (1.0 = no drag, 0.9 = light drag).
    var drag: CGFloat = 1.0
    /// When true, particles bounce off the overlay bounds instead of disappearing.
    var bounceOffBounds: Bool = false
    /// Coefficient of restitution for boundary bounces (0 = sticky, 1 = perfectly elastic).
    var bounciness: CGFloat = 0.5
    /// Angular velocity range (radians/s) applied at birth.
    var spinRange: CGFloat = 0
    /// Whether particles fade out linearly over their lifetime.
    var fadeOut: Bool = true

    // ── Extended physics (AGENT-22) ─────────────────────────────────────

    /// Particle mass — multiplied with `gravity` when configuring
    /// `CAEmitterCell.yAcceleration`.  Heavier particles (> 1.0) feel
    /// weightier; lighter particles (< 1.0) float.  Default 1.0.
    var mass: CGFloat = 1.0

    /// Radial attractor strength toward the emitter point.
    ///
    /// Positive values pull surviving particles back toward the nib,
    /// creating a tighter cluster (useful for glow / sheen).  Negative
    /// values push them outward for explosive scatter (dissolve / blood
    /// splatter).  Implemented as an `emitterSize` scaling factor at
    /// setup time.  Default 0 (no attractor).
    var attractorStrength: CGFloat = 0

    /// Frequency of organic turbulence noise (cycles per second).
    ///
    /// Higher values make the perturbation change rapidly, creating
    /// jittery / electric motion.  Lower values create slow, cloud-like
    /// drift.  Implemented as an additive offset to `velocityRange` that
    /// oscillates over the particle lifetime.  Default 0 (disabled).
    var noiseFrequency: CGFloat = 0

    /// Amplitude of the organic turbulence noise (points).
    ///
    /// Scales the displacement applied by `noiseFrequency`.  Only
    /// effective when `noiseFrequency > 0`.  Default 0.
    var noiseAmplitude: CGFloat = 0

    /// How much writing velocity widens the particle emission cone.
    ///
    /// At zero nib velocity the emission uses its base cone.  As the nib
    /// moves faster (up to `VelocityThicknessParams.velocityCeiling`)
    /// the cone widens by up to this many radians.  Gives fast strokes
    /// a wider, more energetic spray.  Default 0 (no velocity influence).
    var velocitySpawnSpread: CGFloat = 0

    // ── Derived helpers ─────────────────────────────────────────────────

    /// Effective gravity accounting for mass: `gravity × mass`.
    var effectiveGravity: CGFloat { gravity * mass }

    /// Effective turbulence range including noise amplitude.
    /// The engine adds this to `CAEmitterCell.velocityRange`.
    var effectiveTurbulence: CGFloat { turbulence + noiseAmplitude }

    // MARK: Named presets

    /// Mid-flame physics — the main visible orange body of the fire.
    static let firePhysics = ParticlePhysics(
        gravity: -110,        // flames rise (slightly less than core)
        wind: 0,
        turbulence: 50,       // more organic flickering
        drag: 0.90,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.8,
        fadeOut: true,
        mass: 0.6,            // light — flames are buoyant
        attractorStrength: 0.15, // gentle inward pull keeps flames near the nib
        noiseFrequency: 8.0,  // rapid flicker noise
        noiseAmplitude: 12.0, // moderate displacement for realistic flicker
        velocitySpawnSpread: .pi / 6  // fast strokes fan flames outward
    )

    /// Core-flame physics — the bright inner column, hottest and fastest rising.
    static let fireCorePhysics = ParticlePhysics(
        gravity: -190,        // hottest core shoots upward fastest
        wind: 0,
        turbulence: 22,       // tight columnar spread
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.0,
        fadeOut: true
    )

    /// Ember physics — occasional bright sparks that scatter outward then fall.
    /// Embers are launched upward by initial velocity; positive gravity decelerates
    /// them and then pulls them downward — net result: rise then fall trajectory.
    static let fireEmberPhysics = ParticlePhysics(
        gravity: 55,          // embers rise on initial velocity then fall with gravity
        wind: 0,
        turbulence: 70,       // chaotic outward scatter
        drag: 0.80,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 4.5,
        fadeOut: true
    )

    /// Hot core flames — tighter upward cone, faster rise than mid-flame.
    static let fireCorePhysics = ParticlePhysics(
        gravity: -150,        // core rises faster than mid-flame
        wind: 0,
        turbulence: 20,       // tight column, less chaotic
        drag: 0.90,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.5,
        fadeOut: true
    )

    /// Ember sparks — fall after leaving the flame, chaotic scatter.
    static let fireEmberPhysics = ParticlePhysics(
        gravity: 60,          // embers drift downward after launch
        wind: 0,
        turbulence: 80,       // very chaotic — embers scatter randomly
        drag: 0.82,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 5.0,
        fadeOut: true
    )

    static let sparklePhysics = ParticlePhysics(
        gravity: 40,          // sparks fall lightly
        wind: 0,
        turbulence: 60,       // chaotic sparkle spread
        drag: 0.85,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 4.0,
        fadeOut: true,
        mass: 0.4,            // very light — sparks linger before falling
        attractorStrength: -0.3, // outward burst on spawn
        noiseFrequency: 12.0, // rapid jitter gives sparkles their twinkle
        noiseAmplitude: 18.0, // strong displacement for chaotic scatter
        velocitySpawnSpread: .pi / 4  // fast strokes create wide spray
    )

    static let snowPhysics = ParticlePhysics(
        gravity: 25,          // gentle descent
        wind: 8,              // slight sideways drift
        turbulence: 15,       // natural swaying
        drag: 0.97,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.5,
        fadeOut: true,
        mass: 0.3,            // very light — snowflakes float
        attractorStrength: 0,
        noiseFrequency: 2.0,  // slow undulation simulates air currents
        noiseAmplitude: 6.0,  // gentle side-to-side wander
        velocitySpawnSpread: .pi / 8  // slight spread from fast writing
    )

    static let dissolvePhysics = ParticlePhysics(
        gravity: 50,          // crumble downward
        wind: 0,
        turbulence: 45,       // chaotic disintegration
        drag: 0.88,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 3.0,
        fadeOut: true,
        mass: 1.2,            // heavier than average — crumbles, doesn't float
        attractorStrength: -0.5, // explosive outward scatter on disintegrate
        noiseFrequency: 6.0,  // moderate noise for crumbling irregularity
        noiseAmplitude: 10.0,
        velocitySpawnSpread: .pi / 3  // fast strokes scatter widely
    )

    static let rainbowPhysics = ParticlePhysics(
        gravity: 0,
        wind: 0,
        turbulence: 10,
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0.5,
        fadeOut: true,
        mass: 1.0,
        attractorStrength: 0.2,  // gentle inward pull keeps trail tight
        noiseFrequency: 3.0,    // slow organic drift
        noiseAmplitude: 4.0,    // subtle scatter for a paint-like trail
        velocitySpawnSpread: .pi / 10  // minimal spread — trail stays focused
    )

    static let glowPhysics = ParticlePhysics(
        gravity: 0,
        wind: 0,
        turbulence: 5,
        drag: 0.98,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0,
        fadeOut: true,
        mass: 1.0,
        attractorStrength: 0.4,  // strong inward pull — glow hugs the nib
        noiseFrequency: 1.0,    // very slow pulsation
        noiseAmplitude: 2.0,    // barely-visible breathing motion
        velocitySpawnSpread: 0   // no velocity influence — stable aura
    )

    static let sheenPhysics = ParticlePhysics(
        gravity: -10,         // very slight rise for an ethereal look
        wind: 0,
        turbulence: 20,       // gentle scatter for iridescence
        drag: 0.96,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.5,
        fadeOut: true,
        mass: 0.5,            // light — sheen particles drift upward
        attractorStrength: 0.25, // pulled toward nib for tight shimmer
        noiseFrequency: 5.0,  // moderate shimmer oscillation
        noiseAmplitude: 8.0,  // visible but not chaotic
        velocitySpawnSpread: .pi / 6  // moderate spread on fast strokes
    )

    /// Sheen core diamonds — slight rise, moderate scatter.
    static let sheenCorePhysics = ParticlePhysics(
        gravity: -18,         // core particles rise gently
        wind: 0,
        turbulence: 28,       // moderate — focused iridescent shimmer
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 2.0,
        fadeOut: true
    )

    /// Sheen dust circles — gentle fall, more chaotic than core.
    static let sheenDustPhysics = ParticlePhysics(
        gravity: 10,          // dust settles softly downward
        wind: 0,
        turbulence: 50,       // more chaotic — micro-glitter scatter
        drag: 0.90,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 3.0,
        fadeOut: true
    )

    static let shadowPhysics = ParticlePhysics(
        gravity: -22,         // smoke rises gently (negative = upward on screen)
        wind: 10,             // lateral drift for natural dispersion
        turbulence: 50,       // strong billowing / chaotic expansion
        drag: 0.97,           // gentle deceleration — puffs linger and drift
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 2.0,       // organic tumbling rotation
        fadeOut: true,
        mass: 0.8,            // slightly light — smoke is less dense than air
        attractorStrength: -0.2, // outward push for billowing expansion
        noiseFrequency: 3.0,  // slow turbulent billowing
        noiseAmplitude: 15.0, // strong displacement for cloud-like drift
        velocitySpawnSpread: .pi / 5  // fast strokes widen the smoke trail
    )

    /// Fine wisp particles that trail away more erratically than the main puffs.
    static let shadowWispPhysics = ParticlePhysics(
        gravity: -8,          // wisps barely rise — they spread laterally
        wind: 18,             // strong lateral spread for tendrils
        turbulence: 65,       // highly chaotic for wispy, thread-like tendrils
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 3.0,       // fast spin gives tendrils their curling look
        fadeOut: true,
        mass: 0.4,            // very light — wisps are ephemeral
        attractorStrength: -0.4, // strong outward scatter for tendril spread
        noiseFrequency: 7.0,  // rapid perturbation for wispy tendrils
        noiseAmplitude: 20.0, // high displacement for thread-like motion
        velocitySpawnSpread: .pi / 4  // fast writing fans wisps wide
    )

    static let bloodPhysics = ParticlePhysics(
        gravity: 180,         // heavy drops fall fast
        wind: 0,
        turbulence: 20,       // slight splatter
        drag: 0.80,           // high drag so drops slow as they fall
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0.3,
        fadeOut: true,
        mass: 2.5,            // very heavy — blood is viscous and dense
        attractorStrength: -0.6, // explosive splatter away from nib
        noiseFrequency: 4.0,  // moderate wobble as drops fall
        noiseAmplitude: 5.0,  // subtle lateral displacement
        velocitySpawnSpread: .pi / 3  // fast strokes create wide splatter
    )
}

// MARK: - Ink Preset

/// A premium ink configuration: family identity, material traits, writing FX,
/// colour, and stroke width.
///
/// Built-in presets are provided by `InkFamilyRegistry` and have `isBuiltIn == true`
/// (they cannot be deleted).  Users may save unlimited custom presets.
struct InkPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var family: InkFamily
    var traits: InkMaterialTraits
    var writingFX: WritingFXType
    /// RGBA stored as `[Double]` in the 0…1 range — same pattern as `ToolPreset`
    /// so the two models remain consistent and can be merged in a future refactor.
    var colorComponents: [Double]
    var baseWidth: Double
    var isFavorite: Bool
    /// Built-in presets ship with the app and cannot be deleted.
    let isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        family: InkFamily,
        traits: InkMaterialTraits = .standard,
        writingFX: WritingFXType  = .none,
        color: UIColor            = .black,
        baseWidth: Double         = 3.0,
        isFavorite: Bool          = false,
        isBuiltIn: Bool           = false
    ) {
        self.id         = id
        self.name       = name
        self.family     = family
        self.traits     = traits
        self.writingFX  = writingFX
        self.baseWidth  = baseWidth
        self.isFavorite = isFavorite
        self.isBuiltIn  = isBuiltIn

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        colorComponents = [Double(r), Double(g), Double(b), Double(a)]
    }

    var uiColor: UIColor {
        guard colorComponents.count == 4 else { return .black }
        return UIColor(
            red:   CGFloat(colorComponents[0]),
            green: CGFloat(colorComponents[1]),
            blue:  CGFloat(colorComponents[2]),
            alpha: CGFloat(colorComponents[3])
        )
    }

    /// The PencilKit tool derived from this preset's material traits and colour.
    ///
    /// Dry → `.pencil`, high wetness → `.fountainPen` (iOS 17+, pen fallback),
    /// otherwise → `.pen`.  The overlay FX are separate from this tool; they are
    /// rendered by `InkEffectEngine` and never modify the PKCanvasView stroke data.
    var pkTool: PKTool {
        let inkType: PKInkingTool.InkType
        if traits.isDry {
            inkType = .pencil
        } else if traits.wetness > 0.5 {
            if #available(iOS 17, *) { inkType = .fountainPen } else { inkType = .pen }
        } else {
            inkType = .pen
        }
        return PKInkingTool(inkType, color: uiColor, width: baseWidth)
    }
}
