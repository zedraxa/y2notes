import Combine
import Foundation

// MARK: - SettingsProvider

/// Framework-agnostic protocol for app-wide preferences.
///
/// Settings are persisted to UserDefaults. Concrete implementations expose
/// `CurrentValueSubject` publishers; SwiftUI adapters bridge to `@Published`.
protocol SettingsProvider: AnyObject {

    // MARK: - Reactive state

    /// Publishes a notification whenever any setting changes.
    var settingsDidChange: AnyPublisher<Void, Never> { get }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool { get set }

    // MARK: - Document defaults

    var defaultPageType: PageType { get set }
    var defaultPageSize: PageSize { get set }
    var defaultOrientation: PageOrientation { get set }
    // MARK: - Accessibility

    var reduceMotion: Bool { get set }
    var highContrastMode: Bool { get set }

    // MARK: - Pencil

    var pencilOnlyDrawing: Bool { get set }

    // MARK: - Autosave

    var autosaveInterval: Double { get set }

    // MARK: - Actions

    func resetToDefaults()
}
