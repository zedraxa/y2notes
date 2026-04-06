/*
 *  y2_perlin.h
 *  Y2Notes
 *
 *  SIMD-optimized 2D Perlin noise with fBm variants.
 *  Drop-in C replacement for the hot paths in PerlinNoise2D.swift.
 *
 *  All functions are thread-safe (no mutable global state).
 */

#ifndef Y2_PERLIN_H
#define Y2_PERLIN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a seeded Perlin noise generator.
typedef struct Y2PerlinState Y2PerlinState;

/// Create a noise generator with the given seed.
/// Caller owns the returned pointer and must free with y2_perlin_destroy.
Y2PerlinState *y2_perlin_create(uint64_t seed);

/// Free a noise generator.
void y2_perlin_destroy(Y2PerlinState *state);

/// Evaluate Perlin noise at (x, y).  Returns a value in approximately [−1, 1].
double y2_perlin_noise(const Y2PerlinState *state, double x, double y);

/// Fractal Brownian motion (multi-octave noise).
double y2_perlin_fbm(const Y2PerlinState *state,
                     double x, double y,
                     int octaves,
                     double persistence,
                     double lacunarity);

/// Turbulence: fBm using |noise| (ridge-like patterns).
double y2_perlin_turbulence(const Y2PerlinState *state,
                            double x, double y,
                            int octaves,
                            double persistence,
                            double lacunarity);

/// Ridged multi-fractal noise.
double y2_perlin_ridged(const Y2PerlinState *state,
                        double x, double y,
                        int octaves,
                        double persistence,
                        double lacunarity,
                        double offset);

/// Batch evaluate noise into a pre-allocated buffer (for texture generation).
/// Evaluates noise at scale*(col, row) for each pixel and writes UInt8 [0,255]
/// into `outPixels` (row-major, width*height bytes).
void y2_perlin_generate_tile(const Y2PerlinState *state,
                             uint8_t *outPixels,
                             int width, int height,
                             double scale,
                             int octaves,
                             double persistence,
                             double lacunarity,
                             double contrast);

#ifdef __cplusplus
}
#endif

#endif /* Y2_PERLIN_H */
