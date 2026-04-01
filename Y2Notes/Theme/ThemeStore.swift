import SwiftUI

// MARK: - ThemeStore

/// Manages the active Y2Notes theme and persists the user's choice across launches.
///
/// Inject into the SwiftUI environment via `.environmentObject(themeStore)` at the app root,
/// then read with `@EnvironmentObject var themeStore: ThemeStore` in any view.
final class ThemeStore: ObservableObject {

    @Published private(set) var selectedTheme: AppTheme

    private let defaultsKey = "y2notes.selectedTheme"

    init() {
        let raw = UserDefaults.standard.string(forKey: "y2notes.selectedTheme") ?? ""
        selectedTheme = AppTheme(rawValue: raw) ?? .system
    }

    // MARK: - Convenience

    /// The full colour and style definition for the currently selected theme.
    var definition: ThemeDefinition {
        selectedTheme.definition
    }

    // MARK: - Selection

    /// Persist and apply a new theme. Safe to call from any thread (dispatches to main if needed).
    func select(_ theme: AppTheme) {
        if Thread.isMainThread {
            apply(theme)
        } else {
            DispatchQueue.main.async { [weak self] in self?.apply(theme) }
        }
    }

    private func apply(_ theme: AppTheme) {
        selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
    }
}
