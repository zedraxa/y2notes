import Foundation
import UIKit

// MARK: - Shape Instance

/// A single geometric shape placed on a notebook page.  Stored in the Note
/// model's `shapeLayers` parallel array, analogous to `stickerLayers`.
///
/// Shapes sit *above* the sticker layer and *below* the PKDrawing ink layer
/// so that handwriting naturally flows over them.  When selected, a shape
/// temporarily promotes to the top for manipulation, then settles back.
struct ShapeInstance: Codable, Identifiable, Equatable {
    let id: UUID
    /// The geometric primitive this instance represents.
    var shapeType: ShapeType
    /// The defining rectangle in page-coordinate points.
    /// For lines/arrows this is the bounding box of the two endpoints.
    var frame: CGRect
    /// Rotation in radians around the center of `frame`.
    var rotation: CGFloat
    /// Visual style (stroke colour, fill, width, opacity).
    var style: ShapeStyle
    /// Ordering within the shape layer.  Higher values render on top.
    var zIndex: Int
    /// When true the shape cannot be moved, resized, or rotated.
    var isLocked: Bool
    /// Timestamp of initial placement — useful for undo grouping.
    let placedAt: Date

    /// For line/arrow shapes: the normalised start point within `frame`.
    /// (0, 0) = top-left, (1, 1) = bottom-right.  `nil` for rectangles/circles.
    var startNorm: CGPoint?
    /// For line/arrow shapes: the normalised end point within `frame`.
    var endNorm: CGPoint?

    init(
        id: UUID = UUID(),
        shapeType: ShapeType,
        frame: CGRect,
        rotation: CGFloat = 0,
        style: ShapeStyle = ShapeStyle(),
        zIndex: Int = 0,
        isLocked: Bool = false,
        placedAt: Date = Date(),
        startNorm: CGPoint? = nil,
        endNorm: CGPoint? = nil
    ) {
        self.id = id
        self.shapeType = shapeType
        self.frame = frame
        self.rotation = rotation
        self.style = style
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.placedAt = placedAt
        self.startNorm = startNorm
        self.endNorm = endNorm
    }

    // MARK: Codable – manual for CGRect / CGPoint

    enum CodingKeys: String, CodingKey {
        case id, shapeType, frameX, frameY, frameW, frameH, rotation, style
        case zIndex, isLocked, placedAt, startNormX, startNormY, endNormX, endNormY
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,      forKey: .id)
        shapeType = try c.decode(ShapeType.self, forKey: .shapeType)
        let fx    = try c.decode(Double.self, forKey: .frameX)
        let fy    = try c.decode(Double.self, forKey: .frameY)
        let fw    = try c.decode(Double.self, forKey: .frameW)
        let fh    = try c.decode(Double.self, forKey: .frameH)
        frame     = CGRect(x: fx, y: fy, width: fw, height: fh)
        rotation  = try c.decodeIfPresent(CGFloat.self,    forKey: .rotation)  ?? 0
        style     = try c.decodeIfPresent(ShapeStyle.self, forKey: .style)     ?? ShapeStyle()
        zIndex    = try c.decodeIfPresent(Int.self,        forKey: .zIndex)    ?? 0
        isLocked  = try c.decodeIfPresent(Bool.self,       forKey: .isLocked)  ?? false
        placedAt  = try c.decodeIfPresent(Date.self,       forKey: .placedAt)  ?? Date()

        if let sx = try c.decodeIfPresent(Double.self, forKey: .startNormX),
           let sy = try c.decodeIfPresent(Double.self, forKey: .startNormY) {
            startNorm = CGPoint(x: sx, y: sy)
        } else {
            startNorm = nil
        }
        if let ex = try c.decodeIfPresent(Double.self, forKey: .endNormX),
           let ey = try c.decodeIfPresent(Double.self, forKey: .endNormY) {
            endNorm = CGPoint(x: ex, y: ey)
        } else {
            endNorm = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                   forKey: .id)
        try c.encode(shapeType,            forKey: .shapeType)
        try c.encode(Double(frame.origin.x),  forKey: .frameX)
        try c.encode(Double(frame.origin.y),  forKey: .frameY)
        try c.encode(Double(frame.size.width), forKey: .frameW)
        try c.encode(Double(frame.size.height), forKey: .frameH)
        try c.encode(rotation,             forKey: .rotation)
        try c.encode(style,                forKey: .style)
        try c.encode(zIndex,               forKey: .zIndex)
        try c.encode(isLocked,             forKey: .isLocked)
        try c.encode(placedAt,             forKey: .placedAt)
        if let s = startNorm {
            try c.encode(Double(s.x), forKey: .startNormX)
            try c.encode(Double(s.y), forKey: .startNormY)
        }
        if let e = endNorm {
            try c.encode(Double(e.x), forKey: .endNormX)
            try c.encode(Double(e.y), forKey: .endNormY)
        }
    }
}

// MARK: - Shape Style

/// Visual properties for a shape object.  Separate from `DrawingToolStore`
/// so each placed shape carries its own immutable-at-placement style that
/// can be edited individually.
struct ShapeStyle: Codable, Equatable {
    /// Stroke colour RGBA (0…1).
    var strokeColorComponents: [Double]
    /// Stroke width in points.
    var strokeWidth: CGFloat
    /// Fill colour RGBA (0…1), or nil for no fill.
    var fillColorComponents: [Double]?
    /// Overall opacity (0…1).
    var opacity: CGFloat

    init(
        strokeColor: UIColor = .label,
        strokeWidth: CGFloat = 2.0,
        fillColor: UIColor? = nil,
        opacity: CGFloat = 1.0
    ) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        strokeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.strokeColorComponents = [Double(r), Double(g), Double(b), Double(a)]
        self.strokeWidth = strokeWidth
        self.opacity = opacity

        if let fill = fillColor {
            var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
            fill.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
            self.fillColorComponents = [Double(fr), Double(fg), Double(fb), Double(fa)]
        } else {
            self.fillColorComponents = nil
        }
    }

    /// Resolved stroke UIColor.
    var strokeColor: UIColor {
        guard strokeColorComponents.count == 4 else { return .label }
        return UIColor(
            red: CGFloat(strokeColorComponents[0]),
            green: CGFloat(strokeColorComponents[1]),
            blue: CGFloat(strokeColorComponents[2]),
            alpha: CGFloat(strokeColorComponents[3])
        )
    }

    /// Resolved fill UIColor (nil = no fill).
    var fillColor: UIColor? {
        guard let comps = fillColorComponents, comps.count == 4 else { return nil }
        return UIColor(
            red: CGFloat(comps[0]),
            green: CGFloat(comps[1]),
            blue: CGFloat(comps[2]),
            alpha: CGFloat(comps[3])
        )
    }
}

// MARK: - Shape Constants

enum ShapeConstants {
    /// Maximum shapes allowed per page.
    static let maxShapesPerPage = 50
    /// Minimum dimension for a shape (points).
    static let minimumDimension: CGFloat = 10
    /// Minimum scale factor.
    static let minScale: CGFloat = 0.25
    /// Maximum scale factor.
    static let maxScale: CGFloat = 4.0
    /// Snap distance for alignment guides (points).
    static let snapDistance: CGFloat = 6
    /// Rotation snap zone (radians, ~5°).
    static let rotationSnapZone: CGFloat = 5 * .pi / 180
    /// Save debounce interval (seconds).
    static let saveDebounce: TimeInterval = 0.8
    /// Hit-test tolerance for line/arrow shapes (points).
    static let lineHitTolerance: CGFloat = 12
    /// Handle size (points).
    static let handleSize: CGFloat = 10
}
