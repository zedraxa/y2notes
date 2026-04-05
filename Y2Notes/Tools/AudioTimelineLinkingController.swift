import Foundation
import Combine

// MARK: - Bidirectional linking controller

/// Manages the bidirectional relationship between audio playback position
/// and note canvas state.
///
/// **Note → Audio** (tap note → jump audio):
/// The user taps a stroke region or page event; the controller seeks the
/// audio player to the matching `TimelineEvent.offset`.
///
/// **Audio → Note** (scrub audio → jump note):
/// As the audio playback position changes, the controller finds the closest
/// timeline event and drives page switching, zoom restoration, and a
/// transient highlight on the matched canvas region.
///
/// The controller is intentionally a thin coordination layer — it depends
/// on delegate callbacks rather than owning audio or canvas views directly.
@Observable
final class AudioTimelineLinkingController {

    // MARK: - Published state

    /// The audio session currently linked to the editor.
    var activeSession: AudioSession?

    /// Sorted timeline events for the active session (by offset ascending).
    /// Pre-sorted once on session load so look-ups are O(log n).
    private(set) var sortedEvents: [TimelineEvent] = []

    /// The timeline event closest to the current playback position.
    /// Updated whenever `currentPlaybackOffset` changes. Observers (e.g. the
    /// editor view) can watch this to drive page-switch / highlight animations.
    private(set) var currentEvent: TimelineEvent?

    /// Current audio playback offset in seconds from session start.
    /// Set by the audio player on a display-link cadence.
    var currentPlaybackOffset: TimeInterval = 0 {
        didSet { resolveCurrentEvent() }
    }

    /// When true, audio→note navigation is active (the user is scrubbing or
    /// playback is running). UI should show the timeline highlight bar and
    /// auto-navigate pages. When false only note→audio taps are honoured.
    var isAudioDriving: Bool = false

    /// Transient highlight state — set when the controller wants the canvas
    /// to pulse a region. The editor clears this after the animation completes.
    private(set) var highlightMoment: HighlightMoment?

    /// The page the controller wants the editor to display. `nil` means
    /// "don't change the page". The editor should observe this and call
    /// `acknowledgePageSwitch()` after completing the transition.
    private(set) var requestedPageSwitch: PageSwitchRequest?

    // MARK: - Delegate callbacks

    /// Called when the controller wants the audio player to seek.
    /// The host sets this closure when wiring up the controller.
    var onSeekAudio: ((_ offset: TimeInterval) -> Void)?

    /// Called when the controller wants the canvas to restore zoom to a
    /// region. The host sets this closure; the controller invokes it with
    /// the bounding rect in page coordinates.
    var onRestoreZoom: ((_ region: CanvasRegion) -> Void)?

    // MARK: - Init

    init() {}

    // MARK: - Session lifecycle

    /// Load a session and its events. Events are sorted once by offset.
    func attach(session: AudioSession, events: [TimelineEvent]) {
        activeSession = session
        sortedEvents = events.sorted { $0.offset < $1.offset }
        currentPlaybackOffset = 0
        currentEvent = nil
        highlightMoment = nil
        requestedPageSwitch = nil
        isAudioDriving = false
    }

    /// Tear down the current session link.
    func detach() {
        activeSession = nil
        sortedEvents = []
        currentEvent = nil
        currentPlaybackOffset = 0
        highlightMoment = nil
        requestedPageSwitch = nil
        isAudioDriving = false
    }

    // MARK: - Note → Audio (tap note → jump audio)

    /// The user tapped a stroke or region on the canvas. Find the closest
    /// timeline event at or before the current page and seek audio there.
    ///
    /// - Parameters:
    ///   - noteID: The note the user is viewing.
    ///   - pageIndex: 0-based page index.
    ///   - tapX: Optional tap X in page coordinates (for stroke matching).
    ///   - tapY: Optional tap Y in page coordinates (for stroke matching).
    func tapNoteToJumpAudio(
        noteID: UUID,
        pageIndex: Int,
        tapX: Double? = nil,
        tapY: Double? = nil
    ) {
        guard activeSession != nil else { return }

        // Find events on this note + page, preferring stroke events near the tap.
        let candidates = sortedEvents.filter {
            $0.noteID == noteID && $0.pageIndex == pageIndex
        }
        guard !candidates.isEmpty else { return }

        let best: TimelineEvent
        if let x = tapX, let y = tapY {
            // Prefer the stroke event whose bounding box contains the tap point.
            if let hit = candidates
                .filter({ $0.kind == .stroke })
                .first(where: { event in
                    guard case .stroke(let s) = event.payload else { return false }
                    return x >= s.regionX
                        && x <= s.regionX + s.regionWidth
                        && y >= s.regionY
                        && y <= s.regionY + s.regionHeight
                }) {
                best = hit
            } else if let last = candidates.last {
                best = last
            } else {
                return // candidates verified non-empty above; defensive guard
            }
        } else {
            guard let last = candidates.last else { return }
            best = last
        }

        onSeekAudio?(best.offset)
        currentPlaybackOffset = best.offset
        emitHighlight(for: best)
    }

    /// The user tapped a specific timeline event (e.g. from a timeline list UI).
    func jumpAudioToEvent(_ event: TimelineEvent) {
        guard activeSession != nil else { return }
        onSeekAudio?(event.offset)
        currentPlaybackOffset = event.offset
        emitHighlight(for: event)
    }

    // MARK: - Audio → Note (scrub audio → jump note)

    /// Called on every playback tick (display-link cadence).
    /// Updates `currentPlaybackOffset` which triggers `resolveCurrentEvent()`.
    func updatePlaybackPosition(_ offset: TimeInterval) {
        guard isAudioDriving else { return }
        currentPlaybackOffset = offset
    }

    // MARK: - Page switch acknowledgement

    /// The editor calls this after it has completed the page transition
    /// requested by `requestedPageSwitch`.
    func acknowledgePageSwitch() {
        requestedPageSwitch = nil
    }

    /// The editor calls this after it has finished animating the highlight.
    func clearHighlight() {
        highlightMoment = nil
    }

    // MARK: - Internal resolution

    /// Binary-search `sortedEvents` for the event at or just before
    /// `currentPlaybackOffset`, applying `seekSnapTolerance`.
    private func resolveCurrentEvent() {
        guard !sortedEvents.isEmpty else {
            currentEvent = nil
            return
        }

        let idx = binarySearchFloor(
            sortedEvents,
            offset: currentPlaybackOffset
        )
        guard let idx else {
            currentEvent = sortedEvents.first
            requestPageSwitchIfNeeded(for: sortedEvents[0])
            return
        }
        let event = sortedEvents[idx]
        let previousEvent = currentEvent

        currentEvent = event

        // Only drive page-switch / highlight when audio is in control.
        guard isAudioDriving else { return }

        // If the event changed, fire side-effects.
        if previousEvent?.id != event.id {
            requestPageSwitchIfNeeded(for: event)
            restoreZoomIfNeeded(for: event)
            emitHighlight(for: event)
        }
    }

    /// Request the editor to switch pages if the event is on a different page
    /// than what we last requested.
    private func requestPageSwitchIfNeeded(for event: TimelineEvent) {
        let request = PageSwitchRequest(
            noteID: event.noteID,
            pageIndex: event.pageIndex
        )
        // Only emit if it's a new page.
        if requestedPageSwitch != request {
            requestedPageSwitch = request
        }
    }

    /// Ask the editor to zoom to the stroke region (if the event is a stroke).
    private func restoreZoomIfNeeded(for event: TimelineEvent) {
        guard case .stroke(let s) = event.payload else { return }
        let region = CanvasRegion(
            x: s.regionX,
            y: s.regionY,
            width: s.regionWidth,
            height: s.regionHeight
        )
        onRestoreZoom?(region)
    }

    /// Emit a transient highlight for the given event.
    private func emitHighlight(for event: TimelineEvent) {
        switch event.payload {
        case .stroke(let s):
            highlightMoment = HighlightMoment(
                noteID: event.noteID,
                pageIndex: event.pageIndex,
                region: CanvasRegion(
                    x: s.regionX,
                    y: s.regionY,
                    width: s.regionWidth,
                    height: s.regionHeight
                ),
                style: .strokePulse
            )
        case .page:
            highlightMoment = HighlightMoment(
                noteID: event.noteID,
                pageIndex: event.pageIndex,
                region: nil,
                style: .fullPageFlash
            )
        case .navigation:
            highlightMoment = HighlightMoment(
                noteID: event.noteID,
                pageIndex: event.pageIndex,
                region: nil,
                style: .fullPageFlash
            )
        case .object(let o):
            highlightMoment = HighlightMoment(
                noteID: event.noteID,
                pageIndex: event.pageIndex,
                region: nil,
                style: .objectHighlight(objectID: o.objectID)
            )
        }
    }

    // MARK: - Query helpers

    /// Returns all timeline events for a specific page, useful for rendering
    /// timeline markers in a page-level scrubber.
    func events(forNote noteID: UUID, page pageIndex: Int) -> [TimelineEvent] {
        sortedEvents.filter { $0.noteID == noteID && $0.pageIndex == pageIndex }
    }

    /// Returns the closest event to a given offset within the snap tolerance.
    func closestEvent(to offset: TimeInterval) -> TimelineEvent? {
        guard let idx = binarySearchFloor(sortedEvents, offset: offset) else {
            return sortedEvents.first
        }
        let event = sortedEvents[idx]
        if abs(event.offset - offset) <= AudioTimelineConstants.seekSnapTolerance {
            return event
        }
        // Check the next event too.
        let nextIdx = idx + 1
        if nextIdx < sortedEvents.count {
            let next = sortedEvents[nextIdx]
            if abs(next.offset - offset) < abs(event.offset - offset) {
                return next
            }
        }
        return event
    }

    // MARK: - Binary search

    /// Returns the index of the last event whose offset ≤ `offset`,
    /// or `nil` if all events are after `offset`.
    private func binarySearchFloor(
        _ events: [TimelineEvent],
        offset: TimeInterval
    ) -> Int? {
        guard !events.isEmpty else { return nil }
        var lo = 0
        var hi = events.count - 1
        var result: Int?
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if events[mid].offset <= offset {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }
}

// MARK: - Supporting types

/// A request for the editor to switch to a specific page.
struct PageSwitchRequest: Equatable {
    let noteID: UUID
    let pageIndex: Int
}

/// A bounding region in page coordinates.
struct CanvasRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// Describes a transient visual highlight the editor should render.
struct HighlightMoment: Equatable {
    let noteID: UUID
    let pageIndex: Int
    /// The region to highlight (nil = full page).
    let region: CanvasRegion?
    /// Visual style of the highlight.
    let style: HighlightStyle
}

/// How to render the highlight.
enum HighlightStyle: Equatable {
    /// A rounded-rect pulse over a stroke region.
    case strokePulse
    /// A brief full-page flash (for page/navigation events).
    case fullPageFlash
    /// Highlight a specific object (sticker, shape, attachment).
    case objectHighlight(objectID: UUID)
}
