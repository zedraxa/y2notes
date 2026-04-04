import Foundation

// MARK: - Audio session — a single recording linked to a notebook

/// Represents one continuous audio recording session (e.g. a lecture).
/// All timeline events reference the session's start time so they can
/// be resolved to an absolute playback offset.
struct AudioSession: Identifiable, Codable, Hashable {
    let id: UUID
    /// The notebook this recording belongs to.
    var notebookID: UUID
    /// User-editable session title (defaults to date string).
    var title: String
    /// Absolute wall-clock time the recording started.
    let startedAt: Date
    /// Absolute wall-clock time the recording ended (nil while recording).
    var endedAt: Date?
    /// Duration in seconds (computed from file on import, or endedAt − startedAt).
    var duration: TimeInterval
    /// Relative path to the audio file inside the app's Documents directory.
    var filename: String
    /// MIME type of the stored audio (e.g. "audio/m4a").
    var mimeType: String

    init(
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

    /// Identity-only hashing for stable collection behaviour.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioSession, rhs: AudioSession) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Timeline event kinds

/// Discriminator for the different actions that can appear on a timeline.
enum TimelineEventKind: String, Codable, CaseIterable {
    /// A stroke (or set of strokes) was drawn on the canvas.
    case stroke
    /// The user navigated to a different page.
    case page
    /// A navigation action occurred (bookmark, search jump, back/forward).
    case navigation
    /// A sticker was placed.
    case sticker
    /// A shape was placed or resized.
    case shape
    /// An attachment was added.
    case attachment
    /// A text-entry action occurred (typed or OCR).
    case text
}

// MARK: - Timeline event — a single timestamped action

/// A discrete, timestamped action that occurred during an audio recording
/// session.  Events form a sparse timeline that can be binary-searched to
/// find the nearest note action for any playback position.
///
/// The `offset` is seconds from the parent `AudioSession.startedAt`.
/// Storing offsets (not absolute dates) keeps playback math simple and
/// makes events relocatable if a session is trimmed.
struct TimelineEvent: Identifiable, Codable, Hashable {
    let id: UUID
    /// The audio session this event belongs to.
    var sessionID: UUID
    /// Seconds from `AudioSession.startedAt`.
    var offset: TimeInterval
    /// What kind of action this event represents.
    var kind: TimelineEventKind
    /// The note that was active when the event occurred.
    var noteID: UUID
    /// 0-based page index within the note.
    var pageIndex: Int
    /// Kind-specific payload (see `StrokeEvent`, `PageEvent`, etc.).
    var payload: TimelineEventPayload

    init(
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

    /// Identity-only hashing.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TimelineEvent, rhs: TimelineEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Event payloads

/// A type-safe union of event-specific data.
/// Each case carries a lightweight struct with only the metadata needed
/// for timeline display and playback synchronisation.
enum TimelineEventPayload: Codable, Equatable {
    case stroke(StrokeEvent)
    case page(PageEvent)
    case navigation(NavigationEvent)
    /// Generic marker for sticker / shape / attachment / text actions.
    case object(ObjectEvent)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum PayloadType: String, Codable {
        case stroke, page, navigation, object
    }

    func encode(to encoder: Encoder) throws {
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

    init(from decoder: Decoder) throws {
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

/// Metadata for a drawing stroke captured during recording.
struct StrokeEvent: Codable, Equatable {
    /// Number of strokes in this batch (1 for single stroke, >1 for undo-group).
    var strokeCount: Int
    /// Bounding-box origin X of the affected region (page coordinates).
    var regionX: Double
    /// Bounding-box origin Y of the affected region (page coordinates).
    var regionY: Double
    /// Bounding-box width.
    var regionWidth: Double
    /// Bounding-box height.
    var regionHeight: Double
    /// The drawing tool that produced the stroke.
    var toolName: String

    init(
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

/// Metadata for a page-change action during recording.
struct PageEvent: Codable, Equatable {
    /// The page index the user came from.
    var fromPage: Int
    /// The page index the user navigated to.
    var toPage: Int
    /// How the page change was triggered.
    var trigger: PageChangeTrigger

    init(fromPage: Int, toPage: Int, trigger: PageChangeTrigger = .swipe) {
        self.fromPage = fromPage
        self.toPage = toPage
        self.trigger = trigger
    }
}

/// How a page transition was initiated.
enum PageChangeTrigger: String, Codable, Equatable {
    /// Horizontal swipe gesture.
    case swipe
    /// Thumbnail sidebar tap.
    case thumbnail
    /// Page-number input or jump.
    case jump
    /// Programmatic (e.g. search result navigation).
    case programmatic
}

// MARK: - Navigation event

/// Metadata for a navigation action (bookmark jump, search, back/forward).
struct NavigationEvent: Codable, Equatable {
    /// The kind of navigation that occurred.
    var action: NavigationAction
    /// Optional label (e.g. bookmark name, search query).
    var label: String

    init(action: NavigationAction, label: String = "") {
        self.action = action
        self.label = label
    }
}

/// The type of navigation action.
enum NavigationAction: String, Codable, Equatable, CaseIterable {
    case bookmarkJump
    case searchJump
    case back
    case forward
    case externalLink
}

// MARK: - Object event (sticker, shape, attachment, text)

/// Generic metadata for object-level actions on the canvas.
struct ObjectEvent: Codable, Equatable {
    /// The UUID of the affected object (sticker, shape, attachment).
    var objectID: UUID
    /// Human-readable type name (e.g. "sticker", "shape", "attachment").
    var objectType: String
    /// The sub-action performed.
    var action: ObjectAction

    init(objectID: UUID, objectType: String, action: ObjectAction = .placed) {
        self.objectID = objectID
        self.objectType = objectType
        self.action = action
    }
}

/// Sub-actions for canvas objects.
enum ObjectAction: String, Codable, Equatable {
    case placed
    case moved
    case resized
    case deleted
    case edited
}

// MARK: - Constants

enum AudioTimelineConstants {
    /// Maximum events stored per audio session before oldest are pruned.
    static let maxEventsPerSession = 10_000
    /// Minimum seconds between consecutive stroke events (coalesce rapid drawing).
    static let strokeCoalesceInterval: TimeInterval = 0.3
    /// Minimum seconds between consecutive page events (debounce rapid flips).
    static let pageDebounceInterval: TimeInterval = 0.5
    /// Supported audio file extensions.
    static let supportedExtensions = ["m4a", "mp3", "wav", "caf"]
    /// Default MIME type for new recordings.
    static let defaultMimeType = "audio/m4a"
    /// Save debounce for timeline persistence.
    static let saveDebounce: TimeInterval = 1.0
    /// Snap-to-event tolerance when seeking (seconds).
    static let seekSnapTolerance: TimeInterval = 2.0
}
