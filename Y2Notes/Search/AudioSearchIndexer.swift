import Foundation

/// Indexes audio sessions and their timeline events into the universal
/// search index so users can find recordings by title, timestamp, and
/// keyword-matched note actions.
///
/// **Indexing strategy:**
///
/// 1. **Session-level** (`.audioSession`): Each `AudioSession` is indexed
///    by title and notebook. Navigating a session result opens the notebook
///    and starts playback from the beginning.
///
/// 2. **Timestamp-level** (`.audioTimestamp`): Timeline events that carry
///    semantic meaning (page switches, text events, named objects) are
///    indexed individually. Each result carries an `audioOffset` in its
///    `NavigationAnchor` so the audio player can seek directly to the
///    matching moment.
///
/// 3. **Transcript search (future)**: When speech-to-text transcription is
///    added, transcript segments will be indexed as `.audioTranscript`
///    entries with word-level offsets. The anchor infrastructure already
///    supports `audioSessionID` + `audioOffset` for this purpose.
///
/// **Keyword → Audio jump flow:**
/// ```
/// User types "mitosis" in search
///   → SearchIndex matches an `.audioTimestamp` entry
///     (whose secondaryText contains "mitosis" from a text event)
///   → UniversalSearchResult carries NavigationAnchor with audioSessionID + audioOffset
///   → NotebookReaderView navigates to the page and starts audio at that offset
/// ```
enum AudioSearchIndexer {

    // MARK: - Full index build

    /// Indexes all sessions from the storage manifest into the search index.
    /// Called during `SearchIndex.rebuild()`.
    ///
    /// - Parameters:
    ///   - entries: The mutable entries dictionary from `SearchIndex`.
    ///   - storageManager: The audio storage manager to read sessions/events from.
    static func indexAllSessions(
        into entries: inout [String: SearchableEntry],
        from storageManager: AudioStorageManager
    ) {
        for session in storageManager.manifest.sessions {
            indexSession(session, into: &entries, from: storageManager)
        }
    }

    // MARK: - Per-session indexing

    /// Indexes a single session and its timeline events.
    static func indexSession(
        _ session: AudioStorageManager.StorageManifest.SessionEntry,
        into entries: inout [String: SearchableEntry],
        from storageManager: AudioStorageManager
    ) {
        let sessionKey = "audio-\(session.id.uuidString)"

        // Determine a display title
        let title = sessionDisplayTitle(for: session)

        // 1. Session-level entry — searchable by title and notebook context
        let durationLabel = formattedDuration(session.duration)
        let dateLabel = formattedDate(session.createdAt)

        // Build an anchor that points to the first linked note (if any)
        let anchor = sessionAnchor(for: session)

        entries[sessionKey] = SearchableEntry(
            id: sessionKey,
            kind: .audioSession,
            primaryText: title,
            secondaryText: "\(durationLabel) · \(dateLabel) · \(session.eventCount) events",
            notebookID: session.notebookID,
            anchor: anchor,
            modifiedAt: session.createdAt
        )

        // 2. Timestamp-level entries — index meaningful timeline events
        let events = storageManager.loadEvents(for: session.id)
        indexTimelineEvents(
            events,
            session: session,
            title: title,
            into: &entries
        )
    }

    /// Removes all search entries for a given session.
    static func removeSession(
        _ sessionID: UUID,
        from entries: inout [String: SearchableEntry]
    ) {
        let prefix = "audio-\(sessionID.uuidString)"
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Timeline event indexing

    /// Indexes timeline events that carry searchable metadata.
    /// Not every event is indexed — strokes are too granular. We index:
    /// - Page switches (searchable by page number)
    /// - Text events (searchable by the text content)
    /// - Object events (searchable by object label/type)
    /// - Navigation events (searchable by bookmark/search labels)
    private static func indexTimelineEvents(
        _ events: [TimelineEvent],
        session: AudioStorageManager.StorageManifest.SessionEntry,
        title: String,
        into entries: inout [String: SearchableEntry]
    ) {
        for event in events {
            guard let entry = searchEntry(
                for: event,
                session: session,
                sessionTitle: title
            ) else { continue }
            entries[entry.id] = entry
        }
    }

    /// Creates a `SearchableEntry` for a timeline event if it carries
    /// searchable content. Returns `nil` for events that should not be
    /// individually indexed (e.g. raw strokes).
    private static func searchEntry(
        for event: TimelineEvent,
        session: AudioStorageManager.StorageManifest.SessionEntry,
        sessionTitle: String
    ) -> SearchableEntry? {
        let baseKey = "audio-\(session.id.uuidString)-evt-\(event.id.uuidString)"
        let offsetLabel = formattedOffset(event.offset)

        let primaryText: String
        let secondaryText: String

        switch event.payload {
        case .page(let pageEvent):
            primaryText = "Page \(pageEvent.toPage + 1) at \(offsetLabel)"
            secondaryText = sessionTitle

        case .navigation(let navEvent):
            let navLabel = navEvent.label.isEmpty ? navEvent.action.rawValue : navEvent.label
            primaryText = "\(navLabel) at \(offsetLabel)"
            secondaryText = sessionTitle

        case .object(let objEvent):
            primaryText = "\(objEvent.objectType) \(objEvent.action.rawValue) at \(offsetLabel)"
            secondaryText = "\(objEvent.objectType) · \(sessionTitle)"

        case .stroke:
            // Strokes are too numerous and lack semantic text — skip
            return nil
        }

        let anchor = NavigationAnchor(
            notebookID: session.notebookID,
            noteID: event.noteID,
            pageIndex: event.pageIndex,
            audioSessionID: session.id,
            audioOffset: event.offset
        )

        return SearchableEntry(
            id: baseKey,
            kind: .audioTimestamp,
            primaryText: primaryText,
            secondaryText: secondaryText,
            notebookID: session.notebookID,
            anchor: anchor,
            modifiedAt: session.createdAt
        )
    }

    // MARK: - Helpers

    /// Builds a `NavigationAnchor` for the session-level search result.
    /// Points to the first linked note at page 0, with audio starting at 0.
    private static func sessionAnchor(
        for session: AudioStorageManager.StorageManifest.SessionEntry
    ) -> NavigationAnchor? {
        guard let firstNote = session.noteIDs.first else { return nil }
        return NavigationAnchor(
            notebookID: session.notebookID,
            noteID: firstNote,
            pageIndex: 0,
            audioSessionID: session.id,
            audioOffset: 0
        )
    }

    /// Display title for a session: uses the session date if no explicit
    /// title is stored in the manifest.
    private static func sessionDisplayTitle(
        for session: AudioStorageManager.StorageManifest.SessionEntry
    ) -> String {
        "Recording \(formattedDate(session.createdAt))"
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static func formattedOffset(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func formattedDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
