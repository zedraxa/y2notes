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

// MARK: - Tool Preset

/// A saved combination of drawing tool, colour, and stroke width that the user
/// can apply with a single tap and optionally mark as a favourite.
struct ToolPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var tool: DrawingTool
    /// RGBA components stored individually in 0…1 range so no UIColor Codable needed.
    var colorComponents: [Double]
    var width: Double
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        tool: DrawingTool,
        color: UIColor = .black,
        width: Double = 3.0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tool = tool
        self.width = width
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
}
