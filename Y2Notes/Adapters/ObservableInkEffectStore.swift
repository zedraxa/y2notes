import Combine
import SwiftUI

// MARK: - ObservableInkEffectStore

/// Thin SwiftUI adapter that bridges `InkEffectProvider` → `ObservableObject`.
///
/// Mirrors the provider's Combine publishers as `@Published` properties so
/// SwiftUI views can observe ink preset changes through `@EnvironmentObject`.
final class ObservableInkEffectStore: ObservableObject {

    @Published private(set) var activePreset: InkPreset?
    @Published var fxEnabled: Bool = true
    @Published private(set) var userPresets: [InkPreset] = []

    let provider: InkEffectProvider
    private var cancellables = Set<AnyCancellable>()

    init(provider: InkEffectProvider) {
        self.provider = provider

        provider.activePresetPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$activePreset)

        provider.fxEnabledPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$fxEnabled)

        provider.userPresetsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$userPresets)
    }

    // MARK: - Forwarded computed properties

    var deviceTier: DeviceCapabilityTier { provider.deviceTier }
    var isEffectsSupported: Bool { provider.isEffectsSupported }
    var resolvedFX: WritingFXType { provider.resolvedFX }
    var allPresets: [InkPreset] { provider.allPresets }
    var presetsByFamily: [(family: InkFamily, presets: [InkPreset])] { provider.presetsByFamily }

    // MARK: - Forwarded actions

    func selectPreset(_ preset: InkPreset?) { provider.selectPreset(preset) }
    func clearPreset() { provider.clearPreset() }
    func deleteUserPreset(id: UUID) { provider.deleteUserPreset(id: id) }
    func toggleFavorite(id: UUID) { provider.toggleFavorite(id: id) }
    func presetsForTheme(_ theme: AppTheme) -> [InkPreset] { provider.presetsForTheme(theme) }
}
