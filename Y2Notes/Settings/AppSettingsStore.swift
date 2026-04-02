import Foundation
import SwiftUI

// MARK: - AppSettingsStore

/// Central settings store for Y2Notes app-wide preferences.
///
/// Every published property is persisted to UserDefaults and has a real effect
/// on the app's behaviour. Injected at the app root as an @EnvironmentObject.
final class AppSettingsStore: ObservableObject {

    // MARK: Onboarding

    /// Whether the first-launch onboarding flow has been completed.
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: Document Defaults

    /// Default page ruling for new notebooks.
    @Published var defaultPageType: PageType {
        didSet { UserDefaults.standard.set(defaultPageType.rawValue, forKey: Keys.defaultPageType) }
    }

    /// Default page size for new notebooks.
    @Published var defaultPageSize: PageSize {
        didSet { UserDefaults.standard.set(defaultPageSize.rawValue, forKey: Keys.defaultPageSize) }
    }

    /// Default page orientation for new notebooks.
    @Published var defaultOrientation: PageOrientation {
        didSet { UserDefaults.standard.set(defaultOrientation.rawValue, forKey: Keys.defaultOrientation) }
    }

    /// Default paper material for new notebooks.
    @Published var defaultPaperMaterial: PaperMaterial {
        didSet { UserDefaults.standard.set(defaultPaperMaterial.rawValue, forKey: Keys.defaultPaperMaterial) }
    }

    // MARK: Accessibility

    /// When true, animations are reduced throughout the app.
    @Published var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: Keys.reduceMotion) }
    }

    /// When true, the app uses higher-contrast colors for UI chrome.
    @Published var highContrastMode: Bool {
        didSet { UserDefaults.standard.set(highContrastMode, forKey: Keys.highContrastMode) }
    }

    // MARK: Pencil

    /// When true, only Apple Pencil input draws on the canvas; finger input pans/zooms.
    @Published var pencilOnlyDrawing: Bool {
        didSet { UserDefaults.standard.set(pencilOnlyDrawing, forKey: Keys.pencilOnlyDrawing) }
    }

    // MARK: Autosave

    /// Autosave interval in seconds. Minimum 10, maximum 300.
    @Published var autosaveInterval: Double {
        didSet {
            let clamped = min(max(autosaveInterval, 10), 300)
            if clamped != autosaveInterval { autosaveInterval = clamped }
            UserDefaults.standard.set(clamped, forKey: Keys.autosaveInterval)
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard

        hasCompletedOnboarding = ud.bool(forKey: Keys.hasCompletedOnboarding)

        if let raw = ud.string(forKey: Keys.defaultPageType), let v = PageType(rawValue: raw) {
            defaultPageType = v
        } else {
            defaultPageType = .blank
        }

        if let raw = ud.string(forKey: Keys.defaultPageSize), let v = PageSize(rawValue: raw) {
            defaultPageSize = v
        } else {
            defaultPageSize = .letter
        }

        if let raw = ud.string(forKey: Keys.defaultOrientation), let v = PageOrientation(rawValue: raw) {
            defaultOrientation = v
        } else {
            defaultOrientation = .portrait
        }

        if let raw = ud.string(forKey: Keys.defaultPaperMaterial), let v = PaperMaterial(rawValue: raw) {
            defaultPaperMaterial = v
        } else {
            defaultPaperMaterial = .standard
        }

        reduceMotion = ud.bool(forKey: Keys.reduceMotion)
        highContrastMode = ud.bool(forKey: Keys.highContrastMode)

        // Sync from the legacy per-editor AppStorage key if it exists
        pencilOnlyDrawing = ud.bool(forKey: Keys.pencilOnlyDrawing)

        let savedInterval = ud.double(forKey: Keys.autosaveInterval)
        autosaveInterval = savedInterval >= 10 ? savedInterval : 30
    }

    // MARK: - Reset

    /// Resets all settings to factory defaults. Does not reset onboarding.
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
