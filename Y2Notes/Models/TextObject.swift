import Foundation
import UIKit

// MARK: - Text Object

/// A single text box anchored on a notebook page.  Stored in the Note
/// model's `textLayers` parallel array, analogous to `shapeLayers`.
///
/// Text objects sit above the widget layer and below the PKDrawing ink layer
/// so that handwriting naturally flows over them.  The text tool places them
/// with a single tap and they can be moved, resized, and edited inline.
struct TextObject: Codable, Identifiable, Equatable {
    let id: UUID
    /// The text content.
    var content: String
    /// The defining rectangle in page-coordinate points (origin = top-left).
    var frame: CGRect
    /// Font size in points.
    var fontSize: CGFloat
    /// Text colour RGBA (0…1).
    var textColorComponents: [Double]
    /// Background fill colour RGBA (0…1), or nil for transparent.
    var backgroundColorComponents: [Double]?
    /// Text alignment: 0 = left, 1 = center, 2 = right.
    var alignmentRaw: Int
    /// Rotation in radians around the center of `frame`.
    var rotation: CGFloat
    /// Overall opacity (0…1).
    var opacity: CGFloat
    /// Ordering within the text layer.  Higher values render on top.
    var zIndex: Int
    /// When true the object cannot be moved, resized, or edited.
    var isLocked: Bool
    /// Timestamp of initial placement.
    let placedAt: Date

    init(
        id: UUID = UUID(),
        content: String = "",
        frame: CGRect,
        fontSize: CGFloat = 16,
        textColor: UIColor = .label,
        backgroundColor: UIColor? = nil,
        alignment: NSTextAlignment = .left,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1,
        zIndex: Int = 0,
        isLocked: Bool = false,
        placedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.frame = frame
        self.fontSize = fontSize
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.placedAt = placedAt

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        textColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.textColorComponents = [Double(r), Double(g), Double(b), Double(a)]

        if let bg = backgroundColor {
            var br: CGFloat = 0, bg2: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            bg.getRed(&br, green: &bg2, blue: &bb, alpha: &ba)
            self.backgroundColorComponents = [Double(br), Double(bg2), Double(bb), Double(ba)]
        } else {
            self.backgroundColorComponents = nil
        }

        switch alignment {
        case .center: self.alignmentRaw = 1
        case .right:  self.alignmentRaw = 2
        default:      self.alignmentRaw = 0
        }
    }

    /// Resolved text UIColor.
    var textColor: UIColor {
        guard textColorComponents.count == 4 else { return .label }
        return UIColor(
            red:   CGFloat(textColorComponents[0]),
            green: CGFloat(textColorComponents[1]),
            blue:  CGFloat(textColorComponents[2]),
            alpha: CGFloat(textColorComponents[3])
        )
    }

    /// Resolved background UIColor (nil = transparent).
    var backgroundColor: UIColor? {
        guard let comps = backgroundColorComponents, comps.count == 4 else { return nil }
        return UIColor(
            red:   CGFloat(comps[0]),
            green: CGFloat(comps[1]),
            blue:  CGFloat(comps[2]),
            alpha: CGFloat(comps[3])
        )
    }

    /// Resolved NSTextAlignment.
    var textAlignment: NSTextAlignment {
        switch alignmentRaw {
        case 1:  return .center
        case 2:  return .right
        default: return .left
        }
    }

    // MARK: Codable – manual for CGRect

    enum CodingKeys: String, CodingKey {
        case id, content, frameX, frameY, frameW, frameH
        case fontSize, textColorComponents, backgroundColorComponents
        case alignmentRaw, rotation, opacity, zIndex, isLocked, placedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        content   = try c.decode(String.self, forKey: .content)
        let fx    = try c.decode(Double.self, forKey: .frameX)
        let fy    = try c.decode(Double.self, forKey: .frameY)
        let fw    = try c.decode(Double.self, forKey: .frameW)
        let fh    = try c.decode(Double.self, forKey: .frameH)
        frame     = CGRect(x: fx, y: fy, width: fw, height: fh)
        fontSize  = try c.decodeIfPresent(CGFloat.self,   forKey: .fontSize)  ?? 16
        textColorComponents  = try c.decode([Double].self, forKey: .textColorComponents)
        backgroundColorComponents = try c.decodeIfPresent([Double].self, forKey: .backgroundColorComponents)
        alignmentRaw = try c.decodeIfPresent(Int.self,    forKey: .alignmentRaw) ?? 0
        rotation  = try c.decodeIfPresent(CGFloat.self,   forKey: .rotation)   ?? 0
        opacity   = try c.decodeIfPresent(CGFloat.self,   forKey: .opacity)    ?? 1
        zIndex    = try c.decodeIfPresent(Int.self,       forKey: .zIndex)     ?? 0
        isLocked  = try c.decodeIfPresent(Bool.self,      forKey: .isLocked)   ?? false
        placedAt  = try c.decodeIfPresent(Date.self,      forKey: .placedAt)   ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                        forKey: .id)
        try c.encode(content,                   forKey: .content)
        try c.encode(Double(frame.origin.x),    forKey: .frameX)
        try c.encode(Double(frame.origin.y),    forKey: .frameY)
        try c.encode(Double(frame.size.width),  forKey: .frameW)
        try c.encode(Double(frame.size.height), forKey: .frameH)
        try c.encode(fontSize,                  forKey: .fontSize)
        try c.encode(textColorComponents,       forKey: .textColorComponents)
        try c.encodeIfPresent(backgroundColorComponents, forKey: .backgroundColorComponents)
        try c.encode(alignmentRaw,              forKey: .alignmentRaw)
        try c.encode(rotation,                  forKey: .rotation)
        try c.encode(opacity,                   forKey: .opacity)
        try c.encode(zIndex,                    forKey: .zIndex)
        try c.encode(isLocked,                  forKey: .isLocked)
        try c.encode(placedAt,                  forKey: .placedAt)
    }
}

// MARK: - Text Object Constants

enum TextObjectConstants {
    /// Maximum text objects allowed per page.
    static let maxTextObjectsPerPage = 50
    /// Minimum dimension for a text box (points).
    static let minimumDimension: CGFloat = 40
    /// Default text box size.
    static let defaultSize = CGSize(width: 200, height: 60)
    /// Font size range.
    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 72
    /// Snap distance for alignment guides (points).
    static let snapDistance: CGFloat = 6
    /// Handle size (points).
    static let handleSize: CGFloat = 10
    /// Hit-test tolerance (points).
    static let hitTolerance: CGFloat = 8
    /// Save debounce interval (seconds).
    static let saveDebounce: TimeInterval = 0.8
}
