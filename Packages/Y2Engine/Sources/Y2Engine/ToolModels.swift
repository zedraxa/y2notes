import Foundation
import UIKit
import PencilKit
import Y2Core

// MARK: - Drawing Tool

/// The logical drawing tool the user has selected.
/// Cases map directly to PKTool types in DrawingToolStore.pkTool.
public enum DrawingTool: String, CaseIterable, Codable, Identifiable {
    case pen
    case pencil
    case highlighter
    case fountainPen
    case eraser
    case lasso
    case shape
    case sticker
    case text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pen:          return "Pen"
        case .pencil:       return "Pencil"
        case .highlighter:  return "Highlighter"
        case .fountainPen:  return "Fountain Pen"
        case .eraser:       return "Eraser"
        case .lasso:        return "Lasso"
        case .shape:        return "Shape"
        case .sticker:      return "Sticker"
        case .text:         return "Text"
        }
    }

    public var systemImage: String {
        switch self {
        case .pen:          return "pencil.tip"
        case .pencil:       return "pencil"
        case .highlighter:  return "highlighter"
        case .fountainPen:  return "scribble"
        case .eraser:       return "eraser"
        case .lasso:        return "lasso"
        case .shape:        return "square.on.circle"
        case .sticker:      return "face.smiling"
        case .text:         return "character.cursor.ibeam"
        }
    }

    /// True for tools that produce ink strokes (colour/width controls are relevant).
    public var isInking: Bool {
        switch self {
        case .pen, .pencil, .highlighter, .fountainPen, .shape: return true
        case .eraser, .lasso, .sticker, .text: return false
        }
    }

    /// The personality definition for this tool, if it is an inking tool.
    /// Returns `nil` for eraser, lasso, and shape (which delegates to an overlay).
    public var personality: ToolPersonality? {
        ToolPersonality.personality(for: self)
    }
}

// MARK: - Pen Sub-Type

/// Defines the physical character of the pen tool, tuning pressure response,
/// velocity sensitivity, ink flow, and texture for six distinct pen feels.
///
/// Each sub-type maps to a preset `WritingEffectConfig` (pressure curve, ink
/// flow params, stroke taper) that is automatically applied when the user
/// selects it.  The underlying `PKInkingTool` remains `.pen` in all cases —
/// the differences are expressed through overlay physics, not PencilKit ink types.
public enum PenSubType: String, CaseIterable, Codable, Identifiable {
    /// Everyday ballpoint: crisp, consistent, moderate pressure response.
    case ballpoint
    /// Gel pen: smooth flow, vibrant colour, slightly wet character.
    case gel
    /// Felt-tip marker: broad, soft-edged strokes, easy edge-fade.
    case feltTip
    /// Rollerball: fluid and even; thins noticeably at high velocity.
    case rollerball
    /// Technical/drafting pen: hairline precision, zero pressure variation.
    case technicalPen
    /// Sketchy/organic: rough texture, natural opacity variation, expressive.
    case sketchy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ballpoint:    return "Ballpoint"
        case .gel:          return "Gel"
        case .feltTip:      return "Felt Tip"
        case .rollerball:   return "Rollerball"
        case .technicalPen: return "Technical"
        case .sketchy:      return "Sketchy"
        }
    }

    public var systemImage: String {
        switch self {
        case .ballpoint:    return "pencil.tip"
        case .gel:          return "pencil.and.outline"
        case .feltTip:      return "paintbrush.pointed"
        case .rollerball:   return "scribble.variable"
        case .technicalPen: return "ruler"
        case .sketchy:      return "scribble"
        }
    }

    /// Short user-facing tagline shown below the sub-type name.
    public var tagline: String {
        switch self {
        case .ballpoint:    return "Crisp, consistent everyday writing"
        case .gel:          return "Smooth flow, vivid colour"
        case .feltTip:      return "Bold, soft-edged strokes"
        case .rollerball:   return "Fluid, even ink at any speed"
        case .technicalPen: return "Hairline precision, no variation"
        case .sketchy:      return "Organic, hand-drawn character"
        }
    }

    // MARK: - Physics properties

    /// Applied to the user's selected width before passing to `PKInkingTool`.
    /// Felt-tip is widened by default; technical pen is narrowed.
    public var widthMultiplier: CGFloat {
        switch self {
        case .ballpoint:    return 1.0
        case .gel:          return 1.1
        case .feltTip:      return 1.6
        case .rollerball:   return 1.05
        case .technicalPen: return 0.65
        case .sketchy:      return 1.2
        }
    }

    /// Pressure response preset for this sub-type.
    public var pressureCurvePreset: PressureCurvePreset {
        switch self {
        case .ballpoint:    return .balanced
        case .gel:          return .firm
        case .feltTip:      return .light
        case .rollerball:   return .balanced
        case .technicalPen: return .flat
        case .sketchy:      return .light
        }
    }

    /// Velocity ceiling override (pts/s). Lower = more taper at speed.
    public var velocityCeiling: CGFloat {
        switch self {
        case .ballpoint:    return 2000
        case .gel:          return 1500
        case .feltTip:      return 2500
        case .rollerball:   return 1200
        case .technicalPen: return 5000
        case .sketchy:      return 1000
        }
    }

    /// Scales the micro-texture grain relative to its base opacity (1.0 = normal).
    public var microTextureMultiplier: CGFloat {
        switch self {
        case .ballpoint:    return 1.0
        case .gel:          return 0.4
        case .feltTip:      return 1.4
        case .rollerball:   return 0.7
        case .technicalPen: return 0.1
        case .sketchy:      return 2.5
        }
    }

    /// Scales per-segment opacity variance (1.0 = default ±3 %).
    public var opacityVarianceMultiplier: CGFloat {
        switch self {
        case .ballpoint:    return 1.0
        case .gel:          return 0.4
        case .feltTip:      return 1.4
        case .rollerball:   return 0.7
        case .technicalPen: return 0.0
        case .sketchy:      return 3.0
        }
    }

    /// Whether the stroke start/end should fade in/out (taper simulation).
    public var strokeTaperEnabled: Bool {
        switch self {
        case .ballpoint, .gel, .feltTip, .technicalPen: return false
        case .rollerball, .sketchy:                      return true
        }
    }

    /// Whether ink should visually pool (glow expands) when the nib slows.
    public var inkPoolingEnabled: Bool {
        switch self {
        case .gel, .feltTip:                                         return true
        case .ballpoint, .rollerball, .technicalPen, .sketchy:       return false
        }
    }

    /// Pooling glow expansion factor (0 = none, 1 = large pool).
    public var poolingStrength: CGFloat {
        switch self {
        case .gel:     return 0.55
        case .feltTip: return 0.80
        default:       return 0.0
        }
    }
}

// MARK: - Eraser Mode

/// Whether the eraser removes individual pixels or entire strokes.
/// Derived from the active `EraserSubType` — do not store this separately.
public enum EraserMode: String, CaseIterable, Codable {
    case bitmap
    case vector

    public var displayName: String {
        switch self {
        case .bitmap: return "Pixel Eraser"
        case .vector: return "Stroke Eraser"
        }
    }

    public var pkEraserType: PKEraserTool.EraserType {
        switch self {
        case .bitmap: return .bitmap
        case .vector: return .vector
        }
    }
}

// MARK: - Eraser Sub-Type

/// Nuanced eraser personality that controls the erasing behaviour, default tip
/// size, and cursor ring appearance.  Pixel-mode sub-types differ in tip size;
/// vector-mode sub-types differ in their hit-area / semantic intent.
public enum EraserSubType: String, CaseIterable, Codable {
    /// Tiny pixel eraser — ideal for fine-detail corrections (8 pt).
    case precise
    /// Standard pixel eraser — everyday general-purpose use (20 pt).
    case standard
    /// Wide chisel pixel eraser — sweeps away large ink areas quickly (44 pt).
    case chisel
    /// Full-stroke vector eraser — removes an entire PencilKit stroke on contact.
    case stroke
    /// Smart vector eraser — vector removal with an enlarged visual hit-area
    /// cursor to make it easy to target nearby strokes (40 pt cursor).
    case smart

    // MARK: Display

    public var displayName: String {
        switch self {
        case .precise:  return "Precise"
        case .standard: return "Standard"
        case .chisel:   return "Chisel"
        case .stroke:   return "Stroke"
        case .smart:    return "Smart"
        }
    }

    public var systemImage: String {
        switch self {
        case .precise:  return "eraser"
        case .standard: return "eraser.fill"
        case .chisel:   return "rectangle.and.pencil.and.ellipsis"
        case .stroke:   return "scribble.variable"
        case .smart:    return "wand.and.sparkles"
        }
    }

    // MARK: Behaviour

    /// The underlying PencilKit eraser mode this sub-type uses.
    public var eraserMode: EraserMode {
        switch self {
        case .precise, .standard, .chisel: return .bitmap
        case .stroke, .smart:              return .vector
        }
    }

    /// Tip width in points — used both to construct `PKEraserTool` (bitmap modes
    /// only; vector mode ignores width) and to size the cursor ring overlay.
    public var defaultWidth: CGFloat {
        switch self {
        case .precise:  return 8
        case .standard: return 20
        case .chisel:   return 44
        case .stroke:   return 20
        case .smart:    return 40
        }
    }

    /// Minimum adjustable width for this sub-type.
    public var minWidth: CGFloat {
        switch self {
        case .precise:  return 4
        case .standard: return 8
        case .chisel:   return 20
        case .stroke:   return 10
        case .smart:    return 20
        }
    }

    /// Maximum adjustable width for this sub-type.
    public var maxWidth: CGFloat {
        switch self {
        case .precise:  return 16
        case .standard: return 40
        case .chisel:   return 80
        case .stroke:   return 40
        case .smart:    return 80
        }
    }

    /// True for sub-types where a user-adjustable width slider makes sense.
    public var supportsWidthAdjustment: Bool {
        switch self {
        case .precise, .standard, .chisel: return true
        case .stroke, .smart:              return false
        }
    }
}

// MARK: - Shape Type

/// Geometric shapes the shape tool can draw.
public enum ShapeType: String, CaseIterable, Codable {
    case line
    case rectangle
    case circle
    case arrow

    public var displayName: String {
        switch self {
        case .line:      return "Line"
        case .rectangle: return "Rectangle"
        case .circle:    return "Circle"
        case .arrow:     return "Arrow"
        }
    }

    public var systemImage: String {
        switch self {
        case .line:      return "line.diagonal"
        case .rectangle: return "rectangle"
        case .circle:    return "circle"
        case .arrow:     return "arrow.right"
        }
    }
}

// MARK: - Toolbar Mode

/// Derived mode that controls which controls appear in the floating toolbar.
/// This is never stored — it is computed from the active tool and canvas state.
public enum ToolbarMode: Equatable {
    /// Pen / Pencil / Highlighter / Fountain Pen active — show writing tools.
    case writing
    /// Eraser active — show eraser mode toggle.
    case erasing
    /// Lasso active with a selection on canvas — show selection actions.
    case selecting
    /// Shape tool active — show shape picker.
    case shaping
    /// Page overview or page-turn gesture active — toolbar hidden.
    case navigating
    /// Media / sticker / attachment insertion flow — toolbar temporarily replaced.
    case inserting
    /// Sticker tool active — show sticker picker / library.
    case stickering
    /// Text tool active — show font size, colour, and alignment controls.
    case texting
}

// MARK: - Text Object Action

/// Actions available for a selected text object on the canvas.
public enum TextObjectAction {
    case duplicate
    case delete
    case toggleLock
    case bringToFront
    case sendToBack
    case updateFontSize(CGFloat)
    case updateFontFamily(TextFontFamily)
    case toggleBold
    case updateAlignment(NSTextAlignment)
    case updateTextColor(UIColor)
    case updateBackgroundColor(UIColor?)
    case updateBorderRadius(CGFloat)
    case updateBorderColor(UIColor?)
    case updateBorderWidth(CGFloat)
}

// MARK: - Tool Preset

/// A saved combination of drawing tool, colour, stroke width, opacity, and —
/// for pen tools — the active pen sub-type character.  Apply with a single tap
/// and optionally mark as a favourite.
public struct ToolPreset: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var tool: DrawingTool
    /// RGBA components stored individually in 0…1 range so no UIColor Codable needed.
    public var colorComponents: [Double]
    public var width: Double
    /// Stroke opacity applied as alpha on the ink colour (0.05–1.0). Default 1.0.
    public var opacity: Double
    public var isFavorite: Bool
    /// The pen sub-type to restore when this preset is applied.
    /// `nil` for non-pen tools or presets saved before sub-types were introduced.
    public var penSubType: PenSubType?

    public init(
        id: UUID = UUID(),
        name: String,
        tool: DrawingTool,
        color: UIColor = .black,
        width: Double = 3.0,
        opacity: Double = 1.0,
        isFavorite: Bool = false,
        penSubType: PenSubType? = nil
    ) {
        self.id = id
        self.name = name
        self.tool = tool
        self.width = width
        self.opacity = opacity
        self.isFavorite = isFavorite
        self.penSubType = penSubType
        public var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.colorComponents = [Double(r), Double(g), Double(b), Double(a)]
    }

    public var uiColor: UIColor {
        guard colorComponents.count == 4 else { return .black }
        return UIColor(
            red:   CGFloat(colorComponents[0]),
            green: CGFloat(colorComponents[1]),
            blue:  CGFloat(colorComponents[2]),
            alpha: CGFloat(colorComponents[3])
        )
    }

    // MARK: - Codable (manual to handle missing keys in older stored data)

    public enum CodingKeys: String, CodingKey {
        case id, name, tool, colorComponents, width, opacity, isFavorite, penSubType
    }

    public init(from decoder: Decoder) throws {
        public let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,        forKey: .id)
        name            = try c.decode(String.self,      forKey: .name)
        tool            = try c.decode(DrawingTool.self, forKey: .tool)
        colorComponents = try c.decode([Double].self,    forKey: .colorComponents)
        width           = try c.decode(Double.self,      forKey: .width)
        opacity         = try c.decodeIfPresent(Double.self,      forKey: .opacity)     ?? 1.0
        isFavorite      = try c.decode(Bool.self,        forKey: .isFavorite)
        penSubType      = try c.decodeIfPresent(PenSubType.self,  forKey: .penSubType)
    }

    public func encode(to encoder: Encoder) throws {
        public var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(tool,            forKey: .tool)
        try c.encode(colorComponents, forKey: .colorComponents)
        try c.encode(width,           forKey: .width)
        try c.encode(opacity,         forKey: .opacity)
        try c.encode(isFavorite,      forKey: .isFavorite)
        try c.encodeIfPresent(penSubType, forKey: .penSubType)
    }
}

// MARK: - PenSubType → WritingEffectConfig

extension PenSubType {

    /// Builds a `WritingEffectConfig` that reflects the physical character of
    /// this pen sub-type.
    ///
    /// User-toggled advanced effects (`glowPenEnabled`, `neonInkEnabled`, etc.)
    /// are copied from `base` unchanged — the sub-type only overrides the physics
    /// parameters (pressure curve, ink flow, taper, pooling).
    ///
    /// - Parameter base: The existing config to preserve advanced-effect toggles from.
    ///                   Defaults to `.default` (all advanced effects off).
    public func makeWritingEffectConfig(preservingUserToggles base: WritingEffectConfig = .default) -> WritingEffectConfig {
        public var c = base
        c.pressureCurve    = pressureCurvePreset
        c.strokeTaperEnabled = strokeTaperEnabled
        c.inkPoolingEnabled  = inkPoolingEnabled
        c.inkFlow = InkFlowParams(
            microTextureMultiplier:    microTextureMultiplier,
            opacityVarianceMultiplier: opacityVarianceMultiplier,
            velocityCeiling:           velocityCeiling,
            poolingStrength:           poolingStrength
        )
        return c
    }
}
