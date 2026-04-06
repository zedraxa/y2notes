import Combine
import Foundation
import UIKit

// MARK: - ThemeProvider

/// Framework-agnostic protocol for theme management.
///
/// Exposes the active theme and auto-scheduling state via Combine publishers.
/// Core implementations use `CurrentValueSubject` internally; SwiftUI adapters
/// bridge to `@Published` / `ObservableObject`.
protocol ThemeProvider: AnyObject {

    // MARK: - Reactive state

    var selectedThemePublisher: AnyPublisher<AppTheme, Never> { get }
    var effectiveThemePublisher: AnyPublisher<AppTheme, Never> { get }

    // MARK: - Current values

    var selectedTheme: AppTheme { get }
    var effectiveTheme: AppTheme { get }
    var definition: ThemeDefinition { get }

    // MARK: - Auto-scheduling

    var autoScheduleEnabled: Bool { get set }
    var dayTheme: AppTheme { get set }
    var nightTheme: AppTheme { get set }
    var dayStartHour: Int { get set }
    var nightStartHour: Int { get set }
    var isDaytime: Bool { get }

    // MARK: - Actions

    func select(_ theme: AppTheme)
    func cycleToNext()
    func evaluateSchedule()
}
