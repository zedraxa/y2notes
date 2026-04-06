// ColorScience.swift
// Y2Notes
//
// Custom color science engine implementing:
// - sRGB ↔ OKLAB perceptual color space conversion
// - Color harmony generation (complementary, analogous, triadic, etc.)
// - Perceptual color interpolation
// - WCAG 2.1 contrast ratio calculation
// - Accessible color pair generation
//
// All math is hand-implemented — no external color libraries.
//

import UIKit

// MARK: - OKLAB Color Space

/// A color in the OKLAB perceptual color space (Björn Ottosson, 2020).
/// OKLAB is designed so that equal numerical differences correspond to
/// equal perceived differences — unlike sRGB, HSL, or even CIELAB.
///
/// Components:
/// - L: perceptual lightness [0, 1]
/// - a: green–red axis (roughly −0.4 to +0.4)
/// - b: blue–yellow axis (roughly −0.4 to +0.4)
struct OKLab: Equatable {
    var L: Double
    var a: Double
    var b: Double

    /// Chroma (saturation-like): distance from the neutral axis in the a-b plane.
    var chroma: Double {
        (a * a + b * b).squareRoot()
    }

    /// Hue angle in radians [0, 2π).
    var hue: Double {
        var h = atan2(b, a)
        if h < 0 { h += 2.0 * .pi }
        return h
    }

    /// Create from LCH (Lightness, Chroma, Hue in radians).
    static func fromLCH(L: Double, C: Double, h: Double) -> OKLab {
        OKLab(L: L, a: C * cos(h), b: C * sin(h))
    }
}

// MARK: - Conversions

enum ColorConvert {

    // ---- sRGB ↔ Linear RGB ----

    /// sRGB gamma to linear (inverse of the sRGB transfer function).
    static func sRGBToLinear(_ c: Double) -> Double {
        c <= 0.04045
            ? c / 12.92
            : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear to sRGB gamma (sRGB transfer function).
    static func linearToSRGB(_ c: Double) -> Double {
        c <= 0.0031308
            ? c * 12.92
            : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    // ---- sRGB → OKLAB ----

    /// Convert sRGB [0,1] components to OKLAB.
    /// Delegates to SIMD-optimized C kernel (y2_color.c) for the matrix
    /// chain: sRGB → Linear → LMS (M1) → LMS^(1/3) → Lab (M2).
    @inline(__always)
    static func sRGBToOKLab(r: Double, g: Double, b: Double) -> OKLab {
        var L: Double = 0, A: Double = 0, B: Double = 0
        y2_color_srgb_to_oklab(r, g, b, &L, &A, &B)
        return OKLab(L: L, a: A, b: B)
    }

    // ---- OKLAB → sRGB ----

    /// Convert OKLAB to sRGB [0,1] components.
    /// Delegates to SIMD-optimized C kernel (y2_color.c).
    @inline(__always)
    static func oklabToSRGB(_ lab: OKLab) -> (r: Double, g: Double, b: Double) {
        var r: Double = 0, g: Double = 0, b: Double = 0
        y2_color_oklab_to_srgb(lab.L, lab.a, lab.b, &r, &g, &b)
        return (r: r, g: g, b: b)
    }

    // ---- UIColor conversions ----

    /// Convert UIColor to OKLAB.
    static func uiColorToOKLab(_ color: UIColor) -> OKLab {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return sRGBToOKLab(r: Double(r), g: Double(g), b: Double(b))
    }

    /// Convert OKLAB to UIColor.
    static func oklabToUIColor(_ lab: OKLab, alpha: CGFloat = 1.0) -> UIColor {
        let rgb = oklabToSRGB(lab)
        return UIColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: alpha)
    }

    private static func clamp01(_ v: Double) -> Double {
        max(0, min(1, v))
    }
}

// MARK: - Perceptual Color Interpolation

enum ColorInterpolation {

    /// Interpolate between two colors in OKLAB space for perceptually uniform blending.
    /// Factor t ∈ [0, 1]: 0 = color A, 1 = color B.
    static func interpolateOKLab(_ a: UIColor, _ b: UIColor, t: Double) -> UIColor {
        let labA = ColorConvert.uiColorToOKLab(a)
        let labB = ColorConvert.uiColorToOKLab(b)

        let mixed = OKLab(
            L: labA.L + (labB.L - labA.L) * t,
            a: labA.a + (labB.a - labA.a) * t,
            b: labA.b + (labB.b - labA.b) * t
        )

        return ColorConvert.oklabToUIColor(mixed)
    }

    /// Interpolate along the hue arc in OKLCH space (shortest path).
    /// Preserves chroma and lightness gradients while rotating hue.
    static func interpolateOKLCH(_ a: UIColor, _ b: UIColor, t: Double) -> UIColor {
        let labA = ColorConvert.uiColorToOKLab(a)
        let labB = ColorConvert.uiColorToOKLab(b)

        let L = labA.L + (labB.L - labA.L) * t
        let C = labA.chroma + (labB.chroma - labA.chroma) * t

        // Shortest hue interpolation.
        var hA = labA.hue
        var hB = labB.hue
        let diff = hB - hA
        if diff > .pi { hA += 2 * .pi }
        if diff < -.pi { hB += 2 * .pi }
        let h = hA + (hB - hA) * t

        let result = OKLab.fromLCH(L: L, C: C, h: h)
        return ColorConvert.oklabToUIColor(result)
    }

    /// Generate N perceptually equidistant colors between two endpoints.
    /// Delegates to C batch gradient kernel for SIMD-optimized conversion pipeline.
    static func gradient(_ a: UIColor, _ b: UIColor, steps: Int) -> [UIColor] {
        guard steps >= 2 else { return [a] }
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0, aA: CGFloat = 0
        a.getRed(&rA, green: &gA, blue: &bA, alpha: &aA)
        var rB: CGFloat = 0, gB: CGFloat = 0, bB: CGFloat = 0, aB: CGFloat = 0
        b.getRed(&rB, green: &gB, blue: &bB, alpha: &aB)

        var outRGB = [Double](repeating: 0, count: steps * 3)
        y2_color_batch_gradient(Double(rA), Double(gA), Double(bA),
                                Double(rB), Double(gB), Double(bB),
                                Int32(steps), &outRGB)

        return (0..<steps).map { i in
            let alphaT = Double(aA) + (Double(aB) - Double(aA)) * Double(i) / Double(steps - 1)
            return UIColor(red: CGFloat(outRGB[i * 3]),
                          green: CGFloat(outRGB[i * 3 + 1]),
                           blue: CGFloat(outRGB[i * 3 + 2]),
                          alpha: CGFloat(alphaT))
        }
    }
}

// MARK: - Color Harmony

/// Generates harmonious color palettes using color theory applied in OKLCH space.
enum ColorHarmony {

    /// Complementary: opposite hue (180° rotation).
    static func complementary(of color: UIColor) -> UIColor {
        rotateHue(color, by: .pi)
    }

    /// Analogous: two neighbors at ±30° on the hue wheel.
    static func analogous(of color: UIColor, spread: Double = .pi / 6) -> (leading: UIColor, trailing: UIColor) {
        return (
            leading: rotateHue(color, by: -spread),
            trailing: rotateHue(color, by: spread)
        )
    }

    /// Triadic: three colors at 120° intervals.
    static func triadic(of color: UIColor) -> (second: UIColor, third: UIColor) {
        return (
            second: rotateHue(color, by: 2 * .pi / 3),
            third: rotateHue(color, by: 4 * .pi / 3)
        )
    }

    /// Split-complementary: two colors flanking the complement at ±30°.
    static func splitComplementary(of color: UIColor, spread: Double = .pi / 6) -> (leading: UIColor, trailing: UIColor) {
        return (
            leading: rotateHue(color, by: .pi - spread),
            trailing: rotateHue(color, by: .pi + spread)
        )
    }

    /// Tetradic (rectangle): four colors at 90° intervals.
    static func tetradic(of color: UIColor) -> (second: UIColor, third: UIColor, fourth: UIColor) {
        return (
            second: rotateHue(color, by: .pi / 2),
            third: rotateHue(color, by: .pi),
            fourth: rotateHue(color, by: 3 * .pi / 2)
        )
    }

    /// Generate a monochromatic palette by varying lightness in OKLAB space.
    static func monochromatic(of color: UIColor, count: Int = 5) -> [UIColor] {
        let lab = ColorConvert.uiColorToOKLab(color)
        guard count >= 2 else { return [color] }

        // Distribute lightness from 0.25 to 0.90 while keeping hue and chroma.
        let minL = 0.25
        let maxL = 0.90
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let L = minL + (maxL - minL) * t
            let adjusted = OKLab.fromLCH(L: L, C: lab.chroma, h: lab.hue)
            return ColorConvert.oklabToUIColor(adjusted)
        }
    }

    /// Rotate hue in OKLCH space by `angle` radians.
    static func rotateHue(_ color: UIColor, by angle: Double) -> UIColor {
        let lab = ColorConvert.uiColorToOKLab(color)
        let newHue = lab.hue + angle
        let rotated = OKLab.fromLCH(L: lab.L, C: lab.chroma, h: newHue)
        return ColorConvert.oklabToUIColor(rotated)
    }

    /// Desaturate by reducing chroma toward zero (grayscale).
    /// Factor 0 = fully saturated, 1 = fully desaturated.
    static func desaturate(_ color: UIColor, factor: Double) -> UIColor {
        let lab = ColorConvert.uiColorToOKLab(color)
        let newC = lab.chroma * max(0, 1.0 - factor)
        let result = OKLab.fromLCH(L: lab.L, C: newC, h: lab.hue)
        return ColorConvert.oklabToUIColor(result)
    }
}

// MARK: - WCAG Contrast

/// WCAG 2.1 contrast ratio calculations — hand-implemented from the spec.
enum ContrastRatio {

    /// Relative luminance per WCAG 2.1 § 1.4.3.
    /// L = 0.2126·R + 0.7152·G + 0.0722·B (in linear sRGB).
    /// Delegates to C kernel for consistent sRGB→linear transfer function.
    static func relativeLuminance(of color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return y2_color_relative_luminance(Double(r), Double(g), Double(b))
    }

    /// Contrast ratio between two colors per WCAG 2.1.
    /// Returns value in [1, 21].
    static func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let lA = relativeLuminance(of: a)
        let lB = relativeLuminance(of: b)
        let lighter = max(lA, lB)
        let darker = min(lA, lB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Whether the pair meets WCAG AA for normal text (≥ 4.5:1).
    static func meetsAA(_ foreground: UIColor, _ background: UIColor) -> Bool {
        ratio(foreground, background) >= 4.5
    }

    /// Whether the pair meets WCAG AAA for normal text (≥ 7:1).
    static func meetsAAA(_ foreground: UIColor, _ background: UIColor) -> Bool {
        ratio(foreground, background) >= 7.0
    }

    /// Find the lightest or darkest shade of a color that meets WCAG AA
    /// contrast against a given background. Searches in OKLAB lightness.
    static func accessibleShade(
        of color: UIColor,
        against background: UIColor,
        targetRatio: Double = 4.5
    ) -> UIColor {
        let lab = ColorConvert.uiColorToOKLab(color)
        let bgLum = relativeLuminance(of: background)

        // Binary search over lightness.
        var lo = 0.0
        var hi = 1.0

        // Determine search direction: need lighter or darker?
        let needLighter = bgLum < 0.5

        for _ in 0..<32 {
            let mid = (lo + hi) / 2.0
            let candidate = OKLab.fromLCH(L: mid, C: lab.chroma, h: lab.hue)
            let candidateColor = ColorConvert.oklabToUIColor(candidate)
            let r = ratio(candidateColor, background)

            if needLighter {
                if r >= targetRatio {
                    hi = mid  // Can go darker
                } else {
                    lo = mid  // Need to go lighter
                }
            } else {
                if r >= targetRatio {
                    lo = mid  // Can go lighter
                } else {
                    hi = mid  // Need to go darker
                }
            }
        }

        let finalL = needLighter ? hi : lo
        let result = OKLab.fromLCH(L: finalL, C: lab.chroma, h: lab.hue)
        return ColorConvert.oklabToUIColor(result)
    }
}

// MARK: - Perceptual Color Distance

enum ColorDistance {
    /// ΔE in OKLAB space: Euclidean distance in the perceptual color space.
    /// Values < 0.02 are typically imperceptible; > 0.1 are clearly different.
    /// Delegates to SIMD-optimized C kernel for the full sRGB→OKLAB→distance chain.
    static func deltaE(_ a: UIColor, _ b: UIColor) -> Double {
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0
        a.getRed(&rA, green: &gA, blue: &bA, alpha: nil)
        var rB: CGFloat = 0, gB: CGFloat = 0, bB: CGFloat = 0
        b.getRed(&rB, green: &gB, blue: &bB, alpha: nil)
        return y2_color_delta_e(Double(rA), Double(gA), Double(bA),
                                Double(rB), Double(gB), Double(bB))
    }

    /// Whether two colors are perceptually indistinguishable (ΔE < threshold).
    static func isPerceptuallyEqual(_ a: UIColor, _ b: UIColor, threshold: Double = 0.02) -> Bool {
        deltaE(a, b) < threshold
    }

    /// Find the most distinct color in a palette from a reference color.
    static func mostDistinct(from reference: UIColor, in palette: [UIColor]) -> UIColor? {
        palette.max { deltaE(reference, $0) < deltaE(reference, $1) }
    }
}
