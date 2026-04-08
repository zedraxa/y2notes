import Combine
import SwiftUI

// MARK: - ObservableSettingsStore

/// Thin SwiftUI adapter that bridges `SettingsProvider` → `ObservableObject`.
///
/// Subscribes to the provider's change notification and triggers
/// `objectWillChange` so SwiftUI views refresh when any setting changes.
@MainActor
final class ObservableSettingsStore: ObservableObject {

    let provider: SettingsProvider
    private var cancellables = Set<AnyCancellable>()

    init(provider: SettingsProvider) {
        self.provider = provider

        provider.settingsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Forwarded properties

    var hasCompletedOnboarding: Bool {
        get { provider.hasCompletedOnboarding }
        set { provider.hasCompletedOnboarding = newValue }
    }

    var defaultPageType: PageType {
        get { provider.defaultPageType }
        set { provider.defaultPageType = newValue }
    }

    var defaultPageSize: PageSize {
        get { provider.defaultPageSize }
        set { provider.defaultPageSize = newValue }
    }

    var defaultOrientation: PageOrientation {
        get { provider.defaultOrientation }
        set { provider.defaultOrientation = newValue }
    }

    var defaultPaperMaterial: PaperMaterial {
        get { provider.defaultPaperMaterial }
        set { provider.defaultPaperMaterial = newValue }
    }

    var reduceMotion: Bool {
        get { provider.reduceMotion }
        set { provider.reduceMotion = newValue }
    }

    var highContrastMode: Bool {
        get { provider.highContrastMode }
        set { provider.highContrastMode = newValue }
    }

    var pencilOnlyDrawing: Bool {
        get { provider.pencilOnlyDrawing }
        set { provider.pencilOnlyDrawing = newValue }
    }

    var autosaveInterval: Double {
        get { provider.autosaveInterval }
        set { provider.autosaveInterval = newValue }
    }

    // MARK: - Forwarded actions

    func resetToDefaults() { provider.resetToDefaults() }
}
