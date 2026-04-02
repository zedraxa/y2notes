import Foundation

// MARK: - Search scope

/// Scope that constrains a library-wide search.
enum SearchScope {
    /// Search all notes.
    case allNotes
    /// Search only notes belonging to the given notebook.
    case notebook(UUID)
}

// MARK: - Match type

/// The kind of field that produced a search hit.
/// New field types (PDF text, handwriting OCR) can be added here without changing callers.
enum SearchMatchType: Hashable {
    /// Match came from the note title.
    case title
    /// Match came from typed text on the note (keyboard-entered text content).
    case typedText
    /// Match came from the parent notebook name.
    case notebookName
    // Future: case pdfText, case handwritingOCR
}

// MARK: - Search result

/// A single note that matched a search query, together with context about how it matched.
struct SearchResult: Identifiable, Hashable {
    let id = UUID()

    /// The note that matched.
    let noteID: UUID
    /// The notebook the note belongs to (nil = unfiled).
    let notebookID: UUID?

    /// All field types where the query was found.
    let matchTypes: Set<SearchMatchType>

    /// Short excerpt from the matched text that includes the query string.
    /// Empty string when the match was on a non-text field (e.g. notebook name only).
    let snippet: String

    /// Relevance score (higher = more relevant).  Used to sort results.
    let score: Int

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
}

// MARK: - In-document find result

/// A single text match inside a note's typed text, identified by its range.
struct InDocumentMatch: Identifiable {
    let id = UUID()
    /// Zero-based line number of the match (0 if note has a single text block).
    let line: Int
    /// Character range of the match in the full typedText string.
    let range: Range<String.Index>
    /// Short excerpt around the match.
    let snippet: String
}

// MARK: - Search service

/// Pure-function search engine for Y2Notes.
///
/// **V1 covers:**
/// - Note title
/// - Note `typedText` (keyboard-entered text)
/// - Parent notebook name
///
/// **Architecture is open for:**
/// - PDF text extraction results (store extracted text in a future `Note.pdfText` field)
/// - Handwriting OCR results (store recognised text in a future `Note.ocrText` field)
/// All callers read `SearchResult.matchTypes` to learn which fields matched, so adding new
/// field types requires only changes here (no call-site refactoring).
struct SearchService {

    // MARK: Library-wide search

    /// Returns results matching `query` across `notes`, scoped to `scope`.
    ///
    /// Results are sorted by relevance (title match > typedText match > notebook match),
    /// then alphabetically by note title as a tiebreaker.
    ///
    /// - Parameters:
    ///   - query:     The user-entered search string. Returns [] when blank.
    ///   - notes:     All notes visible to the search (pre-filtered if desired).
    ///   - notebooks: Used for notebook-name matching and to populate `notebookID`.
    ///   - scope:     Limits results to all notes or a specific notebook.
    func search(
        query: String,
        in notes: [Note],
        notebooks: [Notebook],
        scope: SearchScope = .allNotes
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scopedNotes: [Note]
        switch scope {
        case .allNotes:
            scopedNotes = notes
        case .notebook(let nbID):
            scopedNotes = notes.filter { $0.notebookID == nbID }
        }

        // Build a notebook-by-ID lookup to avoid O(n²) lookups inside the loop.
        let notebookByID: [UUID: Notebook] = Dictionary(
            uniqueKeysWithValues: notebooks.map { ($0.id, $0) }
        )

        var results: [SearchResult] = []

        for note in scopedNotes {
            var matchTypes: Set<SearchMatchType> = []
            var score = 0
            var snippet = ""

            // ── Title match ──────────────────────────────────────────────
            if note.title.localizedCaseInsensitiveContains(trimmed) {
                matchTypes.insert(.title)
                score += 100
                snippet = makeSnippet(in: note.title, around: trimmed)
            }

            // ── Typed text match ─────────────────────────────────────────
            if !note.typedText.isEmpty,
               note.typedText.localizedCaseInsensitiveContains(trimmed) {
                matchTypes.insert(.typedText)
                score += 50
                if snippet.isEmpty {
                    snippet = makeSnippet(in: note.typedText, around: trimmed)
                }
            }

            // ── Notebook name match ──────────────────────────────────────
            if let nbID = note.notebookID,
               let nb = notebookByID[nbID],
               nb.name.localizedCaseInsensitiveContains(trimmed) {
                matchTypes.insert(.notebookName)
                score += 20
            }

            // Future field types (PDF text, OCR) would be added here.

            if !matchTypes.isEmpty {
                results.append(SearchResult(
                    noteID: note.id,
                    notebookID: note.notebookID,
                    matchTypes: matchTypes,
                    snippet: snippet,
                    score: score
                ))
            }
        }

        // Sort: highest score first; title A-Z within the same score band.
        return results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let t0 = notes.first { $0.id == $0.id }?.title ?? ""
            let t1 = notes.first { $0.id == $1.id }?.title ?? ""
            return t0.localizedCompare(t1) == .orderedAscending
        }
    }

    // MARK: In-document search

    /// Finds all occurrences of `query` inside the note's `typedText`.
    ///
    /// Returns matches in order of appearance. Each match includes a snippet and character range.
    /// When `typedText` is empty (drawing-only note) the array is always empty — the
    /// call-site can display "Search not available — this note contains only drawings."
    ///
    /// **Extension point:** A future version can call this same method on `note.ocrText`
    /// or `note.pdfText` and merge the results.
    func findInDocument(query: String, note: Note) -> [InDocumentMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !note.typedText.isEmpty else { return [] }

        var matches: [InDocumentMatch] = []
        let text = note.typedText
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(
                  of: trimmed,
                  options: .caseInsensitive,
                  range: searchStart ..< text.endIndex
              ) {
            let snippet = makeSnippet(in: text, around: trimmed, centeredAt: range)
            matches.append(InDocumentMatch(line: 0, range: range, snippet: snippet))
            // Advance past the current match to find the next one.
            searchStart = range.upperBound == text.endIndex
                ? text.endIndex
                : text.index(after: range.lowerBound)
        }

        return matches
    }

    // MARK: Private helpers

    /// Returns a short excerpt (≤ 80 characters) from `text` that centres on `query`.
    private func makeSnippet(in text: String, around query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            // Query not found literally — return leading characters.
            return String(text.prefix(80))
        }
        return makeSnippet(in: text, around: query, centeredAt: range)
    }

    private func makeSnippet(
        in text: String,
        around _: String,
        centeredAt range: Range<String.Index>
    ) -> String {
        let maxLength = 80
        let halfWindow = maxLength / 2

        // Walk back from the match start to create a left context window.
        let leading: String
        let distanceFromStart = text.distance(from: text.startIndex, to: range.lowerBound)
        if distanceFromStart <= halfWindow {
            leading = String(text[text.startIndex ..< range.lowerBound])
        } else {
            let startIdx = text.index(range.lowerBound, offsetBy: -halfWindow)
            leading = "…" + String(text[startIdx ..< range.lowerBound])
        }

        // Advance past the match to create a right context window.
        let remainingChars = maxLength - leading.count - text.distance(from: range.lowerBound, to: range.upperBound)
        let trailing: String
        let distanceToEnd = text.distance(from: range.upperBound, to: text.endIndex)
        if distanceToEnd <= max(remainingChars, 0) {
            trailing = String(text[range.upperBound ..< text.endIndex])
        } else {
            let endIdx = text.index(range.upperBound, offsetBy: max(remainingChars, 0))
            trailing = String(text[range.upperBound ..< endIdx]) + "…"
        }

        return leading + String(text[range]) + trailing
    }
}
