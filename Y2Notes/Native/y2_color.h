/*
 *  y2_color.h
 *  Y2Notes
 *
 *  SIMD-optimized color science: OKLAB ↔ sRGB conversions, batch gradient
 *  generation, WCAG 2.1 contrast, and perceptual distance (ΔE).
 *
 *  All functions are thread-safe (no mutable global state).
 */

#ifndef Y2_COLOR_H
#define Y2_COLOR_H

#ifdef __cplusplus
extern "C" {
#endif

/// Convert a single sRGB color [0,1] to OKLAB (Ottosson 2020).
/// Chain: sRGB → Linear → LMS (M1) → LMS^(1/3) → OKLAB (M2).
void y2_color_srgb_to_oklab(double r, double g, double b,
                            double *outL, double *outA, double *outB);

/// Convert OKLAB back to sRGB [0,1], clamped.
/// Inverse of y2_color_srgb_to_oklab.
void y2_color_oklab_to_srgb(double L, double a, double b,
                            double *outR, double *outG, double *outB);

/// Interpolate two sRGB colors in OKLAB space.
/// t ∈ [0,1]: 0 = colorA, 1 = colorB.  Result written to outR/G/B.
void y2_color_interpolate_oklab(double rA, double gA, double bA,
                                double rB, double gB, double bB,
                                double t,
                                double *outR, double *outG, double *outB);

/// Generate a perceptually uniform gradient of `steps` colors between
/// two sRGB endpoints.  Outputs are interleaved [R0,G0,B0, R1,G1,B1, …]
/// into `outRGB` which must hold at least `steps * 3` doubles.
void y2_color_batch_gradient(double rA, double gA, double bA,
                             double rB, double gB, double bB,
                             int steps, double *outRGB);

/// Perceptual color distance (ΔE) in OKLAB space.
/// < 0.02 imperceptible, > 0.1 clearly different.
double y2_color_delta_e(double r1, double g1, double b1,
                        double r2, double g2, double b2);

/// WCAG 2.1 relative luminance of an sRGB color.
/// L = 0.2126·R_lin + 0.7152·G_lin + 0.0722·B_lin
double y2_color_relative_luminance(double r, double g, double b);

/// WCAG 2.1 contrast ratio between two sRGB colors.  Returns [1, 21].
double y2_color_contrast_ratio(double r1, double g1, double b1,
                               double r2, double g2, double b2);

#ifdef __cplusplus
}
#endif

#endif /* Y2_COLOR_H */
