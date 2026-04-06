import Combine
import Foundation
import UIKit

// MARK: - InkEffectProvider

/// Framework-agnostic protocol for managing premium ink presets and writing FX.
///
/// The protocol exposes `AnyPublisher` streams for reactive observation and
/// provides synchronous accessors for snapshot reads. Concrete implementations
/// use `CurrentValueSubject` internally — no SwiftUI dependency required.
protocol InkEffectProvider: AnyObject {

    // MARK: - Reactive state

    var activePresetPublisher: AnyPublisher<InkPreset?, Never> { get }
    var fxEnabledPublisher: AnyPublisher<Bool, Never> { get }
    var userPresetsPublisher: AnyPublisher<[InkPreset], Never> { get }

    // MARK: - Current values

    var activePreset: InkPreset? { get }
    var fxEnabled: Bool { get set }
    var userPresets: [InkPreset] { get }
    var deviceTier: DeviceCapabilityTier { get }
    var isEffectsSupported: Bool { get }
    var resolvedFX: WritingFXType { get }
    var allPresets: [InkPreset] { get }
    var presetsByFamily: [(family: InkFamily, presets: [InkPreset])] { get }

    // MARK: - Actions

    func selectPreset(_ preset: InkPreset?)
    func clearPreset()
    func saveUserPreset(
        name: String,
        family: InkFamily,
        traits: InkMaterialTraits,
        fx: WritingFXType,
        color: UIColor,
        width: Double
    )
    func deleteUserPreset(id: UUID)
    func toggleFavorite(id: UUID)
    func presetsForTheme(_ theme: AppTheme) -> [InkPreset]
}
