import Foundation
import UIKit
import PencilKit

// MARK: - Drawing Tool

/// The logical drawing tool the user has selected.
/// Cases map directly to PKTool types in DrawingToolStore.pkTool.
enum DrawingTool: String, CaseIterable, Codable, Identifiable {
    case pen
    case pencil
    case highlighter
    case fountainPen
    case eraser
    case lasso
    case shape
    case sticker
    case text

    var id: String { rawValue }

    var displayName: String {
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

    var systemImage: String {
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
    var isInking: Bool {
        switch self {
        case .pen, .pencil, .highlighter, .fountainPen, .shape: return true
        case .eraser, .lasso, .sticker, .text: return false
        }
    }

    /// The personality definition for this tool, if it is an inking tool.
    /// Returns `nil` for eraser, lasso, and shape (which delegates to an overlay).
    var personality: ToolPersonality? {
        ToolPersonality.personality(for: self)
    }
}

// MARK: - Eraser Mode

/// Whether the eraser removes individual pixels or entire strokes.
/// Derived from the active `EraserSubType` — do not store this separately.
enum EraserMode: String, CaseIterable, Codable {
    case bitmap
    case vector

    var displayName: String {
        switch self {
        case .bitmap: return "Pixel Eraser"
        case .vector: return "Stroke Eraser"
        }
    }

    var pkEraserType: PKEraserTool.EraserType {
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
enum EraserSubType: String, CaseIterable, Codable {
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

    var displayName: String {
        switch self {
        case .precise:  return "Precise"
        case .standard: return "Standard"
        case .chisel:   return "Chisel"
        case .stroke:   return "Stroke"
        case .smart:    return "Smart"
        }
    }

    var systemImage: String {
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
    var eraserMode: EraserMode {
        switch self {
        case .precise, .standard, .chisel: return .bitmap
        case .stroke, .smart:              return .vector
        }
    }

    /// Tip width in points — used both to construct `PKEraserTool` (bitmap modes
    /// only; vector mode ignores width) and to size the cursor ring overlay.
    var defaultWidth: CGFloat {
        switch self {
        case .precise:  return 8
        case .standard: return 20
        case .chisel:   return 44
        case .stroke:   return 20
        case .smart:    return 40
        }
    }

    /// Minimum adjustable width for this sub-type.
    var minWidth: CGFloat {
        switch self {
        case .precise:  return 4
        case .standard: return 8
        case .chisel:   return 20
        case .stroke:   return 10
        case .smart:    return 20
        }
    }

    /// Maximum adjustable width for this sub-type.
    var maxWidth: CGFloat {
        switch self {
        case .precise:  return 16
        case .standard: return 40
        case .chisel:   return 80
        case .stroke:   return 40
        case .smart:    return 80
        }
    }

    /// True for sub-types where a user-adjustable width slider makes sense.
    var supportsWidthAdjustment: Bool {
        switch self {
        case .precise, .standard, .chisel: return true
        case .stroke, .smart:              return false
        }
    }
}

// MARK: - Shape Type

/// Geometric shapes the shape tool can draw.
enum ShapeType: String, CaseIterable, Codable {
    case line
    case rectangle
    case circle
    case arrow

    var displayName: String {
        switch self {
        case .line:      return "Line"
        case .rectangle: return "Rectangle"
        case .circle:    return "Circle"
        case .arrow:     return "Arrow"
        }
    }

    var systemImage: String {
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
enum ToolbarMode: Equatable {
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
}

// MARK: - Tool Preset

/// A saved combination of drawing tool, colour, stroke width, and opacity that
/// the user can apply with a single tap and optionally mark as a favourite.
struct ToolPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var tool: DrawingTool
    /// RGBA components stored individually in 0…1 range so no UIColor Codable needed.
    var colorComponents: [Double]
    var width: Double
    /// Stroke opacity applied as alpha on the ink colour (0.05–1.0). Default 1.0.
    var opacity: Double
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        tool: DrawingTool,
        color: UIColor = .black,
        width: Double = 3.0,
        opacity: Double = 1.0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tool = tool
        self.width = width
        self.opacity = opacity
        self.isFavorite = isFavorite
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.colorComponents = [Double(r), Double(g), Double(b), Double(a)]
    }

    var uiColor: UIColor {
        guard colorComponents.count == 4 else { return .black }
        return UIColor(
            red:   CGFloat(colorComponents[0]),
            green: CGFloat(colorComponents[1]),
            blue:  CGFloat(colorComponents[2]),
            alpha: CGFloat(colorComponents[3])
        )
    }

    // MARK: - Codable (manual to handle missing `opacity` in older stored data)

    enum CodingKeys: String, CodingKey {
        case id, name, tool, colorComponents, width, opacity, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,        forKey: .id)
        name            = try c.decode(String.self,      forKey: .name)
        tool            = try c.decode(DrawingTool.self, forKey: .tool)
        colorComponents = try c.decode([Double].self,    forKey: .colorComponents)
        width           = try c.decode(Double.self,      forKey: .width)
        opacity         = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        isFavorite      = try c.decode(Bool.self,        forKey: .isFavorite)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(tool,            forKey: .tool)
        try c.encode(colorComponents, forKey: .colorComponents)
        try c.encode(width,           forKey: .width)
        try c.encode(opacity,         forKey: .opacity)
        try c.encode(isFavorite,      forKey: .isFavorite)
    }
}
