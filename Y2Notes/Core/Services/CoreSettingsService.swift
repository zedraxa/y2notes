import Combine
import Foundation

// MARK: - CoreSettingsService

/// Framework-agnostic `SettingsProvider` implementation using `CurrentValueSubject`.
///
/// Persists all settings to UserDefaults. No SwiftUI dependency — SwiftUI
/// views consume this through `ObservableSettingsStore`.
final class CoreSettingsService: SettingsProvider {

    // MARK: - Subjects

    private let _settingsDidChange = PassthroughSubject<Void, Never>()

    // MARK: - SettingsProvider — reactive

    var settingsDidChange: AnyPublisher<Void, Never> {
        _settingsDidChange.eraseToAnyPublisher()
    }

    // MARK: - SettingsProvider — properties

    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
            _settingsDidChange.send()
        }
    }

    var defaultPageType: PageType {
        didSet {
            UserDefaults.standard.set(defaultPageType.rawValue, forKey: Keys.defaultPageType)
            _settingsDidChange.send()
        }
    }

    var defaultPageSize: PageSize {
        didSet {
            UserDefaults.standard.set(defaultPageSize.rawValue, forKey: Keys.defaultPageSize)
            _settingsDidChange.send()
        }
    }

    var defaultOrientation: PageOrientation {
        didSet {
            UserDefaults.standard.set(defaultOrientation.rawValue, forKey: Keys.defaultOrientation)
            _settingsDidChange.send()
        }
    }

    var defaultPaperMaterial: PaperMaterial {
        didSet {
            UserDefaults.standard.set(defaultPaperMaterial.rawValue, forKey: Keys.defaultPaperMaterial)
            _settingsDidChange.send()
        }
    }

    var reduceMotion: Bool {
        didSet {
            UserDefaults.standard.set(reduceMotion, forKey: Keys.reduceMotion)
            _settingsDidChange.send()
        }
    }

    var highContrastMode: Bool {
        didSet {
            UserDefaults.standard.set(highContrastMode, forKey: Keys.highContrastMode)
            _settingsDidChange.send()
        }
    }

    var pencilOnlyDrawing: Bool {
        didSet {
            UserDefaults.standard.set(pencilOnlyDrawing, forKey: Keys.pencilOnlyDrawing)
            _settingsDidChange.send()
        }
    }

    /// Autosave interval in seconds (clamped to 10–300).
    var autosaveInterval: Double = 30 {
        didSet {
            // Note: didSet does NOT re-fire when assigning to self in Swift.
            // This is safe and avoids recursion.
            autosaveInterval = min(max(autosaveInterval, 10), 300)
            UserDefaults.standard.set(autosaveInterval, forKey: Keys.autosaveInterval)
            _settingsDidChange.send()
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard

        hasCompletedOnboarding = ud.bool(forKey: Keys.hasCompletedOnboarding)

        if let raw = ud.string(forKey: Keys.defaultPageType), let v = PageType(rawValue: raw) {
            defaultPageType = v
        } else { defaultPageType = .blank }

        if let raw = ud.string(forKey: Keys.defaultPageSize), let v = PageSize(rawValue: raw) {
            defaultPageSize = v
        } else { defaultPageSize = .letter }

        if let raw = ud.string(forKey: Keys.defaultOrientation), let v = PageOrientation(rawValue: raw) {
            defaultOrientation = v
        } else { defaultOrientation = .portrait }

        if let raw = ud.string(forKey: Keys.defaultPaperMaterial), let v = PaperMaterial(rawValue: raw) {
            defaultPaperMaterial = v
        } else { defaultPaperMaterial = .standard }

        reduceMotion = ud.bool(forKey: Keys.reduceMotion)
        highContrastMode = ud.bool(forKey: Keys.highContrastMode)
        pencilOnlyDrawing = ud.bool(forKey: Keys.pencilOnlyDrawing)

        let savedInterval = ud.double(forKey: Keys.autosaveInterval)
        autosaveInterval = savedInterval >= 10 ? savedInterval : 30
    }

    // MARK: - Actions

    func resetToDefaults() {
        defaultPageType = .blank
        defaultPageSize = .letter
        defaultOrientation = .portrait
        defaultPaperMaterial = .standard
        reduceMotion = false
        highContrastMode = false
        pencilOnlyDrawing = false
        autosaveInterval = 30
    }

    // MARK: - Keys

    private enum Keys {
        static let hasCompletedOnboarding = "y2notes.hasCompletedOnboarding"
        static let defaultPageType        = "y2notes.defaultPageType"
        static let defaultPageSize        = "y2notes.defaultPageSize"
        static let defaultOrientation     = "y2notes.defaultOrientation"
        static let defaultPaperMaterial   = "y2notes.defaultPaperMaterial"
        static let reduceMotion           = "y2notes.reduceMotion"
        static let highContrastMode       = "y2notes.highContrastMode"
        static let pencilOnlyDrawing      = "y2notes.pencilOnlyDrawing"
        static let autosaveInterval       = "y2notes.autosaveInterval"
    }
}
