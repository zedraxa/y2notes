import Foundation
import UIKit

/// Observable store that manages the active `InkPreset` and writing-FX selection.
///
/// **Device compatibility**
/// `deviceTier` is detected once at init from `DeviceCapabilityTier.current` and
/// is read-only for the lifetime of the store.  Any FX that the device cannot
/// support will be silently downgraded to `.none` by `InkEffectEngine.configure`.
///
/// **Theme hook** — `presetsForTheme(_:)` returns theme-curated preset suggestions.
/// Future agents can consume this to auto-switch ink packs when the user changes
/// the app theme.  The hook is intentionally simple so it can be expanded without
/// touching the store's core state management.
///
/// **Base writing path** — when `activePreset` is `nil` (the default) the ink
/// system is entirely transparent: `DrawingToolStore` drives the PKCanvasView tool
/// exactly as before, and no `InkEffectEngine` overlay is rendered.
final class InkEffectStore: ObservableObject {

    // MARK: - Device capability (immutable after init)

    /// The detected device capability tier.  Read-only; never changes at runtime.
    let deviceTier: DeviceCapabilityTier = .current

    /// Whether the device supports *any* overlay FX at all.
    var isEffectsSupported: Bool { deviceTier.supportsAnyFX }

    // MARK: - Published state

    /// The currently active premium ink preset.  `nil` means no premium ink is
    /// selected — base `DrawingToolStore` behaviour is used unchanged.
    @Published var activePreset: InkPreset? {
        didSet { persistActivePresetID() }
    }

    /// Master on/off switch for overlay FX.  Persisted to UserDefaults.
    @Published var fxEnabled: Bool = true {
        didSet { UserDefaults.standard.set(fxEnabled, forKey: Keys.fxEnabled) }
    }

    /// User-created presets (built-ins live in `InkFamilyRegistry`).
    @Published var userPresets: [InkPreset] = [] {
        didSet { persistUserPresets() }
    }

    // MARK: - Computed

    /// The resolved FX that should actually be rendered — `.none` when FX is
    /// disabled, the device can't support it, or no preset is active.
    var resolvedFX: WritingFXType {
        guard fxEnabled, isEffectsSupported, let preset = activePreset else { return .none }
        let fx = preset.writingFX
        return fx.isSupported(on: deviceTier) ? fx : .none
    }

    /// All available presets: built-in (from registry) followed by user-created.
    var allPresets: [InkPreset] {
        InkFamilyRegistry.shared.allBuiltIn + userPresets
    }

    /// Presets grouped by family for picker display.
    var presetsByFamily: [(family: InkFamily, presets: [InkPreset])] {
        InkFamily.allCases.compactMap { family in
            let group = allPresets.filter { $0.family == family }
            return group.isEmpty ? nil : (family, group)
        }
    }

    // MARK: - Init

    init() {
        fxEnabled = UserDefaults.standard.object(forKey: Keys.fxEnabled) as? Bool ?? true
        loadUserPresets()
        restoreActivePreset()
    }

    // MARK: - Preset selection

    /// Selects a preset (or `nil` to return to the plain tool system).
    func selectPreset(_ preset: InkPreset?) {
        activePreset = preset
    }

    /// Clears the active preset so the base drawing tool takes effect.
    func clearPreset() {
        activePreset = nil
    }

    // MARK: - User preset management

    /// Saves a new custom preset to the user collection.
    func saveUserPreset(
        name: String,
        family: InkFamily,
        traits: InkMaterialTraits,
        fx: WritingFXType,
        color: UIColor,
        width: Double
    ) {
        let preset = InkPreset(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? family.displayName : name,
            family: family,
            traits: traits,
            writingFX: fx,
            color: color,
            baseWidth: width,
            isFavorite: false,
            isBuiltIn: false
        )
        userPresets.append(preset)
    }

    /// Permanently removes a user-created preset (built-in presets are ignored).
    func deleteUserPreset(id: UUID) {
        userPresets.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    /// Toggles the favourite star on a user preset.
    func toggleFavorite(id: UUID) {
        if let idx = userPresets.firstIndex(where: { $0.id == id }) {
            userPresets[idx].isFavorite.toggle()
        }
    }

    // MARK: - Theme hook

    /// Returns built-in preset suggestions that pair well with the given theme.
    ///
    /// Future agents can extend this to include theme-specific ink packs loaded
    /// from a bundle or remote resource.
    func presetsForTheme(_ theme: AppTheme) -> [InkPreset] {
        let builtIn = InkFamilyRegistry.shared.allBuiltIn
        switch theme {
        case .system, .light:
            return builtIn.filter { $0.family == .standard || $0.family == .metallic }
        case .sepia:
            return builtIn.filter { $0.family == .standard || $0.family == .watercolor }
        case .dark:
            return builtIn.filter { $0.family == .neon || $0.family == .metallic }
        case .midnight:
            return builtIn.filter { $0.family == .glitch || $0.family == .phantom || $0.family == .neon }
        case .ocean:
            return builtIn.filter { $0.family == .watercolor || $0.family == .neon }
        case .rose, .lavender:
            return builtIn.filter { $0.family == .watercolor || $0.family == .standard }
        case .forest:
            return builtIn.filter { $0.family == .standard || $0.family == .watercolor }
        case .slate, .ember:
            return builtIn.filter { $0.family == .standard || $0.family == .metallic }
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let fxEnabled         = "y2notes.ink.fxEnabled"
        static let userPresets       = "y2notes.ink.userPresets"
        static let activePresetID    = "y2notes.ink.activePresetID"
    }

    private func persistUserPresets() {
        guard let data = try? JSONEncoder().encode(userPresets) else { return }
        UserDefaults.standard.set(data, forKey: Keys.userPresets)
    }

    private func loadUserPresets() {
        guard let data = UserDefaults.standard.data(forKey: Keys.userPresets),
              let loaded = try? JSONDecoder().decode([InkPreset].self, from: data)
        else { return }
        userPresets = loaded
    }

    private func persistActivePresetID() {
        UserDefaults.standard.set(activePreset?.id.uuidString, forKey: Keys.activePresetID)
    }

    private func restoreActivePreset() {
        guard let idString = UserDefaults.standard.string(forKey: Keys.activePresetID),
              let id = UUID(uuidString: idString)
        else { return }
        activePreset = allPresets.first { $0.id == id }
    }
}
