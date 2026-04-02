import SwiftUI
import PencilKit
import PDFKit

// MARK: - Library section

enum LibrarySection: Hashable {
    case allNotes
    case recents
    case favorites
    case notebook(UUID)
    case pdfLibrary
}

// MARK: - Cover gradients (SwiftUI extension on model type)

extension NotebookCover {
    var gradient: LinearGradient {
        switch self {
        case .ocean:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forest:
            return LinearGradient(
                colors: [Color(red: 0.10, green: 0.55, blue: 0.30), .mint],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .sunset:
            return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lavender:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .slate:
            return LinearGradient(
                colors: [Color(white: 0.32), Color(white: 0.52)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .sand:
            return LinearGradient(
                colors: [Color(red: 0.88, green: 0.78, blue: 0.58), Color(red: 0.95, green: 0.88, blue: 0.74)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Root shelf view

/// Three-column NavigationSplitView:
///   Sidebar  — library sections + notebooks list + PDF Documents entry
///   Content  — note grid or PDF library for the selected section
///   Detail   — note editor, PDF viewer, or placeholder
struct ShelfView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore:  PDFStore

    @State private var selectedSection: LibrarySection? = .allNotes
    @State private var selectedNoteID: UUID?
    @State private var selectedPDFID:  UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteStore.notes.first { $0.id == id }
    }

    private var selectedPDFRecord: PDFNoteRecord? {
        guard let id = selectedPDFID else { return nil }
        return pdfStore.records.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ShelfSidebarView(
                selectedSection: $selectedSection,
                onSelectNote: { id in selectedNoteID = id }
            )
        } content: {
            if case .pdfLibrary = selectedSection {
                PDFLibraryView(selectedPDFID: $selectedPDFID)
            } else {
                NoteGridView(
                    section: selectedSection ?? .allNotes,
                    selectedNoteID: $selectedNoteID
                )
            }
        } detail: {
            if let record = selectedPDFRecord {
                PDFViewerView(record: record)
                    .id(record.id)
            } else if let note = selectedNote {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                ShelfDetailPlaceholder()
            }
        }
        // Clear note selection when switching to the PDF section and vice versa.
        .onChange(of: selectedSection) { section in
            if case .pdfLibrary = section {
                selectedNoteID = nil
            } else {
                selectedPDFID = nil
            }
        }
        // If the selected note is deleted elsewhere, clear the selection.
        .onChange(of: noteStore.notes) { _ in
            if let id = selectedNoteID, !noteStore.notes.contains(where: { $0.id == id }) {
                selectedNoteID = nil
            }
        }
        // If the selected PDF record is deleted, clear the selection.
        .onChange(of: pdfStore.records) { _ in
            if let id = selectedPDFID, !pdfStore.records.contains(where: { $0.id == id }) {
                selectedPDFID = nil
            }
        }
    }
}

// MARK: - Sidebar

private struct ShelfSidebarView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore:  PDFStore
    @Binding var selectedSection: LibrarySection?

    @State private var showNewNotebookSheet = false
    @State private var notebookToRename: Notebook?
    @State private var renameText = ""
    @State private var showLibrarySearch = false

    // Binding passed down from ShelfView so tapping a search result selects the note.
    var onSelectNote: (UUID) -> Void

    var body: some View {
        List(selection: $selectedSection) {
            // ── Library ──────────────────────────────────────────────────
            Section("Library") {
                Label("All Notes", systemImage: "doc.plaintext.fill")
                    .tag(LibrarySection.allNotes)
                    .badge(noteStore.notes.count)

                Label("Recents", systemImage: "clock.fill")
                    .tag(LibrarySection.recents)

                Label("Favorites", systemImage: "star.fill")
                    .tag(LibrarySection.favorites)
                    .badge(noteStore.favoritedNotes.count)
                    .foregroundStyle(noteStore.favoritedNotes.isEmpty ? .secondary : .yellow)

                Label("PDF Documents", systemImage: "doc.richtext")
                    .tag(LibrarySection.pdfLibrary)
                    .badge(pdfStore.records.count)
            }

            // ── Study ─────────────────────────────────────────────────────
            Section("Study") {
                NavigationLink(destination: StudySetListView()) {
                    Label("Study Sets", systemImage: "rectangle.on.rectangle.angled")
                        .badge(noteStore.studySets.count)
                }
            }

            // ── Notebooks ─────────────────────────────────────────────────
            Section {
                ForEach(noteStore.notebooks) { notebook in
                    NotebookSidebarRow(
                        notebook: notebook,
                        noteCount: noteStore.notes(inNotebook: notebook.id).count
                    )
                    .tag(LibrarySection.notebook(notebook.id))
                    .contextMenu {
                        Button {
                            notebookToRename = notebook
                            renameText = notebook.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Menu {
                            ForEach(NotebookCover.allCases, id: \.self) { cover in
                                Button(cover.displayName) {
                                    noteStore.updateNotebookCover(id: notebook.id, cover: cover)
                                }
                            }
                        } label: {
                            Label("Change Cover", systemImage: "paintpalette")
                        }

                        Divider()

                        Button(role: .destructive) {
                            noteStore.deleteNotebook(id: notebook.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { noteStore.notebooks[$0].id }.forEach {
                        noteStore.deleteNotebook(id: $0)
                    }
                }
            } header: {
                HStack {
                    Text("Notebooks")
                    Spacer()
                    Button {
                        showNewNotebookSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Notebook")
                }
            }

            // ── Google Drive ─────────────────────────────────────────────
            Section("Google Drive") {
                NavigationLink(destination: GoogleDriveSettingsView()) {
                    Label {
                        Text("Drive Settings")
                    } icon: {
                        Image(systemName: "externaldrive.fill")
                    }
                }
                GoogleDriveSyncStatusView()
            }
        }
        .navigationTitle("Y2Notes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showLibrarySearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search library")
            }
        }
        .sheet(isPresented: $showNewNotebookSheet) {
            NotebookCreationWizard()
        }
        .sheet(isPresented: $showLibrarySearch) {
            LibrarySearchView(onSelectNote: onSelectNote)
        }
        .alert("Rename Notebook", isPresented: Binding(
            get: { notebookToRename != nil },
            set: { if !$0 { notebookToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
                .submitLabel(.done)
            Button("Rename") {
                if let nb = notebookToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    noteStore.renameNotebook(id: nb.id, name: renameText.trimmingCharacters(in: .whitespaces))
                }
                notebookToRename = nil
            }
            Button("Cancel", role: .cancel) { notebookToRename = nil }
        }
    }
}

// MARK: - Notebook sidebar row

private struct NotebookSidebarRow: View {
    let notebook: Notebook
    let noteCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // Mini cover swatch
            RoundedRectangle(cornerRadius: 5)
                .fill(notebook.cover.gradient)
                .frame(width: 28, height: 36)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                )
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Note grid (middle column)

struct NoteGridView: View {
    @EnvironmentObject var noteStore: NoteStore
    let section: LibrarySection
    @Binding var selectedNoteID: UUID?

    @State private var showMoveSheet: Note?
    @State private var noteToRename: Note?
    @State private var renameText = ""

    private var notes: [Note] {
        switch section {
        case .allNotes:
            return noteStore.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        case .recents:
            return noteStore.recentNotes
        case .favorites:
            return noteStore.favoritedNotes
        case .notebook(let id):
            return noteStore.notes(inNotebook: id).sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private var sectionTitle: String {
        switch section {
        case .allNotes:           return "All Notes"
        case .recents:            return "Recents"
        case .favorites:          return "Favorites"
        case .notebook(let id):
            return noteStore.notebooks.first { $0.id == id }?.name ?? "Notebook"
        }
    }

    private var notebookForSection: Notebook? {
        guard case .notebook(let id) = section else { return nil }
        return noteStore.notebooks.first { $0.id == id }
    }

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 16)]

    var body: some View {
        Group {
            if notes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(notes) { note in
                            NoteCardView(note: note, isSelected: selectedNoteID == note.id)
                                .onTapGesture { selectedNoteID = note.id }
                                .contextMenu { noteContextMenu(for: note) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(sectionTitle)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New Note")
            }
            if let nb = notebookForSection {
                ToolbarItem(placement: .navigationBarLeading) {
                    NotebookCoverBadge(cover: nb.cover)
                }
            }
        }
        .sheet(item: $showMoveSheet) { note in
            MoveNoteSheet(note: note)
        }
        .alert("Rename Note", isPresented: Binding(
            get: { noteToRename != nil },
            set: { if !$0 { noteToRename = nil } }
        )) {
            TextField("Title", text: $renameText)
                .submitLabel(.done)
            Button("Rename") {
                if let n = noteToRename {
                    noteStore.updateTitle(for: n.id, title: renameText)
                }
                noteToRename = nil
            }
            Button("Cancel", role: .cancel) { noteToRename = nil }
        }
    }

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        Button {
            noteToRename = note
            renameText = note.title
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            noteStore.toggleFavorite(id: note.id)
        } label: {
            Label(
                note.isFavorited ? "Remove from Favorites" : "Add to Favorites",
                systemImage: note.isFavorited ? "star.slash" : "star"
            )
        }

        Button {
            if let copy = noteStore.duplicateNote(id: note.id) {
                selectedNoteID = copy.id
            }
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            showMoveSheet = note
        } label: {
            Label("Move to Notebook…", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            if selectedNoteID == note.id { selectedNoteID = nil }
            noteStore.deleteNotes(ids: [note.id])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func createNote() {
        let notebookID: UUID?
        if case .notebook(let id) = section { notebookID = id } else { notebookID = nil }
        let note = noteStore.addNote(inNotebook: notebookID)
        selectedNoteID = note.id
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyIcon)
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(emptySubtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button(action: createNote) {
                Label("New Note", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyIcon: String {
        switch section {
        case .allNotes:  return "square.and.pencil"
        case .recents:   return "clock"
        case .favorites: return "star"
        case .notebook:  return "book.closed"
        }
    }

    private var emptyTitle: String {
        switch section {
        case .allNotes:  return "No Notes Yet"
        case .recents:   return "No Recent Notes"
        case .favorites: return "No Favorites Yet"
        case .notebook:  return "Empty Notebook"
        }
    }

    private var emptySubtitle: String {
        switch section {
        case .allNotes:  return "Tap the pencil button to write your first note."
        case .recents:   return "Notes you open recently will appear here."
        case .favorites: return "Tap ★ in a note's menu to collect favorites here."
        case .notebook:  return "Tap the pencil button to add notes to this notebook."
        }
    }
}

// MARK: - Notebook cover badge (toolbar)

private struct NotebookCoverBadge: View {
    let cover: NotebookCover

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(cover.gradient)
            .frame(width: 22, height: 28)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

// MARK: - Note card

private struct NoteCardView: View {
    let note: Note
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Canvas preview area
            ZStack {
                Color(uiColor: .systemBackground)

                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else if note.drawingData.isEmpty {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                } else {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)

            Divider()

            // Footer
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(note.title.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if note.isFavorited {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(note.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .task(id: note.drawingData) {
            thumbnail = await makeThumbnail(from: note.drawingData)
        }
    }

    private func makeThumbnail(from data: Data) async -> UIImage? {
        guard !data.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data),
                  !drawing.bounds.isEmpty else { return nil }
            let renderRect = drawing.bounds.insetBy(dx: -20, dy: -20)
            let scale = max(200 / renderRect.width, 150 / renderRect.height) * 0.5
            return drawing.image(from: renderRect, scale: scale)
        }.value
    }
}

// MARK: - PDF library (middle column)

private struct PDFLibraryView: View {
    @EnvironmentObject var pdfStore: PDFStore
    @Binding var selectedPDFID: UUID?

    @State private var showImporter = false
    @State private var recordToDelete: PDFNoteRecord?
    @State private var showDeleteConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 16)]

    var body: some View {
        Group {
            if pdfStore.records.isEmpty {
                pdfEmptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(pdfStore.records) { record in
                            PDFCardView(record: record, isSelected: selectedPDFID == record.id)
                                .onTapGesture { selectedPDFID = record.id }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        recordToDelete  = record
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("PDF Documents")
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImporter = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import PDF")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let record = pdfStore.importPDF(from: url) {
                    selectedPDFID = record.id
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(recordToDelete?.title ?? "PDF")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let r = recordToDelete {
                    if selectedPDFID == r.id { selectedPDFID = nil }
                    pdfStore.deleteRecord(id: r.id)
                }
                recordToDelete = nil
            }
            Button("Cancel", role: .cancel) { recordToDelete = nil }
        } message: {
            Text("The PDF file and all its annotations will be permanently deleted.")
        }
    }

    // MARK: Empty state

    private var pdfEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No PDF Documents")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Import a PDF to annotate it with your Apple Pencil.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button { showImporter = true } label: {
                Label("Import PDF", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - PDF card

private struct PDFCardView: View {
    let record: PDFNoteRecord
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover thumbnail
            ZStack {
                Color(uiColor: .systemBackground)
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)

            Divider()

            // Footer
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? "Untitled PDF" : record.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(record.title.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                HStack {
                    Text("\(record.pageCount) page\(record.pageCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if !record.annotationData.isEmpty {
                        Image(systemName: "pencil.tip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .task(id: record.pdfFilename) {
            thumbnail = await makePDFThumbnail(for: record)
        }
    }

    private func makePDFThumbnail(for record: PDFNoteRecord) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            // Access pdfStore via the record filename directly — avoids environment capture.
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs
                .appendingPathComponent("PDFNotes")
                .appendingPathComponent(record.pdfFilename)
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: 0) else { return nil }
            let mediaBox = page.bounds(for: .mediaBox)
            let aspectRatio = mediaBox.height / max(mediaBox.width, 1)
            let targetSize = CGSize(width: 200, height: 200 * aspectRatio)
            return page.thumbnail(of: targetSize, for: .mediaBox)
        }.value
    }
}

// MARK: - Detail placeholder

private struct ShelfDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Select a note to start writing")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Or create a new note with the pencil button")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}


// MARK: - Move Note sheet

private struct MoveNoteSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let note: Note

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        noteStore.moveNote(id: note.id, toNotebook: nil)
                        dismiss()
                    } label: {
                        HStack {
                            Label("No Notebook (Unfiled)", systemImage: "tray")
                            Spacer()
                            if note.notebookID == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                if !noteStore.notebooks.isEmpty {
                    Section("Notebooks") {
                        ForEach(noteStore.notebooks) { notebook in
                            Button {
                                noteStore.moveNote(id: note.id, toNotebook: notebook.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(notebook.cover.gradient)
                                        .frame(width: 28, height: 36)
                                        .overlay(
                                            Image(systemName: "book.closed.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.85))
                                        )
                                    Text(notebook.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if note.notebookID == notebook.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
