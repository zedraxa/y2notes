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
        }
    }

    /// True for tools that produce ink strokes (colour/width controls are relevant).
    var isInking: Bool {
        switch self {
        case .pen, .pencil, .highlighter, .fountainPen, .shape: return true
        case .eraser, .lasso: return false
        }
    }
}

// MARK: - Eraser Mode

/// Whether the eraser removes individual pixels or entire strokes.
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
