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
    /// Memory thresholds are conservative to avoid overcommitting older hardware.
    static var current: DeviceCapabilityTier {
        let memory = ProcessInfo.processInfo.physicalMemory
        let cores  = ProcessInfo.processInfo.processorCount
        if memory >= 8_589_934_592 && cores >= 8 { return .ultra    }  // 8 GB+ / 8+ cores
        if memory >= 4_294_967_296 && cores >= 6 { return .pro      }  // 4 GB+ / 6+ cores
        if memory >= 3_221_225_472              { return .standard  }  // 3 GB+
        return .basic
    }

    /// Hard cap on simultaneous emitter particles.  Exceeding this budget causes
    /// visible frame drops; the engine clamps to this value at runtime.
    var maxParticles: Int {
        switch self {
        case .basic:    return 0
        case .standard: return 15
        case .pro:      return 40
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
    case none     // no effect; always available on all devices
    case sparkle  // brief bright sparks on stroke (standard+ tier)
    case fire     // flame particles trailing the nib (pro+ tier)
    case glitch   // digital scan-line / colour-shift artefacts (pro+ tier)
    case ripple   // expanding ring at stroke end (standard+ tier)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .sparkle: return "Sparkle"
        case .fire:    return "Fire"
        case .glitch:  return "Glitch"
        case .ripple:  return "Ripple"
        }
    }

    var systemImage: String {
        switch self {
        case .none:    return "slash.circle"
        case .sparkle: return "sparkles"
        case .fire:    return "flame.fill"
        case .glitch:  return "waveform.path.ecg"
        case .ripple:  return "circle.dashed"
        }
    }

    /// Minimum device tier required for this effect.
    var minimumTier: DeviceCapabilityTier {
        switch self {
        case .none:              return .basic
        case .sparkle, .ripple:  return .standard
        case .fire, .glitch:     return .pro
        }
    }

    func isSupported(on tier: DeviceCapabilityTier) -> Bool {
        tier >= minimumTier
    }
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
