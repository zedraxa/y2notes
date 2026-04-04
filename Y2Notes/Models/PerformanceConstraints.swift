import Foundation

// MARK: - Performance Constraints
//
// Central documentation of performance budgets, timing constraints, and
// concurrency rules for the audio recording and search system.
//
// These values are referenced by runtime assertions (debug-only) and serve
// as the canonical source of truth for performance contracts across the
// recording, storage, playback, and search subsystems.

/// Performance budgets and concurrency rules for the audio recording pipeline.
///
/// Every file-I/O, encoding, or indexing operation during recording **must**
/// run off the main thread to preserve 120 Hz ProMotion frame cadence
/// (8.3 ms per frame).
enum PerformanceConstraints {

    // MARK: - Frame Budget

    /// Maximum main-thread work per frame (120 Hz ProMotion = 8.33 ms).
    static let frameBudgetMs: Double = 8.0

    // MARK: 1. Recording Path — Zero-Lag Guarantees

    /// Recording-start latency budget.  `AVAudioRecorder.prepareToRecord()`
    /// is called in `prewarm()` on view appear; `record()` must never block
    /// main.  Budget: sub-frame (< 16 ms).
    static let recordStartLatencyMs: Double = 16.0

    /// Stroke-event emission budget on main thread.
    /// `emitStrokeEvent()` runs synchronously during Apple Pencil input.
    /// Coalesce guard (0.3 s) and bounding-box merge are O(1).
    static let strokeEventBudgetMs: Double = 2.0

    /// Page-event emission budget on main thread.
    /// `emitPageEvent()` with 0.5 s debounce — one date comparison + early return.
    static let pageEventBudgetMs: Double = 1.0

    /// Autosave flush must happen off main thread, within this wall-time budget.
    /// Serializing ≤ 500 `TimelineEvent` values should stay < 5 ms.
    static let autosaveFlushBudgetMs: Double = 5.0

    // MARK: 2. UI Thread — No Freezes

    /// Binary-search resolution of the current timeline event during playback.
    /// O(log n); for 10,000 events ≈ 14 comparisons — trivial.
    static let resolveEventBudgetMs: Double = 0.5

    /// Highlight / page-switch dispatch: consumed asynchronously by SwiftUI.
    /// Keep onChange handlers under this budget.
    static let pageHighlightHandlerBudgetMs: Double = 4.0

    /// Session-list loading budget.  `loadSessions()` decodes `sessions.json`.
    /// For ≤ 200 sessions (~ 50 KB JSON), target < 10 ms.  Display skeleton
    /// if this budget is exceeded.
    static let sessionListLoadBudgetMs: Double = 50.0

    /// In-memory search scan budget.  Linear scan over ≤ 10,000 entries with
    /// `localizedCaseInsensitiveContains`.  Debounce input by 0.3 s.
    static let searchQueryBudgetMs: Double = 16.0

    // MARK: 3. CPU Budget — Low Power During Recording

    /// Target sustained CPU during recording: < 5 % of one core.
    /// `AVAudioRecorder` at 22,050 Hz mono AAC uses hardware encoder on
    /// Apple Silicon — near-zero CPU.
    static let recordingCPUPercentCap: Double = 5.0

    /// Audio search indexing wall-time budget.
    /// For 100 sessions × 500 events = 50,000 entries, target < 200 ms.
    /// Must run on `.utility` QoS and **never** during active recording.
    static let searchIndexRebuildBudgetMs: Double = 200.0

    /// Post-recording compression QoS.
    /// `AVAssetExportSession` re-encode at 48 kbps runs asynchronously and
    /// must never overlap an active recording.
    static let compressionQoS: DispatchQoS = .utility

    /// Disk-usage check interval during recording (seconds).
    /// File-size stat is < 1 ms.
    static let diskCheckIntervalSeconds: TimeInterval = 30.0

    /// Orphan cleanup wall-time budget on `.utility` QoS.
    static let orphanCleanupBudgetMs: Double = 100.0

    // MARK: 4. Memory Constraints

    /// Maximum in-memory timeline events for an active session.
    /// Each `TimelineEvent` is ~ 200 bytes.  At 500 events/hour sustained
    /// → ~ 100 KB/hour.  Even a 10-hour session is < 1 MB.
    static let maxTimelineMemoryBytes: Int = 10 * 1024 * 1024  // 10 MB

    /// Search-index footprint cap.
    /// 10,000 `SearchableEntry` at ~ 2 KB each ≈ 20 MB.
    static let maxSearchIndexMemoryBytes: Int = 20 * 1024 * 1024  // 20 MB

    // MARK: 5. Disk I/O Constraints

    /// Autosave event flush: ≤ 500 events × ~ 100 bytes JSON ≈ 50 KB.
    static let autosaveMaxFlushBytes: Int = 50 * 1024  // 50 KB

    /// Standard-quality audio write throughput: ~ 11 KB/s.
    static let standardAudioBytesPerSecond: Int = 11 * 1024

    /// High-quality audio write throughput: ~ 22 KB/s.
    static let highAudioBytesPerSecond: Int = 22 * 1024

    // MARK: 6. Concurrency Rules (documented as enum for namespace)

    /// The dedicated background queue for audio storage I/O.
    /// All autosave flushes, recovery checkpoint writes, and event
    /// serialisation run here to keep the main thread free.
    static let storageQueue = DispatchQueue(
        label: "com.y2notes.audioStorage",
        qos: .utility
    )

    // Rule 1: Never block main during recording — all file I/O (autosave,
    //          recovery, compression, search indexing) must use `storageQueue`.
    //
    // Rule 2: No search re-index during recording — `SearchIndex.rebuild()`
    //          with audio indexing must be deferred until recording stops.
    //          Incremental updates for the active session are done post-stop.
    //
    // Rule 3: Compression never overlaps recording — `compressSession()` is
    //          only called after `stopRecording()`.  This is an invariant.
    //
    // Rule 4: Display-link callbacks must be non-allocating —
    //          `resolveCurrentEvent()` does a binary search with no
    //          allocations.  Avoid string formatting or anchor construction
    //          in the hot path.

    // MARK: 7. Future — Transcript Search

    /// Speech-to-text processing: post-recording only, `.background` QoS.
    static let transcriptionQoS: DispatchQoS = .background

    /// Transcript segment indexing budget for a 1-hour recording.
    /// ~ 10,000 words × ~ 50 bytes each ≈ 500 KB.
    static let transcriptIndexBudgetMs: Double = 500.0
}
