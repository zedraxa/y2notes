import UIKit

/// Registry of built-in `InkPreset` values organised by `InkFamily`.
///
/// These presets ship with the app.  `isBuiltIn` is `true` on all of them,
/// so they cannot be deleted from `InkEffectStore`.
///
/// **Adding a new family**:
/// 1. Add a case to `InkFamily`.
/// 2. Add a private static factory method here following the existing pattern.
/// 3. Insert it into `all` below.
///
/// Future theme-driven FX agents can also extend this registry with
/// theme-specific ink packs via a `ThemeInkPack` protocol.
final class InkFamilyRegistry {

    // MARK: - Singleton

    static let shared = InkFamilyRegistry()
    private init() {}

    // MARK: - Public API

    /// All built-in presets, flat, across all families.
    let allBuiltIn: [InkPreset] = {
        InkFamilyRegistry.standardPresets()
        + InkFamilyRegistry.metallicPresets()
        + InkFamilyRegistry.neonPresets()
        + InkFamilyRegistry.watercolorPresets()
        + InkFamilyRegistry.firePresets()
        + InkFamilyRegistry.glitchPresets()
        + InkFamilyRegistry.phantomPresets()
    }()

    /// Returns built-in presets for a specific family.
    func presets(for family: InkFamily) -> [InkPreset] {
        allBuiltIn.filter { $0.family == family }
    }

    // MARK: - Standard

    private static func standardPresets() -> [InkPreset] {[
        InkPreset(name: "Classic Black",
                  family: .standard, traits: .standard, writingFX: .none,
                  color: .black, baseWidth: 2, isFavorite: true, isBuiltIn: true),
        InkPreset(name: "Fine Pencil",
                  family: .standard, traits: .dry, writingFX: .none,
                  color: .darkGray, baseWidth: 2.5, isBuiltIn: true),
        InkPreset(name: "Fountain",
                  family: .standard, traits: .wet, writingFX: .none,
                  color: UIColor(red: 0.10, green: 0.10, blue: 0.50, alpha: 1),
                  baseWidth: 3, isBuiltIn: true),
    ]}

    // MARK: - Metallic

    private static func metallicPresets() -> [InkPreset] {[
        InkPreset(name: "Gold",
                  family: .metallic, traits: .metallic, writingFX: .sparkle,
                  color: UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1),
                  baseWidth: 3, isBuiltIn: true),
        InkPreset(name: "Silver",
                  family: .metallic, traits: .metallic, writingFX: .sparkle,
                  color: UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
                  baseWidth: 3, isBuiltIn: true),
        InkPreset(name: "Copper",
                  family: .metallic, traits: .metallic, writingFX: .sparkle,
                  color: UIColor(red: 0.72, green: 0.45, blue: 0.20, alpha: 1),
                  baseWidth: 3, isBuiltIn: true),
    ]}

    // MARK: - Neon

    private static func neonPresets() -> [InkPreset] {[
        InkPreset(name: "Neon Green",
                  family: .neon, traits: .standard, writingFX: .sparkle,
                  color: UIColor(red: 0.00, green: 1.00, blue: 0.40, alpha: 1),
                  baseWidth: 2.5, isBuiltIn: true),
        InkPreset(name: "Neon Pink",
                  family: .neon, traits: .standard, writingFX: .sparkle,
                  color: UIColor(red: 1.00, green: 0.08, blue: 0.58, alpha: 1),
                  baseWidth: 2.5, isBuiltIn: true),
        InkPreset(name: "Neon Blue",
                  family: .neon, traits: .standard, writingFX: .sparkle,
                  color: UIColor(red: 0.00, green: 0.50, blue: 1.00, alpha: 1),
                  baseWidth: 2.5, isBuiltIn: true),
    ]}

    // MARK: - Watercolour

    private static func watercolorPresets() -> [InkPreset] {[
        InkPreset(name: "Aqua Wash",
                  family: .watercolor, traits: .watercolor, writingFX: .ripple,
                  color: UIColor(red: 0.20, green: 0.60, blue: 0.80, alpha: 0.70),
                  baseWidth: 4, isBuiltIn: true),
        InkPreset(name: "Rose Blush",
                  family: .watercolor, traits: .watercolor, writingFX: .ripple,
                  color: UIColor(red: 0.90, green: 0.50, blue: 0.55, alpha: 0.70),
                  baseWidth: 4, isBuiltIn: true),
        InkPreset(name: "Moss Green",
                  family: .watercolor, traits: .watercolor, writingFX: .none,
                  color: UIColor(red: 0.40, green: 0.60, blue: 0.30, alpha: 0.70),
                  baseWidth: 4, isBuiltIn: true),
    ]}

    // MARK: - Fire

    private static func firePresets() -> [InkPreset] {[
        InkPreset(name: "Ember",
                  family: .fire, traits: .standard, writingFX: .fire,
                  color: UIColor(red: 1.00, green: 0.35, blue: 0.00, alpha: 1),
                  baseWidth: 2.5, isBuiltIn: true),
        InkPreset(name: "Inferno",
                  family: .fire, traits: .standard, writingFX: .fire,
                  color: UIColor(red: 1.00, green: 0.60, blue: 0.10, alpha: 1),
                  baseWidth: 3, isBuiltIn: true),
        InkPreset(name: "Blue Flame",
                  family: .fire, traits: .standard, writingFX: .fire,
                  color: UIColor(red: 0.20, green: 0.40, blue: 1.00, alpha: 1),
                  baseWidth: 2.5, isBuiltIn: true),
    ]}

    // MARK: - Glitch

    private static func glitchPresets() -> [InkPreset] {[
        InkPreset(name: "Data Corrupt",
                  family: .glitch, traits: .standard, writingFX: .glitch,
                  color: UIColor(red: 0.00, green: 0.90, blue: 0.50, alpha: 1),
                  baseWidth: 2, isBuiltIn: true),
        InkPreset(name: "Vaporwave",
                  family: .glitch, traits: .standard, writingFX: .glitch,
                  color: UIColor(red: 0.80, green: 0.00, blue: 1.00, alpha: 1),
                  baseWidth: 2, isBuiltIn: true),
    ]}

    // MARK: - Phantom

    private static func phantomPresets() -> [InkPreset] {[
        InkPreset(name: "Ghost Ink",
                  family: .phantom, traits: .dry, writingFX: .none,
                  color: UIColor(white: 0.95, alpha: 0.15),
                  baseWidth: 3, isBuiltIn: true),
        InkPreset(name: "UV Reveal",
                  family: .phantom, traits: .dry, writingFX: .sparkle,
                  color: UIColor(red: 0.50, green: 0.00, blue: 1.00, alpha: 0.20),
                  baseWidth: 3, isBuiltIn: true),
    ]}
}
