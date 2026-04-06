import Foundation
import UIKit

// MARK: - Text Font Family

public enum TextFontFamily: String, CaseIterable, Codable, Identifiable {
    case system
    case serif
    case monospace
    case rounded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:    return "System"
        case .serif:     return "Serif"
        case .monospace: return "Mono"
        case .rounded:   return "Rounded"
        }
    }

    public var systemImage: String {
        switch self {
        case .system:    return "textformat"
        case .serif:     return "text.book.closed"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .rounded:   return "circle.hexagongrid"
        }
    }

    public func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            if let descriptor = UIFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor
                .withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .monospace:
            if let descriptor = UIFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor
                .withDesign(.monospaced) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            if let descriptor = UIFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor
                .withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: weight)
        }
    }
}

// MARK: - Text Object

public struct TextObject: Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: String
    public var frame: CGRect
    public var fontSize: CGFloat
    public var fontFamily: TextFontFamily
    public var isBold: Bool
    public var textColorComponents: [Double]
    public var backgroundColorComponents: [Double]?
    public var alignmentRaw: Int
    public var rotation: CGFloat
    public var opacity: CGFloat
    public var zIndex: Int
    public var isLocked: Bool
    public var borderRadius: CGFloat
    public var borderColorComponents: [Double]?
    public var borderWidth: CGFloat
    public let placedAt: Date

    public init(
        id: UUID = UUID(),
        content: String = "",
        frame: CGRect,
        fontSize: CGFloat = 16,
        fontFamily: TextFontFamily = .system,
        isBold: Bool = false,
        textColor: UIColor = .label,
        backgroundColor: UIColor? = nil,
        alignment: NSTextAlignment = .left,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1,
        zIndex: Int = 0,
        isLocked: Bool = false,
        borderRadius: CGFloat = 4,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        placedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.frame = frame
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.borderRadius = borderRadius
        self.borderWidth = borderWidth
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

        if let bc = borderColor {
            var br: CGFloat = 0, bg2: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            bc.getRed(&br, green: &bg2, blue: &bb, alpha: &ba)
            self.borderColorComponents = [Double(br), Double(bg2), Double(bb), Double(ba)]
        } else {
            self.borderColorComponents = nil
        }

        switch alignment {
        case .center: self.alignmentRaw = 1
        case .right:  self.alignmentRaw = 2
        default:      self.alignmentRaw = 0
        }
    }

    public var textColor: UIColor {
        guard textColorComponents.count == 4 else { return .label }
        return UIColor(
            red:   CGFloat(textColorComponents[0]),
            green: CGFloat(textColorComponents[1]),
            blue:  CGFloat(textColorComponents[2]),
            alpha: CGFloat(textColorComponents[3])
        )
    }

    public var backgroundColor: UIColor? {
        guard let comps = backgroundColorComponents, comps.count == 4 else { return nil }
        return UIColor(
            red:   CGFloat(comps[0]),
            green: CGFloat(comps[1]),
            blue:  CGFloat(comps[2]),
            alpha: CGFloat(comps[3])
        )
    }

    public var borderColor: UIColor? {
        guard let comps = borderColorComponents, comps.count == 4 else { return nil }
        return UIColor(
            red:   CGFloat(comps[0]),
            green: CGFloat(comps[1]),
            blue:  CGFloat(comps[2]),
            alpha: CGFloat(comps[3])
        )
    }

    public var textAlignment: NSTextAlignment {
        switch alignmentRaw {
        case 1:  return .center
        case 2:  return .right
        default: return .left
        }
    }

    public var resolvedFont: UIFont {
        fontFamily.font(ofSize: fontSize, weight: isBold ? .bold : .regular)
    }

    // MARK: Codable – manual for CGRect

    enum CodingKeys: String, CodingKey {
        case id, content, frameX, frameY, frameW, frameH
        case fontSize, fontFamily, isBold
        case textColorComponents, backgroundColorComponents
        case alignmentRaw, rotation, opacity, zIndex, isLocked, placedAt
        case borderRadius, borderColorComponents, borderWidth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        content   = try c.decode(String.self, forKey: .content)
        let fx    = try c.decode(Double.self, forKey: .frameX)
        let fy    = try c.decode(Double.self, forKey: .frameY)
        let fw    = try c.decode(Double.self, forKey: .frameW)
        let fh    = try c.decode(Double.self, forKey: .frameH)
        frame     = CGRect(x: fx, y: fy, width: fw, height: fh)
        fontSize  = try c.decodeIfPresent(CGFloat.self,   forKey: .fontSize)  ?? 16
        fontFamily = try c.decodeIfPresent(TextFontFamily.self, forKey: .fontFamily) ?? .system
        isBold    = try c.decodeIfPresent(Bool.self,      forKey: .isBold)    ?? false
        textColorComponents  = try c.decode([Double].self, forKey: .textColorComponents)
        backgroundColorComponents = try c.decodeIfPresent([Double].self, forKey: .backgroundColorComponents)
        alignmentRaw = try c.decodeIfPresent(Int.self,    forKey: .alignmentRaw) ?? 0
        rotation  = try c.decodeIfPresent(CGFloat.self,   forKey: .rotation)   ?? 0
        opacity   = try c.decodeIfPresent(CGFloat.self,   forKey: .opacity)    ?? 1
        zIndex    = try c.decodeIfPresent(Int.self,       forKey: .zIndex)     ?? 0
        isLocked  = try c.decodeIfPresent(Bool.self,      forKey: .isLocked)   ?? false
        borderRadius = try c.decodeIfPresent(CGFloat.self, forKey: .borderRadius) ?? 4
        borderColorComponents = try c.decodeIfPresent([Double].self, forKey: .borderColorComponents)
        borderWidth = try c.decodeIfPresent(CGFloat.self, forKey: .borderWidth) ?? 0
        placedAt  = try c.decodeIfPresent(Date.self,      forKey: .placedAt)   ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                        forKey: .id)
        try c.encode(content,                   forKey: .content)
        try c.encode(Double(frame.origin.x),    forKey: .frameX)
        try c.encode(Double(frame.origin.y),    forKey: .frameY)
        try c.encode(Double(frame.size.width),  forKey: .frameW)
        try c.encode(Double(frame.size.height), forKey: .frameH)
        try c.encode(fontSize,                  forKey: .fontSize)
        try c.encode(fontFamily,                forKey: .fontFamily)
        try c.encode(isBold,                    forKey: .isBold)
        try c.encode(textColorComponents,       forKey: .textColorComponents)
        try c.encodeIfPresent(backgroundColorComponents, forKey: .backgroundColorComponents)
        try c.encode(alignmentRaw,              forKey: .alignmentRaw)
        try c.encode(rotation,                  forKey: .rotation)
        try c.encode(opacity,                   forKey: .opacity)
        try c.encode(zIndex,                    forKey: .zIndex)
        try c.encode(isLocked,                  forKey: .isLocked)
        try c.encode(borderRadius,              forKey: .borderRadius)
        try c.encodeIfPresent(borderColorComponents, forKey: .borderColorComponents)
        try c.encode(borderWidth,               forKey: .borderWidth)
        try c.encode(placedAt,                  forKey: .placedAt)
    }
}

// MARK: - Text Object Constants

public enum TextObjectConstants {
    public static let maxTextObjectsPerPage = 50
    public static let minimumDimension: CGFloat = 40
    public static let defaultSize = CGSize(width: 200, height: 60)
    public static let minFontSize: CGFloat = 8
    public static let maxFontSize: CGFloat = 72
    public static let snapDistance: CGFloat = 6
    public static let handleSize: CGFloat = 10
    public static let hitTolerance: CGFloat = 8
    public static let saveDebounce: TimeInterval = 0.8
    public static let defaultBackgroundAlpha: CGFloat = 0.15
    public static let minBorderRadius: CGFloat = 0
    public static let maxBorderRadius: CGFloat = 24
    public static let minBorderWidth: CGFloat = 0
    public static let maxBorderWidth: CGFloat = 4
    public static let minPinchScale: CGFloat = 0.5
    public static let maxPinchScale: CGFloat = 3.0
}
