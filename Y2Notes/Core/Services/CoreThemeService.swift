import Combine
import Foundation
import UIKit

// MARK: - CoreThemeService

/// Framework-agnostic `ThemeProvider` implementation using `CurrentValueSubject`.
///
/// Manages the active theme, auto-scheduling, and persistence to UserDefaults.
/// No SwiftUI dependency — SwiftUI views consume this through `ObservableThemeStore`.
final class CoreThemeService: ThemeProvider {

    // MARK: - Subjects

    private let _selectedTheme: CurrentValueSubject<AppTheme, Never>
    private let _effectiveTheme: CurrentValueSubject<AppTheme, Never>
    private let _autoScheduleEnabled: CurrentValueSubject<Bool, Never>
    private let _dayTheme: CurrentValueSubject<AppTheme, Never>
    private let _nightTheme: CurrentValueSubject<AppTheme, Never>
    private let _dayStartHour: CurrentValueSubject<Int, Never>
    private let _nightStartHour: CurrentValueSubject<Int, Never>

    private var scheduleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - ThemeProvider — publishers

    var selectedThemePublisher: AnyPublisher<AppTheme, Never> {
        _selectedTheme.eraseToAnyPublisher()
    }

    var effectiveThemePublisher: AnyPublisher<AppTheme, Never> {
        _effectiveTheme.eraseToAnyPublisher()
    }

    // MARK: - ThemeProvider — current values

    var selectedTheme: AppTheme { _selectedTheme.value }

    var effectiveTheme: AppTheme { _effectiveTheme.value }

    var definition: ThemeDefinition { effectiveTheme.definition }

    var autoScheduleEnabled: Bool {
        get { _autoScheduleEnabled.value }
        set {
            _autoScheduleEnabled.value = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.autoSchedule)
            reevaluate()
        }
    }

    var dayTheme: AppTheme {
        get { _dayTheme.value }
        set {
            _dayTheme.value = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.dayTheme)
            reevaluate()
        }
    }

    var nightTheme: AppTheme {
        get { _nightTheme.value }
        set {
            _nightTheme.value = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.nightTheme)
            reevaluate()
        }
    }

    var dayStartHour: Int {
        get { _dayStartHour.value }
        set {
            _dayStartHour.value = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.dayStartHour)
            reevaluate()
        }
    }

    var nightStartHour: Int {
        get { _nightStartHour.value }
        set {
            _nightStartHour.value = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.nightStartHour)
            reevaluate()
        }
    }

    var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if dayStartHour < nightStartHour {
            return hour >= dayStartHour && hour < nightStartHour
        } else {
            return hour >= dayStartHour || hour < nightStartHour
        }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        let raw = ud.string(forKey: Keys.selectedTheme) ?? ""
        let theme = AppTheme(rawValue: raw) ?? .system

        _selectedTheme = CurrentValueSubject(theme)
        _autoScheduleEnabled = CurrentValueSubject(ud.bool(forKey: Keys.autoSchedule))
        _dayTheme = CurrentValueSubject(
            AppTheme(rawValue: ud.string(forKey: Keys.dayTheme) ?? "") ?? .light
        )
        _nightTheme = CurrentValueSubject(
            AppTheme(rawValue: ud.string(forKey: Keys.nightTheme) ?? "") ?? .dark
        )

        let dayH: Int = {
            let stored = ud.integer(forKey: Keys.dayStartHour)
            return stored == 0 && !ud.bool(forKey: Keys.autoSchedule) ? 7 : stored
        }()
        let nightH: Int = {
            let stored = ud.integer(forKey: Keys.nightStartHour)
            return stored == 0 && !ud.bool(forKey: Keys.autoSchedule) ? 20 : stored
        }()

        _dayStartHour = CurrentValueSubject(dayH)
        _nightStartHour = CurrentValueSubject(nightH)
        _effectiveTheme = CurrentValueSubject(theme)

        // Derive effective theme whenever inputs change.
        reevaluate()
        startScheduleTimer()
    }

    deinit {
        scheduleTimer?.invalidate()
    }

    // MARK: - Actions

    func select(_ theme: AppTheme) {
        let apply = {
            self._selectedTheme.value = theme
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.selectedTheme)
            self.reevaluate()
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.async(execute: apply) }
    }

    func cycleToNext() {
        let all = AppTheme.allCases
        guard let index = all.firstIndex(of: selectedTheme) else { return }
        let next = all[(index + 1) % all.count]
        select(next)
    }

    func evaluateSchedule() {
        reevaluate()
    }

    // MARK: - Private

    private func reevaluate() {
        if _autoScheduleEnabled.value {
            _effectiveTheme.value = isDaytime ? _dayTheme.value : _nightTheme.value
        } else {
            _effectiveTheme.value = _selectedTheme.value
        }
    }

    private func startScheduleTimer() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self._autoScheduleEnabled.value else { return }
            DispatchQueue.main.async { self.reevaluate() }
        }
    }

    private enum Keys {
        static let selectedTheme = "y2notes.selectedTheme"
        static let autoSchedule  = "y2notes.themeAutoSchedule"
        static let dayTheme      = "y2notes.themeDayTheme"
        static let nightTheme    = "y2notes.themeNightTheme"
        static let dayStartHour  = "y2notes.themeDayStartHour"
        static let nightStartHour = "y2notes.themeNightStartHour"
    }
}
