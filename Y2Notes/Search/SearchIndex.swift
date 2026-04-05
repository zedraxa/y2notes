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
    case widgetContent
    case noteTag
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
/// **Search algorithm:**
/// - Combines Trie-based prefix lookup with BM25 relevance scoring for fast, ranked results.
/// - Falls back to fuzzy matching (bounded Levenshtein automaton) for typo tolerance.
/// - Implemented in TrieIndex — no SQLite or Core Data dependency.
final class SearchIndex {

    // MARK: - Internal storage

    /// All indexed entries keyed by `id` for O(1) upsert/removal.
    private var entries: [String: SearchableEntry] = [:]

    /// Trie-backed full-text index for O(m) prefix search + BM25 ranking.
    /// Indexes combined primary+secondary text per entry UUID.
    private let trie = TrieIndex()

    /// Bidirectional map between trie docIDs and entry keys for O(1) reverse lookup.
    private var trieDocToEntry: [UUID: String] = [:]
    private var entryToTrieDoc: [String: UUID] = [:]

    /// Timestamp of the last full rebuild — callers can skip rebuild if data hasn't changed.
    private(set) var lastFullRebuild: Date = .distantPast

    // MARK: - Building the index

    /// Full rebuild: clears the index and re-indexes everything.
    ///
    /// **Performance (§3, §6 Rule 2):** When `audioStorageManager` is
    /// supplied, audio indexing runs synchronously in-line.  Callers must
    /// ensure this is **not** invoked while a recording is active — defer
    /// the audio portion until after `stopRecording()`.  Pass
    /// `isRecordingActive: true` to skip audio indexing entirely.
    func rebuild(
        notes: [Note],
        notebooks: [Notebook],
        sections: [NotebookSection],
        bookmarks: [PageBookmark],
        pdfRecords: [PDFNoteRecord],
        audioStorageManager: AudioStorageManager? = nil,
        isRecordingActive: Bool = false
    ) {
        entries.removeAll(keepingCapacity: true)
        trie.clear()
        trieDocToEntry.removeAll(keepingCapacity: true)
        entryToTrieDoc.removeAll(keepingCapacity: true)

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

        // Bulk-load the Trie from all indexed entries after the dictionary is populated.
        rebuildTrie()

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

        // Index audio sessions and timeline events.
        // Skipped when a recording is active (§6 Rule 2: no search re-index
        // during recording).  The active session is indexed incrementally
        // after stopRecording() via `updateAudioSession()`.
        if let storageManager = audioStorageManager, !isRecordingActive {
            AudioSearchIndexer.indexAllSessions(into: &entries, from: storageManager)
        }

        lastFullRebuild = Date()
    }

    /// Incrementally update the index for a single note (called after save).
    func updateNote(_ note: Note) {
        // Remove old entries for this note
        let prefix = "note-\(note.id.uuidString)"
        let keysToRemove = entries.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            if let docID = entryToTrieDoc[key] {
                trie.removeDocument(id: docID)
                trieDocToEntry.removeValue(forKey: docID)
                entryToTrieDoc.removeValue(forKey: key)
            }
            entries.removeValue(forKey: key)
        }
        // Re-index
        indexNote(note)
        // Re-populate Trie for the new entries.
        for (key, entry) in entries where key.hasPrefix(prefix) {
            let docID = makeTrieDocID(for: key)
            trie.indexDocument(id: docID, text: entry.primaryText + " " + entry.secondaryText)
        }
    }

    /// Remove all entries for a deleted note.
    func removeNote(_ noteID: UUID) {
        let prefix = "note-\(noteID.uuidString)"
        let keysToRemove = entries.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            if let docID = entryToTrieDoc[key] {
                trie.removeDocument(id: docID)
                trieDocToEntry.removeValue(forKey: docID)
                entryToTrieDoc.removeValue(forKey: key)
            }
            entries.removeValue(forKey: key)
        }
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
    /// Uses Trie-backed BM25 scoring for fast, ranked results:
    /// - Exact prefix hits scored via BM25 (term frequency + inverse document frequency).
    /// - Fuzzy matches (≤1 Levenshtein edit) given discounted BM25 weight.
    /// - Current-notebook boost (+30 pts) and exact-prefix bonus (+15 pts) applied on top.
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

        // --- Phase 1: BM25 ranking from the Trie ---
        // rankedSearch returns (docID, bm25Score) for entries matching via prefix or fuzzy.
        let bm25Hits = trie.rankedSearch(trimmed, maxFuzzyDistance: trimmed.count >= 4 ? 1 : 0)

        // Build a lookup from trie docID → (entry, bm25Score).
        var trieScoreByEntryID: [String: Double] = [:]
        for hit in bm25Hits {
            let entryID = trieDocIDToEntryID(hit.id)
            // Keep the highest BM25 score if multiple trie docs map to the same entry.
            let existing = trieScoreByEntryID[entryID] ?? 0
            trieScoreByEntryID[entryID] = max(existing, hit.score)
        }

        // --- Phase 2: Score assembly and linear-scan fallback ---
        // For entries that matched via the Trie, use BM25 as the primary score.
        // For entries where the Trie gave no signal (e.g. very short queries), fall back
        // to the original substring logic to ensure nothing is missed.
        var results: [UniversalSearchResult] = []

        for (entryID, entry) in entries {
            var score = 0
            var matchKinds: Set<SearchEntryKind> = []
            var snippet = ""

            if let bm25 = trieScoreByEntryID[entryID] {
                // Trie matched: use BM25 scaled to an integer score range comparable
                // to the legacy base scores (0–150 range).
                let scaled = Int(bm25 * 50.0)
                matchKinds.insert(entry.kind)
                score += scaled + baseScore(for: entry.kind)
                snippet = makeSnippet(in: entry.primaryText + " " + entry.secondaryText, around: trimmed)
            } else {
                // Fallback substring check (handles single-character queries, CJK, etc.)
                if entry.primaryText.localizedCaseInsensitiveContains(trimmed) {
                    matchKinds.insert(entry.kind)
                    score += baseScore(for: entry.kind)
                    snippet = makeSnippet(in: entry.primaryText, around: trimmed)
                }
                if !entry.secondaryText.isEmpty,
                   entry.secondaryText.localizedCaseInsensitiveContains(trimmed) {
                    matchKinds.insert(entry.kind)
                    score += baseScore(for: entry.kind) / 2
                    if snippet.isEmpty {
                        snippet = makeSnippet(in: entry.secondaryText, around: trimmed)
                    }
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

        // Tags — index each tag so searches for "#lecture" or "lecture" find the note.
        if !note.tags.isEmpty {
            let tagText = note.tags.joined(separator: " ")
            entries["\(baseID)-tags"] = SearchableEntry(
                id: "\(baseID)-tags",
                kind: .noteTag,
                primaryText: note.title,
                secondaryText: tagText,
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

        // Widget content — each widget indexed individually with page-level anchor.
        // Searchable by title, body text, and checklist items.
        for (pageIdx, layer) in note.widgetLayers.enumerated() {
            guard let widgets = layer else { continue }
            for widget in widgets {
                let key = "\(baseID)-wgt-\(widget.id.uuidString)"
                let textContent = searchableText(for: widget)
                guard !textContent.isEmpty else { continue }
                let kindLabel = widget.kind.rawValue.capitalized
                entries[key] = SearchableEntry(
                    id: key,
                    kind: .widgetContent,
                    primaryText: textContent,
                    secondaryText: "\(kindLabel) · \(note.title)",
                    notebookID: note.notebookID,
                    anchor: note.notebookID.map { nbID in
                        NavigationAnchor(
                            notebookID: nbID,
                            noteID: note.id,
                            pageIndex: pageIdx,
                            objectID: widget.id
                        )
                    },
                    modifiedAt: widget.placedAt
                )
            }
        }

        // Expansion region content — index widgets and attachments within each region.
        // Results from expansion regions use the region's page index + regionID for
        // precise navigation, and rank slightly below main page results.
        for region in note.expansionRegions where !region.isCollapsed {
            // Expansion widgets
            for widget in region.widgetLayers {
                let key = "\(baseID)-exp-wgt-\(widget.id.uuidString)"
                let textContent = searchableText(for: widget)
                guard !textContent.isEmpty else { continue }
                let kindLabel = widget.kind.rawValue.capitalized
                // Compute canvasPoint as center of the widget frame for scroll-to targeting
                let center = CGPoint(
                    x: widget.frame.boundingRect.midX,
                    y: widget.frame.boundingRect.midY
                )
                entries[key] = SearchableEntry(
                    id: key,
                    kind: .widgetContent,
                    primaryText: textContent,
                    secondaryText: "\(kindLabel) · \(note.title) (expanded area)",
                    notebookID: note.notebookID,
                    anchor: note.notebookID.map { nbID in
                        NavigationAnchor(
                            notebookID: nbID,
                            noteID: note.id,
                            pageIndex: region.pageIndex,
                            objectID: widget.id,
                            regionID: region.id,
                            canvasPoint: center
                        )
                    },
                    modifiedAt: widget.placedAt
                )
            }

            // Expansion attachments
            for attachment in region.attachmentLayers {
                let key = "\(baseID)-exp-att-\(attachment.id.uuidString)"
                let typeName = attachment.type.rawValue.capitalized
                let displayLabel = attachment.label.isEmpty ? "\(typeName) Attachment" : attachment.label
                let center = CGPoint(
                    x: attachment.frame.boundingRect.midX,
                    y: attachment.frame.boundingRect.midY
                )
                entries[key] = SearchableEntry(
                    id: key,
                    kind: .attachmentLabel,
                    primaryText: displayLabel,
                    secondaryText: "\(typeName) · \(note.title) (expanded area)",
                    notebookID: note.notebookID,
                    anchor: note.notebookID.map { nbID in
                        NavigationAnchor(
                            notebookID: nbID,
                            noteID: note.id,
                            pageIndex: region.pageIndex,
                            objectID: attachment.id,
                            regionID: region.id,
                            canvasPoint: center
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
        case .widgetContent:   return 35
        case .noteTag:         return 45
        }
    }

    /// Extracts searchable text from a widget's payload (title, body, items).
    private func searchableText(for widget: NoteWidget) -> String {
        switch widget.payload {
        case .checklist(let title, let items):
            let itemTexts = items.map(\.text).filter { !$0.isEmpty }
            return ([title] + itemTexts).joined(separator: " ")

        case .quickTable(let title, _, _, let cells, _):
            let cellTexts = cells.map(\.text).filter { !$0.isEmpty }
            return ([title] + cellTexts).joined(separator: " ")

        case .calloutBox(let title, let body, _):
            return [title, body].filter { !$0.isEmpty }.joined(separator: " ")

        case .referenceCard(let title, let body):
            return [title, body].filter { !$0.isEmpty }.joined(separator: " ")

        case .stickyNote(let body, _):
            return body

        case .flashcard(let front, let back, _, _):
            return [front, back].filter { !$0.isEmpty }.joined(separator: " ")

        case .progressTracker(let title, _, _):
            return title
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

    // MARK: - Trie Helpers

    /// Rebuild the Trie from the current `entries` dictionary.
    /// Called after a full rebuild or bulk import.
    private func rebuildTrie() {
        trie.clear()
        trieDocToEntry.removeAll(keepingCapacity: true)
        entryToTrieDoc.removeAll(keepingCapacity: true)
        for (key, entry) in entries {
            let docID = computeTrieDocID(for: key)
            trieDocToEntry[docID] = key
            entryToTrieDoc[key] = docID
            let text = [entry.primaryText, entry.secondaryText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            trie.indexDocument(id: docID, text: text)
        }
    }

    /// Derives a stable UUID for the Trie from a string entry key using FNV-1a.
    private func makeTrieDocID(for entryKey: String) -> UUID {
        let docID = computeTrieDocID(for: entryKey)
        // Register in bidirectional map so reverse lookup is O(1).
        if trieDocToEntry[docID] == nil {
            trieDocToEntry[docID] = entryKey
            entryToTrieDoc[entryKey] = docID
        }
        return docID
    }

    /// Pure hash computation — no side effects on the bidirectional map.
    private func computeTrieDocID(for entryKey: String) -> UUID {
        // Fold the key's UTF-8 bytes into a 128-bit UUID via FNV-1a.
        var hash0: UInt64 = 14695981039346656037
        var hash1: UInt64 = 14695981039346656037
        let bytes = Array(entryKey.utf8)
        for (i, byte) in bytes.enumerated() {
            if i % 2 == 0 {
                hash0 ^= UInt64(byte)
                hash0 &*= 1099511628211
            } else {
                hash1 ^= UInt64(byte)
                hash1 &*= 1099511628211
            }
        }
        let uuidBytes: [UInt8] = [
            UInt8((hash0 >> 56) & 0xFF), UInt8((hash0 >> 48) & 0xFF),
            UInt8((hash0 >> 40) & 0xFF), UInt8((hash0 >> 32) & 0xFF),
            UInt8((hash0 >> 24) & 0xFF), UInt8((hash0 >> 16) & 0xFF),
            UInt8((hash0 >>  8) & 0xFF), UInt8( hash0        & 0xFF),
            UInt8((hash1 >> 56) & 0xFF), UInt8((hash1 >> 48) & 0xFF),
            UInt8((hash1 >> 40) & 0xFF), UInt8((hash1 >> 32) & 0xFF),
            UInt8((hash1 >> 24) & 0xFF), UInt8((hash1 >> 16) & 0xFF),
            UInt8((hash1 >>  8) & 0xFF), UInt8( hash1        & 0xFF),
        ]
        return UUID(uuid: (
            uuidBytes[0],  uuidBytes[1],  uuidBytes[2],  uuidBytes[3],
            uuidBytes[4],  uuidBytes[5],  uuidBytes[6],  uuidBytes[7],
            uuidBytes[8],  uuidBytes[9],  uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    /// Converts a Trie docID back to the original entry key in O(1) using the bidirectional map.
    private func trieDocIDToEntryID(_ docID: UUID) -> String {
        trieDocToEntry[docID] ?? ""
    }
}
