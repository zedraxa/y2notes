import Foundation

// MARK: - Searchable entry

/// A single indexed record that can appear in search results.
/// Wraps content from any source (note, bookmark, section, sticker, etc.)
/// and resolves to a `NavigationAnchor` for exact jump-to-location.
struct SearchableEntry: Identifiable {
    let id: String
    let kind: SearchEntryKind
    /// Primary searchable text (title, label, name).
    let primaryText: String
    /// Secondary searchable text (snippet, body, OCR).
    let secondaryText: String
    /// The notebook this entry belongs to (nil = cross-notebook or unfiled).
    let notebookID: UUID?
    /// Navigation anchor for jumping directly to this entry's location.
    let anchor: NavigationAnchor?
    /// When the source content was last modified — used for staleness checks.
    let modifiedAt: Date
}

/// The kind of content a search entry represents.
enum SearchEntryKind: String, Hashable {
    case noteTitle
    case noteText
    case noteOCR
    case notebookName
    case bookmarkLabel
    case sectionName
    case stickerLabel
    case pdfTitle
    case attachmentLabel
    case audioSession
    case audioTimestamp
}

// MARK: - Grouped search result

/// A search hit resolved to a jumpable location.
struct UniversalSearchResult: Identifiable {
    let id: String
    /// The indexed entry that matched.
    let entry: SearchableEntry
    /// Which field(s) matched the query.
    let matchKinds: Set<SearchEntryKind>
    /// Relevance score (higher = better). Includes current-notebook boost.
    let score: Int
    /// Short excerpt around the matching text.
    let snippet: String
}

/// Logical grouping for presenting results.
enum SearchResultGroup: String, CaseIterable {
    case currentNotebook = "This Notebook"
    case bookmarks       = "Bookmarks"
    case recordings      = "Recordings"
    case otherNotebooks  = "Other Notebooks"
    case pdfs            = "PDFs"
    case unfiled         = "Unfiled"
}

// MARK: - Search index

/// In-memory search index that aggregates content from all sources and resolves
/// results to `NavigationAnchor` targets for jump-to-location behaviour.
///
/// **Design principles:**
/// - Local-first: all data lives on-device, no network dependency.
/// - Incremental: re-index only changed items (keyed by note/bookmark/section ID).
/// - Current-notebook priority: results in the active notebook score higher.
/// - Anchor-based: every result carries a `NavigationAnchor` for exact page jump.
///
/// **Future-friendly:**
/// - `SearchEntryKind` is extensible — add `.audioTranscript`, `.tag`, `.widget` later.
/// - Full-text indexing can be swapped for a Core Data FTS or SQLite FTS5 backend
///   without changing the public API.
final class SearchIndex {

    // MARK: - Internal storage

    /// All indexed entries keyed by `id` for O(1) upsert/removal.
    private var entries: [String: SearchableEntry] = [:]

    /// Timestamp of the last full rebuild — callers can skip rebuild if data hasn't changed.
    private(set) var lastFullRebuild: Date = .distantPast

    // MARK: - Building the index

    /// Full rebuild: clears the index and re-indexes everything.
    func rebuild(
        notes: [Note],
        notebooks: [Notebook],
        sections: [NotebookSection],
        bookmarks: [PageBookmark],
        pdfRecords: [PDFNoteRecord],
        audioStorageManager: AudioStorageManager? = nil
    ) {
        entries.removeAll(keepingCapacity: true)

        // Index notebooks
        for nb in notebooks {
            let key = "nb-\(nb.id.uuidString)"
            entries[key] = SearchableEntry(
                id: key,
                kind: .notebookName,
                primaryText: nb.name,
                secondaryText: "",
                notebookID: nb.id,
                anchor: nil,   // notebook-level; open first page
                modifiedAt: nb.modifiedAt
            )
        }

        // Index sections
        for sec in sections {
            let key = "sec-\(sec.id.uuidString)"
            entries[key] = SearchableEntry(
                id: key,
                kind: .sectionName,
                primaryText: sec.name,
                secondaryText: "",
                notebookID: sec.notebookID,
                anchor: nil,
                modifiedAt: Date()
            )
        }

        // Index notes (title + text + OCR as separate entries)
        for note in notes {
            indexNote(note)
        }

        // Index bookmarks
        for bm in bookmarks {
            let key = "bm-\(bm.id.uuidString)"
            let label = bm.label.isEmpty ? "Page \(bm.anchor.pageIndex + 1)" : bm.label
            entries[key] = SearchableEntry(
                id: key,
                kind: .bookmarkLabel,
                primaryText: label,
                secondaryText: "",
                notebookID: bm.anchor.notebookID,
                anchor: bm.anchor,
                modifiedAt: bm.createdAt
            )
        }

        // Index PDF records
        for pdf in pdfRecords {
            let key = "pdf-\(pdf.id.uuidString)"
            entries[key] = SearchableEntry(
                id: key,
                kind: .pdfTitle,
                primaryText: pdf.title,
                secondaryText: "",
                notebookID: nil,
                anchor: nil,
                modifiedAt: Date()
            )
        }

        // Index audio sessions and timeline events
        if let storageManager = audioStorageManager {
            AudioSearchIndexer.indexAllSessions(into: &entries, from: storageManager)
        }

        lastFullRebuild = Date()
    }

    /// Incrementally update the index for a single note (called after save).
    func updateNote(_ note: Note) {
        // Remove old entries for this note
        let prefix = "note-\(note.id.uuidString)"
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
        // Re-index
        indexNote(note)
    }

    /// Remove all entries for a deleted note.
    func removeNote(_ noteID: UUID) {
        let prefix = "note-\(noteID.uuidString)"
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Re-index bookmarks (called when NavigationStore changes).
    func updateBookmarks(_ bookmarks: [PageBookmark]) {
        entries = entries.filter { !$0.key.hasPrefix("bm-") }
        for bm in bookmarks {
            let key = "bm-\(bm.id.uuidString)"
            let label = bm.label.isEmpty ? "Page \(bm.anchor.pageIndex + 1)" : bm.label
            entries[key] = SearchableEntry(
                id: key,
                kind: .bookmarkLabel,
                primaryText: label,
                secondaryText: "",
                notebookID: bm.anchor.notebookID,
                anchor: bm.anchor,
                modifiedAt: bm.createdAt
            )
        }
    }

    /// Incrementally update the index for a single audio session (called after
    /// recording stops or a session is recovered).
    func updateAudioSession(
        _ session: AudioStorageManager.StorageManifest.SessionEntry,
        from storageManager: AudioStorageManager
    ) {
        AudioSearchIndexer.removeSession(session.id, from: &entries)
        AudioSearchIndexer.indexSession(session, into: &entries, from: storageManager)
    }

    /// Remove all entries for a deleted audio session.
    func removeAudioSession(_ sessionID: UUID) {
        AudioSearchIndexer.removeSession(sessionID, from: &entries)
    }

    // MARK: - Querying

    /// Searches the index for `query`, with optional current-notebook prioritisation.
    ///
    /// - Parameters:
    ///   - query: User-entered search string. Returns [] when blank.
    ///   - currentNotebookID: If set, results in this notebook get a score boost.
    ///   - limit: Maximum results returned (default 50).
    /// - Returns: Sorted results grouped by relevance.
    func search(
        query: String,
        currentNotebookID: UUID? = nil,
        limit: Int = 50
    ) -> [UniversalSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [UniversalSearchResult] = []

        for (_, entry) in entries {
            var score = 0
            var matchKinds: Set<SearchEntryKind> = []
            var snippet = ""

            // Primary text match
            if entry.primaryText.localizedCaseInsensitiveContains(trimmed) {
                matchKinds.insert(entry.kind)
                score += baseScore(for: entry.kind)
                snippet = makeSnippet(in: entry.primaryText, around: trimmed)
            }

            // Secondary text match
            if !entry.secondaryText.isEmpty,
               entry.secondaryText.localizedCaseInsensitiveContains(trimmed) {
                matchKinds.insert(entry.kind)
                score += baseScore(for: entry.kind) / 2
                if snippet.isEmpty {
                    snippet = makeSnippet(in: entry.secondaryText, around: trimmed)
                }
            }

            guard !matchKinds.isEmpty else { continue }

            // Current-notebook boost: +30 points
            if let current = currentNotebookID, entry.notebookID == current {
                score += 30
            }

            // Exact-prefix bonus
            if entry.primaryText.localizedStandardRange(of: trimmed)?.lowerBound == entry.primaryText.startIndex {
                score += 15
            }

            results.append(UniversalSearchResult(
                id: entry.id,
                entry: entry,
                matchKinds: matchKinds,
                score: score,
                snippet: snippet
            ))
        }

        // Sort by score descending, then primary text ascending
        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.primaryText.localizedCompare(rhs.entry.primaryText) == .orderedAscending
        }

        return Array(results.prefix(limit))
    }

    /// Groups results by `SearchResultGroup` for sectioned display.
    func groupResults(
        _ results: [UniversalSearchResult],
        currentNotebookID: UUID?
    ) -> [(group: SearchResultGroup, results: [UniversalSearchResult])] {
        var groups: [SearchResultGroup: [UniversalSearchResult]] = [:]

        for result in results {
            let group: SearchResultGroup
            if result.entry.kind == .pdfTitle {
                group = .pdfs
            } else if result.entry.kind == .bookmarkLabel {
                group = .bookmarks
            } else if result.entry.kind == .audioSession || result.entry.kind == .audioTimestamp {
                group = .recordings
            } else if let nbID = result.entry.notebookID, nbID == currentNotebookID {
                group = .currentNotebook
            } else if result.entry.notebookID != nil {
                group = .otherNotebooks
            } else {
                group = .unfiled
            }
            groups[group, default: []].append(result)
        }

        // Return in display order
        return SearchResultGroup.allCases.compactMap { groupKey in
            guard let items = groups[groupKey], !items.isEmpty else { return nil }
            return (group: groupKey, results: items)
        }
    }

    // MARK: - Private helpers

    private func indexNote(_ note: Note) {
        let baseID = "note-\(note.id.uuidString)"

        // Title entry — always indexed even if empty
        entries["\(baseID)-title"] = SearchableEntry(
            id: "\(baseID)-title",
            kind: .noteTitle,
            primaryText: note.title,
            secondaryText: "",
            notebookID: note.notebookID,
            anchor: note.notebookID.map { nbID in
                NavigationAnchor(notebookID: nbID, noteID: note.id, pageIndex: 0)
            },
            modifiedAt: note.modifiedAt
        )

        // Typed text entry (searchable body)
        if !note.typedText.isEmpty {
            entries["\(baseID)-text"] = SearchableEntry(
                id: "\(baseID)-text",
                kind: .noteText,
                primaryText: note.title,
                secondaryText: note.typedText,
                notebookID: note.notebookID,
                anchor: note.notebookID.map { nbID in
                    NavigationAnchor(notebookID: nbID, noteID: note.id, pageIndex: 0)
                },
                modifiedAt: note.modifiedAt
            )
        }

        // OCR text entry
        if !note.ocrText.isEmpty {
            entries["\(baseID)-ocr"] = SearchableEntry(
                id: "\(baseID)-ocr",
                kind: .noteOCR,
                primaryText: note.title,
                secondaryText: note.ocrText,
                notebookID: note.notebookID,
                anchor: note.notebookID.map { nbID in
                    NavigationAnchor(notebookID: nbID, noteID: note.id, pageIndex: 0)
                },
                modifiedAt: note.modifiedAt
            )
        }

        // Sticker labels (aggregate unique categories per note)
        let allStickers = note.stickerLayers.compactMap { $0 }.flatMap { $0 }
        if !allStickers.isEmpty {
            let labels = Array(Set(allStickers.map(\.stickerID))).joined(separator: " ")
            entries["\(baseID)-stickers"] = SearchableEntry(
                id: "\(baseID)-stickers",
                kind: .stickerLabel,
                primaryText: labels,
                secondaryText: note.title,
                notebookID: note.notebookID,
                anchor: note.notebookID.map { nbID in
                    NavigationAnchor(notebookID: nbID, noteID: note.id, pageIndex: 0)
                },
                modifiedAt: note.modifiedAt
            )
        }

        // Attachment labels — each attachment indexed individually with page-level anchor.
        // Searchable by label (name) and type (image/pdf/link).
        for (pageIdx, layer) in note.attachmentLayers.enumerated() {
            guard let attachments = layer else { continue }
            for attachment in attachments {
                let key = "\(baseID)-att-\(attachment.id.uuidString)"
                let typeName = attachment.type.rawValue.capitalized
                let displayLabel = attachment.label.isEmpty ? "\(typeName) Attachment" : attachment.label
                entries[key] = SearchableEntry(
                    id: key,
                    kind: .attachmentLabel,
                    primaryText: displayLabel,
                    secondaryText: "\(typeName) · \(note.title)",
                    notebookID: note.notebookID,
                    anchor: note.notebookID.map { nbID in
                        NavigationAnchor(
                            notebookID: nbID,
                            noteID: note.id,
                            pageIndex: pageIdx,
                            objectID: attachment.id
                        )
                    },
                    modifiedAt: attachment.placedAt
                )
            }
        }
    }

    private func baseScore(for kind: SearchEntryKind) -> Int {
        switch kind {
        case .noteTitle:       return 100
        case .noteText:        return 50
        case .noteOCR:         return 40
        case .notebookName:    return 80
        case .bookmarkLabel:   return 60
        case .sectionName:     return 70
        case .stickerLabel:    return 20
        case .pdfTitle:        return 60
        case .attachmentLabel: return 35
        case .audioSession:    return 55
        case .audioTimestamp:  return 30
        }
    }

    private func makeSnippet(in text: String, around query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(80))
        }
        let maxLen = 80
        let halfWindow = maxLen / 2

        let distFromStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let leading: String
        if distFromStart <= halfWindow {
            leading = String(text[text.startIndex ..< range.lowerBound])
        } else {
            let start = text.index(range.lowerBound, offsetBy: -halfWindow)
            leading = "…" + String(text[start ..< range.lowerBound])
        }

        let remaining = maxLen - leading.count - text.distance(from: range.lowerBound, to: range.upperBound)
        let distToEnd = text.distance(from: range.upperBound, to: text.endIndex)
        let trailing: String
        if distToEnd <= max(remaining, 0) {
            trailing = String(text[range.upperBound ..< text.endIndex])
        } else {
            let end = text.index(range.upperBound, offsetBy: max(remaining, 0))
            trailing = String(text[range.upperBound ..< end]) + "…"
        }

        return leading + String(text[range]) + trailing
    }
}
