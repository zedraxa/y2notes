import Combine
import SwiftUI

// MARK: - ObservableThemeStore

/// Thin SwiftUI adapter that bridges `ThemeProvider` → `ObservableObject`.
///
/// Mirrors the provider's `CurrentValueSubject` state as `@Published`
/// properties so SwiftUI views can observe theme changes through
/// `@EnvironmentObject`.
@MainActor
final class ObservableThemeStore: ObservableObject {

    @Published private(set) var selectedTheme: AppTheme = .system
    @Published private(set) var effectiveTheme: AppTheme = .system

    let provider: ThemeProvider
    private var cancellables = Set<AnyCancellable>()

    init(provider: ThemeProvider) {
        self.provider = provider

        provider.selectedThemePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedTheme)

        provider.effectiveThemePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$effectiveTheme)
    }

    // MARK: - Forwarded properties

    var definition: ThemeDefinition { provider.definition }

    var autoScheduleEnabled: Bool {
        get { provider.autoScheduleEnabled }
        set { provider.autoScheduleEnabled = newValue; objectWillChange.send() }
    }

    var dayTheme: AppTheme {
        get { provider.dayTheme }
        set { provider.dayTheme = newValue; objectWillChange.send() }
    }

    var nightTheme: AppTheme {
        get { provider.nightTheme }
        set { provider.nightTheme = newValue; objectWillChange.send() }
    }

    // MARK: - Forwarded actions

    func select(_ theme: AppTheme) { provider.select(theme) }
    func cycleToNext() { provider.cycleToNext() }
}
