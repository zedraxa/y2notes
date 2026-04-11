import Foundation
import UIKit

/// Simplified store that manages the active writing FX (fire or sparkle).
///
/// With only two effects available, this store is now minimal and focused
/// on basic FX selection and persistence.
@MainActor
final class InkEffectStore: ObservableObject {

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
    /// disabled or no preset is active.
    var resolvedFX: WritingFXType {
        guard fxEnabled, let preset = activePreset else { return .none }
        return preset.writingFX
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
    func presetsForTheme(_ theme: AppTheme) -> [InkPreset] {
        // Simplified: just return all built-in presets
        return InkFamilyRegistry.shared.allBuiltIn
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
