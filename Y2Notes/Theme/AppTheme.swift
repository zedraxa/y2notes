import SwiftUI

// MARK: - AppTheme

/// All built-in Y2Notes themes.
/// The raw value is persisted in UserDefaults; do not rename cases without a migration.
///
/// The enum is intentionally open to future premium additions — add a case, set
/// `isPremium = true`, and the picker disables it automatically until unlocked.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system   = "system"
    case light    = "light"
    case dark     = "dark"
    case sepia    = "sepia"
    case midnight = "midnight"
    case ocean    = "ocean"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   return "System"
        case .light:    return "Light"
        case .dark:     return "Dark"
        case .sepia:    return "Sepia"
        case .midnight: return "Midnight"
        case .ocean:    return "Ocean"
        }
    }

    var systemImage: String {
        switch self {
        case .system:   return "iphone"
        case .light:    return "sun.max"
        case .dark:     return "moon.fill"
        case .sepia:    return "book.closed"
        case .midnight: return "moon.stars.fill"
        case .ocean:    return "water.waves"
        }
    }

    /// Reserved for a future premium-tier expansion.
    /// When true the picker shows the theme greyed-out and disables selection.
    var isPremium: Bool { false }

    var definition: ThemeDefinition {
        switch self {
        case .system:
            return ThemeDefinition(
                colorScheme: nil,
                canvasBackground: .systemBackground,
                primaryText: .label,
                secondaryText: .secondaryLabel,
                accent: UIColor(named: "AccentColor") ?? .systemBlue
            )
        case .light:
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: .white,
                primaryText: .black,
                secondaryText: UIColor(white: 0.40, alpha: 1),
                accent: UIColor(named: "AccentColor") ?? .systemBlue
            )
        case .dark:
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(white: 0.12, alpha: 1),
                primaryText: .white,
                secondaryText: UIColor(white: 0.60, alpha: 1),
                accent: UIColor(named: "AccentColor") ?? .systemBlue
            )
        case .sepia:
            // Warm parchment — comfortable for long reading and writing sessions.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.961, green: 0.941, blue: 0.906, alpha: 1),
                primaryText: UIColor(red: 0.24, green: 0.18, blue: 0.10, alpha: 1),
                secondaryText: UIColor(red: 0.48, green: 0.38, blue: 0.26, alpha: 1),
                accent: UIColor(red: 0.63, green: 0.38, blue: 0.10, alpha: 1)
            )
        case .midnight:
            // Deep navy — reduces eye strain in dark environments.
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(red: 0.05, green: 0.11, blue: 0.17, alpha: 1),
                primaryText: UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1),
                secondaryText: UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1),
                accent: UIColor(red: 0.37, green: 0.65, blue: 0.99, alpha: 1)
            )
        case .ocean:
            // Pale blue — calm and focused without full dark mode.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.94, green: 0.97, blue: 1.00, alpha: 1),
                primaryText: UIColor(red: 0.05, green: 0.18, blue: 0.32, alpha: 1),
                secondaryText: UIColor(red: 0.25, green: 0.42, blue: 0.60, alpha: 1),
                accent: UIColor(red: 0.07, green: 0.48, blue: 0.75, alpha: 1)
            )
        }
    }
}

// MARK: - ThemeDefinition

/// All colours a theme exposes for UI components and the PencilKit drawing canvas.
struct ThemeDefinition {
    /// Preferred SwiftUI color scheme, or nil to follow the system setting.
    let colorScheme: ColorScheme?

    // MARK: Canvas
    /// Background colour applied to PKCanvasView.
    let canvasBackground: UIColor

    // MARK: UI chrome
    let primaryText: UIColor
    let secondaryText: UIColor
    let accent: UIColor

    // MARK: Derived SwiftUI colours (convenience)
    var primaryTextColor: Color   { Color(uiColor: primaryText) }
    var secondaryTextColor: Color { Color(uiColor: secondaryText) }
    var accentColor: Color        { Color(uiColor: accent) }
    var canvasBackgroundColor: Color { Color(uiColor: canvasBackground) }

    // MARK: Contrast protection

    /// Returns true when the canvas background is perceptually dark (< 50 % relative luminance).
    /// Drawing tools should use a light default ink colour when this returns true so that new
    /// strokes are immediately visible against the canvas.
    var canvasIsDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        canvasBackground.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Relative luminance (WCAG 2.1 formula).
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.5
    }

    /// A safe default ink colour that contrasts with the canvas background (near-white or
    /// near-black). The canvas coordinator applies this when building the initial inking tool.
    var contrastingInkColor: UIColor {
        canvasIsDark
            ? UIColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1)  // light slate
            : UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)  // near-black
    }
}
