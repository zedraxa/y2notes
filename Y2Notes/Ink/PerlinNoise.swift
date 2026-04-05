// PerlinNoise.swift
// Y2Notes
//
// Custom 2D Perlin noise generator with fractal Brownian motion (fBm).
// Implements Ken Perlin's improved noise algorithm from scratch —
// no external noise libraries, all gradient math hand-coded.
//

import Foundation
import CoreGraphics

// MARK: - Perlin Noise 2D

/// A deterministic 2D Perlin noise generator using the improved algorithm (Perlin 2002).
///
/// Key properties:
/// - Smooth, continuous noise (C¹-continuous via Hermite interpolation)
/// - Tileable with period 256
/// - Deterministic for a given seed
/// - No external dependencies
final class PerlinNoise2D {

    // MARK: - Permutation Table

    /// The permutation table (doubled for wrapping).
    private let perm: [Int]

    /// Gradient vectors for 2D: 8 unit-length gradients at 45° intervals.
    /// Using integer directions for speed (normalisation not needed since
    /// we only compute dot products with fractional coordinates in [0,1)).
    private static let gradients: [(Double, Double)] = [
        ( 1,  0), (-1,  0), ( 0,  1), ( 0, -1),
        ( 1,  1), (-1,  1), ( 1, -1), (-1, -1)
    ]

    /// Create a noise generator with a given seed.
    /// The seed shuffles the permutation table using a Fisher-Yates shuffle
    /// with a custom linear congruential generator.
    init(seed: UInt64 = 0) {
        var table = Array(0..<256)

        // Fisher-Yates shuffle using LCG(a=6364136223846793005, c=1442695040888963407).
        var state = seed
        for i in stride(from: 255, through: 1, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let j = Int(state >> 33) % (i + 1)
            table.swapAt(i, j)
        }

        // Double the table for easy wrapping (avoids modulo in hot path).
        perm = table + table
    }

    // MARK: - Noise Evaluation

    /// Evaluate Perlin noise at (x, y). Returns a value in approximately [−1, 1].
    func noise(x: Double, y: Double) -> Double {
        // Integer cell coordinates (wrapped to 0–255).
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255

        // Fractional position within cell.
        let xf = x - floor(x)
        let yf = y - floor(y)

        // Fade curves: 6t⁵ − 15t⁴ + 10t³ (Perlin's improved smoothstep).
        let u = fade(xf)
        let v = fade(yf)

        // Hash coordinates of the 4 cell corners.
        let aa = perm[perm[xi    ] + yi    ]
        let ab = perm[perm[xi    ] + yi + 1]
        let ba = perm[perm[xi + 1] + yi    ]
        let bb = perm[perm[xi + 1] + yi + 1]

        // Gradient dot products at each corner.
        let g00 = grad(hash: aa, x: xf,       y: yf)
        let g10 = grad(hash: ba, x: xf - 1.0, y: yf)
        let g01 = grad(hash: ab, x: xf,       y: yf - 1.0)
        let g11 = grad(hash: bb, x: xf - 1.0, y: yf - 1.0)

        // Bilinear interpolation with fade curves.
        let x0 = lerp(g00, g10, t: u)
        let x1 = lerp(g01, g11, t: u)
        return lerp(x0, x1, t: v)
    }

    // MARK: - Fractal Brownian Motion

    /// Multi-octave fractal Brownian motion (fBm).
    ///
    /// Layers multiple octaves of noise with increasing frequency and decreasing amplitude.
    /// - Parameters:
    ///   - octaves: Number of noise layers (1–8 typical).
    ///   - persistence: Amplitude decay per octave (0.5 typical = each octave half as loud).
    ///   - lacunarity: Frequency multiplier per octave (2.0 typical = each octave twice as detailed).
    func fbm(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var maxAmplitude = 0.0  // For normalisation.

        for _ in 0..<octaves {
            total += noise(x: x * frequency, y: y * frequency) * amplitude
            maxAmplitude += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }

        // Normalise to [−1, 1].
        return total / maxAmplitude
    }

    /// Turbulence: fBm using absolute value of noise (creates ridge-like patterns).
    func turbulence(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var maxAmplitude = 0.0

        for _ in 0..<octaves {
            total += abs(noise(x: x * frequency, y: y * frequency)) * amplitude
            maxAmplitude += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }

        return total / maxAmplitude
    }

    /// Ridged multi-fractal noise (creates sharp ridge features like mountain ranges or fibers).
    func ridged(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0, offset: Double = 1.0) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var weight = 1.0

        for _ in 0..<octaves {
            var signal = noise(x: x * frequency, y: y * frequency)
            signal = offset - abs(signal)  // Create ridges.
            signal *= signal               // Sharpen.
            signal *= weight               // Weight by previous octave.

            total += signal * amplitude
            weight = min(1.0, max(0.0, signal * 2.0))
            amplitude *= persistence
            frequency *= lacunarity
        }

        return total
    }

    // MARK: - Internals

    /// Improved Perlin fade: 6t⁵ − 15t⁴ + 10t³
    /// This is C²-continuous (second derivative is 0 at t=0 and t=1).
    @inline(__always)
    private func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    @inline(__always)
    private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + t * (b - a)
    }

    /// Compute gradient dot product for a hash value and fractional position.
    @inline(__always)
    private func grad(hash: Int, x: Double, y: Double) -> Double {
        let g = Self.gradients[hash & 7]
        return g.0 * x + g.1 * y
    }
}

// MARK: - Noise Texture Generator

/// Generates CGImage noise textures for use as paper grain, overlay patterns, etc.
enum NoiseTextureGenerator {

    /// Material types for paper grain simulation.
    enum PaperMaterial {
        /// Standard smooth paper — subtle uniform grain.
        case smooth
        /// Textured linen — fibrous directional pattern.
        case linen
        /// Rough kraft paper — large coarse grain.
        case kraft
        /// Laid paper — visible parallel lines from paper mold.
        case laid
        /// Watercolor paper — cold-press bumpy texture.
        case watercolor
    }

    /// Generate a noise texture tile of the given size.
    ///
    /// - Parameters:
    ///   - width: Tile width in pixels.
    ///   - height: Tile height in pixels.
    ///   - material: Paper material type affecting noise character.
    ///   - scale: Noise frequency (higher = finer detail). Default 0.05.
    ///   - seed: Random seed for deterministic generation.
    /// - Returns: A grayscale CGImage suitable for tiling.
    static func generateTile(
        width: Int = 128,
        height: Int = 128,
        material: PaperMaterial = .smooth,
        scale: Double = 0.05,
        seed: UInt64 = 42
    ) -> CGImage? {
        let noise = PerlinNoise2D(seed: seed)
        var pixels = [UInt8](repeating: 0, count: width * height)

        let config = materialConfig(material)

        for y in 0..<height {
            for x in 0..<width {
                let nx = Double(x) * scale * config.frequencyScale
                let ny = Double(y) * scale * config.frequencyScale

                var value: Double
                switch config.noiseType {
                case .fbm:
                    value = noise.fbm(
                        x: nx, y: ny,
                        octaves: config.octaves,
                        persistence: config.persistence,
                        lacunarity: config.lacunarity
                    )
                case .turbulence:
                    value = noise.turbulence(
                        x: nx, y: ny,
                        octaves: config.octaves,
                        persistence: config.persistence,
                        lacunarity: config.lacunarity
                    )
                case .ridged:
                    value = noise.ridged(
                        x: nx, y: ny,
                        octaves: config.octaves,
                        persistence: config.persistence,
                        lacunarity: config.lacunarity
                    )
                }

                // Apply directional bias for materials like linen and laid.
                if config.directionalBias > 0 {
                    let bias = noise.noise(x: nx * 3.0, y: ny * 0.3) * config.directionalBias
                    value = value * (1.0 - config.directionalBias) + bias
                }

                // Map from [-1, 1] to [0, 255], applying contrast.
                let normalised = (value * config.contrast + 1.0) * 0.5
                let clamped = max(0.0, min(1.0, normalised))
                pixels[y * width + x] = UInt8(clamped * 255.0)
            }
        }

        // Create CGImage from pixel buffer.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        return context.makeImage()
    }

    // MARK: - Material Configuration

    private enum NoiseType { case fbm, turbulence, ridged }

    private struct MaterialConfig {
        let noiseType: NoiseType
        let octaves: Int
        let persistence: Double
        let lacunarity: Double
        let frequencyScale: Double
        let contrast: Double
        let directionalBias: Double
    }

    private static func materialConfig(_ material: PaperMaterial) -> MaterialConfig {
        switch material {
        case .smooth:
            return MaterialConfig(
                noiseType: .fbm, octaves: 4, persistence: 0.5,
                lacunarity: 2.0, frequencyScale: 1.0, contrast: 0.6,
                directionalBias: 0
            )
        case .linen:
            return MaterialConfig(
                noiseType: .fbm, octaves: 5, persistence: 0.6,
                lacunarity: 2.2, frequencyScale: 1.5, contrast: 0.8,
                directionalBias: 0.5  // Horizontal fiber direction
            )
        case .kraft:
            return MaterialConfig(
                noiseType: .turbulence, octaves: 6, persistence: 0.55,
                lacunarity: 1.8, frequencyScale: 0.6, contrast: 1.0,
                directionalBias: 0.1
            )
        case .laid:
            return MaterialConfig(
                noiseType: .fbm, octaves: 3, persistence: 0.4,
                lacunarity: 2.0, frequencyScale: 1.2, contrast: 0.5,
                directionalBias: 0.7  // Strong horizontal lines
            )
        case .watercolor:
            return MaterialConfig(
                noiseType: .ridged, octaves: 5, persistence: 0.5,
                lacunarity: 2.1, frequencyScale: 0.8, contrast: 0.9,
                directionalBias: 0
            )
        }
    }
}

// MARK: - Zoom-Adaptive Ruling

/// Computes adaptive page ruling parameters based on zoom level.
/// Lines become sparser at low zoom (readability) and denser at high zoom (precision).
enum AdaptiveRuling {

    struct RulingParams {
        /// Distance between lines in points.
        let spacing: CGFloat
        /// Line width in points.
        let lineWidth: CGFloat
        /// Line opacity [0, 1].
        let lineOpacity: CGFloat
        /// Dot radius for dot-grid (points).
        let dotRadius: CGFloat
    }

    /// Compute ruling parameters for a given zoom scale.
    ///
    /// Uses a perceptual density curve: ruling density follows a sigmoid
    /// that maintains constant perceived density on screen.
    ///
    /// - Parameters:
    ///   - baseSpacing: Default spacing at 1× zoom.
    ///   - zoomScale: Current canvas zoom level.
    ///   - baseLineWidth: Default line width at 1× zoom.
    /// - Returns: Adapted parameters for the current zoom.
    static func adaptedParams(
        baseSpacing: CGFloat,
        zoomScale: CGFloat,
        baseLineWidth: CGFloat = 0.5
    ) -> RulingParams {
        // Sigmoid mapping: keeps perceived spacing roughly constant.
        // At 0.5× zoom, show every other line (spacing × 2).
        // At 2× zoom, keep full detail (spacing × 1).
        // At 4× zoom, add sub-lines (spacing × 0.5).
        let zoomFactor = sigmoid(Double(zoomScale), midpoint: 1.0, steepness: 2.0)
        let spacingMultiplier = 1.0 / max(0.25, zoomFactor)
        let adaptedSpacing = baseSpacing * CGFloat(spacingMultiplier)

        // Line width: thinner at high zoom (already zoomed in),
        // thicker at low zoom (need to be visible).
        let widthFactor = 1.0 / max(0.5, Double(zoomScale))
        let adaptedWidth = max(0.25, baseLineWidth * CGFloat(widthFactor))

        // Opacity: fade lines slightly when very zoomed out to reduce clutter.
        let opacity = min(1.0, CGFloat(0.5 + 0.5 * sigmoid(Double(zoomScale), midpoint: 0.4, steepness: 3.0)))

        // Dot radius scales inversely with zoom (keep constant perceived size).
        let dotRadius = max(0.5, 1.5 / max(0.5, zoomScale))

        return RulingParams(
            spacing: adaptedSpacing,
            lineWidth: adaptedWidth,
            lineOpacity: opacity,
            dotRadius: dotRadius
        )
    }

    /// Standard logistic sigmoid: 1 / (1 + e^(−k(x − x₀)))
    private static func sigmoid(_ x: Double, midpoint: Double, steepness: Double) -> Double {
        1.0 / (1.0 + exp(-steepness * (x - midpoint)))
    }
}
