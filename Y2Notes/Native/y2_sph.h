/*
 *  y2_sph.h
 *  Y2Notes
 *
 *  SIMD-optimized SPH (Smoothed Particle Hydrodynamics) kernel functions
 *  and batch particle operations for the ink fluid simulation.
 *
 *  All functions are thread-safe (no mutable global state).
 */

#ifndef Y2_SPH_H
#define Y2_SPH_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A particle for the SPH batch operations.
/// Layout matches the hot fields of FluidParticle in Swift.
typedef struct {
    double px, py;   // position
    double vx, vy;   // velocity
    double density;
    double pressure;
} Y2SPHParticle;

/// SPH kernel: Poly6  W(r², h²)
/// Returns 0 when r² > h².
double y2_sph_poly6(double rSquared, double hSquared);

/// SPH kernel gradient: Spiky  ∇W(r, h)
/// Returns 0 when r > h or r ≈ 0.
double y2_sph_spiky_gradient(double r, double h);

/// SPH kernel Laplacian: Viscosity  ∇²W(r, h)
/// Returns 0 when r > h.
double y2_sph_viscosity_laplacian(double r, double h);

/// Batch compute density and pressure for all particles.
/// O(n × avgNeighbors) via spatial hash internally.
///
/// - particles: array of Y2SPHParticle (density and pressure fields are written).
/// - count: number of particles.
/// - smoothingRadius: SPH kernel support radius h.
/// - restDensity: equilibrium density ρ₀.
/// - stiffness: equation-of-state constant k.
void y2_sph_compute_density_pressure(Y2SPHParticle *particles,
                                     size_t count,
                                     double smoothingRadius,
                                     double restDensity,
                                     double stiffness);

/// Batch apply forces (pressure + viscosity + surface tension + gravity)
/// and integrate velocity for all particles.
///
/// - particles: array of Y2SPHParticle (velocity fields are updated).
/// - count: number of particles.
/// - smoothingRadius: SPH kernel support radius h.
/// - viscosity: dynamic viscosity coefficient μ.
/// - surfaceTension: surface tension coefficient.
/// - gravityX, gravityY: gravity vector.
/// - restDensity: equilibrium density ρ₀.
/// - dt: time step.
/// - damping: velocity damping (0–1).
void y2_sph_apply_forces_integrate(Y2SPHParticle *particles,
                                   size_t count,
                                   double smoothingRadius,
                                   double viscosity,
                                   double surfaceTension,
                                   double gravityX, double gravityY,
                                   double restDensity,
                                   double dt,
                                   double damping);

/// Integrate position from velocity for all particles.
void y2_sph_integrate_position(Y2SPHParticle *particles,
                               size_t count,
                               double dt);

#ifdef __cplusplus
}
#endif

#endif /* Y2_SPH_H */
