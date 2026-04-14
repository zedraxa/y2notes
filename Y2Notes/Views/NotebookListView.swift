import SwiftUI

// MARK: - Notebook List View (QuizJet-style grid / list browser)

/// Full-screen notebook browser with grid/list toggle, search, sort,
/// and spring-press interaction — ported from QuizJet and adapted to
/// Y2Notes' NoteStore data model.
struct NotebookListView: View {
    @EnvironmentObject private var noteStore: NoteStore

    /// Called when the user selects a notebook to open it.
    var onOpenNotebook: (UUID) -> Void

    @State private var searchText: String = ""
    @State private var useGridLayout: Bool = true
    @State private var sortOrder: NotebookSortOrder = .modified
    @State private var showNewNotebookSheet: Bool = false
    @State private var notebookToDelete: Notebook?
    @State private var showDeleteConfirmation: Bool = false
    @State private var notebookToRename: Notebook?
    @State private var renameText: String = ""

    // MARK: - Filtering + sorting

    private var filtered: [Notebook] {
        var result = noteStore.notebooks
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        // Pinned notebooks always float to the top.
        switch sortOrder {
        case .modified:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.modifiedAt > $1.modifiedAt
            }
        case .created:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
        case .name:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.name.localizedCompare($1.name) == .orderedAscending
            }
        case .lastOpened:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
        case .pageCount:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return noteStore.notes(inNotebook: $0.id).count >
                       noteStore.notes(inNotebook: $1.id).count
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        Group {
            if noteStore.notebooks.isEmpty {
                emptyState
            } else if useGridLayout {
                notebookGrid
            } else {
                notebookList
            }
        }
        .navigationTitle("Notebooks")
        .searchable(text: $searchText, prompt: "Search notebooks")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !noteStore.notebooks.isEmpty {
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(NotebookSortOrder.allCases, id: \.self) { order in
                                Label(order.displayName, systemImage: order.systemImage)
                                    .tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Sort notebooks")
                }

                Button {
                    withAnimation { useGridLayout.toggle() }
                } label: {
                    Image(systemName: useGridLayout ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(useGridLayout ? "Switch to list view" : "Switch to grid view")

                Button { showNewNotebookSheet = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Create new notebook")
            }
        }
        .sheet(isPresented: $showNewNotebookSheet) {
            NotebookQuickCreator()
        }
        .confirmationDialog(
            "Delete Notebook",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let nb = notebookToDelete { noteStore.deleteNotebook(id: nb.id) }
                notebookToDelete = nil
            }
            Button("Cancel", role: .cancel) { notebookToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(notebookToDelete?.name ?? "this notebook")\"? This cannot be undone.")
        }
        .alert("Rename Notebook", isPresented: Binding(
            get: { notebookToRename != nil },
            set: { if !$0 { notebookToRename = nil } }
        )) {
            TextField("Name", text: $renameText).submitLabel(.done)
            Button("Rename") {
                if let nb = notebookToRename,
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    noteStore.renameNotebook(
                        id: nb.id,
                        name: renameText.trimmingCharacters(in: .whitespaces)
                    )
                }
                notebookToRename = nil
            }
            Button("Cancel", role: .cancel) { notebookToRename = nil }
        }
    }

    // MARK: - Grid

    private var notebookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 16
            ) {
                ForEach(filtered) { nb in
                    NotebookGridCardView(
                        notebook: nb,
                        noteCount: noteStore.notes(inNotebook: nb.id).count
                    )
                    .onTapGesture { onOpenNotebook(nb.id) }
                    .contextMenu { contextMenu(for: nb) }
                }
            }
            .padding()
        }
    }

    // MARK: - List

    private var notebookList: some View {
        List {
            ForEach(filtered) { nb in
                NotebookListRowView(
                    notebook: nb,
                    noteCount: noteStore.notes(inNotebook: nb.id).count
                )
                .contentShape(Rectangle())
                .onTapGesture { onOpenNotebook(nb.id) }
                .contextMenu { contextMenu(for: nb) }
            }
            .onDelete { offsets in
                if let idx = offsets.first {
                    notebookToDelete = filtered[idx]
                    showDeleteConfirmation = true
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for nb: Notebook) -> some View {
        Button {
            notebookToRename = nb
            renameText = nb.name
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            noteStore.toggleNotebookPin(id: nb.id)
        } label: {
            Label(nb.isPinned ? "Unpin" : "Pin",
                  systemImage: nb.isPinned ? "pin.slash" : "pin")
        }

        Button {
            noteStore.toggleNotebookLock(id: nb.id)
        } label: {
            Label(nb.isLocked ? "Unlock" : "Lock",
                  systemImage: nb.isLocked ? "lock.open" : "lock")
        }

        Button {
            noteStore.duplicateNotebook(id: nb.id)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            notebookToDelete = nb
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse, options: .repeating)
            Text("No Notebooks Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Create your first notebook and start writing with Apple Pencil.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { showNewNotebookSheet = true } label: {
                Label("New Notebook", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Notebook grid card (QuizJet-style, adapted for Y2Notes)

struct NotebookGridCardView: View {
    let notebook: Notebook
    let noteCount: Int

    @State private var isPressed: Bool = false

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Cover ──────────────────────────────────────────────────────
            ZStack(alignment: .bottomTrailing) {
                coverBackground
                    .frame(height: 100)

                // Top overlay badges (pin, lock)
                VStack {
                    HStack {
                        if notebook.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()
                        if notebook.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                    .padding(6)
                    Spacer()
                }

                // Note-count badge (bottom-right)
                HStack(spacing: 3) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 8))
                    Text("\(noteCount)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
                .padding(8)
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            ))

            // ── Info ───────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(notebook.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if notebook.colorTag != .none {
                        Circle()
                            .fill(notebook.colorTag.color)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(Self.dateFormatter.localizedString(for: notebook.modifiedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !notebook.description.isEmpty {
                    Text(notebook.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .shadow(
            color: .black.opacity(isPressed ? 0.12 : 0.06),
            radius: isPressed ? 2 : 4,
            y: isPressed ? 1 : 2
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(notebook.name), \(noteCount) note\(noteCount == 1 ? "" : "s")"
            + (notebook.isLocked ? ", locked" : "")
        )
        .accessibilityHint("Double tap to open this notebook")
    }

    @ViewBuilder
    private var coverBackground: some View {
        if let data = notebook.customCoverData, let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
                .frame(height: 100)
                .clipped()
        } else {
            notebook.cover.gradient
        }
    }
}

// MARK: - Notebook list row (QuizJet-style, adapted for Y2Notes)

struct NotebookListRowView: View {
    let notebook: Notebook
    let noteCount: Int

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Cover strip
            Group {
                if let data = notebook.customCoverData, let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    notebook.cover.gradient
                }
            }
            .frame(width: 6)
            .cornerRadius(3)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        if notebook.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                        Text(notebook.name)
                            .font(.headline)
                        if notebook.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if notebook.colorTag != .none {
                            Circle()
                                .fill(notebook.colorTag.color)
                                .frame(width: 8, height: 8)
                        }
                        Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(6)
                    }
                }

                HStack(spacing: 6) {
                    Text(Self.dateFormatter.localizedString(for: notebook.modifiedAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if !notebook.description.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(notebook.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(notebook.name), \(noteCount) note\(noteCount == 1 ? "" : "s")"
            + (notebook.isLocked ? ", locked" : "")
        )
    }
}
