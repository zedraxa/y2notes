import SwiftUI

// MARK: - Library search view

/// Full-screen sheet that searches all notes by title, typed text, and notebook name.
///
/// Results are grouped by notebook and sorted by relevance score.
/// Tapping a result calls `onSelectNote` so the caller can navigate to the note.
struct LibrarySearchView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a result row. Dismiss the sheet and navigate to the note.
    let onSelectNote: (UUID) -> Void

    @State private var query = ""
    @FocusState private var queryFieldFocused: Bool

    private let searchService = SearchService()

    private var results: [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return searchService.search(
            query: query,
            in: noteStore.notes,
            notebooks: noteStore.notebooks
        )
    }

    /// Results grouped by notebook (nil group = unfiled).
    private var groupedResults: [(notebookName: String, results: [SearchResult])] {
        var groups: [UUID?: [SearchResult]] = [:]
        for result in results {
            groups[result.notebookID, default: []].append(result)
        }

        var output: [(notebookName: String, results: [SearchResult])] = []

        // Notebooks first (alphabetical), then unfiled.
        let sortedNBIDs = groups.keys.compactMap { $0 }.sorted { a, b in
            let na = noteStore.notebooks.first { $0.id == a }?.name ?? ""
            let nb = noteStore.notebooks.first { $0.id == b }?.name ?? ""
            return na.localizedCompare(nb) == .orderedAscending
        }
        for nbID in sortedNBIDs {
            if let batch = groups[nbID] {
                let name = noteStore.notebooks.first { $0.id == nbID }?.name ?? "Unknown Notebook"
                output.append((notebookName: name, results: batch))
            }
        }
        if let unfiled = groups[nil] {
            output.append((notebookName: "Unfiled", results: unfiled))
        }
        return output
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchPrompt
                } else if results.isEmpty {
                    noResults
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search titles, text, notebooks…"
            )
            .onAppear { queryFieldFocused = true }
        }
    }

    // MARK: Idle state

    private var searchPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Search across all your notes")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Matches titles, typed text, and notebook names")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: No results

    private var noResults: some View {
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

    // MARK: Results list

    private var resultsList: some View {
        List {
            ForEach(groupedResults, id: \.notebookName) { group in
                Section(group.notebookName) {
                    ForEach(group.results) { result in
                        if let note = noteStore.notes.first(where: { $0.id == result.noteID }) {
                            SearchResultRow(note: note, result: result)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    dismiss()
                                    onSelectNote(note.id)
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let note: Note
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                matchBadges
            }

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(note.modifiedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var matchBadges: some View {
        HStack(spacing: 4) {
            if result.matchTypes.contains(.typedText) {
                Image(systemName: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if result.matchTypes.contains(.notebookName) {
                Image(systemName: "book.closed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
