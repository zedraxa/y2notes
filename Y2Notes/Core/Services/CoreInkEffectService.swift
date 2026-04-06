import Combine
import Foundation
import UIKit

// MARK: - CoreInkEffectService

/// Framework-agnostic `InkEffectProvider` implementation using `CurrentValueSubject`.
///
/// Manages premium ink presets, FX enabled state, and user presets.
/// No SwiftUI or `ObservableObject` dependency. Persistence uses UserDefaults
/// (same keys as the legacy `InkEffectStore`).
final class CoreInkEffectService: InkEffectProvider {

    // MARK: - Subjects

    private let _activePreset: CurrentValueSubject<InkPreset?, Never>
    private let _fxEnabled: CurrentValueSubject<Bool, Never>
    private let _userPresets: CurrentValueSubject<[InkPreset], Never>

    // MARK: - InkEffectProvider — publishers

    var activePresetPublisher: AnyPublisher<InkPreset?, Never> {
        _activePreset.eraseToAnyPublisher()
    }

    var fxEnabledPublisher: AnyPublisher<Bool, Never> {
        _fxEnabled.eraseToAnyPublisher()
    }

    var userPresetsPublisher: AnyPublisher<[InkPreset], Never> {
        _userPresets.eraseToAnyPublisher()
    }

    // MARK: - InkEffectProvider — current values

    var activePreset: InkPreset? { _activePreset.value }

    var fxEnabled: Bool {
        get { _fxEnabled.value }
        set {
            _fxEnabled.value = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.fxEnabled)
        }
    }

    var userPresets: [InkPreset] { _userPresets.value }

    let deviceTier: DeviceCapabilityTier = .current

    var isEffectsSupported: Bool { deviceTier.supportsAnyFX }

    var resolvedFX: WritingFXType {
        guard fxEnabled, isEffectsSupported, let preset = activePreset else { return .none }
        let fx = preset.writingFX
        return fx.isSupported(on: deviceTier) ? fx : .none
    }

    var allPresets: [InkPreset] {
        InkFamilyRegistry.shared.allBuiltIn + _userPresets.value
    }

    var presetsByFamily: [(family: InkFamily, presets: [InkPreset])] {
        InkFamily.allCases.compactMap { family in
            let group = allPresets.filter { $0.family == family }
            return group.isEmpty ? nil : (family, group)
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        _fxEnabled = CurrentValueSubject(ud.object(forKey: Keys.fxEnabled) as? Bool ?? true)

        // Load user presets
        var loaded: [InkPreset] = []
        if let data = ud.data(forKey: Keys.userPresets),
           let decoded = try? JSONDecoder().decode([InkPreset].self, from: data) {
            loaded = decoded
        }
        _userPresets = CurrentValueSubject(loaded)

        // Restore active preset
        var restored: InkPreset?
        if let idString = ud.string(forKey: Keys.activePresetID),
           let id = UUID(uuidString: idString) {
            let all = InkFamilyRegistry.shared.allBuiltIn + loaded
            restored = all.first { $0.id == id }
        }
        _activePreset = CurrentValueSubject(restored)
    }

    // MARK: - Actions

    func selectPreset(_ preset: InkPreset?) {
        _activePreset.value = preset
        persistActivePresetID()
    }

    func clearPreset() {
        _activePreset.value = nil
        persistActivePresetID()
    }

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
        var current = _userPresets.value
        current.append(preset)
        _userPresets.value = current
        persistUserPresets()
    }

    func deleteUserPreset(id: UUID) {
        var current = _userPresets.value
        current.removeAll { $0.id == id && !$0.isBuiltIn }
        _userPresets.value = current
        persistUserPresets()
    }

    func toggleFavorite(id: UUID) {
        var current = _userPresets.value
        if let idx = current.firstIndex(where: { $0.id == id }) {
            current[idx].isFavorite.toggle()
            _userPresets.value = current
            persistUserPresets()
        }
    }

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
        case .paper:
            return builtIn.filter { $0.family == .standard || $0.family == .watercolor }
        }
    }

    // MARK: - Persistence

    private enum Keys {
        static let fxEnabled      = "y2notes.ink.fxEnabled"
        static let userPresets    = "y2notes.ink.userPresets"
        static let activePresetID = "y2notes.ink.activePresetID"
    }

    private func persistUserPresets() {
        guard let data = try? JSONEncoder().encode(_userPresets.value) else { return }
        UserDefaults.standard.set(data, forKey: Keys.userPresets)
    }

    private func persistActivePresetID() {
        UserDefaults.standard.set(_activePreset.value?.id.uuidString, forKey: Keys.activePresetID)
    }
}
