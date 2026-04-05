import Foundation

// MARK: - SnapshotStore
//
// Singleton that manages per-note version history snapshots.
// Follows the same patterns as AudioStorageManager: manifest-based indexing,
// background I/O on PerformanceConstraints.storageQueue, and disk budget enforcement.

final class SnapshotStore {

    // MARK: - Singleton

    static let shared = SnapshotStore()

    // MARK: - Constants

    enum Constants {
        /// Minimum interval between automatic snapshots for the same note.
        static let minSnapshotInterval: TimeInterval = 30
        /// Maximum number of snapshots per note before compaction is forced.
        static let maxSnapshotsPerNote: Int = 500
    }

    // MARK: - State

    /// In-memory index cache: noteID → history index (metadata only).
    private var indexCache: [UUID: SnapshotHistoryIndex] = [:]

    /// Tracks the last snapshot time per note to enforce minimum interval.
    private var lastSnapshotTime: [UUID: Date] = [:]

    private let fileManager = FileManager.default

    // MARK: - Paths

    /// Root directory for all snapshot history.
    /// `Documents/History/`
    static var historyDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("History", isDirectory: true)
    }

    /// Per-note history directory.
    /// `Documents/History/{noteID}/`
    private func noteHistoryDirectory(for noteID: UUID) -> URL {
        Self.historyDirectory.appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    /// Path to the history index JSON for a note.
    private func indexURL(for noteID: UUID) -> URL {
        noteHistoryDirectory(for: noteID).appendingPathComponent("history_index.json")
    }

    /// Path to a snapshot's page data file.
    private func snapshotDataURL(for noteID: UUID, snapshotID: UUID) -> URL {
        noteHistoryDirectory(for: noteID).appendingPathComponent("\(snapshotID.uuidString).snapshot")
    }

    // MARK: - Init

    init() {
        ensureHistoryDirectory()
    }

    private func ensureHistoryDirectory() {
        try? fileManager.createDirectory(at: Self.historyDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API — Create snapshots

    /// Creates a snapshot of the given note, capturing only the specified dirty pages.
    /// Called from the autosave flush path on `storageQueue`.
    ///
    /// - Parameters:
    ///   - note: The note to snapshot.
    ///   - dirtyPages: Set of page indices that changed since the last snapshot.
    ///                 If empty, all pages are considered changed.
    ///   - trigger: What caused this snapshot.
    /// - Returns: The created snapshot metadata, or nil if skipped (too recent).
    @discardableResult
    func createSnapshot(
        for note: Note,
        dirtyPages: Set<Int>,
        trigger: SnapshotTrigger = .autosave
    ) -> NoteSnapshot? {
        // Enforce minimum interval for autosave triggers.
        if trigger == .autosave,
           let lastTime = lastSnapshotTime[note.id],
           Date().timeIntervalSince(lastTime) < Constants.minSnapshotInterval {
            return nil
        }

        let effectiveDirtyPages = dirtyPages.isEmpty
            ? Set(0 ..< note.pages.count)
            : dirtyPages

        // Load or create the index for this note.
        var index = loadIndex(for: note.id)

        // Build summary.
        let summary = buildSummary(
            changedPages: effectiveDirtyPages,
            totalPages: note.pages.count,
            trigger: trigger
        )

        // Collect page data for changed pages.
        var pageDataMap: [Int: Data] = [:]
        var stickerMap: [Int: [StickerInstance]] = [:]
        var shapeMap: [Int: [ShapeInstance]] = [:]
        var attachmentMap: [Int: [AttachmentObject]] = [:]

        for pageIdx in effectiveDirtyPages where pageIdx < note.pages.count {
            pageDataMap[pageIdx] = note.pages[pageIdx]
            if pageIdx < note.stickerLayers.count, let stickers = note.stickerLayers[pageIdx] {
                stickerMap[pageIdx] = stickers
            }
            if pageIdx < note.shapeLayers.count, let shapes = note.shapeLayers[pageIdx] {
                shapeMap[pageIdx] = shapes
            }
            if pageIdx < note.attachmentLayers.count, let attachments = note.attachmentLayers[pageIdx] {
                attachmentMap[pageIdx] = attachments
            }
        }

        let parentID = index.snapshots.last?.id
        let dataSizeBytes = pageDataMap.values.reduce(0) { $0 + $1.count }

        let snapshot = NoteSnapshot(
            noteID: note.id,
            sequenceNumber: index.nextSequenceNumber,
            parentSnapshotID: parentID,
            changedPageIndices: Array(effectiveDirtyPages.sorted()),
            totalPageCount: note.pages.count,
            title: note.title,
            noteModifiedAt: note.modifiedAt,
            summary: summary,
            dataSizeBytes: dataSizeBytes,
            trigger: trigger
        )

        let pageData = SnapshotPageData(
            snapshotID: snapshot.id,
            pages: pageDataMap,
            stickerLayers: stickerMap,
            shapeLayers: shapeMap,
            attachmentLayers: attachmentMap,
            expansionRegions: note.expansionRegions
        )

        // Write page data to disk.
        let noteDir = noteHistoryDirectory(for: note.id)
        try? fileManager.createDirectory(at: noteDir, withIntermediateDirectories: true)

        let dataURL = snapshotDataURL(for: note.id, snapshotID: snapshot.id)
        if let encoded = try? JSONEncoder().encode(pageData) {
            try? encoded.write(to: dataURL, options: .atomic)
        }

        // Update index.
        index.snapshots.append(snapshot)
        index.nextSequenceNumber += 1
        saveIndex(index, for: note.id)

        // Update caches.
        indexCache[note.id] = index
        lastSnapshotTime[note.id] = Date()

        return snapshot
    }

    // MARK: - Public API — Read snapshots

    /// Returns the snapshot history for a note (metadata only, no page data).
    func snapshots(for noteID: UUID) -> [NoteSnapshot] {
        let index = loadIndex(for: noteID)
        return index.snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    /// Loads the full page data for a specific snapshot.
    func loadSnapshotData(noteID: UUID, snapshotID: UUID) -> SnapshotPageData? {
        let url = snapshotDataURL(for: noteID, snapshotID: snapshotID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SnapshotPageData.self, from: data)
    }

    /// Reconstructs a full note state from a snapshot by combining its page data
    /// with the most recent data for pages it doesn't include.
    ///
    /// Walks backward through the snapshot chain to find the latest data for each page.
    func reconstructNote(from snapshotID: UUID, noteID: UUID, currentNote: Note) -> Note? {
        let allSnapshots = snapshots(for: noteID)
        guard let targetIndex = allSnapshots.firstIndex(where: { $0.id == snapshotID }) else {
            return nil
        }

        let target = allSnapshots[targetIndex]
        var reconstructedPages = Array(repeating: Data(), count: target.totalPageCount)
        var reconstructedStickers: [[StickerInstance]?] = Array(repeating: nil, count: target.totalPageCount)
        var reconstructedShapes: [[ShapeInstance]?] = Array(repeating: nil, count: target.totalPageCount)
        var reconstructedAttachments: [[AttachmentObject]?] = Array(repeating: nil, count: target.totalPageCount)
        var resolvedPages = Set<Int>()

        // Walk from the target snapshot backward (most recent first within the sublist).
        // allSnapshots is sorted newest-first; target is at targetIndex.
        // We need target and everything older.
        let relevantSnapshots = Array(allSnapshots[targetIndex...])

        for snapshot in relevantSnapshots {
            guard let pageData = loadSnapshotData(noteID: noteID, snapshotID: snapshot.id) else {
                continue
            }
            for (pageIdx, data) in pageData.pages where pageIdx < target.totalPageCount {
                if !resolvedPages.contains(pageIdx) {
                    reconstructedPages[pageIdx] = data
                    reconstructedStickers[pageIdx] = pageData.stickerLayers[pageIdx]
                    reconstructedShapes[pageIdx] = pageData.shapeLayers[pageIdx]
                    reconstructedAttachments[pageIdx] = pageData.attachmentLayers[pageIdx]
                    resolvedPages.insert(pageIdx)
                }
            }
            if resolvedPages.count >= target.totalPageCount { break }
        }

        var restoredNote = currentNote
        restoredNote.pages = reconstructedPages
        restoredNote.title = target.title
        restoredNote.modifiedAt = Date()
        restoredNote.stickerLayers = reconstructedStickers
        restoredNote.shapeLayers = reconstructedShapes
        restoredNote.attachmentLayers = reconstructedAttachments

        // Restore expansion regions from the target snapshot (use the most
        // recent snapshot that has expansion data — the target itself).
        if let targetData = loadSnapshotData(noteID: noteID, snapshotID: snapshotID) {
            restoredNote.expansionRegions = targetData.expansionRegions
        }

        // Ensure parallel arrays are sized correctly.
        while restoredNote.pageTypes.count < restoredNote.pages.count {
            restoredNote.pageTypes.append(nil)
        }
        if restoredNote.pageTypes.count > restoredNote.pages.count {
            restoredNote.pageTypes = Array(restoredNote.pageTypes.prefix(restoredNote.pages.count))
        }
        while restoredNote.pageColors.count < restoredNote.pages.count {
            restoredNote.pageColors.append(nil)
        }
        if restoredNote.pageColors.count > restoredNote.pages.count {
            restoredNote.pageColors = Array(restoredNote.pageColors.prefix(restoredNote.pages.count))
        }

        return restoredNote
    }

    /// Reconstructs a single page from a snapshot.
    func reconstructPage(
        from snapshotID: UUID,
        noteID: UUID,
        pageIndex: Int
    ) -> (data: Data, stickers: [StickerInstance]?, shapes: [ShapeInstance]?, attachments: [AttachmentObject]?)? {
        let allSnapshots = snapshots(for: noteID)
        guard let targetIdx = allSnapshots.firstIndex(where: { $0.id == snapshotID }) else {
            return nil
        }

        // Walk backward from the target snapshot to find data for this page.
        for snapshot in allSnapshots[targetIdx...] {
            guard let pageData = loadSnapshotData(noteID: noteID, snapshotID: snapshot.id),
                  let data = pageData.pages[pageIndex] else { continue }
            return (
                data: data,
                stickers: pageData.stickerLayers[pageIndex],
                shapes: pageData.shapeLayers[pageIndex],
                attachments: pageData.attachmentLayers[pageIndex]
            )
        }
        return nil
    }

    // MARK: - Public API — Pin/unpin

    /// Toggles the pinned state of a snapshot.
    func togglePin(noteID: UUID, snapshotID: UUID) {
        var index = loadIndex(for: noteID)
        if let idx = index.snapshots.firstIndex(where: { $0.id == snapshotID }) {
            index.snapshots[idx].isPinned.toggle()
            saveIndex(index, for: noteID)
            indexCache[noteID] = index
        }
    }

    // MARK: - Public API — Delete history

    /// Removes all snapshot history for a note (e.g., when the note is deleted).
    func deleteHistory(for noteID: UUID) {
        indexCache.removeValue(forKey: noteID)
        lastSnapshotTime.removeValue(forKey: noteID)
        let dir = noteHistoryDirectory(for: noteID)
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - Compaction

    /// Runs the tiered retention compaction.  Should be called on `storageQueue`
    /// at launch and periodically (e.g., every 24 hours).
    func runCompaction() {
        guard let enumerator = fileManager.enumerator(
            at: Self.historyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for case let dirURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue,
                  let noteID = UUID(uuidString: dirURL.lastPathComponent) else { continue }
            compactSnapshots(for: noteID)
        }

        enforceDiskBudget()
    }

    private func compactSnapshots(for noteID: UUID) {
        var index = loadIndex(for: noteID)
        let now = Date()
        var toRemove = Set<UUID>()

        // Group snapshots into retention tiers and prune excess.
        for tier in SnapshotRetention.allTiers {
            let tierStart = now.addingTimeInterval(-tier.maxAge)
            let tierSnapshots = index.snapshots
                .filter { $0.createdAt >= tierStart && $0.createdAt < now && !$0.isPinned }
                .sorted { $0.createdAt < $1.createdAt }

            guard tierSnapshots.count > 1 else { continue }

            // Within the tier, keep at most one snapshot per `interval`.
            var lastKept: Date?
            for snapshot in tierSnapshots {
                if let last = lastKept,
                   snapshot.createdAt.timeIntervalSince(last) < tier.interval {
                    toRemove.insert(snapshot.id)
                } else {
                    lastKept = snapshot.createdAt
                }
            }
        }

        // Remove old snapshots beyond 30 days (unless pinned or manually created).
        let cutoff = now.addingTimeInterval(-SnapshotRetention.monthly.maxAge)
        for snapshot in index.snapshots
        where snapshot.createdAt < cutoff && !snapshot.isPinned && snapshot.trigger != .manual {
            toRemove.insert(snapshot.id)
        }

        // Cap total snapshots per note.
        if index.snapshots.count > Constants.maxSnapshotsPerNote {
            let excess = index.snapshots.count - Constants.maxSnapshotsPerNote
            let candidates = index.snapshots
                .filter { !$0.isPinned && $0.trigger != .manual }
                .sorted { $0.createdAt < $1.createdAt }
            for snapshot in candidates.prefix(excess) {
                toRemove.insert(snapshot.id)
            }
        }

        // Delete snapshot data files and update index.
        for snapshotID in toRemove {
            let dataURL = snapshotDataURL(for: noteID, snapshotID: snapshotID)
            try? fileManager.removeItem(at: dataURL)
        }
        index.snapshots.removeAll { toRemove.contains($0.id) }
        saveIndex(index, for: noteID)
        indexCache[noteID] = index
    }

    private func enforceDiskBudget() {
        var totalSize: Int64 = 0
        var allSnapshots: [(noteID: UUID, snapshot: NoteSnapshot)] = []

        guard let enumerator = fileManager.enumerator(
            at: Self.historyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        for case let dirURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue,
                  let noteID = UUID(uuidString: dirURL.lastPathComponent) else { continue }
            let index = loadIndex(for: noteID)
            for snapshot in index.snapshots {
                totalSize += Int64(snapshot.dataSizeBytes)
                allSnapshots.append((noteID: noteID, snapshot: snapshot))
            }
        }

        guard totalSize > SnapshotRetention.diskBudgetBytes else { return }

        // Sort oldest first, remove unpinned until under budget.
        let removable = allSnapshots
            .filter { !$0.snapshot.isPinned && $0.snapshot.trigger != .manual }
            .sorted { $0.snapshot.createdAt < $1.snapshot.createdAt }

        for item in removable {
            guard totalSize > SnapshotRetention.diskBudgetBytes else { break }
            let dataURL = snapshotDataURL(for: item.noteID, snapshotID: item.snapshot.id)
            try? fileManager.removeItem(at: dataURL)
            totalSize -= Int64(item.snapshot.dataSizeBytes)

            // Remove from index.
            if var index = indexCache[item.noteID] {
                index.snapshots.removeAll { $0.id == item.snapshot.id }
                saveIndex(index, for: item.noteID)
                indexCache[item.noteID] = index
            }
        }
    }

    // MARK: - Total disk usage

    /// Returns the total bytes used by all snapshot history.
    func totalDiskUsage() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: Self.historyDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Index persistence

    private func loadIndex(for noteID: UUID) -> SnapshotHistoryIndex {
        if let cached = indexCache[noteID] { return cached }
        let url = indexURL(for: noteID)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(SnapshotHistoryIndex.self, from: data) else {
            let fresh = SnapshotHistoryIndex(noteID: noteID)
            indexCache[noteID] = fresh
            return fresh
        }
        indexCache[noteID] = index
        return index
    }

    private func saveIndex(_ index: SnapshotHistoryIndex, for noteID: UUID) {
        let url = indexURL(for: noteID)
        let dir = noteHistoryDirectory(for: noteID)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func buildSummary(changedPages: Set<Int>, totalPages: Int, trigger: SnapshotTrigger) -> String {
        let triggerLabel: String
        switch trigger {
        case .autosave: triggerLabel = "Autosave"
        case .lifecycle: triggerLabel = "Background save"
        case .manual: triggerLabel = "Manual save"
        case .preDestructive: triggerLabel = "Pre-delete backup"
        case .preRestore: triggerLabel = "Pre-restore backup"
        }

        if changedPages.count == totalPages {
            return "\(triggerLabel) — all pages"
        }
        let pageList = changedPages.sorted().map { "Page \($0 + 1)" }.joined(separator: ", ")
        return "\(triggerLabel) — \(pageList)"
    }
}
