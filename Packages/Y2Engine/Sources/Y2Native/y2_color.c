/*
 *  y2_color.c
 *  Y2Notes
 *
 *  SIMD-optimized OKLAB ↔ sRGB color science.
 *  Uses Arm NEON intrinsics on Apple Silicon for 3×3 matrix–vector
 *  multiplications.  Falls back to scalar on other architectures.
 */

#include "y2_color.h"
#include <math.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define Y2_HAS_NEON 1
#else
#define Y2_HAS_NEON 0
#endif

// ─── Transfer functions ────────────────────────────────────────────

static inline double srgb_to_linear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : pow((c + 0.055) / 1.055, 2.4);
}

static inline double linear_to_srgb(double c) {
    return c <= 0.0031308
        ? c * 12.92
        : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

static inline double clamp01(double v) {
    if (v < 0.0) return 0.0;
    if (v > 1.0) return 1.0;
    return v;
}

// ─── Ottosson matrices ─────────────────────────────────────────────

// M1: Linear RGB → LMS
static const double M1[3][3] = {
    { 0.4122214708, 0.5363325363, 0.0514459929 },
    { 0.2119034982, 0.6806995451, 0.1073969566 },
    { 0.0883024619, 0.2817188376, 0.6299787005 }
};

// M2: LMS' → OKLAB
static const double M2[3][3] = {
    {  0.2104542553,  0.7936177850, -0.0040720468 },
    {  1.9779984951, -2.4285922050,  0.4505937099 },
    {  0.0259040371,  0.7827717662, -0.8086757660 }
};

// M2_inv: OKLAB → LMS'
static const double M2_inv[3][3] = {
    { 1.0,  0.3963377774,  0.2158037573 },
    { 1.0, -0.1055613458, -0.0638541728 },
    { 1.0, -0.0894841775, -1.2914855480 }
};

// M1_inv: LMS → Linear RGB
static const double M1_inv[3][3] = {
    {  4.0767416621, -3.3077115913,  0.2309699292 },
    { -1.2684380046,  2.6097574011, -0.3413193965 },
    { -0.0041960863, -0.7034186147,  1.7076147010 }
};

// ─── Matrix–vector multiply ────────────────────────────────────────

/// 3×3 matrix × 3-vector → 3-vector.
/// On NEON: 3 FMA lanes per output element using float64x2.
static inline void mat3_mul(const double M[3][3],
                            double x, double y, double z,
                            double *ox, double *oy, double *oz) {
#if Y2_HAS_NEON
    /* Load 2 elements at a time from each matrix row. */
    float64x2_t v01 = { x, y };
    double      v2  = z;

    /* Row 0 */
    float64x2_t r0_01 = vld1q_f64(M[0]);
    float64x2_t p0 = vmulq_f64(r0_01, v01);
    *ox = vaddvq_f64(p0) + M[0][2] * v2;

    /* Row 1 */
    float64x2_t r1_01 = vld1q_f64(M[1]);
    float64x2_t p1 = vmulq_f64(r1_01, v01);
    *oy = vaddvq_f64(p1) + M[1][2] * v2;

    /* Row 2 */
    float64x2_t r2_01 = vld1q_f64(M[2]);
    float64x2_t p2 = vmulq_f64(r2_01, v01);
    *oz = vaddvq_f64(p2) + M[2][2] * v2;
#else
    *ox = M[0][0]*x + M[0][1]*y + M[0][2]*z;
    *oy = M[1][0]*x + M[1][1]*y + M[1][2]*z;
    *oz = M[2][0]*x + M[2][1]*y + M[2][2]*z;
#endif
}

// ─── Public API ────────────────────────────────────────────────────

void y2_color_srgb_to_oklab(double r, double g, double b,
                            double *outL, double *outA, double *outB) {
    /* sRGB → Linear */
    double lr = srgb_to_linear(r);
    double lg = srgb_to_linear(g);
    double lb = srgb_to_linear(b);

    /* Linear → LMS via M1 */
    double l, m, s;
    mat3_mul(M1, lr, lg, lb, &l, &m, &s);

    /* Perceptual cube root */
    double lp = cbrt(l);
    double mp = cbrt(m);
    double sp = cbrt(s);

    /* LMS' → OKLAB via M2 */
    mat3_mul(M2, lp, mp, sp, outL, outA, outB);
}

void y2_color_oklab_to_srgb(double L, double a, double b,
                            double *outR, double *outG, double *outB) {
    /* OKLAB → LMS' via M2_inv */
    double lp, mp, sp;
    mat3_mul(M2_inv, L, a, b, &lp, &mp, &sp);

    /* Undo cube root */
    double l = lp * lp * lp;
    double m = mp * mp * mp;
    double s = sp * sp * sp;

    /* LMS → Linear via M1_inv */
    double lr, lg, lb;
    mat3_mul(M1_inv, l, m, s, &lr, &lg, &lb);

    /* Linear → sRGB, clamped */
    *outR = clamp01(linear_to_srgb(lr));
    *outG = clamp01(linear_to_srgb(lg));
    *outB = clamp01(linear_to_srgb(lb));
}

void y2_color_interpolate_oklab(double rA, double gA, double bA,
                                double rB, double gB, double bB,
                                double t,
                                double *outR, double *outG, double *outB) {
    double La, Aa, Ba;
    y2_color_srgb_to_oklab(rA, gA, bA, &La, &Aa, &Ba);

    double Lb, Ab, Bb;
    y2_color_srgb_to_oklab(rB, gB, bB, &Lb, &Ab, &Bb);

    double Lm = La + (Lb - La) * t;
    double Am = Aa + (Ab - Aa) * t;
    double Bm = Ba + (Bb - Ba) * t;

    y2_color_oklab_to_srgb(Lm, Am, Bm, outR, outG, outB);
}

void y2_color_batch_gradient(double rA, double gA, double bA,
                             double rB, double gB, double bB,
                             int steps, double *outRGB) {
    if (steps < 1) return;
    if (steps == 1) {
        outRGB[0] = rA; outRGB[1] = gA; outRGB[2] = bA;
        return;
    }

    double La, Aa, Ba;
    y2_color_srgb_to_oklab(rA, gA, bA, &La, &Aa, &Ba);

    double Lb, Ab, Bb;
    y2_color_srgb_to_oklab(rB, gB, bB, &Lb, &Ab, &Bb);

    double dL = Lb - La;
    double dA = Ab - Aa;
    double dB = Bb - Ba;
    double inv = 1.0 / (double)(steps - 1);

    for (int i = 0; i < steps; i++) {
        double t = (double)i * inv;
        double Lm = La + dL * t;
        double Am = Aa + dA * t;
        double Bm = Ba + dB * t;

        double oR, oG, oB;
        y2_color_oklab_to_srgb(Lm, Am, Bm, &oR, &oG, &oB);
        outRGB[i * 3 + 0] = oR;
        outRGB[i * 3 + 1] = oG;
        outRGB[i * 3 + 2] = oB;
    }
}

double y2_color_delta_e(double r1, double g1, double b1,
                        double r2, double g2, double b2) {
    double L1, a1, b1_lab;
    y2_color_srgb_to_oklab(r1, g1, b1, &L1, &a1, &b1_lab);

    double L2, a2, b2_lab;
    y2_color_srgb_to_oklab(r2, g2, b2, &L2, &a2, &b2_lab);

    double dL = L1 - L2;
    double da = a1 - a2;
    double db = b1_lab - b2_lab;
    return sqrt(dL * dL + da * da + db * db);
}

double y2_color_relative_luminance(double r, double g, double b) {
    double lr = srgb_to_linear(r);
    double lg = srgb_to_linear(g);
    double lb = srgb_to_linear(b);
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb;
}

double y2_color_contrast_ratio(double r1, double g1, double b1,
                               double r2, double g2, double b2) {
    double lum1 = y2_color_relative_luminance(r1, g1, b1);
    double lum2 = y2_color_relative_luminance(r2, g2, b2);
    double lighter = lum1 > lum2 ? lum1 : lum2;
    double darker  = lum1 > lum2 ? lum2 : lum1;
    return (lighter + 0.05) / (darker + 0.05);
}
