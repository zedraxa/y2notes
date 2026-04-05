import SwiftUI
import UIKit

// MARK: - ThemeCategory

/// Groups themes for display in the picker.
enum ThemeCategory: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark  = "Dark"
    case warm  = "Warm"
    case cool  = "Cool"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .light: return "sun.max"
        case .dark:  return "moon.fill"
        case .warm:  return "flame"
        case .cool:  return "snowflake"
        }
    }
}

// MARK: - AppTheme

/// All built-in Y2Notes themes.
/// The raw value is persisted in UserDefaults; do not rename cases without a migration.
///
/// The enum is intentionally open to future premium additions — add a case, set
/// `isPremium = true`, and the picker disables it automatically until unlocked.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system    = "system"
    case light     = "light"
    case dark      = "dark"
    case sepia     = "sepia"
    case midnight  = "midnight"
    case ocean     = "ocean"
    case rose      = "rose"
    case forest    = "forest"
    case lavender  = "lavender"
    case slate     = "slate"
    case ember     = "ember"
    case paper     = "paper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   return "System"
        case .light:    return "Light"
        case .dark:     return "Dark"
        case .sepia:    return "Sepia"
        case .midnight: return "Midnight"
        case .ocean:    return "Ocean"
        case .rose:     return "Rose"
        case .forest:   return "Forest"
        case .lavender: return "Lavender"
        case .slate:    return "Slate"
        case .ember:    return "Ember"
        case .paper:    return "Paper"
        }
    }

    /// One-line description shown in the theme picker beneath the theme name.
    var description: String {
        switch self {
        case .system:   return "Follows your device's Light or Dark setting"
        case .light:    return "Crisp white canvas for everyday note-taking"
        case .dark:     return "Easy on the eyes in low-light environments"
        case .sepia:    return "Warm parchment tones for long writing sessions"
        case .midnight: return "Deep navy that reduces eye strain at night"
        case .ocean:    return "Cool pale-blue calm for focused study"
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
        case .rose:     return "heart.fill"
        case .forest:   return "leaf.fill"
        case .lavender: return "sparkles"
        case .slate:    return "cube.fill"
        case .ember:    return "flame.fill"
        case .paper:    return "doc.plaintext"
        }
    }

    /// Human-readable one-line description of the theme mood.
    var subtitle: String {
        switch self {
        case .system:   return "Follows your device settings"
        case .light:    return "Bright and clean"
        case .dark:     return "Easy on the eyes at night"
        case .sepia:    return "Warm parchment for long sessions"
        case .midnight: return "Deep navy, low blue light"
        case .ocean:    return "Calm pale blue"
        case .rose:     return "Soft pink, warm and gentle"
        case .forest:   return "Earthy green, grounded focus"
        case .lavender: return "Light purple, creative calm"
        case .slate:    return "Cool neutral gray"
        case .ember:    return "Dark amber glow"
        case .paper:    return "Classic off-white, minimal"
        }
    }

    /// Category the theme belongs to — used for grouping in the picker.
    var category: ThemeCategory {
        switch self {
        case .system, .light, .paper:       return .light
        case .dark, .midnight, .slate:      return .dark
        case .sepia, .rose, .ember:         return .warm
        case .ocean, .forest, .lavender:    return .cool
        }
    }

    /// Reserved for a future premium-tier expansion.
    /// When true the picker shows the theme greyed-out and disables selection.
    var isPremium: Bool { false }

    /// All themes in a specific category.
    static func themes(in category: ThemeCategory) -> [AppTheme] {
        allCases.filter { $0.category == category }
    }

    // MARK: - Definition

    var definition: ThemeDefinition {
        switch self {
        case .system:
            return ThemeDefinition(
                colorScheme: nil,
                canvasBackground: .systemBackground,
                primaryText: .label,
                secondaryText: .secondaryLabel,
                accent: UIColor(named: "AccentColor") ?? .systemBlue,
                toolbarBackground: .secondarySystemBackground,
                surfaceColor: .tertiarySystemBackground,
                separatorColor: .separator,
                selectionTint: (UIColor(named: "AccentColor") ?? .systemBlue).withAlphaComponent(0.18)
            )
        case .light:
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: .white,
                primaryText: .black,
                secondaryText: UIColor(white: 0.40, alpha: 1),
                accent: UIColor(named: "AccentColor") ?? .systemBlue,
                toolbarBackground: UIColor(white: 0.97, alpha: 1),
                surfaceColor: UIColor(white: 0.95, alpha: 1),
                separatorColor: UIColor(white: 0.85, alpha: 1),
                selectionTint: (UIColor(named: "AccentColor") ?? .systemBlue).withAlphaComponent(0.15)
            )
        case .dark:
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(white: 0.12, alpha: 1),
                primaryText: .white,
                secondaryText: UIColor(white: 0.60, alpha: 1),
                accent: UIColor(named: "AccentColor") ?? .systemBlue,
                toolbarBackground: UIColor(white: 0.08, alpha: 1),
                surfaceColor: UIColor(white: 0.16, alpha: 1),
                separatorColor: UIColor(white: 0.24, alpha: 1),
                selectionTint: (UIColor(named: "AccentColor") ?? .systemBlue).withAlphaComponent(0.22)
            )
        case .sepia:
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.961, green: 0.941, blue: 0.906, alpha: 1),
                primaryText: UIColor(red: 0.24, green: 0.18, blue: 0.10, alpha: 1),
                secondaryText: UIColor(red: 0.48, green: 0.38, blue: 0.26, alpha: 1),
                accent: UIColor(red: 0.63, green: 0.38, blue: 0.10, alpha: 1),
                toolbarBackground: UIColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 1),
                surfaceColor: UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1),
                separatorColor: UIColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1),
                selectionTint: UIColor(red: 0.63, green: 0.38, blue: 0.10, alpha: 0.18)
            )
        case .midnight:
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(red: 0.05, green: 0.11, blue: 0.17, alpha: 1),
                primaryText: UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1),
                secondaryText: UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1),
                accent: UIColor(red: 0.37, green: 0.65, blue: 0.99, alpha: 1),
                toolbarBackground: UIColor(red: 0.04, green: 0.08, blue: 0.13, alpha: 1),
                surfaceColor: UIColor(red: 0.07, green: 0.14, blue: 0.21, alpha: 1),
                separatorColor: UIColor(red: 0.14, green: 0.22, blue: 0.30, alpha: 1),
                selectionTint: UIColor(red: 0.37, green: 0.65, blue: 0.99, alpha: 0.20)
            )
        case .ocean:
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.94, green: 0.97, blue: 1.00, alpha: 1),
                primaryText: UIColor(red: 0.05, green: 0.18, blue: 0.32, alpha: 1),
                secondaryText: UIColor(red: 0.25, green: 0.42, blue: 0.60, alpha: 1),
                accent: UIColor(red: 0.07, green: 0.48, blue: 0.75, alpha: 1),
                toolbarBackground: UIColor(red: 0.91, green: 0.95, blue: 0.99, alpha: 1),
                surfaceColor: UIColor(red: 0.92, green: 0.96, blue: 1.00, alpha: 1),
                separatorColor: UIColor(red: 0.78, green: 0.86, blue: 0.94, alpha: 1),
                selectionTint: UIColor(red: 0.07, green: 0.48, blue: 0.75, alpha: 0.16)
            )

        // MARK: New themes

        case .rose:
            // Soft pink — warm and gentle, ideal for creative journaling.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.99, green: 0.95, blue: 0.96, alpha: 1),
                primaryText: UIColor(red: 0.28, green: 0.12, blue: 0.16, alpha: 1),
                secondaryText: UIColor(red: 0.52, green: 0.34, blue: 0.40, alpha: 1),
                accent: UIColor(red: 0.80, green: 0.30, blue: 0.46, alpha: 1),
                toolbarBackground: UIColor(red: 0.97, green: 0.92, blue: 0.93, alpha: 1),
                surfaceColor: UIColor(red: 0.98, green: 0.93, blue: 0.94, alpha: 1),
                separatorColor: UIColor(red: 0.90, green: 0.80, blue: 0.84, alpha: 1),
                selectionTint: UIColor(red: 0.80, green: 0.30, blue: 0.46, alpha: 0.16)
            )
        case .forest:
            // Earthy green — grounded and focused, draws from nature.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.94, green: 0.97, blue: 0.94, alpha: 1),
                primaryText: UIColor(red: 0.10, green: 0.22, blue: 0.12, alpha: 1),
                secondaryText: UIColor(red: 0.30, green: 0.46, blue: 0.32, alpha: 1),
                accent: UIColor(red: 0.18, green: 0.56, blue: 0.28, alpha: 1),
                toolbarBackground: UIColor(red: 0.91, green: 0.95, blue: 0.91, alpha: 1),
                surfaceColor: UIColor(red: 0.92, green: 0.96, blue: 0.93, alpha: 1),
                separatorColor: UIColor(red: 0.78, green: 0.86, blue: 0.78, alpha: 1),
                selectionTint: UIColor(red: 0.18, green: 0.56, blue: 0.28, alpha: 0.16)
            )
        case .lavender:
            // Light purple — creative and calm, soft focus.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.96, green: 0.95, blue: 1.00, alpha: 1),
                primaryText: UIColor(red: 0.18, green: 0.12, blue: 0.30, alpha: 1),
                secondaryText: UIColor(red: 0.40, green: 0.34, blue: 0.55, alpha: 1),
                accent: UIColor(red: 0.50, green: 0.32, blue: 0.80, alpha: 1),
                toolbarBackground: UIColor(red: 0.94, green: 0.92, blue: 0.99, alpha: 1),
                surfaceColor: UIColor(red: 0.95, green: 0.93, blue: 1.00, alpha: 1),
                separatorColor: UIColor(red: 0.84, green: 0.80, blue: 0.92, alpha: 1),
                selectionTint: UIColor(red: 0.50, green: 0.32, blue: 0.80, alpha: 0.16)
            )
        case .slate:
            // Cool neutral gray — minimal, distraction-free dark mode.
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1),
                primaryText: UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1),
                secondaryText: UIColor(red: 0.58, green: 0.60, blue: 0.65, alpha: 1),
                accent: UIColor(red: 0.55, green: 0.62, blue: 0.75, alpha: 1),
                toolbarBackground: UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                surfaceColor: UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1),
                separatorColor: UIColor(red: 0.26, green: 0.28, blue: 0.32, alpha: 1),
                selectionTint: UIColor(red: 0.55, green: 0.62, blue: 0.75, alpha: 0.20)
            )
        case .ember:
            // Dark amber glow — warm dark mode for evening sessions.
            return ThemeDefinition(
                colorScheme: .dark,
                canvasBackground: UIColor(red: 0.14, green: 0.10, blue: 0.07, alpha: 1),
                primaryText: UIColor(red: 0.95, green: 0.88, blue: 0.78, alpha: 1),
                secondaryText: UIColor(red: 0.68, green: 0.58, blue: 0.46, alpha: 1),
                accent: UIColor(red: 0.92, green: 0.55, blue: 0.20, alpha: 1),
                toolbarBackground: UIColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 1),
                surfaceColor: UIColor(red: 0.18, green: 0.13, blue: 0.09, alpha: 1),
                separatorColor: UIColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 1),
                selectionTint: UIColor(red: 0.92, green: 0.55, blue: 0.20, alpha: 0.22)
            )
        case .paper:
            // Classic off-white — minimal and timeless, the feel of real paper.
            return ThemeDefinition(
                colorScheme: .light,
                canvasBackground: UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1),
                primaryText: UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
                secondaryText: UIColor(red: 0.45, green: 0.44, blue: 0.42, alpha: 1),
                accent: UIColor(red: 0.40, green: 0.40, blue: 0.38, alpha: 1),
                toolbarBackground: UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1),
                surfaceColor: UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1),
                separatorColor: UIColor(red: 0.88, green: 0.86, blue: 0.83, alpha: 1),
                selectionTint: UIColor(red: 0.40, green: 0.40, blue: 0.38, alpha: 0.14)
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

    // MARK: Surface & chrome
    /// Background for toolbars, navigation bars, and input areas.
    let toolbarBackground: UIColor
    /// Background for cards, popovers, and grouped surfaces.
    let surfaceColor: UIColor
    /// Divider / separator lines.
    let separatorColor: UIColor
    /// Tint applied to selected items, highlights, and focus rings.
    let selectionTint: UIColor

    // MARK: Derived SwiftUI colours (convenience)
    var primaryTextColor: Color       { Color(uiColor: primaryText) }
    var secondaryTextColor: Color     { Color(uiColor: secondaryText) }
    var accentColor: Color            { Color(uiColor: accent) }
    var canvasBackgroundColor: Color  { Color(uiColor: canvasBackground) }
    var toolbarBackgroundColor: Color { Color(uiColor: toolbarBackground) }
    var surfaceSwiftUIColor: Color    { Color(uiColor: surfaceColor) }
    var separatorSwiftUIColor: Color  { Color(uiColor: separatorColor) }
    var selectionTintColor: Color     { Color(uiColor: selectionTint) }

    // MARK: Contrast protection

    /// Returns true when the canvas background is perceptually dark (< 50 % relative luminance).
    /// Drawing tools should use a light default ink colour when this returns true so that new
    /// strokes are immediately visible against the canvas.
    var canvasIsDark: Bool {
        // Use the custom WCAG-compliant luminance from ColorScience (linear sRGB, not gamma).
        ContrastRatio.relativeLuminance(of: canvasBackground) < 0.5
    }

    /// A safe default ink colour that contrasts with the canvas background (near-white or
    /// near-black). The canvas coordinator applies this when building the initial inking tool.
    var contrastingInkColor: UIColor {
        canvasIsDark
            ? UIColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1)  // light slate
            : UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)  // near-black
    }

    // MARK: Perceptual Color Science (OKLAB)

    /// WCAG 2.1 contrast ratio between the primary text and the surface color.
    /// Computed using hand-implemented sRGB→linear→luminance — no library.
    var primaryTextContrastRatio: Double {
        ContrastRatio.ratio(primaryText, surfaceColor)
    }

    /// Returns true when the primary text meets WCAG AA (≥ 4.5:1) against the surface.
    var meetsContrastAA: Bool {
        ContrastRatio.meetsAA(primaryText, surfaceColor)
    }

    /// Perceptual ΔE distance between the accent and canvas background in OKLAB space.
    /// Values > 0.1 mean the accent is clearly distinguishable from the background.
    var accentCanvasDeltaE: Double {
        ColorDistance.deltaE(accent, canvasBackground)
    }

    /// Complementary accent color, rotated 180° in OKLCH hue space.
    /// Useful for contrast highlights without manually specifying colors per theme.
    var complementaryAccent: UIColor {
        ColorHarmony.complementary(of: accent)
    }

    /// Perceptually interpolated midpoint between the toolbar and surface backgrounds.
    /// Useful for rendering subtle depth layers (cards on sheets, etc.).
    var midSurface: UIColor {
        ColorInterpolation.interpolateOKLab(toolbarBackground, surfaceColor, t: 0.5)
    }
}
