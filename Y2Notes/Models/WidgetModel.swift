import Foundation
import CoreGraphics

// MARK: - Widget Kind

/// The type of widget that can be placed on a note page.
enum WidgetKind: String, Codable, CaseIterable, Equatable {
    case checklist
    case quickTable
    case calloutBox
    case referenceCard
    case stickyNote
    case flashcard
    case progressTracker
}

// MARK: - Widget Frame

/// Position and size of a widget on the page canvas.
struct WidgetFrame: Codable, Equatable {
    /// Centre point in page coordinates (points).
    var position: CGPoint
    /// Display size in page coordinates.
    var size: CGSize
    /// Rotation in radians (reserved for P1 – always 0 for now).
    var rotation: CGFloat

    // Custom Codable – CGPoint / CGSize / CGFloat are not Codable by default.
    enum CodingKeys: String, CodingKey {
        case posX, posY, width, height, rotation
    }

    init(position: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(CGFloat.self, forKey: .posX)
        let y = try c.decode(CGFloat.self, forKey: .posY)
        position = CGPoint(x: x, y: y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        size = CGSize(width: w, height: h)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(rotation, forKey: .rotation)
    }

    /// The bounding rectangle in page coordinates (origin at top-left of the widget).
    var boundingRect: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Checklist Item

/// A single row in a checklist widget.
struct ChecklistItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String = "", isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

// MARK: - Table Cell

/// A single cell in a quick-table widget.
struct TableCell: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

// MARK: - Callout Style

/// Visual style for a callout-box widget.
enum CalloutStyle: String, Codable, Equatable, CaseIterable {
    /// Informational note.
    case note
    /// Warning / attention.
    case important
    /// Helpful hint.
    case tip
    /// Danger / caution.
    case warning
}

// MARK: - Sticky Note Color

/// Pastel background colour for a sticky-note widget.
enum StickyNoteColor: String, Codable, Equatable, CaseIterable {
    case yellow
    case pink
    case blue
    case green
    case purple
}

// MARK: - Widget Payload

/// Type-specific content carried by a widget.
enum WidgetPayload: Codable, Equatable {
    case checklist(title: String, items: [ChecklistItem])
    case quickTable(title: String, columns: Int, rows: Int, cells: [TableCell])
    case calloutBox(title: String, body: String, style: CalloutStyle)
    case referenceCard(title: String, body: String)
    case stickyNote(body: String, color: StickyNoteColor)
    case flashcard(front: String, back: String, isFlipped: Bool)
    case progressTracker(title: String, current: Int, total: Int)

    // MARK: - Codable

    /// Discriminator key written alongside the associated values.
    private enum CodingKeys: String, CodingKey {
        case type
        case title, items
        case columns, rows, cells
        case body, style
        case color
        case front, back, isFlipped
        case current, total
    }

    private enum PayloadType: String, Codable {
        case checklist, quickTable, calloutBox, referenceCard
        case stickyNote, flashcard, progressTracker
    }

    init(from decoder: Decoder) throws {
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
            self = .quickTable(title: title, columns: columns, rows: rows, cells: cells)
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
            self = .flashcard(front: front, back: back, isFlipped: isFlipped)
        case .progressTracker:
            let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            let current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
            let total = try c.decodeIfPresent(Int.self, forKey: .total) ?? WidgetConstants.defaultProgressTotal
            self = .progressTracker(title: title, current: current, total: total)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .checklist(let title, let items):
            try c.encode(PayloadType.checklist, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(items, forKey: .items)
        case .quickTable(let title, let columns, let rows, let cells):
            try c.encode(PayloadType.quickTable, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(columns, forKey: .columns)
            try c.encode(rows, forKey: .rows)
            try c.encode(cells, forKey: .cells)
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
        case .flashcard(let front, let back, let isFlipped):
            try c.encode(PayloadType.flashcard, forKey: .type)
            try c.encode(front, forKey: .front)
            try c.encode(back, forKey: .back)
            try c.encode(isFlipped, forKey: .isFlipped)
        case .progressTracker(let title, let current, let total):
            try c.encode(PayloadType.progressTracker, forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(current, forKey: .current)
            try c.encode(total, forKey: .total)
        }
    }
}

// MARK: - Note Widget

/// A single widget instance placed on a note page.
struct NoteWidget: Codable, Identifiable, Equatable {
    let id: UUID
    /// Kind of widget (checklist, table, callout, reference card).
    var kind: WidgetKind
    /// Position and size on the page canvas.
    var frame: WidgetFrame
    /// Type-specific content.
    var payload: WidgetPayload
    /// Ordering index within the widget layer.
    var zIndex: Int
    /// When true the widget cannot be moved or resized.
    var isLocked: Bool
    /// Date the widget was placed on the page.
    var placedAt: Date
    /// Optional custom border colour, RGBA 0…1.
    var borderColorComponents: [Double]?

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, kind, frame, payload, zIndex, isLocked, placedAt
        case borderColorComponents
    }

    init(
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

    init(from decoder: Decoder) throws {
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

    /// Creates a checklist widget at the given centre position with default content.
    static func makeChecklist(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .checklist,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultChecklistSize
            ),
            payload: .checklist(title: "", items: [])
        )
    }

    /// Creates a quick-table widget at the given centre position with the specified dimensions.
    static func makeQuickTable(
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
            payload: .quickTable(title: "", columns: columns, rows: rows, cells: cells)
        )
    }

    /// Creates a callout-box widget at the given centre position with the specified style.
    static func makeCalloutBox(
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

    /// Creates a reference-card widget at the given centre position with default content.
    static func makeReferenceCard(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .referenceCard,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultReferenceSize
            ),
            payload: .referenceCard(title: "", body: "")
        )
    }

    /// Creates a sticky-note widget at the given centre position with the specified colour.
    static func makeStickyNote(at position: CGPoint, color: StickyNoteColor = .yellow) -> NoteWidget {
        NoteWidget(
            kind: .stickyNote,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultStickyNoteSize
            ),
            payload: .stickyNote(body: "", color: color)
        )
    }

    /// Creates a flashcard widget at the given centre position with empty front and back.
    static func makeFlashcard(at position: CGPoint) -> NoteWidget {
        NoteWidget(
            kind: .flashcard,
            frame: WidgetFrame(
                position: position,
                size: WidgetConstants.defaultFlashcardSize
            ),
            payload: .flashcard(front: "", back: "", isFlipped: false)
        )
    }

    /// Creates a progress-tracker widget at the given centre position with a default goal of 10.
    static func makeProgressTracker(at position: CGPoint) -> NoteWidget {
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

enum WidgetConstants {
    static let maxWidgetsPerPage = 20
    static let widgetWarningThreshold = 15

    /// Minimum display width in page points.
    static let minimumWidth: CGFloat = 120
    /// Minimum display height in page points.
    static let minimumHeight: CGFloat = 60

    /// Default card size for newly placed checklist widgets.
    static let defaultChecklistSize = CGSize(width: 240, height: 200)
    /// Default card size for newly placed table widgets.
    static let defaultTableSize = CGSize(width: 300, height: 240)
    /// Default card size for newly placed callout widgets.
    static let defaultCalloutSize = CGSize(width: 260, height: 120)
    /// Default card size for newly placed reference-card widgets.
    static let defaultReferenceSize = CGSize(width: 260, height: 160)
    /// Default card size for newly placed sticky-note widgets.
    static let defaultStickyNoteSize = CGSize(width: 200, height: 200)
    /// Default card size for newly placed flashcard widgets.
    static let defaultFlashcardSize = CGSize(width: 280, height: 180)
    /// Default card size for newly placed progress-tracker widgets.
    static let defaultProgressTrackerSize = CGSize(width: 260, height: 100)

    /// Distance (points) for snap-to-guide behaviour.
    static let snapDistance: CGFloat = 6
    /// Fractional position of the left margin snap guide (relative to page width).
    static let leftMarginFraction: CGFloat = 0.15
    /// Fractional position of the right margin snap guide (relative to page width).
    static let rightMarginFraction: CGFloat = 0.85
    /// Fractional position of the top margin snap guide (relative to page height).
    static let topMarginFraction: CGFloat = 0.10
    /// Hit-test tolerance around corner handles (points).
    static let handleTolerance: CGFloat = 20
    /// Visual handle radius drawn at corners when selected.
    static let handleRadius: CGFloat = 6

    /// Corner radius for the widget card background.
    static let cardCornerRadius: CGFloat = 8
    /// Selection border width.
    static let selectionBorderWidth: CGFloat = 2
    /// Selection border opacity.
    static let selectionBorderOpacity: CGFloat = 0.6

    /// Offset used when duplicating a widget.
    static let duplicateOffset: CGFloat = 20

    /// Debounce interval (seconds) before persisting widget changes.
    static let saveDebounce: TimeInterval = 0.8

    /// Font size for widget titles.
    static let titleFontSize: CGFloat = 14
    /// Font size for widget body text.
    static let bodyFontSize: CGFloat = 12
    /// Size of checklist checkbox controls.
    static let checkboxSize: CGFloat = 18
    /// Inner padding for table cells.
    static let cellPadding: CGFloat = 8
    /// Outer padding inside the widget container.
    static let containerPadding: CGFloat = 12
    /// Default total goal value for newly placed progress-tracker widgets.
    static let defaultProgressTotal: Int = 10
    /// Default border opacity.
    static let borderOpacity: CGFloat = 0.3
}
