// FluidSimulation.swift
// Y2Notes
//
// Custom simplified fluid dynamics engine for realistic ink flow.
// Implements a particle-based viscosity model, surface tension approximation,
// and ink blending — all hand-coded without physics libraries.
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

// MARK: - SPH Kernels

/// Smoothed Particle Hydrodynamics (SPH) kernel functions.
/// These are the mathematical foundations of the fluid simulation.
///
/// The kernel W(r, h) determines how a particle's properties influence
/// its neighbors based on distance r and support radius h.
private enum SPHKernel {

    /// Poly6 kernel: W(r, h) = 315 / (64π h⁹) · (h² − r²)³
    /// Used for density estimation (smooth, non-negative).
    @inline(__always)
    static func poly6(rSquared: Double, hSquared: Double) -> Double {
        guard rSquared <= hSquared else { return 0 }
        let diff = hSquared - rSquared
        // Normalisation constant for 2D: 4 / (π h⁸)
        let h8 = hSquared * hSquared * hSquared * hSquared
        return (4.0 / (.pi * h8)) * diff * diff * diff
    }

    /// Spiky kernel gradient: ∇W(r, h) = −45 / (π h⁶) · (h − r)² · (r̂)
    /// Used for pressure force (sharp near center, prevents particle clumping).
    @inline(__always)
    static func spikyGradient(r: Double, h: Double) -> Double {
        guard r > 1e-6 && r <= h else { return 0 }
        let diff = h - r
        // 2D normalisation: −10 / (π h⁵)
        let h5 = h * h * h * h * h
        return (-10.0 / (.pi * h5)) * diff * diff
    }

    /// Viscosity kernel Laplacian: ∇²W(r, h) = 45 / (π h⁶) · (h − r)
    /// Used for viscosity force (smooths velocity differences).
    @inline(__always)
    static func viscosityLaplacian(r: Double, h: Double) -> Double {
        guard r <= h else { return 0 }
        let diff = h - r
        // 2D normalisation: 40 / (π h⁵)
        let h5 = h * h * h * h * h
        return (40.0 / (.pi * h5)) * diff
    }
}

// MARK: - Fluid Simulation Engine

/// A simplified SPH (Smoothed Particle Hydrodynamics) fluid simulation
/// for realistic ink flow on a note-taking canvas.
///
/// The simulation loop per tick:
/// 1. Compute density at each particle (SPH density summation)
/// 2. Compute pressure from density (equation of state)
/// 3. Compute forces: pressure gradient + viscosity + surface tension + gravity
/// 4. Integrate velocity and position (symplectic Euler)
/// 5. Apply boundary conditions and damping
/// 6. Age particles (drying)
final class FluidSimulation {

    // MARK: - State

    private(set) var particles: [FluidParticle] = []
    private var config: FluidConfig

    /// Spatial hash grid for O(n) neighbor search instead of O(n²).
    private var grid: SpatialHashGrid

    // MARK: - Init

    init(config: FluidConfig = FluidConfig()) {
        self.config = config
        self.grid = SpatialHashGrid(cellSize: config.smoothingRadius)
    }

    // MARK: - Public API

    /// Add ink particles at a position (e.g. from a pen stroke).
    /// - Parameters:
    ///   - position: Canvas position in points.
    ///   - velocity: Initial velocity (from nib movement).
    ///   - color: RGBA ink color.
    ///   - count: Number of particles to emit (1–8 typical).
    func emitInk(at position: CGPoint, velocity: CGPoint, color: (r: Double, g: Double, b: Double, a: Double), count: Int = 3) {
        let toAdd = min(count, config.maxParticles - particles.count)
        guard toAdd > 0 else { return }

        for i in 0..<toAdd {
            // Slight jitter for natural spread.
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
    /// Call this at ~60fps for smooth animation.
    func step() {
        guard !particles.isEmpty else { return }

        // 1. Rebuild spatial hash.
        rebuildGrid()

        // 2. Compute density & pressure.
        computeDensityAndPressure()

        // 3. Compute and apply forces.
        applyForces()

        // 4. Integrate position.
        integrate()

        // 5. Age and evaporate.
        ageParticles()
    }

    /// Get the current ink density at a point (for rendering opacity).
    func densityAt(_ point: CGPoint) -> Double {
        let h = config.smoothingRadius
        let hSq = h * h
        var density = 0.0

        for neighbor in grid.query(around: point, radius: h) {
            let dx = Double(point.x - particles[neighbor].position.x)
            let dy = Double(point.y - particles[neighbor].position.y)
            let rSq = dx * dx + dy * dy
            density += SPHKernel.poly6(rSquared: rSq, hSquared: hSq)
        }

        return density
    }

    /// Blend ink color at a point (weighted average of nearby particles).
    func blendedColorAt(_ point: CGPoint) -> (r: Double, g: Double, b: Double, a: Double)? {
        let h = config.smoothingRadius
        let hSq = h * h
        var totalWeight = 0.0
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0

        let neighbors = grid.query(around: point, radius: h)
        guard !neighbors.isEmpty else { return nil }

        for idx in neighbors {
            let p = particles[idx]
            guard p.isWet else { continue }

            let dx = Double(point.x - p.position.x)
            let dy = Double(point.y - p.position.y)
            let rSq = dx * dx + dy * dy
            let w = SPHKernel.poly6(rSquared: rSq, hSquared: hSq)

            r += p.color.r * w
            g += p.color.g * w
            b += p.color.b * w
            a += p.color.a * w
            totalWeight += w
        }

        guard totalWeight > 1e-10 else { return nil }
        return (r: r / totalWeight, g: g / totalWeight, b: b / totalWeight, a: min(1.0, a / totalWeight))
    }

    /// Update simulation configuration.
    func updateConfig(_ newConfig: FluidConfig) {
        config = newConfig
        grid = SpatialHashGrid(cellSize: newConfig.smoothingRadius)
    }

    /// Remove all particles.
    func reset() {
        particles.removeAll()
    }

    // MARK: - Simulation Steps

    private func rebuildGrid() {
        grid.clear()
        for i in 0..<particles.count {
            grid.insert(index: i, position: particles[i].position)
        }
    }

    /// SPH density summation: ρᵢ = Σⱼ mⱼ W(|rᵢ − rⱼ|, h)
    /// Then pressure via Tait equation: P = k (ρ/ρ₀ − 1)
    private func computeDensityAndPressure() {
        let h = config.smoothingRadius
        let hSq = h * h

        for i in 0..<particles.count {
            var density = 0.0
            let neighbors = grid.query(around: particles[i].position, radius: h)

            for j in neighbors {
                let dx = Double(particles[i].position.x - particles[j].position.x)
                let dy = Double(particles[i].position.y - particles[j].position.y)
                let rSq = dx * dx + dy * dy
                density += SPHKernel.poly6(rSquared: rSq, hSquared: hSq)
            }

            particles[i].density = max(density, 1e-6)
            // Tait equation of state for pressure.
            particles[i].pressure = config.stiffness * (particles[i].density / config.restDensity - 1.0)
        }
    }

    /// Compute forces: −∇P/ρ (pressure) + μ∇²v/ρ (viscosity) + surface tension + gravity
    private func applyForces() {
        let h = config.smoothingRadius

        for i in 0..<particles.count {
            var forceX = 0.0
            var forceY = 0.0
            let neighbors = grid.query(around: particles[i].position, radius: h)

            for j in neighbors where j != i {
                let dx = Double(particles[i].position.x - particles[j].position.x)
                let dy = Double(particles[i].position.y - particles[j].position.y)
                let r = (dx * dx + dy * dy).squareRoot()
                guard r > 1e-6 else { continue }

                let dirX = dx / r
                let dirY = dy / r

                // Pressure force: −∇P using spiky kernel gradient.
                let pressureScalar = -(particles[i].pressure + particles[j].pressure)
                    / (2.0 * particles[j].density)
                    * SPHKernel.spikyGradient(r: r, h: h)
                forceX += pressureScalar * dirX
                forceY += pressureScalar * dirY

                // Viscosity force: μ ∇²v using viscosity kernel Laplacian.
                let viscLaplacian = SPHKernel.viscosityLaplacian(r: r, h: h)
                let dvx = Double(particles[j].velocity.x - particles[i].velocity.x)
                let dvy = Double(particles[j].velocity.y - particles[i].velocity.y)
                let viscFactor = config.viscosity * viscLaplacian / particles[j].density
                forceX += dvx * viscFactor
                forceY += dvy * viscFactor

                // Surface tension (simplified): pull toward density gradient.
                let tensionScalar = -config.surfaceTension
                    * SPHKernel.poly6(rSquared: r * r, hSquared: h * h)
                forceX += tensionScalar * dirX
                forceY += tensionScalar * dirY
            }

            // Apply gravity.
            forceX += Double(config.gravity.x)
            forceY += Double(config.gravity.y)

            // F = ma → a = F (mass = 1 for simplicity).
            let ax = forceX / max(particles[i].density, 1e-6) * config.restDensity
            let ay = forceY / max(particles[i].density, 1e-6) * config.restDensity

            // Update velocity (symplectic Euler).
            particles[i].velocity.x += CGFloat(ax * config.dt)
            particles[i].velocity.y += CGFloat(ay * config.dt)

            // Apply damping.
            particles[i].velocity.x *= CGFloat(config.damping)
            particles[i].velocity.y *= CGFloat(config.damping)
        }
    }

    /// Integrate position from velocity.
    private func integrate() {
        let dt = CGFloat(config.dt)
        for i in 0..<particles.count {
            particles[i].position.x += particles[i].velocity.x * dt
            particles[i].position.y += particles[i].velocity.y * dt
        }
    }

    /// Age particles and remove dead ones.
    private func ageParticles() {
        for i in 0..<particles.count {
            particles[i].lifetime += 1
            if particles[i].lifetime >= config.dryingRate {
                particles[i].isWet = false
                // Gradually reduce alpha after drying.
                let extraAge = particles[i].lifetime - config.dryingRate
                let fade = max(0, 1.0 - Double(extraAge) / 100.0)
                particles[i].color.a *= fade
            }
        }
        // Remove fully faded particles.
        particles.removeAll { $0.color.a < 0.01 }
    }
}

// MARK: - Spatial Hash Grid

/// A uniform spatial hash grid for efficient O(1) average-case neighbor queries.
/// Divides 2D space into cells of `cellSize` and maps particles to cells.
///
/// This replaces the naive O(n²) all-pairs distance check with O(n·k)
/// where k is the average number of neighbors per particle.
private final class SpatialHashGrid {
    private let cellSize: Double
    private let inverseCellSize: Double
    /// Cell hash → list of particle indices.
    private var cells: [Int: [Int]] = [:]

    init(cellSize: Double) {
        self.cellSize = cellSize
        self.inverseCellSize = 1.0 / cellSize
    }

    func insert(index: Int, position: CGPoint) {
        let key = cellKey(position)
        cells[key, default: []].append(index)
    }

    func clear() {
        cells.removeAll(keepingCapacity: true)
    }

    /// Query all particle indices within `radius` of `point`.
    /// Checks the 3×3 grid of cells surrounding the point.
    func query(around point: CGPoint, radius: Double) -> [Int] {
        let cx = Int(floor(Double(point.x) * inverseCellSize))
        let cy = Int(floor(Double(point.y) * inverseCellSize))

        var result: [Int] = []
        let rSq = radius * radius

        for dx in -1...1 {
            for dy in -1...1 {
                let key = hashCombine(cx + dx, cy + dy)
                guard let indices = cells[key] else { continue }
                result.append(contentsOf: indices)
            }
        }

        return result
    }

    private func cellKey(_ position: CGPoint) -> Int {
        let cx = Int(floor(Double(position.x) * inverseCellSize))
        let cy = Int(floor(Double(position.y) * inverseCellSize))
        return hashCombine(cx, cy)
    }

    /// Simple spatial hash combining two integers.
    /// Uses a large prime for good distribution.
    @inline(__always)
    private func hashCombine(_ x: Int, _ y: Int) -> Int {
        x &* 73856093 ^ y &* 19349663
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
