import Foundation
import UIKit

// MARK: - Writing Effect Category

/// Categorises writing effects by their purpose and render cost.
///
/// **Core effects** (always-on when enabled) simulate physical ink behaviour:
/// pressure spread, velocity thickness, edge fade, paper grain, opacity ripple.
/// They run entirely within the PencilKit stroke pipeline at near-zero cost.
///
/// **Advanced effects** (user-toggleable) add magical enhancements on top:
/// glow pen, neon ink, gradient ink, ink trail fade.  Each is rendered in a
/// lightweight overlay layer and respects `DeviceCapabilityTier` budgets.
enum WritingEffectCategory: String, Codable, CaseIterable {
    case core
    case advanced
}

// MARK: - Core Writing Effect

/// Physical ink effects that simulate real pen-on-paper behaviour.
///
/// These run inline with the PencilKit stroke data — they modify `PKStroke`
/// properties or apply post-render compositing filters.  Because they operate
/// on data the GPU is already processing, they add < 0.5 ms per stroke segment
/// and never allocate new layers.
///
/// **Design principle**: natural first, magical second.
enum CoreWritingEffect: String, CaseIterable, Codable, Identifiable {
    /// Ink spreads wider with higher Apple Pencil force.
    /// Maps `PKStrokePoint.force` → width multiplier (1.0–2.4×).
    case pressureSpread

    /// Stroke width thins at high velocity, thickens when slow.
    /// Maps inter-point velocity → inverse width factor (0.6–1.0×).
    case velocityThickness

    /// Stroke edges fade to a softer alpha, simulating ink drying at boundaries.
    /// Applies a 2 px feather mask along the stroke outline.
    case edgeFade

    /// Multiplies a subtle noise texture into the stroke, simulating paper grain.
    /// Uses a pre-rendered 64×64 tileable grain image composited at 8 % opacity.
    case microTexture

    /// Slight per-segment opacity variation (±3 %) for organic feel.
    /// Uses a deterministic hash of the point index — no randomness at render time.
    case opacityFluctuation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pressureSpread:    return "Pressure Spread"
        case .velocityThickness: return "Velocity Thickness"
        case .edgeFade:          return "Edge Fade"
        case .microTexture:      return "Paper Grain"
        case .opacityFluctuation: return "Opacity Ripple"
        }
    }

    var systemImage: String {
        switch self {
        case .pressureSpread:    return "hand.draw"
        case .velocityThickness: return "arrow.up.right"
        case .edgeFade:          return "circle.dashed"
        case .microTexture:      return "rectangle.grid.1x2"
        case .opacityFluctuation: return "waveform"
        }
    }
}

// MARK: - Advanced Writing Effect

/// Toggleable visual enhancements rendered in a lightweight overlay.
///
/// Each effect uses a single `CALayer` or `CAEmitterLayer` above the canvas
/// and is subject to `DeviceCapabilityTier` gating.  All advanced effects are
/// disabled by default; the user opts in via the Ink Effect Picker.
enum AdvancedWritingEffect: String, CaseIterable, Codable, Identifiable {
    /// Soft outer glow around the nib while writing.
    /// Rendered via a `CAGradientLayer` (radial) sized 40×40 pt, 15 % opacity.
    /// GPU cost: single gradient fill per frame — negligible.
    case glowPen

    /// Bright emissive ink for highlighting concepts.
    /// Applies `compositingFilter = "screenBlendMode"` on the stroke's
    /// rendered image, plus a subtle 2 px outer shadow in the ink colour.
    /// GPU cost: one extra compositing pass — < 0.3 ms.
    case neonInk

    /// Stroke colour shifts based on drawing speed or pressure.
    /// Colour is interpolated per-segment between two user-chosen stops.
    /// No extra layer — modifies the `PKInkingTool` colour inline.
    case gradientInk

    /// Short-lived translucent trail behind the stroke that fades over 0.3 s.
    /// Rendered as a fading `CAShapeLayer` path that is pruned every 300 ms.
    /// GPU cost: one shape layer with path animation — < 0.4 ms.
    case inkTrailFade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glowPen:      return "Glow Pen"
        case .neonInk:      return "Neon Ink"
        case .gradientInk:  return "Gradient Ink"
        case .inkTrailFade: return "Ink Trail"
        }
    }

    var systemImage: String {
        switch self {
        case .glowPen:      return "light.max"
        case .neonInk:      return "lightbulb.fill"
        case .gradientInk:  return "paintbrush"
        case .inkTrailFade: return "wind"
        }
    }

    /// Minimum device tier required.  All advanced effects require at least
    /// `.standard` (A12+) to guarantee 120 fps headroom.
    var minimumTier: DeviceCapabilityTier {
        switch self {
        case .glowPen:      return .standard
        case .neonInk:      return .standard
        case .gradientInk:  return .standard   // no extra layer; just colour math
        case .inkTrailFade: return .standard
        }
    }

    func isSupported(on tier: DeviceCapabilityTier) -> Bool {
        tier >= minimumTier
    }
}

// MARK: - Writing Effect Configuration

/// User-facing configuration for the complete writing-effect stack.
///
/// Persisted to UserDefaults via `Codable`.  The `InkEffectEngine` reads this
/// configuration each frame to decide which effects to apply.
struct WritingEffectConfig: Codable, Equatable {

    // Core effects — individually toggleable (default: all on)
    var pressureSpreadEnabled: Bool    = true
    var velocityThicknessEnabled: Bool = true
    var edgeFadeEnabled: Bool          = true
    var microTextureEnabled: Bool      = true
    var opacityFluctuationEnabled: Bool = true

    // Advanced effects — individually toggleable (default: all off)
    var glowPenEnabled: Bool      = false
    var neonInkEnabled: Bool      = false
    var gradientInkEnabled: Bool  = false
    var inkTrailFadeEnabled: Bool = false

    /// Gradient ink colour stops (start → end).
    var gradientStartColor: [Double] = [0.0, 0.0, 0.0, 1.0]  // RGBA
    var gradientEndColor: [Double]   = [0.2, 0.4, 1.0, 1.0]

    /// Gradient ink mapping source.
    var gradientSource: GradientSource = .velocity

    // MARK: - Convenience

    /// Whether any core effect is active.
    var hasCoreEffects: Bool {
        pressureSpreadEnabled || velocityThicknessEnabled || edgeFadeEnabled
            || microTextureEnabled || opacityFluctuationEnabled
    }

    /// Whether any advanced effect is active.
    var hasAdvancedEffects: Bool {
        glowPenEnabled || neonInkEnabled || gradientInkEnabled || inkTrailFadeEnabled
    }

    /// Returns the set of active core effects for iteration.
    var activeCoreEffects: [CoreWritingEffect] {
        var result: [CoreWritingEffect] = []
        if pressureSpreadEnabled    { result.append(.pressureSpread) }
        if velocityThicknessEnabled { result.append(.velocityThickness) }
        if edgeFadeEnabled          { result.append(.edgeFade) }
        if microTextureEnabled      { result.append(.microTexture) }
        if opacityFluctuationEnabled { result.append(.opacityFluctuation) }
        return result
    }

    /// Returns the set of active advanced effects for iteration.
    var activeAdvancedEffects: [AdvancedWritingEffect] {
        var result: [AdvancedWritingEffect] = []
        if glowPenEnabled      { result.append(.glowPen) }
        if neonInkEnabled      { result.append(.neonInk) }
        if gradientInkEnabled  { result.append(.gradientInk) }
        if inkTrailFadeEnabled { result.append(.inkTrailFade) }
        return result
    }

    /// Filters out advanced effects the device cannot support.
    func resolved(for tier: DeviceCapabilityTier) -> WritingEffectConfig {
        var copy = self
        if !AdvancedWritingEffect.glowPen.isSupported(on: tier)      { copy.glowPenEnabled = false }
        if !AdvancedWritingEffect.neonInk.isSupported(on: tier)      { copy.neonInkEnabled = false }
        if !AdvancedWritingEffect.gradientInk.isSupported(on: tier)  { copy.gradientInkEnabled = false }
        if !AdvancedWritingEffect.inkTrailFade.isSupported(on: tier) { copy.inkTrailFadeEnabled = false }
        return copy
    }

    /// Further filters effects based on adaptive intensity.
    ///
    /// Call after `resolved(for:)` to apply runtime adaptive constraints.
    /// At `.reduced`, all advanced effects are disabled.  At `.minimal`,
    /// all optional core effects (micro-texture, opacity fluctuation) are
    /// also disabled.
    func adapted(for intensity: EffectIntensity) -> WritingEffectConfig {
        var copy = self
        if !intensity.allowsAdvancedWritingEffects {
            copy.glowPenEnabled      = false
            copy.neonInkEnabled      = false
            copy.gradientInkEnabled  = false
            copy.inkTrailFadeEnabled = false
        }
        if intensity == .minimal {
            copy.microTextureEnabled       = false
            copy.opacityFluctuationEnabled = false
        }
        return copy
    }

    // MARK: Default preset

    static let `default` = WritingEffectConfig()
}

// MARK: - Gradient Source

/// What drives the colour interpolation for gradient ink.
enum GradientSource: String, Codable, CaseIterable {
    case velocity  // fast → start colour, slow → end colour
    case pressure  // light → start colour, heavy → end colour
}

// MARK: - Writing Effect Rendering Pipeline

/// Documents the five-stage rendering pipeline for writing effects.
///
/// This is a compile-time specification — no runtime instances are created.
/// Each stage's budget is enforced by the performance constraints below.
///
/// ```
///  Stage 1: Input Sampling    (< 0.2 ms)
///  ────────────────────────────────────
///  Read PKStrokePoint force + velocity from the coalescence buffer.
///  No allocations; pure arithmetic on the existing point array.
///
///  Stage 2: Core Transform    (< 0.5 ms)
///  ────────────────────────────────────
///  Apply pressure spread, velocity thickness, opacity fluctuation.
///  Modifies width/alpha on PKStrokePoint data in-place before PencilKit
///  commits the stroke to the canvas backing store.
///
///  Stage 3: Post-Render Compositing    (< 0.3 ms)
///  ────────────────────────────────────
///  Edge fade + micro texture are applied as CIFilter compositing on the
///  canvas snapshot tile.  Uses Metal-backed CIContext for zero-copy GPU ops.
///
///  Stage 4: Overlay Effects    (< 0.8 ms)
///  ────────────────────────────────────
///  Glow pen, neon ink, ink trail fade rendered in the non-interactive
///  overlay UIView (same overlay as InkEffectEngine).
///  CAGradientLayer / CAShapeLayer / compositingFilter — all GPU-composited.
///
///  Stage 5: Cleanup & Pruning    (< 0.1 ms)
///  ────────────────────────────────────
///  Trail fade paths older than 300 ms are removed.
///  Emitter birth rates are zeroed when the pencil lifts.
/// ```
///
/// **Total budget per frame: < 1.9 ms** (well within the 8.3 ms frame budget).
enum WritingEffectPipeline {
    /// Input sampling — read force + velocity from coalescence buffer.
    static let stage1InputSamplingBudgetMs: Double = 0.2
    /// Core transform — modify stroke width/alpha in-place.
    static let stage2CoreTransformBudgetMs: Double = 0.5
    /// Post-render compositing — CIFilter edge fade + texture.
    static let stage3CompositingBudgetMs: Double = 0.3
    /// Overlay effects — CALayer glow / neon / trail.
    static let stage4OverlayBudgetMs: Double = 0.8
    /// Cleanup — prune expired trail paths.
    static let stage5CleanupBudgetMs: Double = 0.1

    /// Sum of all stages.  Must stay below `PerformanceConstraints.frameBudgetMs`.
    static let totalBudgetMs: Double = 1.9
}

// MARK: - Pressure Spread Parameters

/// Tuning constants for pressure-based ink spread.
///
/// Apple Pencil force range is 0.0–6.67 (first-gen) or 0.0–4.17 (second-gen).
/// We normalise to 0–1 then apply a response curve.
enum PressureSpreadParams {
    /// Minimum width multiplier at zero force.
    static let minMultiplier: CGFloat = 1.0
    /// Maximum width multiplier at full force.
    static let maxMultiplier: CGFloat = 2.4
    /// Response curve exponent (< 1 = more sensitive at light pressure).
    static let curveExponent: CGFloat = 0.7
    /// Force normalisation ceiling (points above this are clamped to 1.0).
    static let forceCeiling: CGFloat = 4.0
}

// MARK: - Velocity Thickness Parameters

/// Tuning constants for velocity-based thickness variation.
enum VelocityThicknessParams {
    /// Width factor at maximum velocity (thinnest strokes when moving fast).
    static let minFactor: CGFloat = 0.6
    /// Width factor at zero velocity (thickest strokes when stationary/slow).
    static let maxFactor: CGFloat = 1.0
    /// Velocity ceiling (points/second) — above this the factor is clamped to `minFactor`.
    static let velocityCeiling: CGFloat = 2000.0
    /// Smoothing factor for exponential moving average (0–1, higher = more responsive).
    static let smoothing: CGFloat = 0.3
}

// MARK: - Edge Fade Parameters

/// Tuning constants for subtle ink fade at stroke edges.
enum EdgeFadeParams {
    /// Feather width in points along the stroke outline.
    static let featherWidth: CGFloat = 2.0
    /// Minimum alpha at the outermost feather edge.
    static let edgeAlpha: CGFloat = 0.15
}

// MARK: - Micro Texture Parameters

/// Tuning constants for paper grain interaction.
enum MicroTextureParams {
    /// Tile size of the pre-rendered grain texture (px).
    static let tileSize: Int = 64
    /// Compositing opacity of the grain overlay.
    static let opacity: CGFloat = 0.08
    /// Scales with `InkMaterialTraits.granularity` — rough paper = more grain.
    static let granularityScale: CGFloat = 1.5
}

// MARK: - Opacity Fluctuation Parameters

/// Tuning constants for slight per-segment opacity variation.
enum OpacityFluctuationParams {
    /// Maximum deviation from the base alpha (±).
    static let maxDeviation: CGFloat = 0.03
    /// Hash seed for deterministic per-point variation.
    static let hashSeed: UInt64 = 0xA5A5_DEAD_BEEF_CAFE
}

// MARK: - Glow Pen Parameters

/// Tuning constants for the soft outer glow effect.
enum GlowPenParams {
    /// Diameter of the radial gradient layer (points).
    static let diameter: CGFloat = 40.0
    /// Base opacity of the glow (scales with pressure).
    static let baseOpacity: CGFloat = 0.15
    /// Maximum opacity at full pressure.
    static let maxOpacity: CGFloat = 0.35
    /// Fade-out duration when the pencil lifts (seconds).
    static let fadeOutDuration: TimeInterval = 0.25
}

// MARK: - Neon Ink Parameters

/// Tuning constants for the neon highlighting effect.
enum NeonInkParams {
    /// Outer shadow radius (points).
    static let shadowRadius: CGFloat = 2.0
    /// Shadow opacity.
    static let shadowOpacity: Float = 0.6
    /// Compositing filter applied to the stroke layer.
    static let compositingFilter: String = "screenBlendMode"
}

// MARK: - Ink Trail Fade Parameters

/// Tuning constants for the short-lived trail behind the stroke.
enum InkTrailFadeParams {
    /// Maximum age before a trail segment is pruned (seconds).
    static let maxAge: TimeInterval = 0.3
    /// Trail line width (points).
    static let lineWidth: CGFloat = 1.5
    /// Trail starting opacity.
    static let startOpacity: CGFloat = 0.4
    /// Prune interval — how often expired segments are removed (seconds).
    static let pruneInterval: TimeInterval = 0.3
}
