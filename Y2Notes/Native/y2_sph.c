/*
 *  y2_sph.c
 *  Y2Notes
 *
 *  SIMD-optimized SPH kernel functions and batch particle operations
 *  for the ink fluid simulation.  Uses Arm NEON on Apple Silicon.
 */

#include "y2_sph.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define Y2_HAS_NEON 1
#else
#define Y2_HAS_NEON 0
#endif

// ─── Constants ─────────────────────────────────────────────────────

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ─── SPH Kernels (scalar) ──────────────────────────────────────────

double y2_sph_poly6(double rSquared, double hSquared) {
    if (rSquared > hSquared) return 0.0;
    double diff = hSquared - rSquared;
    double h8 = hSquared * hSquared * hSquared * hSquared;
    return (4.0 / (M_PI * h8)) * diff * diff * diff;
}

double y2_sph_spiky_gradient(double r, double h) {
    if (r <= 1e-6 || r > h) return 0.0;
    double diff = h - r;
    double h5 = h * h * h * h * h;
    return (-10.0 / (M_PI * h5)) * diff * diff;
}

double y2_sph_viscosity_laplacian(double r, double h) {
    if (r > h) return 0.0;
    double diff = h - r;
    double h5 = h * h * h * h * h;
    return (40.0 / (M_PI * h5)) * diff;
}

// ─── Spatial Hash (internal) ───────────────────────────────────────

#define HASH_BUCKETS 2048
#define HASH_MASK    (HASH_BUCKETS - 1)

typedef struct {
    int *indices;      // particle indices in this bucket
    int  count;
    int  capacity;
} HashBucket;

typedef struct {
    HashBucket buckets[HASH_BUCKETS];
    double inverseCellSize;
} SpatialHash;

static inline int hash_combine(int x, int y) {
    return (int)(((unsigned)x * 73856093u) ^ ((unsigned)y * 19349663u));
}

static void hash_init(SpatialHash *h, double cellSize) {
    h->inverseCellSize = 1.0 / cellSize;
    for (int i = 0; i < HASH_BUCKETS; i++) {
        h->buckets[i].indices = NULL;
        h->buckets[i].count = 0;
        h->buckets[i].capacity = 0;
    }
}

static void hash_clear(SpatialHash *h) {
    for (int i = 0; i < HASH_BUCKETS; i++) {
        h->buckets[i].count = 0;
    }
}

static void hash_free(SpatialHash *h) {
    for (int i = 0; i < HASH_BUCKETS; i++) {
        free(h->buckets[i].indices);
        h->buckets[i].indices = NULL;
        h->buckets[i].count = 0;
        h->buckets[i].capacity = 0;
    }
}

static void hash_insert(SpatialHash *h, int index, double px, double py) {
    int cx = (int)floor(px * h->inverseCellSize);
    int cy = (int)floor(py * h->inverseCellSize);
    int key = hash_combine(cx, cy) & HASH_MASK;
    HashBucket *b = &h->buckets[key];
    if (b->count >= b->capacity) {
        int newCap = b->capacity == 0 ? 16 : b->capacity * 2;
        b->indices = (int *)realloc(b->indices, (size_t)newCap * sizeof(int));
        b->capacity = newCap;
    }
    b->indices[b->count++] = index;
}

/// Query indices of particles in the 3×3 cell neighborhood.
/// Writes indices into `out` (pre-allocated, max `maxOut`).
/// Returns the number of indices written.
static int hash_query(const SpatialHash *h, double px, double py,
                      int *out, int maxOut) {
    int cx = (int)floor(px * h->inverseCellSize);
    int cy = (int)floor(py * h->inverseCellSize);
    int n = 0;
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            int key = hash_combine(cx + dx, cy + dy) & HASH_MASK;
            const HashBucket *b = &h->buckets[key];
            for (int k = 0; k < b->count && n < maxOut; k++) {
                out[n++] = b->indices[k];
            }
        }
    }
    return n;
}

// ─── Batch density + pressure ──────────────────────────────────────

void y2_sph_compute_density_pressure(Y2SPHParticle *particles,
                                     size_t count,
                                     double smoothingRadius,
                                     double restDensity,
                                     double stiffness) {
    if (count == 0) return;

    double hSq = smoothingRadius * smoothingRadius;

    // Build spatial hash.
    SpatialHash grid;
    hash_init(&grid, smoothingRadius);
    for (size_t i = 0; i < count; i++) {
        hash_insert(&grid, (int)i, particles[i].px, particles[i].py);
    }

    // Stack-allocated neighbor buffer (generous upper bound).
    int neighbors[512];

    for (size_t i = 0; i < count; i++) {
        double density = 0.0;
        int nCount = hash_query(&grid, particles[i].px, particles[i].py,
                                neighbors, 512);

        for (int k = 0; k < nCount; k++) {
            int j = neighbors[k];
            double dx = particles[i].px - particles[j].px;
            double dy = particles[i].py - particles[j].py;
            double rSq = dx * dx + dy * dy;
            density += y2_sph_poly6(rSq, hSq);
        }

        particles[i].density = density > 1e-6 ? density : 1e-6;
        particles[i].pressure = stiffness * (particles[i].density / restDensity - 1.0);
    }

    hash_free(&grid);
}

// ─── Batch forces + velocity integration ───────────────────────────

void y2_sph_apply_forces_integrate(Y2SPHParticle *particles,
                                   size_t count,
                                   double smoothingRadius,
                                   double viscosity,
                                   double surfaceTension,
                                   double gravityX, double gravityY,
                                   double restDensity,
                                   double dt,
                                   double damping) {
    if (count == 0) return;

    double h = smoothingRadius;
    double hSq = h * h;

    // Build spatial hash.
    SpatialHash grid;
    hash_init(&grid, h);
    for (size_t i = 0; i < count; i++) {
        hash_insert(&grid, (int)i, particles[i].px, particles[i].py);
    }

    int neighbors[512];

    for (size_t i = 0; i < count; i++) {
        double forceX = 0.0;
        double forceY = 0.0;

        int nCount = hash_query(&grid, particles[i].px, particles[i].py,
                                neighbors, 512);

        for (int k = 0; k < nCount; k++) {
            int j = neighbors[k];
            if ((size_t)j == i) continue;

            double dx = particles[i].px - particles[j].px;
            double dy = particles[i].py - particles[j].py;
            double rSq = dx * dx + dy * dy;
            double r = sqrt(rSq);
            if (r <= 1e-6) continue;

            double dirX = dx / r;
            double dirY = dy / r;

            // Pressure force.
            double pressureScalar = -(particles[i].pressure + particles[j].pressure)
                                  / (2.0 * particles[j].density)
                                  * y2_sph_spiky_gradient(r, h);
            forceX += pressureScalar * dirX;
            forceY += pressureScalar * dirY;

            // Viscosity force.
            double viscLaplacian = y2_sph_viscosity_laplacian(r, h);
            double dvx = particles[j].vx - particles[i].vx;
            double dvy = particles[j].vy - particles[i].vy;
            double viscFactor = viscosity * viscLaplacian / particles[j].density;
            forceX += dvx * viscFactor;
            forceY += dvy * viscFactor;

            // Surface tension.
            double tensionScalar = -surfaceTension * y2_sph_poly6(rSq, hSq);
            forceX += tensionScalar * dirX;
            forceY += tensionScalar * dirY;
        }

        // Gravity.
        forceX += gravityX;
        forceY += gravityY;

        // Acceleration.
        double invDensity = restDensity / fmax(particles[i].density, 1e-6);
        double ax = forceX * invDensity;
        double ay = forceY * invDensity;

        // Update velocity (symplectic Euler) and apply damping.
        particles[i].vx = (particles[i].vx + ax * dt) * damping;
        particles[i].vy = (particles[i].vy + ay * dt) * damping;
    }

    hash_free(&grid);
}

// ─── Position integration ──────────────────────────────────────────

void y2_sph_integrate_position(Y2SPHParticle *particles,
                               size_t count,
                               double dt) {
#if Y2_HAS_NEON
    // Process 2 particles at a time via NEON double-precision.
    size_t i = 0;
    float64x2_t vdt = vdupq_n_f64(dt);
    for (; i + 1 < count; i += 2) {
        float64x2_t px = { particles[i].px, particles[i + 1].px };
        float64x2_t py = { particles[i].py, particles[i + 1].py };
        float64x2_t vx = { particles[i].vx, particles[i + 1].vx };
        float64x2_t vy = { particles[i].vy, particles[i + 1].vy };

        px = vmlaq_f64(px, vx, vdt);
        py = vmlaq_f64(py, vy, vdt);

        particles[i    ].px = vgetq_lane_f64(px, 0);
        particles[i + 1].px = vgetq_lane_f64(px, 1);
        particles[i    ].py = vgetq_lane_f64(py, 0);
        particles[i + 1].py = vgetq_lane_f64(py, 1);
    }
    // Handle odd particle.
    if (i < count) {
        particles[i].px += particles[i].vx * dt;
        particles[i].py += particles[i].vy * dt;
    }
#else
    for (size_t i = 0; i < count; i++) {
        particles[i].px += particles[i].vx * dt;
        particles[i].py += particles[i].vy * dt;
    }
#endif
}
