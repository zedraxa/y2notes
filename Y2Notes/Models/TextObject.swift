import UIKit

// MARK: - TextFontFamily

/// The broad font family for a placed text object.
enum TextFontFamily: String, CaseIterable, Codable, Identifiable {
    case system     = "system"
    case serif      = "serif"
    case monospace  = "monospace"
    case rounded    = "rounded"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:    return NSLocalizedString("TextStyle.Font.System", comment: "")
        case .serif:     return NSLocalizedString("TextStyle.Font.Serif", comment: "")
        case .monospace: return NSLocalizedString("TextStyle.Font.Mono", comment: "")
        case .rounded:   return NSLocalizedString("TextStyle.Font.Rounded", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .system:    return "textformat"
        case .serif:     return "textformat.abc"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .rounded:   return "textformat.alt"
        }
    }

    func uiFont(size: CGFloat, isBold: Bool, isItalic: Bool) -> UIFont {
        let baseDescriptor: UIFontDescriptor
        switch self {
        case .system:
            baseDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        case .serif:
            baseDescriptor = (UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.serif))
                ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        case .monospace:
            baseDescriptor = (UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.monospaced))
                ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        case .rounded:
            baseDescriptor = (UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.rounded))
                ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if isBold   { traits.insert(.traitBold) }
        if isItalic { traits.insert(.traitItalic) }

        let described = (traits.isEmpty ? baseDescriptor : (baseDescriptor.withSymbolicTraits(traits) ?? baseDescriptor))
        return UIFont(descriptor: described, size: size)
    }
}

// MARK: - TextAlignmentType

/// Horizontal alignment for a placed text object.
enum TextAlignmentType: String, CaseIterable, Codable, Identifiable {
    case leading  = "leading"
    case center   = "center"
    case trailing = "trailing"

    var id: String { rawValue }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading:  return .left
        case .center:   return .center
        case .trailing: return .right
        }
    }

    var systemImage: String {
        switch self {
        case .leading:  return "text.alignleft"
        case .center:   return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .leading:  return NSLocalizedString("TextStyle.AlignLeft", comment: "")
        case .center:   return NSLocalizedString("TextStyle.AlignCenter", comment: "")
        case .trailing: return NSLocalizedString("TextStyle.AlignRight", comment: "")
        }
    }
}

// MARK: - TextObjectAction

/// Actions emitted by `TextObjectHandlesView` and handled by `NoteEditorView`.
enum TextObjectAction {
    case updateObject(TextObject)
    case delete
    case duplicate
    case bringForward
    case sendBackward
    case toggleLock
    case editText
}

// MARK: - TextObject

/// A styled, positioned text annotation placed on a note page.
///
/// Stored in `Note.textLayers[pageIndex]` alongside shape and widget layers.
struct TextObject: Codable, Identifiable, Equatable {

    let id: UUID
    var text: String
    var frame: CGRect
    var rotation: CGFloat                       // radians

    // Typography
    var fontFamily: TextFontFamily
    var fontSize: CGFloat                       // points (8…72)
    var isBold: Bool
    var isItalic: Bool
    var isUnderline: Bool
    var isStrikethrough: Bool
    var alignment: TextAlignmentType

    // Colors (stored as [r, g, b, a] Double arrays for Codable convenience)
    var textColorComponents: [Double]           // text / foreground colour
    var backgroundColorComponents: [Double]?   // nil = transparent background
    var borderColorComponents: [Double]?        // nil = no border

    // Appearance
    var borderWidth: CGFloat                    // 0 = no border
    var borderRadius: CGFloat                   // corner radius for bg rect
    var shadowOpacity: Float                    // 0…1
    var shadowRadius: CGFloat
    var opacity: CGFloat                        // overall transparency

    // Canvas metadata
    var zIndex: Int
    var isLocked: Bool
    let placedAt: Date

    // MARK: Init

    init(
        id: UUID = UUID(),
        text: String = "",
        frame: CGRect,
        rotation: CGFloat = 0,
        fontFamily: TextFontFamily = .system,
        fontSize: CGFloat = 18,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isStrikethrough: Bool = false,
        alignment: TextAlignmentType = .leading,
        textColorComponents: [Double] = [0, 0, 0, 1],
        backgroundColorComponents: [Double]? = nil,
        borderColorComponents: [Double]? = nil,
        borderWidth: CGFloat = 0,
        borderRadius: CGFloat = 6,
        shadowOpacity: Float = 0,
        shadowRadius: CGFloat = 4,
        opacity: CGFloat = 1,
        zIndex: Int = 0,
        isLocked: Bool = false,
        placedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.frame = frame
        self.rotation = rotation
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.alignment = alignment
        self.textColorComponents = textColorComponents
        self.backgroundColorComponents = backgroundColorComponents
        self.borderColorComponents = borderColorComponents
        self.borderWidth = borderWidth
        self.borderRadius = borderRadius
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.opacity = opacity
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.placedAt = placedAt
    }

    // MARK: Computed Helpers

    var textColor: UIColor {
        let c = textColorComponents
        guard c.count >= 4 else { return .label }
        return UIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
    }

    var backgroundColor: UIColor? {
        guard let c = backgroundColorComponents, c.count >= 4 else { return nil }
        return UIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
    }

    var borderColor: UIColor? {
        guard let c = borderColorComponents, c.count >= 4 else { return nil }
        return UIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
    }

    func uiFont() -> UIFont {
        fontFamily.uiFont(size: fontSize, isBold: isBold, isItalic: isItalic)
    }

    func attributedString() -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont(),
            .foregroundColor: textColor
        ]
        let para = NSMutableParagraphStyle()
        para.alignment = alignment.nsTextAlignment
        attrs[.paragraphStyle] = para
        if isUnderline     { attrs[.underlineStyle]     = NSUnderlineStyle.single.rawValue }
        if isStrikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, text, frameX, frameY, frameW, frameH
        case rotation, fontFamily, fontSize, isBold, isItalic, isUnderline, isStrikethrough
        case alignment, textColorComponents, backgroundColorComponents
        case borderColorComponents, borderWidth, borderRadius
        case shadowOpacity, shadowRadius, opacity, zIndex, isLocked, placedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        text       = try c.decode(String.self, forKey: .text)
        let x      = try c.decode(Double.self, forKey: .frameX)
        let y      = try c.decode(Double.self, forKey: .frameY)
        let w      = try c.decode(Double.self, forKey: .frameW)
        let h      = try c.decode(Double.self, forKey: .frameH)
        frame      = CGRect(x: x, y: y, width: w, height: h)
        rotation   = CGFloat(try c.decode(Double.self, forKey: .rotation))
        fontFamily = (try? c.decode(TextFontFamily.self, forKey: .fontFamily)) ?? .system
        fontSize   = CGFloat((try? c.decode(Double.self, forKey: .fontSize)) ?? 18)
        isBold          = (try? c.decode(Bool.self, forKey: .isBold))          ?? false
        isItalic        = (try? c.decode(Bool.self, forKey: .isItalic))        ?? false
        isUnderline     = (try? c.decode(Bool.self, forKey: .isUnderline))     ?? false
        isStrikethrough = (try? c.decode(Bool.self, forKey: .isStrikethrough)) ?? false
        alignment    = (try? c.decode(TextAlignmentType.self, forKey: .alignment)) ?? .leading
        textColorComponents       = try c.decode([Double].self, forKey: .textColorComponents)
        backgroundColorComponents = try? c.decode([Double].self, forKey: .backgroundColorComponents)
        borderColorComponents     = try? c.decode([Double].self, forKey: .borderColorComponents)
        borderWidth   = CGFloat((try? c.decode(Double.self, forKey: .borderWidth))   ?? 0)
        borderRadius  = CGFloat((try? c.decode(Double.self, forKey: .borderRadius))  ?? 6)
        shadowOpacity =   Float((try? c.decode(Double.self, forKey: .shadowOpacity)) ?? 0)
        shadowRadius  = CGFloat((try? c.decode(Double.self, forKey: .shadowRadius))  ?? 4)
        opacity       = CGFloat((try? c.decode(Double.self, forKey: .opacity))       ?? 1)
        zIndex        = (try? c.decode(Int.self,  forKey: .zIndex))    ?? 0
        isLocked      = (try? c.decode(Bool.self, forKey: .isLocked))  ?? false
        placedAt      = (try? c.decode(Date.self, forKey: .placedAt))  ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,   forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(Double(frame.origin.x),    forKey: .frameX)
        try c.encode(Double(frame.origin.y),    forKey: .frameY)
        try c.encode(Double(frame.size.width),  forKey: .frameW)
        try c.encode(Double(frame.size.height), forKey: .frameH)
        try c.encode(Double(rotation),  forKey: .rotation)
        try c.encode(fontFamily,         forKey: .fontFamily)
        try c.encode(Double(fontSize),   forKey: .fontSize)
        try c.encode(isBold,          forKey: .isBold)
        try c.encode(isItalic,        forKey: .isItalic)
        try c.encode(isUnderline,     forKey: .isUnderline)
        try c.encode(isStrikethrough, forKey: .isStrikethrough)
        try c.encode(alignment,               forKey: .alignment)
        try c.encode(textColorComponents,     forKey: .textColorComponents)
        try c.encodeIfPresent(backgroundColorComponents, forKey: .backgroundColorComponents)
        try c.encodeIfPresent(borderColorComponents,     forKey: .borderColorComponents)
        try c.encode(Double(borderWidth),  forKey: .borderWidth)
        try c.encode(Double(borderRadius), forKey: .borderRadius)
        try c.encode(Double(shadowOpacity), forKey: .shadowOpacity)
        try c.encode(Double(shadowRadius),  forKey: .shadowRadius)
        try c.encode(Double(opacity), forKey: .opacity)
        try c.encode(zIndex,    forKey: .zIndex)
        try c.encode(isLocked,  forKey: .isLocked)
        try c.encode(placedAt,  forKey: .placedAt)
    }
}
