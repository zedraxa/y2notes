/*
 *  y2_perlin.c
 *  Y2Notes
 *
 *  SIMD-optimized 2D Perlin noise (improved algorithm, Perlin 2002).
 *  Uses Arm NEON intrinsics on Apple Silicon for vectorized gradient
 *  dot products.  Falls back to scalar code on other architectures.
 */

#include "y2_perlin.h"
#include <stdlib.h>
#include <math.h>
#include <string.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define Y2_HAS_NEON 1
#else
#define Y2_HAS_NEON 0
#endif

// ─── Permutation table ─────────────────────────────────────────────

struct Y2PerlinState {
    int perm[512];  // Doubled for easy wrapping (avoids modulo in hot path).
};

// 8 gradient directions at 45° intervals.
static const double kGradX[8] = { 1, -1,  0,  0,  1, -1,  1, -1 };
static const double kGradY[8] = { 0,  0,  1, -1,  1,  1, -1, -1 };

// ─── Lifecycle ─────────────────────────────────────────────────────

Y2PerlinState *y2_perlin_create(uint64_t seed) {
    Y2PerlinState *s = (Y2PerlinState *)malloc(sizeof(Y2PerlinState));
    if (!s) return NULL;

    // Fill identity permutation [0, 256).
    int table[256];
    for (int i = 0; i < 256; i++) table[i] = i;

    // Fisher-Yates shuffle using the same LCG as the Swift version
    // so that identical seeds produce identical noise fields.
    uint64_t state = seed;
    for (int i = 255; i >= 1; i--) {
        state = state * UINT64_C(6364136223846793005)
              + UINT64_C(1442695040888963407);
        int j = (int)(state >> 33) % (i + 1);
        int tmp = table[i];
        table[i] = table[j];
        table[j] = tmp;
    }

    // Double the table for wrapping.
    memcpy(s->perm,       table, 256 * sizeof(int));
    memcpy(s->perm + 256, table, 256 * sizeof(int));
    return s;
}

void y2_perlin_destroy(Y2PerlinState *state) {
    free(state);
}

// ─── Internals ─────────────────────────────────────────────────────

/// Improved Perlin fade: 6t⁵ − 15t⁴ + 10t³
static inline double fade(double t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static inline double lerp_d(double a, double b, double t) {
    return a + t * (b - a);
}

/// Gradient dot product.
static inline double grad(int hash, double x, double y) {
    int idx = hash & 7;
    return kGradX[idx] * x + kGradY[idx] * y;
}

// ─── Single-sample noise ───────────────────────────────────────────

double y2_perlin_noise(const Y2PerlinState *s, double x, double y) {
    const int *p = s->perm;

    int xi = ((int)floor(x)) & 255;
    int yi = ((int)floor(y)) & 255;

    double xf = x - floor(x);
    double yf = y - floor(y);

    double u = fade(xf);
    double v = fade(yf);

    // Hash the 4 cell corners.
    int aa = p[p[xi    ] + yi    ];
    int ab = p[p[xi    ] + yi + 1];
    int ba = p[p[xi + 1] + yi    ];
    int bb = p[p[xi + 1] + yi + 1];

#if Y2_HAS_NEON
    // Vectorize the 4 gradient dot products using NEON.
    //   g00 = grad(aa, xf,     yf    )
    //   g10 = grad(ba, xf-1,   yf    )
    //   g01 = grad(ab, xf,     yf-1  )
    //   g11 = grad(bb, xf-1,   yf-1  )
    double gx[4], gy[4], fx[4], fy[4];
    int hashes[4] = { aa, ba, ab, bb };
    fx[0] = xf;       fy[0] = yf;
    fx[1] = xf - 1.0; fy[1] = yf;
    fx[2] = xf;       fy[2] = yf - 1.0;
    fx[3] = xf - 1.0; fy[3] = yf - 1.0;
    for (int i = 0; i < 4; i++) {
        int idx = hashes[i] & 7;
        gx[i] = kGradX[idx];
        gy[i] = kGradY[idx];
    }
    // NEON: 2×float64x2 multiply-accumulate.
    float64x2_t gx_lo = vld1q_f64(gx);
    float64x2_t gx_hi = vld1q_f64(gx + 2);
    float64x2_t gy_lo = vld1q_f64(gy);
    float64x2_t gy_hi = vld1q_f64(gy + 2);
    float64x2_t fx_lo = vld1q_f64(fx);
    float64x2_t fx_hi = vld1q_f64(fx + 2);
    float64x2_t fy_lo = vld1q_f64(fy);
    float64x2_t fy_hi = vld1q_f64(fy + 2);

    float64x2_t dot_lo = vmlaq_f64(vmulq_f64(gx_lo, fx_lo), gy_lo, fy_lo);
    float64x2_t dot_hi = vmlaq_f64(vmulq_f64(gx_hi, fx_hi), gy_hi, fy_hi);

    double dots[4];
    vst1q_f64(dots,     dot_lo);
    vst1q_f64(dots + 2, dot_hi);

    double g00 = dots[0], g10 = dots[1], g01 = dots[2], g11 = dots[3];
#else
    double g00 = grad(aa, xf,       yf);
    double g10 = grad(ba, xf - 1.0, yf);
    double g01 = grad(ab, xf,       yf - 1.0);
    double g11 = grad(bb, xf - 1.0, yf - 1.0);
#endif

    double x0 = lerp_d(g00, g10, u);
    double x1 = lerp_d(g01, g11, u);
    return lerp_d(x0, x1, v);
}

// ─── fBm variants ──────────────────────────────────────────────────

double y2_perlin_fbm(const Y2PerlinState *s,
                     double x, double y,
                     int octaves,
                     double persistence,
                     double lacunarity) {
    double total = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double maxAmp = 0.0;

    for (int i = 0; i < octaves; i++) {
        total += y2_perlin_noise(s, x * frequency, y * frequency) * amplitude;
        maxAmp += amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return total / maxAmp;
}

double y2_perlin_turbulence(const Y2PerlinState *s,
                            double x, double y,
                            int octaves,
                            double persistence,
                            double lacunarity) {
    double total = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double maxAmp = 0.0;

    for (int i = 0; i < octaves; i++) {
        total += fabs(y2_perlin_noise(s, x * frequency, y * frequency)) * amplitude;
        maxAmp += amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return total / maxAmp;
}

double y2_perlin_ridged(const Y2PerlinState *s,
                        double x, double y,
                        int octaves,
                        double persistence,
                        double lacunarity,
                        double offset) {
    double total = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double weight = 1.0;

    for (int i = 0; i < octaves; i++) {
        double signal = y2_perlin_noise(s, x * frequency, y * frequency);
        signal = offset - fabs(signal);
        signal *= signal;
        signal *= weight;

        total += signal * amplitude;
        weight = fmin(1.0, fmax(0.0, signal * 2.0));
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return total;
}

// ─── Batch tile generation ─────────────────────────────────────────

void y2_perlin_generate_tile(const Y2PerlinState *s,
                             uint8_t *outPixels,
                             int width, int height,
                             double scale,
                             int octaves,
                             double persistence,
                             double lacunarity,
                             double contrast) {
    for (int row = 0; row < height; row++) {
        double ny = (double)row * scale;
        for (int col = 0; col < width; col++) {
            double nx = (double)col * scale;
            double value = y2_perlin_fbm(s, nx, ny, octaves, persistence, lacunarity);
            double normalised = (value * contrast + 1.0) * 0.5;
            if (normalised < 0.0) normalised = 0.0;
            if (normalised > 1.0) normalised = 1.0;
            outPixels[row * width + col] = (uint8_t)(normalised * 255.0);
        }
    }
}
