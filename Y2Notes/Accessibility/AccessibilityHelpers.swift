import UIKit
import SwiftUI

// MARK: - WCAG Contrast Utilities

/// Utilities for validating colour contrast ratios according to WCAG 2.1 guidelines.
///
/// Usage:
/// ```swift
/// let ratio = ContrastChecker.contrastRatio(between: foreground, and: background)
/// let passes = ContrastChecker.meetsAA(foreground: fg, background: bg, isLargeText: false)
/// ```
enum ContrastChecker {

    /// Computes the WCAG 2.1 contrast ratio between two colours.
    /// Returns a value in [1, 21]. Higher is more contrasting.
    static func contrastRatio(between c1: UIColor, and c2: UIColor) -> Double {
        let l1 = relativeLuminance(of: c1)
        let l2 = relativeLuminance(of: c2)
        let lighter = max(l1, l2)
        let darker  = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Returns true when the foreground/background pair meets WCAG 2.1 AA.
    /// - Normal text: contrast ratio ≥ 4.5:1.
    /// - Large text (≥ 18 pt or 14 pt bold): contrast ratio ≥ 3:1.
    static func meetsAA(foreground: UIColor, background: UIColor, isLargeText: Bool = false) -> Bool {
        let ratio = contrastRatio(between: foreground, and: background)
        return ratio >= (isLargeText ? 3.0 : 4.5)
    }

    /// Returns true when the foreground/background pair meets WCAG 2.1 AAA.
    /// - Normal text: contrast ratio ≥ 7:1.
    /// - Large text: contrast ratio ≥ 4.5:1.
    static func meetsAAA(foreground: UIColor, background: UIColor, isLargeText: Bool = false) -> Bool {
        let ratio = contrastRatio(between: foreground, and: background)
        return ratio >= (isLargeText ? 4.5 : 7.0)
    }

    /// Relative luminance per WCAG 2.1 (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).
    static func relativeLuminance(of color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        func linearise(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.04045
                ? c / 12.92
                : pow((c + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)
    }
}

// MARK: - ThemeDefinition Contrast Validation

extension ThemeDefinition {

    /// Contrast ratio of primary text against canvas background.
    var primaryTextContrastRatio: Double {
        ContrastChecker.contrastRatio(between: primaryText, and: canvasBackground)
    }

    /// Contrast ratio of secondary text against canvas background.
    var secondaryTextContrastRatio: Double {
        ContrastChecker.contrastRatio(between: secondaryText, and: canvasBackground)
    }

    /// Contrast ratio of accent colour against canvas background.
    var accentContrastRatio: Double {
        ContrastChecker.contrastRatio(between: accent, and: canvasBackground)
    }

    /// Returns true when all text colours meet WCAG 2.1 AA against the canvas.
    var meetsWCAGAA: Bool {
        ContrastChecker.meetsAA(foreground: primaryText, background: canvasBackground)
            && ContrastChecker.meetsAA(foreground: secondaryText, background: canvasBackground, isLargeText: true)
            && ContrastChecker.meetsAA(foreground: accent, background: canvasBackground, isLargeText: true)
    }
}

// MARK: - View Modifiers

/// Applies reduced-motion preference, suppressing animations when the user has enabled
/// the system Reduce Motion setting or the app's own reduce-motion toggle.
struct ReduceMotionModifier: ViewModifier {
    @EnvironmentObject var settingsStore: AppSettingsStore

    func body(content: Content) -> some View {
        if settingsStore.reduceMotion {
            content.transaction { $0.animation = nil }
        } else {
            content
        }
    }
}

extension View {
    /// Strips animations when the app's reduce-motion setting is active.
    func respectsReduceMotion() -> some View {
        modifier(ReduceMotionModifier())
    }
}

// MARK: - High Contrast Modifier

/// Applies heavier font weight and increased contrast when the app's
/// high-contrast setting is active. Uses `legibilityWeight` environment
/// which is the SwiftUI-sanctioned way to signal bold text preference.
struct HighContrastModifier: ViewModifier {
    @EnvironmentObject var settingsStore: AppSettingsStore

    func body(content: Content) -> some View {
        content
            .environment(\.legibilityWeight, settingsStore.highContrastMode ? .bold : .regular)
    }
}

extension View {
    /// Applies the app's high-contrast preference to the view hierarchy.
    func respectsHighContrast() -> some View {
        modifier(HighContrastModifier())
    }
}
