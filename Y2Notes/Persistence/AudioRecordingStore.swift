import AVFoundation
import Foundation

/// Singleton-style store that manages audio recording lifecycle, file storage,
/// and session persistence.  Wraps `AVAudioRecorder` with a pre-warm pattern
/// so start latency is sub-frame.
///
/// **File layout**: Audio files live at
/// `Documents/Recordings/{sessionID}.m4a`.
/// Session metadata + timeline events are persisted to
/// `Documents/Recordings/sessions.json`.
///
/// **Storage integration**: Uses `AudioStorageManager` for manifest-based
/// session linking, autosave, crash recovery, and post-recording compression.
///
/// **Thread safety**: All published state is updated on the main actor.
/// Audio callbacks dispatch back to main before mutating state.
final class AudioRecordingStore: ObservableObject {

    // MARK: - Published State

    /// True while the recorder is actively capturing audio.
    @Published private(set) var isRecording: Bool = false

    /// The session currently being recorded (nil when idle).
    @Published private(set) var activeSession: AudioSession?

    /// Elapsed seconds since recording started, updated every second.
    @Published private(set) var elapsedTime: TimeInterval = 0

    /// All saved sessions, newest first.
    @Published private(set) var sessions: [AudioSession] = []

    /// Timeline events for the active session (in-memory, flushed on stop).
    @Published private(set) var activeEvents: [TimelineEvent] = []

    // MARK: - Recording Quality

    enum RecordingQuality: String, CaseIterable, Identifiable {
        case standard
        case high

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .high: return "High"
            }
        }

        var settings: [String: Any] {
            switch self {
            case .standard:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 22_050,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ]
            case .high:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            }
        }
    }

    /// User-selected recording quality. Persisted to UserDefaults.
    @Published var quality: RecordingQuality = .standard {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: Keys.quality)
        }
    }

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var elapsedTimer: Timer?
    private var lastStrokeEventTime: Date?
    private var lastPageEventTime: Date?
    private var pendingStrokeRegion: (x: Double, y: Double, w: Double, h: Double)?
    private var pendingStrokeCount: Int = 0

    /// The storage manager handles file layout, autosave, recovery, and compression.
    private let storageManager = AudioStorageManager.shared

    /// Note IDs encountered during the current recording session.
    private var sessionNoteIDs: Set<UUID> = []

    /// Called after a recording session is stopped and finalized.
    /// Use to trigger incremental search re-indexing (§6 Rule 2).
    var onSessionRecorded: ((AudioSession) -> Void)?

    // MARK: - Paths

    private static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var sessionsFileURL: URL {
        recordingsDirectory.appendingPathComponent("sessions.json")
    }

    private func audioFileURL(for sessionID: UUID) -> URL {
        Self.recordingsDirectory.appendingPathComponent("\(sessionID.uuidString).m4a")
    }

    // MARK: - Persistence Keys

    private enum Keys {
        static let quality = "y2notes.recording.quality"
    }

    // MARK: - Init

    init() {
        loadQuality()
        loadSessions()
        mergeRecoveredSessions()
        configureAudioSession()
    }

    /// Checks the storage manager for sessions recovered from interrupted
    /// recordings and merges them into the local sessions list.
    private func mergeRecoveredSessions() {
        for entry in storageManager.manifest.sessions {
            if !sessions.contains(where: { $0.id == entry.id }) {
                let recovered = AudioSession(
                    id: entry.id,
                    notebookID: entry.notebookID,
                    title: "Recovered — " + Self.defaultTitle(for: entry.createdAt),
                    startedAt: entry.createdAt,
                    endedAt: entry.createdAt.addingTimeInterval(entry.duration),
                    duration: entry.duration,
                    filename: entry.filename
                )
                sessions.insert(recovered, at: 0)
            }
        }
        if !sessions.isEmpty {
            saveSessions()
        }
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("[AudioRecordingStore] Failed to configure AVAudioSession: \(error)")
        }
    }

    // MARK: - Pre-warm

    /// Prepares the recorder so that `startRecording()` has sub-frame latency.
    /// Call on view appear.
    func prewarm(notebookID: UUID) {
        guard recorder == nil else { return }
        let sessionID = UUID()
        let url = audioFileURL(for: sessionID)
        do {
            recorder = try AVAudioRecorder(url: url, settings: quality.settings)
            recorder?.prepareToRecord()
        } catch {
            print("[AudioRecordingStore] Pre-warm failed: \(error)")
        }
    }

    // MARK: - Start / Stop

    /// Begins recording immediately. Returns the new session.
    @discardableResult
    func startRecording(notebookID: UUID, noteID: UUID, pageIndex: Int) -> AudioSession? {
        guard !isRecording else { return activeSession }

        let sessionID = UUID()
        let url = audioFileURL(for: sessionID)
        let now = Date()

        // Create recorder if not pre-warmed or URL changed
        do {
            recorder = try AVAudioRecorder(url: url, settings: quality.settings)
            recorder?.prepareToRecord()
        } catch {
            print("[AudioRecordingStore] Recorder init failed: \(error)")
            return nil
        }

        guard recorder?.record() == true else {
            print("[AudioRecordingStore] record() returned false")
            return nil
        }

        let filename = "\(sessionID.uuidString).m4a"
        let session = AudioSession(
            id: sessionID,
            notebookID: notebookID,
            title: Self.defaultTitle(for: now),
            startedAt: now,
            filename: filename
        )

        activeSession = session
        activeEvents = []
        isRecording = true
        elapsedTime = 0
        lastStrokeEventTime = nil
        lastPageEventTime = nil
        pendingStrokeRegion = nil
        pendingStrokeCount = 0
        sessionNoteIDs = [noteID]

        // Register with storage manager for manifest tracking and autosave
        storageManager.registerSession(session)
        storageManager.beginAutosave(
            for: sessionID,
            notebookID: notebookID,
            startedAt: now,
            filename: filename
        )

        startElapsedTimer()

        return session
    }

    /// Stops the active recording and saves the session.
    func stopRecording() {
        guard isRecording, var session = activeSession else { return }

        // Flush any pending coalesced stroke event
        flushPendingStrokeEvent()

        recorder?.stop()
        stopElapsedTimer()

        // End autosave and collect any remaining events
        _ = storageManager.endAutosave()

        session.endedAt = Date()
        session.duration = session.endedAt!.timeIntervalSince(session.startedAt)

        // Save session
        sessions.insert(session, at: 0)
        saveSessions()
        saveEvents(activeEvents, for: session.id)

        // Finalize with storage manager (updates manifest with file size, links)
        storageManager.finalizeSession(
            session.id,
            duration: session.duration,
            eventCount: activeEvents.count,
            noteIDs: Array(sessionNoteIDs)
        )

        // Trigger background compression for standard quality recordings
        if quality == .standard {
            storageManager.compressSession(session.id) { _ in }
        }

        // Notify for incremental search re-indexing (§6 Rule 2).
        let completedSession = session
        onSessionRecorded?(completedSession)

        // Reset state
        activeSession = nil
        activeEvents = []
        isRecording = false
        elapsedTime = 0
        recorder = nil
        sessionNoteIDs = []
    }

    /// Deletes a saved session and its audio file.
    func deleteSession(_ sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
        saveSessions()

        // Remove from storage manager (deletes files + manifest entry)
        storageManager.removeSession(sessionID)
    }

    /// Renames a session.
    func renameSession(_ sessionID: UUID, to newTitle: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].title = newTitle
        saveSessions()
    }

    /// Loads timeline events for a given session from disk.
    func loadEvents(for sessionID: UUID) -> [TimelineEvent] {
        let url = Self.recordingsDirectory
            .appendingPathComponent("\(sessionID.uuidString)_events.json")
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([TimelineEvent].self, from: data)
        else { return [] }
        return events
    }

    // MARK: - Timeline Event Emission

    /// Records a stroke event, coalescing rapid strokes per AudioTimelineConstants.
    func emitStrokeEvent(
        noteID: UUID,
        pageIndex: Int,
        regionX: Double,
        regionY: Double,
        regionWidth: Double,
        regionHeight: Double,
        toolName: String
    ) {
        guard isRecording, let _ = activeSession else { return }
        let now = Date()

        // Coalesce rapid strokes
        if let lastTime = lastStrokeEventTime,
           now.timeIntervalSince(lastTime) < AudioTimelineConstants.strokeCoalesceInterval,
           let pending = pendingStrokeRegion {
            // Merge bounding boxes
            let minX = min(pending.x, regionX)
            let minY = min(pending.y, regionY)
            let maxX = max(pending.x + pending.w, regionX + regionWidth)
            let maxY = max(pending.y + pending.h, regionY + regionHeight)
            pendingStrokeRegion = (minX, minY, maxX - minX, maxY - minY)
            pendingStrokeCount += 1
            lastStrokeEventTime = now
            return
        }

        // Flush any previous pending stroke first
        flushPendingStrokeEvent()

        // Start new pending stroke
        pendingStrokeRegion = (regionX, regionY, regionWidth, regionHeight)
        pendingStrokeCount = 1
        lastStrokeEventTime = now

        // Schedule flush after coalesce interval
        DispatchQueue.main.asyncAfter(
            deadline: .now() + AudioTimelineConstants.strokeCoalesceInterval + 0.05
        ) { [weak self] in
            self?.flushPendingStrokeEvent()
        }
    }

    private func flushPendingStrokeEvent() {
        guard let session = activeSession,
              let region = pendingStrokeRegion,
              pendingStrokeCount > 0 else { return }

        let event = TimelineEvent(
            sessionID: session.id,
            offset: Date().timeIntervalSince(session.startedAt),
            kind: .stroke,
            noteID: session.notebookID, // Will be overridden by caller context
            pageIndex: 0,
            payload: .stroke(StrokeEvent(
                strokeCount: pendingStrokeCount,
                regionX: region.x,
                regionY: region.y,
                regionWidth: region.w,
                regionHeight: region.h,
                toolName: "pen"
            ))
        )

        appendEvent(event)
        pendingStrokeRegion = nil
        pendingStrokeCount = 0
    }

    /// Records a page-change event with debouncing.
    func emitPageEvent(
        noteID: UUID,
        fromPage: Int,
        toPage: Int,
        trigger: PageChangeTrigger
    ) {
        guard isRecording, let session = activeSession else { return }
        let now = Date()

        // Debounce rapid page flips
        if let lastTime = lastPageEventTime,
           now.timeIntervalSince(lastTime) < AudioTimelineConstants.pageDebounceInterval {
            // Replace the last page event's toPage
            if let lastIdx = activeEvents.lastIndex(where: { $0.kind == .page }) {
                if case .page(var pageEvt) = activeEvents[lastIdx].payload {
                    pageEvt.toPage = toPage
                    activeEvents[lastIdx].payload = .page(pageEvt)
                    activeEvents[lastIdx].offset = now.timeIntervalSince(session.startedAt)
                    lastPageEventTime = now
                    return
                }
            }
        }

        let event = TimelineEvent(
            sessionID: session.id,
            offset: now.timeIntervalSince(session.startedAt),
            kind: .page,
            noteID: noteID,
            pageIndex: toPage,
            payload: .page(PageEvent(
                fromPage: fromPage,
                toPage: toPage,
                trigger: trigger
            ))
        )

        appendEvent(event)
        lastPageEventTime = now
    }

    /// Records an object event (sticker, shape, attachment placement, etc.).
    func emitObjectEvent(
        noteID: UUID,
        pageIndex: Int,
        objectID: UUID,
        objectType: String,
        action: ObjectAction
    ) {
        guard isRecording, let session = activeSession else { return }

        let event = TimelineEvent(
            sessionID: session.id,
            offset: Date().timeIntervalSince(session.startedAt),
            kind: objectType == "sticker" ? .sticker :
                  objectType == "shape" ? .shape :
                  objectType == "attachment" ? .attachment : .text,
            noteID: noteID,
            pageIndex: pageIndex,
            payload: .object(ObjectEvent(
                objectID: objectID,
                objectType: objectType,
                action: action
            ))
        )

        appendEvent(event)
    }

    // MARK: - Private Helpers

    private func appendEvent(_ event: TimelineEvent) {
        activeEvents.append(event)

        // Track note IDs for session linking
        if !sessionNoteIDs.contains(event.noteID) {
            sessionNoteIDs.insert(event.noteID)
            if let session = activeSession {
                storageManager.linkNote(event.noteID, toSession: session.id)
            }
        }

        // Queue for autosave (storage manager flushes on debounced interval)
        storageManager.queueEvent(event)

        // Prune if over limit
        if activeEvents.count > AudioTimelineConstants.maxEventsPerSession {
            activeEvents.removeFirst(activeEvents.count - AudioTimelineConstants.maxEventsPerSession)
        }
    }

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let session = self.activeSession else { return }
            DispatchQueue.main.async {
                self.elapsedTime = Date().timeIntervalSince(session.startedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Persistence

    private func loadQuality() {
        if let raw = UserDefaults.standard.string(forKey: Keys.quality),
           let q = RecordingQuality(rawValue: raw) {
            quality = q
        }
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: Self.sessionsFileURL),
              let loaded = try? JSONDecoder().decode([AudioSession].self, from: data)
        else { return }
        sessions = loaded
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        let url = Self.sessionsFileURL
        PerformanceConstraints.storageQueue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func saveEvents(_ events: [TimelineEvent], for sessionID: UUID) {
        let url = Self.recordingsDirectory
            .appendingPathComponent("\(sessionID.uuidString)_events.json")
        guard let data = try? JSONEncoder().encode(events) else { return }
        PerformanceConstraints.storageQueue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Checkpoint: saves current events to disk without stopping.
    /// Called on app backgrounding.  Encoding happens on main (fast),
    /// file write dispatched to storage queue (§6 Rule 1).
    func checkpoint() {
        guard isRecording, let session = activeSession else { return }
        saveEvents(activeEvents, for: session.id)
        storageManager.forceCheckpoint()
    }

    // MARK: - Helpers

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }

    /// Formatted elapsed time string (mm:ss).
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
