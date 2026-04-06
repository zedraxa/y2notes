// FluidSimulation.swift
// Y2Notes
//
// Custom simplified fluid dynamics engine for realistic ink flow.
// The compute-heavy SPH steps (density, pressure, forces) are delegated
// to SIMD-optimized C kernels in Native/y2_sph.c.  The Swift layer owns
// particle lifecycle, spatial hashing at the API level, and ink blending.
//

import Foundation
import CoreGraphics

// MARK: - Fluid Particle

/// A discrete particle in the ink fluid simulation.
/// Each particle carries position, velocity, and ink properties.
struct FluidParticle {
    var position: CGPoint
    var velocity: CGPoint
    /// Ink density at this particle (affects viscosity and opacity).
    var density: Double
    /// Pressure computed from density (Tait equation of state).
    var pressure: Double = 0
    /// Color components for ink blending [r, g, b, a].
    var color: (r: Double, g: Double, b: Double, a: Double)
    /// Lifetime in simulation steps (particles evaporate over time).
    var lifetime: Int = 0
    /// Whether this particle is "wet" (can still blend).
    var isWet: Bool = true
}

// MARK: - Fluid Configuration

/// Tuning parameters for the ink fluid simulation.
struct FluidConfig {
    /// Rest density of the fluid (ink at equilibrium).
    var restDensity: Double = 1000.0
    /// Stiffness constant for the equation of state (higher = more incompressible).
    var stiffness: Double = 200.0
    /// Dynamic viscosity coefficient (higher = thicker ink).
    var viscosity: Double = 0.8
    /// Surface tension coefficient (higher = more cohesive droplets).
    var surfaceTension: Double = 0.04
    /// Gravity vector (points per step²).
    var gravity: CGPoint = CGPoint(x: 0, y: 0.01)
    /// Smoothing radius (kernel support, in points).
    var smoothingRadius: Double = 12.0
    /// Time step per simulation tick.
    var dt: Double = 0.016  // ~60fps
    /// Damping applied each step to prevent explosions (0–1, lower = more damping).
    var damping: Double = 0.98
    /// Rate of ink drying (lifetime steps before a particle becomes dry).
    var dryingRate: Int = 300
    /// Maximum particles (performance budget).
    var maxParticles: Int = 500
}

// MARK: - Fluid Simulation Engine

/// A simplified SPH (Smoothed Particle Hydrodynamics) fluid simulation
/// for realistic ink flow on a note-taking canvas.
///
/// The hot-path steps (density/pressure computation, force integration)
/// are delegated to the C kernel in ``Native/y2_sph.c`` which uses
/// SIMD intrinsics on Apple Silicon.  The Swift layer manages particle
/// lifecycle, emission, aging, and the public query API.
final class FluidSimulation {

    // MARK: - State

    private(set) var particles: [FluidParticle] = []
    private var config: FluidConfig

    // MARK: - Init

    init(config: FluidConfig = FluidConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Add ink particles at a position (e.g. from a pen stroke).
    func emitInk(at position: CGPoint, velocity: CGPoint,
                 color: (r: Double, g: Double, b: Double, a: Double), count: Int = 3) {
        let toAdd = min(count, config.maxParticles - particles.count)
        guard toAdd > 0 else { return }

        for i in 0..<toAdd {
            let jitter = CGPoint(
                x: (Double(i) - Double(toAdd) / 2.0) * 1.5,
                y: (sin(Double(i) * 1.618) * 1.2)
            )
            let particle = FluidParticle(
                position: CGPoint(x: position.x + jitter.x, y: position.y + jitter.y),
                velocity: CGPoint(x: velocity.x * 0.3, y: velocity.y * 0.3),
                density: config.restDensity,
                color: color
            )
            particles.append(particle)
        }
    }

    /// Advance the simulation by one time step.
    /// The compute-heavy SPH work (density, pressure, forces) is executed
    /// in the C kernel via y2_sph_* functions for SIMD performance.
    func step() {
        guard !particles.isEmpty else { return }

        // ── Marshal Swift particles → C struct array ──
        var cParticles = particles.map { p in
            Y2SPHParticle(
                px: Double(p.position.x), py: Double(p.position.y),
                vx: Double(p.velocity.x), vy: Double(p.velocity.y),
                density: p.density,
                pressure: p.pressure
            )
        }

        let count = cParticles.count

        // ── 1+2: Density & pressure (C kernel with internal spatial hash) ──
        y2_sph_compute_density_pressure(
            &cParticles, count,
            config.smoothingRadius,
            config.restDensity,
            config.stiffness
        )

        // ── 3+4: Forces + velocity integration (C kernel) ──
        y2_sph_apply_forces_integrate(
            &cParticles, count,
            config.smoothingRadius,
            config.viscosity,
            config.surfaceTension,
            Double(config.gravity.x), Double(config.gravity.y),
            config.restDensity,
            config.dt,
            config.damping
        )

        // ── 5: Position integration (NEON-vectorized) ──
        y2_sph_integrate_position(&cParticles, count, config.dt)

        // ── Unmarshal C → Swift ──
        for i in 0..<count {
            particles[i].position = CGPoint(x: cParticles[i].px, y: cParticles[i].py)
            particles[i].velocity = CGPoint(x: cParticles[i].vx, y: cParticles[i].vy)
            particles[i].density  = cParticles[i].density
            particles[i].pressure = cParticles[i].pressure
        }

        // ── 6: Age and evaporate (remains Swift — not compute-hot) ──
        ageParticles()
    }

    /// Get the current ink density at a point (for rendering opacity).
    /// Note: Uses O(n) scan since max particles is 500; the C kernel's
    /// internal spatial hash is only live during `step()`.
    func densityAt(_ point: CGPoint) -> Double {
        let hSq = config.smoothingRadius * config.smoothingRadius
        var density = 0.0

        for p in particles {
            let dx = Double(point.x - p.position.x)
            let dy = Double(point.y - p.position.y)
            let rSq = dx * dx + dy * dy
            guard rSq <= hSq else { continue }
            density += y2_sph_poly6(rSq, hSq)
        }

        return density
    }

    /// Blend ink color at a point (weighted average of nearby particles).
    /// Note: Uses O(n) scan since max particles is 500; the C kernel's
    /// internal spatial hash is only live during `step()`.
    func blendedColorAt(_ point: CGPoint) -> (r: Double, g: Double, b: Double, a: Double)? {
        let h = config.smoothingRadius
        let hSq = h * h
        var totalWeight = 0.0
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0

        for p in particles where p.isWet {
            let dx = Double(point.x - p.position.x)
            let dy = Double(point.y - p.position.y)
            let rSq = dx * dx + dy * dy
            guard rSq <= hSq else { continue }

            let w = y2_sph_poly6(rSq, hSq)
            r += p.color.r * w
            g += p.color.g * w
            b += p.color.b * w
            a += p.color.a * w
            totalWeight += w
        }

        guard totalWeight > 1e-10 else { return nil }
        return (r: r / totalWeight, g: g / totalWeight,
                b: b / totalWeight, a: min(1.0, a / totalWeight))
    }

    /// Update simulation configuration.
    func updateConfig(_ newConfig: FluidConfig) {
        config = newConfig
    }

    /// Remove all particles.
    func reset() {
        particles.removeAll()
    }

    // MARK: - Internal

    /// Age particles and remove dead ones.
    private func ageParticles() {
        for i in 0..<particles.count {
            particles[i].lifetime += 1
            if particles[i].lifetime >= config.dryingRate {
                particles[i].isWet = false
                let extraAge = particles[i].lifetime - config.dryingRate
                let fade = max(0, 1.0 - Double(extraAge) / 100.0)
                particles[i].color.a *= fade
            }
        }
        particles.removeAll { $0.color.a < 0.01 }
    }
}

// MARK: - Ink Blending

/// Weighted ink color blending using Kubelka-Munk theory approximation.
/// This simulates how real pigments mix (subtractive, not additive like light).
///
/// KM theory models paint as two components:
/// - K: absorption coefficient (how much light the pigment absorbs)
/// - S: scattering coefficient (how much light the pigment scatters back)
///
/// R = 1 + K/S − √((K/S)² + 2·K/S)
enum InkBlending {

    /// Blend two ink colors with given ratio using Kubelka-Munk approximation.
    /// `ratio` ∈ [0, 1]: 0 = pure colorA, 1 = pure colorB.
    static func blend(
        colorA: (r: Double, g: Double, b: Double),
        colorB: (r: Double, g: Double, b: Double),
        ratio: Double
    ) -> (r: Double, g: Double, b: Double) {
        // Convert reflectance to K/S ratio per channel.
        let ksA = (r: reflectanceToKS(colorA.r), g: reflectanceToKS(colorA.g), b: reflectanceToKS(colorA.b))
        let ksB = (r: reflectanceToKS(colorB.r), g: reflectanceToKS(colorB.g), b: reflectanceToKS(colorB.b))

        // Linearly interpolate K/S ratios (this is where KM mixing happens).
        let t = max(0, min(1, ratio))
        let mixedKS = (
            r: ksA.r * (1 - t) + ksB.r * t,
            g: ksA.g * (1 - t) + ksB.g * t,
            b: ksA.b * (1 - t) + ksB.b * t
        )

        // Convert back to reflectance.
        return (
            r: ksToReflectance(mixedKS.r),
            g: ksToReflectance(mixedKS.g),
            b: ksToReflectance(mixedKS.b)
        )
    }

    /// Reflectance R → K/S ratio.
    /// K/S = (1 − R)² / (2R)
    private static func reflectanceToKS(_ R: Double) -> Double {
        let r = max(0.001, min(0.999, R))  // Clamp to avoid division by zero.
        return (1 - r) * (1 - r) / (2 * r)
    }

    /// K/S ratio → Reflectance R.
    /// R = 1 + K/S − √((K/S)² + 2·K/S)
    private static func ksToReflectance(_ ks: Double) -> Double {
        let r = 1.0 + ks - (ks * ks + 2.0 * ks).squareRoot()
        return max(0, min(1, r))
    }
}
