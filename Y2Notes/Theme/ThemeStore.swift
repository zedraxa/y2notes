import SwiftUI

// MARK: - ThemeStore

/// Manages the active Y2Notes theme and persists the user's choice across launches.
///
/// Inject into the SwiftUI environment via `.environmentObject(themeStore)` at the app root,
/// then read with `@EnvironmentObject var themeStore: ThemeStore` in any view.
final class ThemeStore: ObservableObject {

    @Published private(set) var selectedTheme: AppTheme

    // MARK: - Auto-Scheduling

    /// When true the store automatically switches between `dayTheme` and `nightTheme` based
    /// on time-of-day. Manual selection is still possible; it temporarily overrides until the
    /// next schedule tick.
    @Published var autoScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(autoScheduleEnabled, forKey: Keys.autoSchedule); evaluateSchedule() }
    }
    @Published var dayTheme: AppTheme {
        didSet { UserDefaults.standard.set(dayTheme.rawValue, forKey: Keys.dayTheme); evaluateSchedule() }
    }
    @Published var nightTheme: AppTheme {
        didSet { UserDefaults.standard.set(nightTheme.rawValue, forKey: Keys.nightTheme); evaluateSchedule() }
    }
    /// Hour (0-23) when the day theme activates. Default 7 (7:00 AM).
    @Published var dayStartHour: Int {
        didSet { UserDefaults.standard.set(dayStartHour, forKey: Keys.dayStartHour); evaluateSchedule() }
    }
    /// Hour (0-23) when the night theme activates. Default 20 (8:00 PM).
    @Published var nightStartHour: Int {
        didSet { UserDefaults.standard.set(nightStartHour, forKey: Keys.nightStartHour); evaluateSchedule() }
    }

    /// The currently resolved theme to display. When scheduling is off this equals
    /// `selectedTheme`; when on it equals the time-appropriate theme.
    var effectiveTheme: AppTheme {
        guard autoScheduleEnabled else { return selectedTheme }
        return isDaytime ? dayTheme : nightTheme
    }

    /// Convenience — the full colour definition for the effective theme.
    var definition: ThemeDefinition {
        effectiveTheme.definition
    }

    // MARK: - Private

    private enum Keys {
        static let selectedTheme = "y2notes.selectedTheme"
        static let autoSchedule  = "y2notes.themeAutoSchedule"
        static let dayTheme      = "y2notes.themeDayTheme"
        static let nightTheme    = "y2notes.themeNightTheme"
        static let dayStartHour  = "y2notes.themeDayStartHour"
        static let nightStartHour = "y2notes.themeNightStartHour"
    }

    private var scheduleTimer: Timer?

    // MARK: - Init

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.selectedTheme) ?? ""
        selectedTheme = AppTheme(rawValue: raw) ?? .system

        autoScheduleEnabled = UserDefaults.standard.bool(forKey: Keys.autoSchedule)
        dayTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.dayTheme) ?? "") ?? .light
        nightTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.nightTheme) ?? "") ?? .dark
        dayStartHour = {
            let stored = UserDefaults.standard.integer(forKey: Keys.dayStartHour)
            return stored == 0 && !UserDefaults.standard.bool(forKey: Keys.autoSchedule) ? 7 : stored
        }()
        nightStartHour = {
            let stored = UserDefaults.standard.integer(forKey: Keys.nightStartHour)
            return stored == 0 && !UserDefaults.standard.bool(forKey: Keys.autoSchedule) ? 20 : stored
        }()

        startScheduleTimer()
    }

    deinit {
        scheduleTimer?.invalidate()
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

    /// Advance to the next theme in the `AppTheme.allCases` cycle.
    func cycleToNext() {
        let all = AppTheme.allCases
        guard let index = all.firstIndex(of: selectedTheme) else { return }
        let next = all[(index + 1) % all.count]
        select(next)
    }

    // MARK: - Schedule Helpers

    /// True when the current hour falls within the daytime range.
    var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if dayStartHour < nightStartHour {
            return hour >= dayStartHour && hour < nightStartHour
        } else {
            // Wraps midnight, e.g. day=6 night=2
            return hour >= dayStartHour || hour < nightStartHour
        }
    }

    /// Re-evaluates the schedule and publishes a change if the effective theme shifted.
    func evaluateSchedule() {
        guard autoScheduleEnabled else { return }
        // Trigger a publish so views depending on `effectiveTheme` refresh.
        objectWillChange.send()
    }

    // MARK: - Private

    private func apply(_ theme: AppTheme) {
        selectedTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Keys.selectedTheme)
    }

    /// Fires once per minute to re-evaluate the schedule at hour boundaries.
    private func startScheduleTimer() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.autoScheduleEnabled else { return }
            DispatchQueue.main.async { self.evaluateSchedule() }
        }
    }
}
