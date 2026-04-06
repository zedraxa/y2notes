import Foundation
import CoreGraphics

// MARK: - Widget Kind

public enum WidgetKind: String, Codable, CaseIterable, Equatable {
    case checklist
    case quickTable
    case calloutBox
    case referenceCard
    case stickyNote
    case flashcard
    case progressTracker
}

// MARK: - Widget Frame

public struct WidgetFrame: Codable, Equatable {
    public var position: CGPoint
    public var size: CGSize
    public var rotation: CGFloat

    enum CodingKeys: String, CodingKey {
        case posX, posY, width, height, rotation
    }

    public init(position: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(CGFloat.self, forKey: .posX)
        let y = try c.decode(CGFloat.self, forKey: .posY)
        position = CGPoint(x: x, y: y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        size = CGSize(width: w, height: h)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(rotation, forKey: .rotation)
    }

    public var boundingRect: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Checklist Priority

public enum ChecklistPriority: String, Codable, Equatable, CaseIterable {
    case none
    case low
    case medium
    case high
}

// MARK: - Checklist Item

public struct ChecklistItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var isChecked: Bool
    public var priority: ChecklistPriority

    public init(id: UUID = UUID(), text: String = "", isChecked: Bool = false, priority: ChecklistPriority = .none) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
        self.priority = priority
    }
}

// MARK: - Table Cell

public struct TableCell: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

// MARK: - Callout Style

public enum CalloutStyle: String, Codable, Equatable, CaseIterable {
    case note
    case important
    case tip
    case warning
}

// MARK: - Sticky Note Color

public enum StickyNoteColor: String, Codable, Equatable, CaseIterable {
    case yellow
    case pink
    case blue
    case green
    case purple
}

// MARK: - Widget Payload

public enum WidgetPayload: Codable, Equatable {
    case checklist(title: String, items: [ChecklistItem])
    case quickTable(title: String, columns: Int, rows: Int, cells: [TableCell], hasHeaderRow: Bool)
    case calloutBox(title: String, body: String, style: CalloutStyle)
    case referenceCard(title: String, body: String)
    case stickyNote(body: String, color: StickyNoteColor)
    case flashcard(front: String, back: String, isFlipped: Bool, confidenceLevel: Int)
    case progressTracker(title: String, current: Int, total: Int)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case title, items
        case columns, rows, cells, hasHeaderRow
        case body, style
        case color
        case front, back, isFlipped, confidenceLevel
        case current, total
    }

    private enum PayloadType: String, Codable {
        case checklist, quickTable, calloutBox, referenceCard
        case stickyNote, flashcard, progressTracker
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(PayloadType.self, forKey: .type)
        switch kind {
        case .checklist:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let items = try c.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
            self = .checklist(title: title, items: items)
        case .quickTable:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 2
            let rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 3
            let cells = try c.decodeIfPresent([TableCell].self, forKey: .cells) ?? []
            let hasHeaderRow = try c.decodeIfPresent(Bool.self, forKey: .hasHeaderRow) ?? false
            self = .quickTable(title: title, columns: columns, rows: rows, cells: cells, hasHeaderRow: hasHeaderRow)
        case .calloutBox:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            let style = try c.decodeIfPresent(CalloutStyle.self, forKey: .style) ?? .note
            self = .calloutBox(title: title, body: body, style: style)
        case .referenceCard:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            self = .referenceCard(title: title, body: body)
        case .stickyNote:
            let body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            let color = try c.decodeIfPresent(StickyNoteColor.self, forKey: .color) ?? .yellow
            self = .stickyNote(body: body, color: color)
        case .flashcard:
            let front = try c.decodeIfPresent(String.self, forKey: .front) ?? ""
            let back = try c.decodeIfPresent(String.self, forKey: .back) ?? ""
            let isFlipped = try c.decodeIfPresent(Bool.self, forKey: .isFlipped) ?? false
            let confidenceLevel = try c.decodeIfPresent(Int.self, forKey: .confidenceLevel) ?? 0
            self = .flashcard(front: front, back: back, isFlipped: isFlipped, confidenceLevel: confidenceLevel)
        case .progressTracker:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
            let total = try c.decodeIfPresent(Int.self, forKey: .total) ?? WidgetConstants.defaultProgressTotal
            self = .progressTracker(title: title, current: current, total: total)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .checklist(let title, let items):
            try c.encode(PayloadType.checklist, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(items, forKey: .items)
        case .quickTable(let title, let columns, let rows, let cells, let hasHeaderRow):
            try c.encode(PayloadType.quickTable, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(columns, forKey: .columns)
            try c.encode(rows, forKey: .rows)
            try c.encode(cells, forKey: .cells)
            try c.encode(hasHeaderRow, forKey: .hasHeaderRow)
        case .calloutBox(let title, let body, let style):
            try c.encode(PayloadType.calloutBox, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(body, forKey: .body)
            try c.encode(style, forKey: .style)
        case .referenceCard(let title, let body):
            try c.encode(PayloadType.referenceCard, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(body, forKey: .body)
        case .stickyNote(let body, let color):
            try c.encode(PayloadType.stickyNote, forKey: .type)
            try c.encode(body, forKey: .body)
            try c.encode(color, forKey: .color)
        case .flashcard(let front, let back, let isFlipped, let confidenceLevel):
            try c.encode(PayloadType.flashcard, forKey: .type)
            try c.encode(front, forKey: .front)
            try c.encode(back, forKey: .back)
            try c.encode(isFlipped, forKey: .isFlipped)
            try c.encode(confidenceLevel, forKey: .confidenceLevel)
        case .progressTracker(let title, let current, let total):
            try c.encode(PayloadType.progressTracker, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(current, forKey: .current)
            try c.encode(total, forKey: .total)
        }
    }
}

// MARK: - Note Widget

public struct NoteWidget: Codable, Identifiable, Equatable {
    public let id: UUID
    public var kind: WidgetKind
    public var frame: WidgetFrame
    public var payload: WidgetPayload
    public var zIndex: Int
    public var isLocked: Bool
    public var placedAt: Date
    public var borderColorComponents: [Double]?

    enum CodingKeys: String, CodingKey {
        case id, kind, frame, payload, zIndex, isLocked, placedAt
        case borderColorComponents
    }

    public init(
        id: UUID = UUID(),
        kind: WidgetKind,
        frame: WidgetFrame,
        payload: WidgetPayload,
        zIndex: Int = 0,
        isLocked: Bool = false,
        placedAt: Date = Date(),
        borderColorComponents: [Double]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.payload = payload
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.placedAt = placedAt
        self.borderColorComponents = borderColorComponents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        frame = try c.decode(WidgetFrame.self, forKey: .frame)
        payload = try c.decode(WidgetPayload.self, forKey: .payload)
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        placedAt = try c.decodeIfPresent(Date.self, forKey: .placedAt) ?? Date()
        borderColorComponents = try c.decodeIfPresent([Double].self, forKey: .borderColorComponents)
    }

    // MARK: - Factory Methods

    public static func makeChecklist(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .checklist,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultChecklistSize
            ),
            payload: .checklist(title: "", items: [])
        )
    }

    public static func makeQuickTable(
        at position: CGPoint,
        columns: Int = 2,
        rows: Int = 3
    ) -> NoteWidget {
        let cells = (0 ..< columns * rows).map { _ in TableCell() }
        return NoteWidget(
            kind: .quickTable,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultTableSize
            ),
            payload: .quickTable(title: "", columns: columns, rows: rows, cells: cells, hasHeaderRow: true)
        )
    }

    public static func makeCalloutBox(
        at position: CGPoint,
        style: CalloutStyle = .note
    ) -> NoteWidget {
        NoteWidget(
            kind: .calloutBox,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultCalloutSize
            ),
            payload: .calloutBox(title: "", body: "", style: style)
        )
    }

    public static func makeReferenceCard(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .referenceCard,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultReferenceSize
            ),
            payload: .referenceCard(title: "", body: "")
        )
    }

    public static func makeStickyNote(at position: CGPoint, color: StickyNoteColor = .yellow) -> NoteWidget {
        NoteWidget(
            kind: .stickyNote,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultStickyNoteSize
            ),
            payload: .stickyNote(body: "", color: color)
        )
    }

    public static func makeFlashcard(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .flashcard,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultFlashcardSize
            ),
            payload: .flashcard(front: "", back: "", isFlipped: false, confidenceLevel: 0)
        )
    }

    public static func makeProgressTracker(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .progressTracker,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultProgressTrackerSize
            ),
            payload: .progressTracker(title: "", current: 0, total: WidgetConstants.defaultProgressTotal)
        )
    }
}

// MARK: - Constants

public enum WidgetConstants {
    public static let maxWidgetsPerPage = 20
    public static let widgetWarningThreshold = 15
    public static let minimumWidth: CGFloat = 120
    public static let minimumHeight: CGFloat = 60
    public static let defaultChecklistSize = CGSize(width: 240, height: 200)
    public static let defaultTableSize = CGSize(width: 300, height: 240)
    public static let defaultCalloutSize = CGSize(width: 260, height: 120)
    public static let defaultReferenceSize = CGSize(width: 260, height: 160)
    public static let defaultStickyNoteSize = CGSize(width: 200, height: 200)
    public static let defaultFlashcardSize = CGSize(width: 280, height: 180)
    public static let defaultProgressTrackerSize = CGSize(width: 260, height: 100)
    public static let snapDistance: CGFloat = 6
    public static let leftMarginFraction: CGFloat = 0.15
    public static let rightMarginFraction: CGFloat = 0.85
    public static let topMarginFraction: CGFloat = 0.10
    public static let handleTolerance: CGFloat = 20
    public static let handleRadius: CGFloat = 6
    public static let cardCornerRadius: CGFloat = 8
    public static let selectionBorderWidth: CGFloat = 2
    public static let selectionBorderOpacity: CGFloat = 0.6
    public static let duplicateOffset: CGFloat = 20
    public static let saveDebounce: TimeInterval = 0.8
    public static let titleFontSize: CGFloat = 14
    public static let bodyFontSize: CGFloat = 12
    public static let checkboxSize: CGFloat = 18
    public static let cellPadding: CGFloat = 8
    public static let containerPadding: CGFloat = 12
    public static let defaultProgressTotal: Int = 10
    public static let borderOpacity: CGFloat = 0.3
    public static let borderWidth: CGFloat = 1
}

// MARK: - Display helpers

extension ChecklistPriority {
    public var displayName: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    public var iconName: String {
        switch self {
        case .none:   return "circle"
        case .low:    return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high:   return "exclamationmark.circle"
        }
    }
}

extension CalloutStyle {
    public var displayName: String {
        switch self {
        case .note:      return "Note"
        case .important: return "Important"
        case .tip:       return "Tip"
        case .warning:   return "Warning"
        }
    }
}

extension StickyNoteColor {
    public var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .pink:   return "Pink"
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .purple: return "Purple"
        }
    }
}
