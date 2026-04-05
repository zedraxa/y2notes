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
/// The `InkEffectEngine` reads these to drive physically-realistic motion.
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

    // MARK: Extended physics fields

    /// Particle mass (1.0 = neutral).  Values > 1 amplify gravity and resist
    /// acceleration; values < 1 make particles buoyant and highly responsive.
    var mass: CGFloat = 1.0

    /// Centripetal pull strength toward the emitter origin (points/s²).
    /// Positive values create a swirl-inward orbit; 0 = no attractor.
    var attractorStrength: CGFloat = 0

    /// Frequency of a Perlin-like noise layer added on top of base turbulence
    /// (cycles per second).  0 = no noise modulation.
    var noiseFrequency: CGFloat = 0

    /// Peak amplitude of the noise displacement (points).  Combined with
    /// `noiseFrequency` to produce organic, non-repeating particle jitter.
    var noiseAmplitude: CGFloat = 0

    /// Scale factor applied to each particle's initial velocity at spawn.
    /// Values > 1 widen the spawn cone; values < 1 narrow it.
    var velocitySpawnSpread: CGFloat = 1.0

    // MARK: Computed physics helpers

    /// Effective downward acceleration after applying `mass` and an optional
    /// external multiplier (e.g. from `EffectIntensity.durationMultiplier`).
    func effectiveGravity(multiplier: CGFloat = 1.0) -> CGFloat {
        gravity * multiplier * mass
    }

    /// Effective turbulence strength, blending base `turbulence` with the
    /// noise layer (`noiseAmplitude × noiseFrequency`) and an optional scale.
    func effectiveTurbulence(scale: CGFloat = 1.0) -> CGFloat {
        (turbulence + noiseAmplitude * noiseFrequency) * scale
    }

    // MARK: Named presets

    static let firePhysics = ParticlePhysics(
        gravity: -120,        // flames rise
        wind: 0,
        turbulence: 35,       // flickering
        drag: 0.92,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 2.0,
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
        fadeOut: true
    )

    static let snowPhysics = ParticlePhysics(
        gravity: 25,          // gentle descent
        wind: 8,              // slight sideways drift
        turbulence: 15,       // natural swaying
        drag: 0.97,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.5,
        fadeOut: true
    )

    static let dissolvePhysics = ParticlePhysics(
        gravity: 50,          // crumble downward
        wind: 0,
        turbulence: 45,       // chaotic disintegration
        drag: 0.88,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 3.0,
        fadeOut: true
    )

    static let rainbowPhysics = ParticlePhysics(
        gravity: 0,
        wind: 0,
        turbulence: 10,
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0.5,
        fadeOut: true
    )

    static let glowPhysics = ParticlePhysics(
        gravity: 0,
        wind: 0,
        turbulence: 5,
        drag: 0.98,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0,
        fadeOut: true
    )

    static let sheenPhysics = ParticlePhysics(
        gravity: -10,         // very slight rise for an ethereal look
        wind: 0,
        turbulence: 20,       // gentle scatter for iridescence
        drag: 0.96,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.5,
        fadeOut: true
    )

    static let shadowPhysics = ParticlePhysics(
        gravity: 15,          // smoke sinks slowly
        wind: 5,              // slight horizontal drift
        turbulence: 25,       // wispy billowing
        drag: 0.94,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0.8,
        fadeOut: true
    )

    static let bloodPhysics = ParticlePhysics(
        gravity: 180,         // heavy drops fall fast
        wind: 0,
        turbulence: 20,       // slight splatter
        drag: 0.80,           // high drag so drops slow as they fall
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 0.3,
        fadeOut: true
    )

    // MARK: Distinct per-layer presets

    /// Core flame layer — high-velocity rising particles with noise modulation.
    static let fireCorePhysics = ParticlePhysics(
        gravity: -140,        // flames rise strongly
        wind: 0,
        turbulence: 30,       // natural flicker
        drag: 0.91,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.8,
        fadeOut: true,
        mass: 0.8,            // lighter → gravity amplified less, rises faster
        attractorStrength: 0,
        noiseFrequency: 2.5,  // rapid noise bursts for flame dancing
        noiseAmplitude: 12,
        velocitySpawnSpread: 1.1
    )

    /// Ember / mid-flame layer — slower, wider spread with gentle oscillation.
    static let fireEmberPhysics = ParticlePhysics(
        gravity: -55,         // embers rise, but slower than core
        wind: 4,              // slight lateral drift
        turbulence: 55,       // wide chaotic scatter
        drag: 0.89,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 3.5,
        fadeOut: true,
        mass: 1.2,            // heavier embers pulled back by gravity sooner
        attractorStrength: 0,
        noiseFrequency: 1.8,
        noiseAmplitude: 18,
        velocitySpawnSpread: 1.4
    )

    /// Sheen core layer — rising diamond particles with rapid hue cycling.
    static let sheenCorePhysics = ParticlePhysics(
        gravity: -18,         // core diamonds float upward
        wind: 0,
        turbulence: 28,       // moderate scatter for sparkle feel
        drag: 0.95,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 2.2,
        fadeOut: true,
        mass: 0.7,
        attractorStrength: 0,
        noiseFrequency: 3.0,  // high-frequency noise for iridescent shimmer
        noiseAmplitude: 8,
        velocitySpawnSpread: 0.9
    )

    /// Sheen dust layer — micro-particles with slightly different physics for
    /// the layered holographic look.  Hue offset by 0.20 in the engine.
    static let sheenDustPhysics = ParticlePhysics(
        gravity: 10,          // dust settles very gently
        wind: 0,
        turbulence: 50,       // high spread for a cloud-of-colour feel
        drag: 0.93,
        bounceOffBounds: false,
        bounciness: 0,
        spinRange: 1.0,
        fadeOut: true,
        mass: 1.3,
        attractorStrength: 0,
        noiseFrequency: 1.5,
        noiseAmplitude: 20,
        velocitySpawnSpread: 1.6
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
