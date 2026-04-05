import SwiftUI
import PencilKit

// MARK: - Sort order

enum NoteSortOrder: String, CaseIterable {
    case modifiedDesc = "Recently Modified"
    case modifiedAsc  = "Oldest Modified"
    case titleAsc     = "Title A–Z"
    case titleDesc    = "Title Z–A"
    case createdDesc  = "Newest Created"
    case createdAsc   = "Oldest Created"

    var systemImage: String {
        switch self {
        case .modifiedDesc, .createdDesc: return "arrow.down.circle"
        case .modifiedAsc,  .createdAsc:  return "arrow.up.circle"
        case .titleAsc:                   return "textformat.abc"
        case .titleDesc:                  return "textformat.abc"
        }
    }
}

// MARK: - Note list

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?

    @State private var searchText  = ""
    @State private var sortOrder: NoteSortOrder = .modifiedDesc
    @State private var showThemePicker = false
    @State private var showNoteCreationSheet = false
    @State private var showNotebookWizard = false
    @State private var notesPendingDeletion: IndexSet?

    private let sortFeedback   = UISelectionFeedbackGenerator()
    private let deleteFeedback = UINotificationFeedbackGenerator()

    private let sortFeedback   = UISelectionFeedbackGenerator()
    private let deleteFeedback = UINotificationFeedbackGenerator()

    // Filtered + sorted projection of the store.
    private var displayedNotes: [Note] {
        let source = searchText.isEmpty
            ? noteStore.notes
            : noteStore.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .modifiedDesc: return source.sorted { $0.modifiedAt > $1.modifiedAt }
        case .modifiedAsc:  return source.sorted { $0.modifiedAt < $1.modifiedAt }
        case .titleAsc:     return source.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleDesc:    return source.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .createdDesc:  return source.sorted { $0.createdAt > $1.createdAt }
        case .createdAsc:   return source.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        List(selection: $selectedNoteID) {
            ForEach(displayedNotes) { note in
                NoteRowView(note: note)
                    .tag(note.id)
            }
            .onDelete { offsets in
                notesPendingDeletion = offsets
            }
        }
        .animation(.default, value: displayedNotes.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: displayedNotes.map(\.id))
        .navigationTitle("Y2Notes")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // GoodNotes-style "+" New menu.
                Menu {
                    Button {
                        quickNote()
                    } label: {
                        Label("Quick Note", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button {
                        showNoteCreationSheet = true
                    } label: {
                        Label("New Note…", systemImage: "doc.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Divider()

                    Button {
                        showNotebookWizard = true
                    } label: {
                        Label("New Notebook…", systemImage: "book.closed.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New")
                .accessibilityHint("Opens a menu to create a new note or notebook")
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showThemePicker = true
                } label: {
                    Image(systemName: "paintpalette")
                }
                .accessibilityLabel("Choose theme")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .overlay {
            if displayedNotes.isEmpty {
                emptyOverlay
            }
        }
        .confirmationDialog(
            "Delete Note",
            isPresented: Binding(
                get: { notesPendingDeletion != nil },
                set: { if !$0 { notesPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let offsets = notesPendingDeletion {
                    deleteDisplayedNotes(at: offsets)
                }
                notesPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                notesPendingDeletion = nil
            }
        } message: {
            if let offsets = notesPendingDeletion {
                let count = offsets.count
                Text("Are you sure you want to delete \(count) note\(count == 1 ? "" : "s")? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerView()
        }
        .sheet(isPresented: $showNoteCreationSheet) {
            NoteCreationSheet(
                notebookID: nil,
                onCreated: { id in selectedNoteID = id }
            )
        }
        .sheet(isPresented: $showNotebookWizard) {
            NotebookQuickCreator()
        }
    }

    // MARK: Sort menu

    private var sortMenu: some View {
        Menu {
            ForEach(NoteSortOrder.allCases, id: \.self) { order in
                Button {
                    sortFeedback.selectionChanged()
                    sortOrder = order
                } label: {
                    if sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort notes")
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyOverlay: some View {
        if !searchText.isEmpty {
            EmptySearchStateView(query: searchText)
        } else if noteStore.notes.isEmpty {
            EmptyLibraryStateView {
                showNoteCreationSheet = true
            }
        }
    }

    // MARK: Actions

    private func quickNote() {
        let note = noteStore.addNote()
        selectedNoteID = note.id
    }

    /// `onDelete` passes offsets into `displayedNotes` (filtered/sorted), so we map to IDs
    /// before handing off to the store to avoid index mismatch.
    private func deleteDisplayedNotes(at offsets: IndexSet) {
        deleteFeedback.notificationOccurred(.warning)
        let ids = offsets.map { displayedNotes[$0].id }
        noteStore.deleteNotes(ids: ids)
    }
}

// MARK: - Empty: no search results

private struct EmptySearchStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No notes match \"\(query)\"")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Empty: no notes at all

private struct EmptyLibraryStateView: View {
    let onCreateNote: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.8

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

            VStack(spacing: 8) {
                Text("No Notes Yet")
                    .font(.title2.bold())
                    .foregroundStyle(Color(uiColor: .label))
                Text("Tap the button below to create your first note.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .opacity(textOpacity)

            Button {
                onCreateNote()
            } label: {
                Label("Create a Note", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .scaleEffect(buttonScale)
            .opacity(textOpacity)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.3)) {
                textOpacity = 1.0
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.4)) {
                buttonScale = 1.0
            }
        }
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: Note

    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = false

    var body: some View {
        HStack(spacing: 12) {
            // Color label stripe on the left edge of the thumbnail
            if let label = note.colorLabel {
                label.color
                    .frame(width: 3)
                    .clipShape(Capsule())
                    .padding(.vertical, 6)
            }

            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .foregroundStyle(note.title.isEmpty ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                    .lineLimit(1)
                Text(note.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.09), in: Capsule())
                                .lineLimit(1)
                        }
                        if note.tags.count > 3 {
                            Text("+\(note.tags.count - 3)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // Re-generate the thumbnail whenever the drawing data changes.
        .task(id: note.drawingData) {
            isLoadingThumbnail = true
            thumbnail = await makeThumbnail(from: note.drawingData)
            isLoadingThumbnail = false
        }
    }

    // MARK: Thumbnail view

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(uiColor: .secondaryLabel).opacity(0.25), lineWidth: 0.5)
                )

            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if isLoadingThumbnail {
                ShimmerView()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.4))
            }
        }
        .frame(width: 60, height: 44)
    }

    // MARK: Thumbnail generation

    /// Renders the stored PKDrawing to a small UIImage on a background thread.
    /// Returns nil when the note has no strokes yet.
    private func makeThumbnail(from data: Data) async -> UIImage? {
        guard !data.isEmpty else { return nil }

        return await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data),
                  !drawing.bounds.isEmpty else { return nil }

            // Expand the tight bounding box so strokes near the edge aren't clipped.
            let renderRect = drawing.bounds.insetBy(dx: -20, dy: -20)

            // Target ≈ 120×90 px output: derive scale so the longer axis fits,
            // then halve it to keep the image lightweight.
            let targetWidth:  CGFloat = 120
            let targetHeight: CGFloat = 90
            let scale = max(targetWidth / renderRect.width,
                            targetHeight / renderRect.height) * 0.5
            return drawing.image(from: renderRect, scale: scale)
        }.value
    }
}

// MARK: - Shimmer skeleton view

/// A horizontal shimmer animation used as a loading placeholder.
private struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(uiColor: .systemFill), location: 0),
                            .init(color: Color(uiColor: .tertiarySystemFill).opacity(0.6), location: 0.4),
                            .init(color: Color(uiColor: .systemFill), location: 1)
                        ],
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 1, y: 0.5)
                    )
                )
                .frame(width: w)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}
