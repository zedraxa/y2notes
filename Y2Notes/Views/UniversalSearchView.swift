import SwiftUI

// MARK: - UniversalSearchView

/// Full-screen search sheet that queries across notebooks, notes, bookmarks, PDFs,
/// and all indexed content. Results are grouped by context and jump to exact locations
/// via `NavigationAnchor`.
///
/// **Search scope:** notebook titles, note titles, typed text, handwriting OCR,
/// bookmark labels, section names, sticker IDs, PDF titles, and attachment names/types.
///
/// **Jump behaviour:** Tapping a result dismisses the sheet and calls `onJump`
/// with either a `NavigationAnchor` (for in-notebook navigation) or a note/PDF ID
/// (for cross-notebook open). The caller resolves the anchor to a flat page index.
struct UniversalSearchView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore:  PDFStore
    @EnvironmentObject var navigationStore: NavigationStore
    @Environment(\.dismiss) private var dismiss

    /// The currently open notebook (if any) — used for "This Notebook" prioritisation.
    let currentNotebookID: UUID?

    /// Called when the user selects a note-level result. Receives noteID.
    let onSelectNote: (UUID) -> Void
    /// Called when the user selects a result with a navigation anchor for exact page jump.
    let onJumpToAnchor: (NavigationAnchor) -> Void
    /// Called when the user selects a PDF result. Receives pdfRecordID.
    var onSelectPDF: ((UUID) -> Void)?

    @State private var query = ""
    @State private var debouncedQuery = ""
    @FocusState private var queryFieldFocused: Bool
    @State private var searchIndex = SearchIndex()

    // MARK: - Computed results

    private var results: [UniversalSearchResult] {
        searchIndex.search(query: debouncedQuery, currentNotebookID: currentNotebookID)
    }

    private var groupedResults: [(group: SearchResultGroup, results: [UniversalSearchResult])] {
        searchIndex.groupResults(results, currentNotebookID: currentNotebookID)
    }

    private var hasAnyResults: Bool { !results.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchPromptView
                } else if !hasAnyResults {
                    noResultsView
                } else {
                    resultsListView
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Notes, bookmarks, handwriting, attachments, PDFs…"
            )
            .task(id: query) {
                // §2 Search constraint: debounce input by 0.3 s to avoid
                // per-keystroke work.  `.task(id:)` auto-cancels on each
                // new keystroke, so only the final value fires.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                debouncedQuery = query
            }
            .onAppear {
                rebuildIndex()
                queryFieldFocused = true
            }
        }
    }

    // MARK: - Idle state

    private var searchPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Search everything")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Titles, typed text, handwriting, bookmarks, notebooks, attachments, and PDFs")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - No results

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No results for \"\(query)\"")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Try a different keyword or check the spelling.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Results list

    private var resultsListView: some View {
        List {
            ForEach(groupedResults, id: \.group) { section in
                Section(section.group.rawValue) {
                    ForEach(section.results) { result in
                        resultRow(result)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Result row

    @ViewBuilder
    private func resultRow(_ result: UniversalSearchResult) -> some View {
        Button {
            handleSelection(result)
        } label: {
            HStack(spacing: 12) {
                resultIcon(result)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.entry.primaryText.isEmpty ? "Untitled" : result.entry.primaryText)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if !result.snippet.isEmpty {
                        Text(result.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 4) {
                        ForEach(Array(result.matchKinds), id: \.self) { kind in
                            matchBadge(kind)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icons

    private func resultIcon(_ result: UniversalSearchResult) -> some View {
        let name: String
        switch result.entry.kind {
        case .noteTitle, .noteText, .noteOCR:
            name = "doc.text"
        case .notebookName:
            name = "book.closed"
        case .bookmarkLabel:
            name = "bookmark.fill"
        case .sectionName:
            name = "folder"
        case .stickerLabel:
            name = "star.circle"
        case .pdfTitle:
            name = "doc.richtext.fill"
        case .attachmentLabel:
            name = "paperclip"
        case .audioSession, .audioTimestamp:
            name = "waveform"
        case .widgetContent:
            name = "square.grid.2x2"
        }
        return Image(systemName: name)
    }

    @ViewBuilder
    private func matchBadge(_ kind: SearchEntryKind) -> some View {
        let (icon, label): (String, String) = {
            switch kind {
            case .noteTitle:       return ("textformat", "Title")
            case .noteText:        return ("text.alignleft", "Text")
            case .noteOCR:         return ("pencil.and.scribble", "Handwriting")
            case .notebookName:    return ("book.closed", "Notebook")
            case .bookmarkLabel:   return ("bookmark", "Bookmark")
            case .sectionName:     return ("folder", "Section")
            case .stickerLabel:    return ("star.circle", "Sticker")
            case .pdfTitle:        return ("doc.richtext", "PDF")
            case .attachmentLabel: return ("paperclip", "Attachment")
            case .audioSession:    return ("waveform", "Audio")
            case .audioTimestamp:  return ("clock.badge.waveform", "Timestamp")
            case .widgetContent:   return ("square.grid.2x2", "Widget")
            }
        }()

        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    // MARK: - Selection handling

    private func handleSelection(_ result: UniversalSearchResult) {
        dismiss()

        // If the result has a direct anchor, use it for exact page jump
        if let anchor = result.entry.anchor {
            onJumpToAnchor(anchor)
            return
        }

        // Otherwise resolve by kind
        switch result.entry.kind {
        case .noteTitle, .noteText, .noteOCR, .stickerLabel, .attachmentLabel, .widgetContent:
            // Extract noteID from the entry id (format: "note-<UUID>-suffix")
            if let noteID = extractNoteID(from: result.entry.id) {
                onSelectNote(noteID)
            }
        case .pdfTitle:
            if let pdfID = extractUUID(from: result.entry.id, prefix: "pdf-") {
                onSelectPDF?(pdfID)
            }
        case .notebookName:
            // Open the notebook — caller can handle via onSelectNote for the first note
            break
        case .bookmarkLabel:
            // Bookmarks always have anchors — handled above
            break
        case .sectionName:
            break
        case .audioSession, .audioTimestamp:
            // Audio entries — jump to the associated note if possible
            if let noteID = extractNoteID(from: result.entry.id) {
                onSelectNote(noteID)
            }
        }
    }

    private func extractNoteID(from entryID: String) -> UUID? {
        // Format: "note-<UUID>-title" or "note-<UUID>-text" etc.
        // UUID is 36 chars: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        guard entryID.hasPrefix("note-") else { return nil }
        let afterPrefix = entryID.dropFirst(5) // drop "note-"
        guard afterPrefix.count >= 36 else { return nil }
        let uuidString = String(afterPrefix.prefix(36))
        return UUID(uuidString: uuidString)
    }

    private func extractUUID(from entryID: String, prefix: String) -> UUID? {
        guard entryID.hasPrefix(prefix) else { return nil }
        let remainder = String(entryID.dropFirst(prefix.count))
        return UUID(uuidString: remainder)
    }

    // MARK: - Index management

    private func rebuildIndex() {
        let storageManager = AudioStorageManager.shared
        searchIndex.rebuild(
            notes: noteStore.notes,
            notebooks: noteStore.notebooks,
            sections: noteStore.sections,
            bookmarks: navigationStore.bookmarks,
            pdfRecords: pdfStore.records,
            audioStorageManager: storageManager,
            isRecordingActive: storageManager.isRecordingActive
        )
    }
}
