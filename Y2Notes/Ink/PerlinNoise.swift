// PerlinNoise.swift
// Y2Notes
//
// 2D Perlin noise generator with fractal Brownian motion (fBm).
// Hot-path evaluation is delegated to the SIMD-optimized C kernel
// in Native/y2_perlin.c (Arm NEON on Apple Silicon, scalar fallback
// elsewhere).  The Swift layer owns the C state and exposes
// an identical API so callers don't change.
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
/// - SIMD-accelerated via C kernel (Native/y2_perlin.c)
final class PerlinNoise2D {

    /// Opaque C state (permutation table + seed).
    /// `fileprivate` so NoiseTextureGenerator (same file) can use the batch C kernel.
    fileprivate let cState: OpaquePointer

    /// Create a noise generator with a given seed.
    init(seed: UInt64 = 0) {
        guard let state = y2_perlin_create(seed) else {
            fatalError("y2_perlin_create returned nil — out of memory")
        }
        cState = OpaquePointer(state)
    }

    deinit {
        y2_perlin_destroy(UnsafeMutablePointer(cState))
    }

    // MARK: - Noise Evaluation

    /// Evaluate Perlin noise at (x, y).  Returns a value in approximately [−1, 1].
    @inline(__always)
    func noise(x: Double, y: Double) -> Double {
        y2_perlin_noise(UnsafePointer(cState), x, y)
    }

    // MARK: - Fractal Brownian Motion

    /// Multi-octave fractal Brownian motion (fBm).
    func fbm(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0) -> Double {
        y2_perlin_fbm(UnsafePointer(cState), x, y,
                      Int32(octaves), persistence, lacunarity)
    }

    /// Turbulence: fBm using |noise| (ridge-like patterns).
    func turbulence(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0) -> Double {
        y2_perlin_turbulence(UnsafePointer(cState), x, y,
                             Int32(octaves), persistence, lacunarity)
    }

    /// Ridged multi-fractal noise (sharp ridge features).
    func ridged(x: Double, y: Double, octaves: Int = 6, persistence: Double = 0.5, lacunarity: Double = 2.0, offset: Double = 1.0) -> Double {
        y2_perlin_ridged(UnsafePointer(cState), x, y,
                         Int32(octaves), persistence, lacunarity, offset)
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

        // Fast path: delegate entirely to C batch kernel for simple fBm
        // materials without directional bias.
        if config.noiseType == .fbm && config.directionalBias == 0 {
            pixels.withUnsafeMutableBufferPointer { buf in
                y2_perlin_generate_tile(
                    UnsafePointer(noise.cState),
                    buf.baseAddress!,
                    Int32(width), Int32(height),
                    scale * config.frequencyScale,
                    Int32(config.octaves),
                    config.persistence,
                    config.lacunarity,
                    config.contrast
                )
            }
        } else {
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

                    if config.directionalBias > 0 {
                        let bias = noise.noise(x: nx * 3.0, y: ny * 0.3) * config.directionalBias
                        value = value * (1.0 - config.directionalBias) + bias
                    }

                    let normalised = (value * config.contrast + 1.0) * 0.5
                    let clamped = max(0.0, min(1.0, normalised))
                    pixels[y * width + x] = UInt8(clamped * 255.0)
                }
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
