import SwiftUI

// MARK: - Sort order

enum NoteSortOrder: String, CaseIterable, Identifiable {
    case modifiedDescending = "Last Modified"
    case modifiedAscending  = "Oldest First"
    case titleAscending     = "Title A→Z"
    case titleDescending    = "Title Z→A"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .modifiedDescending: return "clock.arrow.circlepath"
        case .modifiedAscending:  return "clock"
        case .titleAscending:     return "textformat.abc"
        case .titleDescending:    return "textformat"
        }
    }
}

// MARK: - Note list

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?

    @State private var searchText = ""
    @State private var sortOrder: NoteSortOrder = .modifiedDescending

    // Filtered and sorted projection of the store — computed on demand.
    private var displayedNotes: [Note] {
        let base: [Note] = searchText.isEmpty
            ? noteStore.notes
            : noteStore.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .modifiedDescending:
            return base.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedAscending:
            return base.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAscending:
            return base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return base.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            if displayedNotes.isEmpty && !searchText.isEmpty {
                noResultsRow
            } else {
                ForEach(displayedNotes) { note in
                    NoteRowView(note: note)
                        .tag(note.id)
                        // Leading swipe: duplicate
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                duplicateNote(note)
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                }
                .onDelete(perform: deleteNotes)
            }
        }
        .navigationTitle("Y2Notes")
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                sortMenu
                Button(action: createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
        }
    }

    // MARK: - Sort menu

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(NoteSortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.systemImage)
                        .tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel("Sort notes")
        }
    }

    // MARK: - No-results placeholder

    private var noResultsRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Results")
                .font(.headline)
            Text("No notes match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func createNote() {
        let note = noteStore.addNote()
        selectedNoteID = note.id
    }

    private func duplicateNote(_ note: Note) {
        if let copy = noteStore.duplicateNote(noteID: note.id) {
            selectedNoteID = copy.id
        }
    }

    /// Delete using IDs so indices stay valid against the filtered/sorted projection.
    private func deleteNotes(at offsets: IndexSet) {
        let idsToDelete = offsets.map { displayedNotes[$0].id }
        idsToDelete.forEach { noteStore.deleteNote(noteID: $0) }
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(note.title.isEmpty ? .secondary : .primary)
            Text(note.modifiedAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

