import Foundation

// MARK: - Audio session

public struct AudioSession: Identifiable, Codable, Hashable {
    public let id: UUID
    public var notebookID: UUID
    public var title: String
    public let startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval
    public var filename: String
    public var mimeType: String

    public init(
        id: UUID = UUID(),
        notebookID: UUID,
        title: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        filename: String,
        mimeType: String = "audio/m4a"
    ) {
        self.id = id
        self.notebookID = notebookID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.filename = filename
        self.mimeType = mimeType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AudioSession, rhs: AudioSession) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Timeline event kinds

public enum TimelineEventKind: String, Codable, CaseIterable {
    case stroke
    case page
    case navigation
    case sticker
    case shape
    case attachment
    case text
}

// MARK: - Timeline event

public struct TimelineEvent: Identifiable, Codable, Hashable {
    public let id: UUID
    public var sessionID: UUID
    public var offset: TimeInterval
    public var kind: TimelineEventKind
    public var noteID: UUID
    public var pageIndex: Int
    public var payload: TimelineEventPayload

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        offset: TimeInterval,
        kind: TimelineEventKind,
        noteID: UUID,
        pageIndex: Int,
        payload: TimelineEventPayload
    ) {
        self.id = id
        self.sessionID = sessionID
        self.offset = offset
        self.kind = kind
        self.noteID = noteID
        self.pageIndex = pageIndex
        self.payload = payload
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Event payloads

public enum TimelineEventPayload: Codable, Equatable {
    case stroke(StrokeEvent)
    case page(PageEvent)
    case navigation(NavigationEvent)
    case object(ObjectEvent)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum PayloadType: String, Codable {
        case stroke, page, navigation, object
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stroke(let e):
            try container.encode(PayloadType.stroke, forKey: .type)
            try container.encode(e, forKey: .data)
        case .page(let e):
            try container.encode(PayloadType.page, forKey: .type)
            try container.encode(e, forKey: .data)
        case .navigation(let e):
            try container.encode(PayloadType.navigation, forKey: .type)
            try container.encode(e, forKey: .data)
        case .object(let e):
            try container.encode(PayloadType.object, forKey: .type)
            try container.encode(e, forKey: .data)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .stroke:
            self = .stroke(try container.decode(StrokeEvent.self, forKey: .data))
        case .page:
            self = .page(try container.decode(PageEvent.self, forKey: .data))
        case .navigation:
            self = .navigation(try container.decode(NavigationEvent.self, forKey: .data))
        case .object:
            self = .object(try container.decode(ObjectEvent.self, forKey: .data))
        }
    }
}

// MARK: - Stroke event

public struct StrokeEvent: Codable, Equatable {
    public var strokeCount: Int
    public var regionX: Double
    public var regionY: Double
    public var regionWidth: Double
    public var regionHeight: Double
    public var toolName: String

    public init(
        strokeCount: Int = 1,
        regionX: Double = 0,
        regionY: Double = 0,
        regionWidth: Double = 0,
        regionHeight: Double = 0,
        toolName: String = "pen"
    ) {
        self.strokeCount = strokeCount
        self.regionX = regionX
        self.regionY = regionY
        self.regionWidth = regionWidth
        self.regionHeight = regionHeight
        self.toolName = toolName
    }
}

// MARK: - Page event

public struct PageEvent: Codable, Equatable {
    public var fromPage: Int
    public var toPage: Int
    public var trigger: PageChangeTrigger

    public init(fromPage: Int, toPage: Int, trigger: PageChangeTrigger = .swipe) {
        self.fromPage = fromPage
        self.toPage = toPage
        self.trigger = trigger
    }
}

public enum PageChangeTrigger: String, Codable, Equatable {
    case swipe
    case thumbnail
    case jump
    case programmatic
}

// MARK: - Navigation event

public struct NavigationEvent: Codable, Equatable {
    public var action: NavigationAction
    public var label: String

    public init(action: NavigationAction, label: String = "") {
        self.action = action
        self.label = label
    }
}

public enum NavigationAction: String, Codable, Equatable, CaseIterable {
    case bookmarkJump
    case searchJump
    case back
    case forward
    case externalLink
}

// MARK: - Object event

public struct ObjectEvent: Codable, Equatable {
    public var objectID: UUID
    public var objectType: String
    public var action: ObjectAction

    public init(objectID: UUID, objectType: String, action: ObjectAction = .placed) {
        self.objectID = objectID
        self.objectType = objectType
        self.action = action
    }
}

public enum ObjectAction: String, Codable, Equatable {
    case placed
    case moved
    case resized
    case deleted
    case edited
}

// MARK: - Constants

public enum AudioTimelineConstants {
    public static let maxEventsPerSession = 10_000
    public static let strokeCoalesceInterval: TimeInterval = 0.3
    public static let pageDebounceInterval: TimeInterval = 0.5
    public static let supportedExtensions = ["m4a", "mp3", "wav", "caf"]
    public static let defaultMimeType = "audio/m4a"
    public static let saveDebounce: TimeInterval = 1.0
    public static let seekSnapTolerance: TimeInterval = 2.0
}
