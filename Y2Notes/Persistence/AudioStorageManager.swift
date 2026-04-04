import Foundation
import AVFoundation
import os

private let storageLogger = Logger(subsystem: "com.y2notes", category: "AudioStorage")

/// Manages audio file storage, compression, session linking, autosave, and
/// crash recovery for the audio recording system.
///
/// **File layout**:
/// ```
/// Documents/Recordings/
///   manifest.json                          — session index (notebook→session links)
///   {sessionID}.m4a                        — audio file
///   {sessionID}_events.json                — timeline events
///   {sessionID}_recovery.json              — in-flight recovery checkpoint
///   orphans/                               — recovered files from interrupted sessions
/// ```
///
/// **Design principles**:
/// - Audio writes directly to disk via `AVAudioRecorder` (no in-memory buffering).
/// - Timeline events live in-memory during recording; autosaved on a debounced
///   interval (piggybacks on `WritingConfig.saveDebounceInterval`).
/// - On crash recovery, interrupted sessions are detected by the presence of
///   `_recovery.json` files without a matching completed session in the manifest.
/// - Compression is a post-recording background pass that can re-encode
///   Standard→Low bitrate files to reclaim disk space.
final class AudioStorageManager {

    // MARK: - Singleton

    static let shared = AudioStorageManager()

    // MARK: - Constants

    enum StorageConstants {
        /// Maximum total disk usage for recordings before cleanup warnings (500 MB).
        static let diskBudgetBytes: Int64 = 500 * 1024 * 1024
        /// Maximum single recording file size before auto-stop (2 GB).
        static let maxSingleFileBytes: Int64 = 2 * 1024 * 1024 * 1024
        /// Autosave interval for timeline events during recording (seconds).
        static let autosaveInterval: TimeInterval = 0.8
        /// Interval between disk-usage checks during recording (seconds).
        static let diskCheckInterval: TimeInterval = 30.0
        /// Maximum age for orphan recovery files before auto-cleanup (days).
        static let orphanMaxAgeDays: Int = 7
        /// Compression quality for post-recording optimization.
        static let compressionBitrate: Int = 48_000
    }

    // MARK: - Storage Manifest

    /// Index of all sessions with their notebook links, stored as a single
    /// lightweight JSON file for fast startup enumeration.
    struct StorageManifest: Codable {
        var version: Int = 1
        var sessions: [SessionEntry] = []
        var lastCleanup: Date?

        struct SessionEntry: Codable, Identifiable {
            let id: UUID
            var notebookID: UUID
            var noteIDs: [UUID]
            var filename: String
            var eventsFilename: String
            var fileSizeBytes: Int64
            var eventCount: Int
            var createdAt: Date
            var duration: TimeInterval
            var isCompressed: Bool
        }
    }

    /// In-memory manifest, loaded on init.
    private(set) var manifest = StorageManifest()

    // MARK: - Recovery State

    /// Checkpoint written periodically during recording so a crash can be recovered.
    struct RecoveryCheckpoint: Codable {
        let sessionID: UUID
        let notebookID: UUID
        let startedAt: Date
        let filename: String
        var lastEventOffset: TimeInterval
        var eventCount: Int
        var checkpointedAt: Date
    }

    // MARK: - Autosave State

    private var autosaveTimer: Timer?
    private var diskCheckTimer: Timer?
    private var pendingEvents: [TimelineEvent] = []
    private var activeRecoveryCheckpoint: RecoveryCheckpoint?

    // MARK: - Paths

    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var manifestURL: URL {
        recordingsDirectory.appendingPathComponent("manifest.json")
    }

    private static var orphansDirectory: URL {
        let dir = recordingsDirectory.appendingPathComponent("orphans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func audioFileURL(for sessionID: UUID) -> URL {
        Self.recordingsDirectory.appendingPathComponent("\(sessionID.uuidString).m4a")
    }

    func eventsFileURL(for sessionID: UUID) -> URL {
        Self.recordingsDirectory.appendingPathComponent("\(sessionID.uuidString)_events.json")
    }

    private func recoveryFileURL(for sessionID: UUID) -> URL {
        Self.recordingsDirectory.appendingPathComponent("\(sessionID.uuidString)_recovery.json")
    }

    // MARK: - Init

    init() {
        loadManifest()
        recoverInterruptedSessions()
        cleanupOrphans()
    }

    // MARK: - Manifest Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: Self.manifestURL),
              let loaded = try? JSONDecoder().decode(StorageManifest.self, from: data)
        else {
            storageLogger.info("No manifest found — starting fresh")
            return
        }
        manifest = loaded
        storageLogger.info("Loaded manifest with \(loaded.sessions.count) sessions")
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else {
            storageLogger.error("Failed to encode manifest")
            return
        }
        let url = Self.manifestURL
        PerformanceConstraints.storageQueue.async {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                storageLogger.error("Failed to write manifest: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Session Linking

    /// Registers a new session in the manifest, linking it to a notebook.
    func registerSession(_ session: AudioSession) {
        let entry = StorageManifest.SessionEntry(
            id: session.id,
            notebookID: session.notebookID,
            noteIDs: [],
            filename: session.filename,
            eventsFilename: "\(session.id.uuidString)_events.json",
            fileSizeBytes: 0,
            eventCount: 0,
            createdAt: session.startedAt,
            duration: session.duration,
            isCompressed: false
        )
        manifest.sessions.insert(entry, at: 0)
        saveManifest()
        storageLogger.info("Registered session \(session.id) for notebook \(session.notebookID)")
    }

    /// Updates a session entry after recording stops (file size, duration, events).
    func finalizeSession(
        _ sessionID: UUID,
        duration: TimeInterval,
        eventCount: Int,
        noteIDs: [UUID]
    ) {
        guard let idx = manifest.sessions.firstIndex(where: { $0.id == sessionID }) else {
            storageLogger.warning("Cannot finalize — session \(sessionID) not in manifest")
            return
        }

        let audioURL = audioFileURL(for: sessionID)
        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: audioURL.path
        )[.size] as? Int64) ?? 0

        manifest.sessions[idx].fileSizeBytes = fileSize
        manifest.sessions[idx].duration = duration
        manifest.sessions[idx].eventCount = eventCount
        manifest.sessions[idx].noteIDs = noteIDs
        saveManifest()

        // Remove recovery checkpoint
        removeRecoveryCheckpoint(for: sessionID)

        storageLogger.info(
            "Finalized session \(sessionID): \(Self.formattedBytes(fileSize)), \(eventCount) events"
        )
    }

    /// Returns all sessions linked to a specific notebook.
    func sessions(forNotebook notebookID: UUID) -> [StorageManifest.SessionEntry] {
        manifest.sessions.filter { $0.notebookID == notebookID }
    }

    /// Returns all sessions that reference a specific note.
    func sessions(forNote noteID: UUID) -> [StorageManifest.SessionEntry] {
        manifest.sessions.filter { $0.noteIDs.contains(noteID) }
    }

    /// Links an additional note ID to a session (called when recording spans
    /// multiple notes during tab switches).
    func linkNote(_ noteID: UUID, toSession sessionID: UUID) {
        guard let idx = manifest.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if !manifest.sessions[idx].noteIDs.contains(noteID) {
            manifest.sessions[idx].noteIDs.append(noteID)
            saveManifest()
        }
    }

    /// Removes a session from the manifest and deletes its files.
    func removeSession(_ sessionID: UUID) {
        manifest.sessions.removeAll { $0.id == sessionID }
        saveManifest()

        let fm = FileManager.default
        try? fm.removeItem(at: audioFileURL(for: sessionID))
        try? fm.removeItem(at: eventsFileURL(for: sessionID))
        try? fm.removeItem(at: recoveryFileURL(for: sessionID))

        storageLogger.info("Removed session \(sessionID) and its files")
    }

    // MARK: - Autosave

    /// Starts the autosave timer for timeline events during recording.
    /// Events are flushed to disk at `StorageConstants.autosaveInterval`.
    func beginAutosave(for sessionID: UUID, notebookID: UUID, startedAt: Date, filename: String) {
        pendingEvents = []
        activeRecoveryCheckpoint = RecoveryCheckpoint(
            sessionID: sessionID,
            notebookID: notebookID,
            startedAt: startedAt,
            filename: filename,
            lastEventOffset: 0,
            eventCount: 0,
            checkpointedAt: Date()
        )

        // Write initial recovery checkpoint
        writeRecoveryCheckpoint()

        autosaveTimer = Timer.scheduledTimer(
            withTimeInterval: StorageConstants.autosaveInterval,
            repeats: true
        ) { [weak self] _ in
            self?.flushPendingEvents()
        }

        diskCheckTimer = Timer.scheduledTimer(
            withTimeInterval: StorageConstants.diskCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkDiskUsage(sessionID: sessionID)
        }

        storageLogger.info("Autosave started for session \(sessionID)")
    }

    /// Queues a timeline event for autosave. Events accumulate in memory and
    /// are flushed to disk on the autosave interval.
    func queueEvent(_ event: TimelineEvent) {
        pendingEvents.append(event)
    }

    /// Flushes pending events to the events file on disk.
    /// All file I/O is dispatched to `PerformanceConstraints.storageQueue`
    /// to keep the main thread free during recording (§1, §6 Rule 1).
    private func flushPendingEvents() {
        guard let checkpoint = activeRecoveryCheckpoint,
              !pendingEvents.isEmpty else { return }

        // Snapshot pending events and clear immediately so new events
        // can accumulate while the write is in flight.
        let eventsToFlush = pendingEvents
        pendingEvents.removeAll()

        let url = eventsFileURL(for: checkpoint.sessionID)

        PerformanceConstraints.storageQueue.async { [weak self] in
            // Load existing events, append pending, write back
            var allEvents: [TimelineEvent] = []
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONDecoder().decode([TimelineEvent].self, from: data) {
                allEvents = existing
            }
            allEvents.append(contentsOf: eventsToFlush)

            // Prune if over limit
            if allEvents.count > AudioTimelineConstants.maxEventsPerSession {
                allEvents.removeFirst(allEvents.count - AudioTimelineConstants.maxEventsPerSession)
            }

            if let data = try? JSONEncoder().encode(allEvents) {
                try? data.write(to: url, options: .atomic)
            }

            // Update recovery checkpoint on the storage queue as well
            DispatchQueue.main.async {
                self?.activeRecoveryCheckpoint?.eventCount = allEvents.count
                self?.activeRecoveryCheckpoint?.lastEventOffset = eventsToFlush.last?.offset ?? 0
                self?.activeRecoveryCheckpoint?.checkpointedAt = Date()
                self?.writeRecoveryCheckpoint()
            }

            storageLogger.debug("Flushed \(eventsToFlush.count) events to disk (total: \(allEvents.count))")
        }
    }

    /// Stops the autosave timer and flushes remaining events.
    func endAutosave() -> [TimelineEvent] {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        diskCheckTimer?.invalidate()
        diskCheckTimer = nil

        // Final flush
        let remaining = pendingEvents
        flushPendingEvents()
        activeRecoveryCheckpoint = nil
        pendingEvents = []

        storageLogger.info("Autosave stopped")
        return remaining
    }

    /// Forces an immediate checkpoint (called on app backgrounding).
    func forceCheckpoint() {
        flushPendingEvents()
        storageLogger.info("Forced checkpoint")
    }

    // MARK: - Recovery

    /// Writes the current recovery checkpoint to disk on the storage queue
    /// (§1 constraint: recovery checkpoint writes are background-only).
    private func writeRecoveryCheckpoint() {
        guard let checkpoint = activeRecoveryCheckpoint else { return }
        let url = recoveryFileURL(for: checkpoint.sessionID)
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        PerformanceConstraints.storageQueue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Removes the recovery checkpoint for a completed session.
    private func removeRecoveryCheckpoint(for sessionID: UUID) {
        let url = recoveryFileURL(for: sessionID)
        try? FileManager.default.removeItem(at: url)
    }

    /// Scans for `_recovery.json` files that don't have a matching completed
    /// session in the manifest, indicating an interrupted recording.
    private func recoverInterruptedSessions() {
        let fm = FileManager.default
        let dir = Self.recordingsDirectory

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let recoveryFiles = contents.filter { $0.lastPathComponent.hasSuffix("_recovery.json") }
        guard !recoveryFiles.isEmpty else { return }

        for recoveryURL in recoveryFiles {
            guard let data = try? Data(contentsOf: recoveryURL),
                  let checkpoint = try? JSONDecoder().decode(
                      RecoveryCheckpoint.self,
                      from: data
                  )
            else {
                try? fm.removeItem(at: recoveryURL)
                continue
            }

            let sessionID = checkpoint.sessionID

            // Skip if session already completed in manifest
            if manifest.sessions.contains(where: { $0.id == sessionID }) {
                try? fm.removeItem(at: recoveryURL)
                continue
            }

            // Check if audio file exists
            let audioURL = audioFileURL(for: sessionID)
            guard fm.fileExists(atPath: audioURL.path) else {
                // No audio file — clean up
                try? fm.removeItem(at: recoveryURL)
                try? fm.removeItem(at: eventsFileURL(for: sessionID))
                storageLogger.warning("Recovery: no audio for session \(sessionID) — discarded")
                continue
            }

            // Recover: determine actual audio duration from the file
            let duration = Self.audioDuration(at: audioURL) ?? 0

            // Create a recovered session entry
            let entry = StorageManifest.SessionEntry(
                id: sessionID,
                notebookID: checkpoint.notebookID,
                noteIDs: [],
                filename: checkpoint.filename,
                eventsFilename: "\(sessionID.uuidString)_events.json",
                fileSizeBytes: Self.fileSize(at: audioURL),
                eventCount: checkpoint.eventCount,
                createdAt: checkpoint.startedAt,
                duration: duration,
                isCompressed: false
            )
            manifest.sessions.insert(entry, at: 0)

            // Clean up recovery file
            try? fm.removeItem(at: recoveryURL)

            storageLogger.info(
                "Recovered interrupted session \(sessionID) — "
                + "\(Self.formattedDuration(duration)), \(checkpoint.eventCount) events"
            )
        }

        saveManifest()
    }

    // MARK: - Large File Handling

    /// Checks if the active recording is approaching file size limits.
    /// Returns true if recording should continue, false if it should auto-stop.
    private func checkDiskUsage(sessionID: UUID) {
        let audioURL = audioFileURL(for: sessionID)
        let fileSize = Self.fileSize(at: audioURL)

        if fileSize >= StorageConstants.maxSingleFileBytes {
            storageLogger.warning(
                "Session \(sessionID) reached max file size (\(Self.formattedBytes(fileSize)))"
            )
            NotificationCenter.default.post(
                name: .audioRecordingFileSizeLimitReached,
                object: nil,
                userInfo: ["sessionID": sessionID]
            )
        }

        let totalUsage = calculateTotalDiskUsage()
        if totalUsage >= StorageConstants.diskBudgetBytes {
            storageLogger.warning(
                "Total recordings disk usage at budget limit: \(Self.formattedBytes(totalUsage))"
            )
            NotificationCenter.default.post(
                name: .audioRecordingDiskBudgetReached,
                object: nil,
                userInfo: ["totalBytes": totalUsage]
            )
        }
    }

    /// Calculates total disk usage of all recordings.
    func calculateTotalDiskUsage() -> Int64 {
        let fm = FileManager.default
        let dir = Self.recordingsDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        return contents.reduce(Int64(0)) { total, url in
            total + Self.fileSize(at: url)
        }
    }

    /// Formatted string for disk usage (e.g. "12.3 MB").
    var formattedDiskUsage: String {
        Self.formattedBytes(calculateTotalDiskUsage())
    }

    /// Formatted string for remaining disk budget.
    var formattedRemainingBudget: String {
        let used = calculateTotalDiskUsage()
        let remaining = max(0, StorageConstants.diskBudgetBytes - used)
        return Self.formattedBytes(remaining)
    }

    // MARK: - Compression

    /// Compresses an audio file in the background to reduce disk usage.
    /// Called after recording stops if the file exceeds a size threshold.
    /// Uses AVAssetExportSession with a lower bitrate preset.
    func compressSession(
        _ sessionID: UUID,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        let sourceURL = audioFileURL(for: sessionID)
        let tempURL = Self.recordingsDirectory
            .appendingPathComponent("\(sessionID.uuidString)_compressed.m4a")

        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            completion(.failure(StorageError.compressionNotAvailable))
            return
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a

        exportSession.exportAsynchronously { [weak self] in
            guard let self else { return }
            switch exportSession.status {
            case .completed:
                let fm = FileManager.default
                let originalSize = Self.fileSize(at: sourceURL)
                let compressedSize = Self.fileSize(at: tempURL)

                // Only keep compressed version if it's actually smaller
                if compressedSize < originalSize {
                    do {
                        try fm.removeItem(at: sourceURL)
                        try fm.moveItem(at: tempURL, to: sourceURL)

                        DispatchQueue.main.async {
                            if let idx = self.manifest.sessions.firstIndex(
                                where: { $0.id == sessionID }
                            ) {
                                self.manifest.sessions[idx].isCompressed = true
                                self.manifest.sessions[idx].fileSizeBytes = compressedSize
                                self.saveManifest()  // saveManifest() dispatches to storageQueue
                            }
                        }

                        let saved = originalSize - compressedSize
                        storageLogger.info(
                            "Compressed session \(sessionID): "
                            + "\(Self.formattedBytes(originalSize)) → \(Self.formattedBytes(compressedSize)) "
                            + "(saved \(Self.formattedBytes(saved)))"
                        )
                        completion(.success(saved))
                    } catch {
                        try? fm.removeItem(at: tempURL)
                        completion(.failure(error))
                    }
                } else {
                    // Compressed version is larger — discard it
                    try? fm.removeItem(at: tempURL)
                    storageLogger.info(
                        "Compression skipped for \(sessionID) — no size reduction"
                    )
                    completion(.success(0))
                }

            case .failed:
                try? FileManager.default.removeItem(at: tempURL)
                let err = exportSession.error ?? StorageError.compressionFailed
                storageLogger.error("Compression failed for \(sessionID): \(err.localizedDescription)")
                completion(.failure(err))

            case .cancelled:
                try? FileManager.default.removeItem(at: tempURL)
                completion(.failure(StorageError.compressionCancelled))

            default:
                break
            }
        }
    }

    /// Compresses all uncompressed sessions in the background.
    func compressAllUncompressed() {
        let uncompressed = manifest.sessions.filter { !$0.isCompressed }
        guard !uncompressed.isEmpty else { return }

        storageLogger.info("Starting background compression of \(uncompressed.count) sessions")

        for entry in uncompressed {
            compressSession(entry.id) { result in
                switch result {
                case .success(let saved):
                    if saved > 0 {
                        storageLogger.info("Background compression saved \(Self.formattedBytes(saved))")
                    }
                case .failure(let error):
                    storageLogger.error("Background compression error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Orphan Cleanup

    /// Removes recovery files and orphaned audio files older than the max age.
    /// Dispatched to `.utility` QoS (§3 constraint: < 100 ms, never during recording).
    private func cleanupOrphans() {
        PerformanceConstraints.storageQueue.async { [weak self] in
            self?.performOrphanCleanup()
        }
    }

    private func performOrphanCleanup() {
        let fm = FileManager.default
        let dir = Self.recordingsDirectory
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -StorageConstants.orphanMaxAgeDays,
            to: Date()
        )!

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let knownIDs = Set(manifest.sessions.map(\.id))

        for url in contents {
            // Skip the manifest and orphans directory
            let name = url.lastPathComponent
            if name == "manifest.json" || name == "orphans" { continue }

            // Extract session ID from filename
            let baseName = name
                .replacingOccurrences(of: "_events.json", with: "")
                .replacingOccurrences(of: "_recovery.json", with: "")
                .replacingOccurrences(of: ".m4a", with: "")

            guard let sessionID = UUID(uuidString: baseName) else { continue }

            // If session is known, skip
            if knownIDs.contains(sessionID) { continue }

            // Check age
            if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
               modDate > cutoff {
                continue
            }

            // Move to orphans or delete
            let orphanDest = Self.orphansDirectory.appendingPathComponent(name)
            if name.hasSuffix(".m4a") {
                try? fm.moveItem(at: url, to: orphanDest)
                storageLogger.info("Moved orphan audio to orphans/: \(name)")
            } else {
                try? fm.removeItem(at: url)
                storageLogger.debug("Removed orphan file: \(name)")
            }
        }

        // Clean old orphans
        if let orphanContents = try? fm.contentsOfDirectory(
            at: Self.orphansDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            for url in orphanContents {
                if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate,
                   modDate < cutoff {
                    try? fm.removeItem(at: url)
                    storageLogger.debug("Cleaned old orphan: \(url.lastPathComponent)")
                }
            }
        }

        manifest.lastCleanup = Date()
        saveManifest()
    }

    // MARK: - Timeline Event Storage

    /// Saves timeline events for a session to disk on the storage queue
    /// (§6 Rule 1: never block main during recording).
    func saveEvents(_ events: [TimelineEvent], for sessionID: UUID) {
        let url = eventsFileURL(for: sessionID)
        guard let data = try? JSONEncoder().encode(events) else {
            storageLogger.error("Failed to encode events for session \(sessionID)")
            return
        }
        PerformanceConstraints.storageQueue.async {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                storageLogger.error("Failed to write events: \(error.localizedDescription)")
            }
        }
    }

    /// Loads timeline events for a session from disk.
    func loadEvents(for sessionID: UUID) -> [TimelineEvent] {
        let url = eventsFileURL(for: sessionID)
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([TimelineEvent].self, from: data)
        else { return [] }
        return events
    }

    // MARK: - Queries

    /// Returns the total number of sessions.
    var sessionCount: Int { manifest.sessions.count }

    /// Returns the total event count across all sessions.
    var totalEventCount: Int {
        manifest.sessions.reduce(0) { $0 + $1.eventCount }
    }

    /// Returns sessions sorted by creation date (newest first).
    var recentSessions: [StorageManifest.SessionEntry] {
        manifest.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Utility

    private static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? Int64) ?? 0
    }

    private static func audioDuration(at url: URL) -> TimeInterval? {
        let asset = AVAsset(url: url)
        let duration = asset.duration
        guard duration.timescale > 0 else { return nil }
        return CMTimeGetSeconds(duration)
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Errors

    enum StorageError: LocalizedError {
        case compressionNotAvailable
        case compressionFailed
        case compressionCancelled

        var errorDescription: String? {
            switch self {
            case .compressionNotAvailable: return "Audio compression is not available."
            case .compressionFailed: return "Audio compression failed."
            case .compressionCancelled: return "Audio compression was cancelled."
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a recording file approaches the maximum single-file size limit.
    static let audioRecordingFileSizeLimitReached = Notification.Name(
        "com.y2notes.audioRecordingFileSizeLimitReached"
    )
    /// Posted when total recording disk usage reaches the budget limit.
    static let audioRecordingDiskBudgetReached = Notification.Name(
        "com.y2notes.audioRecordingDiskBudgetReached"
    )
}
