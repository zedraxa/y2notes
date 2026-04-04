// swiftlint:disable file_length
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
    case documentLibrary
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
        case .ruby:
            return LinearGradient(colors: [Color(red: 0.72, green: 0.11, blue: 0.11), Color(red: 0.90, green: 0.30, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.20), Color(red: 0.15, green: 0.15, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .jade:
            return LinearGradient(colors: [Color(red: 0.00, green: 0.50, blue: 0.30), Color(red: 0.20, green: 0.70, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .coral:
            return LinearGradient(colors: [Color(red: 1.00, green: 0.50, blue: 0.31), Color(red: 1.00, green: 0.70, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .copper:
            return LinearGradient(colors: [Color(red: 0.72, green: 0.45, blue: 0.20), Color(red: 0.85, green: 0.60, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .nebula:
            return LinearGradient(colors: [Color(red: 0.30, green: 0.10, blue: 0.50), Color(red: 0.55, green: 0.20, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    @EnvironmentObject var documentStore: DocumentStore

    @State private var selectedSection: LibrarySection? = .allNotes
    @State private var selectedNoteID: UUID?
    @State private var selectedPDFID:  UUID?
    @State private var selectedDocumentID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return noteStore.notes.first { $0.id == id }
    }

    private var selectedPDFRecord: PDFNoteRecord? {
        guard let id = selectedPDFID else { return nil }
        return pdfStore.records.first { $0.id == id }
    }

    private var selectedDocument: ImportedDocument? {
        guard let id = selectedDocumentID else { return nil }
        return documentStore.documents.first { $0.id == id }
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
            } else if case .documentLibrary = selectedSection {
                DocumentLibraryView()
            } else {
                NoteGridView(
                    section: selectedSection ?? .allNotes,
                    selectedNoteID: $selectedNoteID
                )
            }
        } detail: {
            if let doc = selectedDocument {
                DocumentViewerView(
                    document: doc,
                    fileURL: documentStore.storedURL(for: doc)
                )
                .id(doc.id)
            } else if let record = selectedPDFRecord {
                PDFViewerView(record: record)
                    .id(record.id)
            } else if let note = selectedNote {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                ShelfDetailPlaceholder()
            }
        }
        // Clear irrelevant selections when switching sections.
        .onChange(of: selectedSection) { _, section in
            switch section {
            case .pdfLibrary:
                selectedNoteID = nil
                selectedDocumentID = nil
            case .documentLibrary:
                selectedNoteID = nil
                selectedPDFID  = nil
            default:
                selectedPDFID  = nil
                selectedDocumentID = nil
            }
        }
        // If the selected note is deleted elsewhere, clear the selection.
        .onChange(of: noteStore.notes) { _, _ in
            if let id = selectedNoteID, !noteStore.notes.contains(where: { $0.id == id }) {
                selectedNoteID = nil
            }
        }
        // If the selected PDF record is deleted, clear the selection.
        .onChange(of: pdfStore.records) { _, _ in
            if let id = selectedPDFID, !pdfStore.records.contains(where: { $0.id == id }) {
                selectedPDFID = nil
            }
        }
        // If the selected document is deleted, clear the selection.
        .onChange(of: documentStore.documents) { _, _ in
            if let id = selectedDocumentID, !documentStore.documents.contains(where: { $0.id == id }) {
                selectedDocumentID = nil
            }
        }
    }
}

// MARK: - Sidebar

private struct ShelfSidebarView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore:  PDFStore
    @EnvironmentObject var documentStore: DocumentStore
    @Binding var selectedSection: LibrarySection?

    @State private var showNewNotebookSheet = false
    @State private var notebookToRename: Notebook?
    @State private var renameText = ""
    @State private var showLibrarySearch = false
    @State private var showSettings = false
    @State private var sidebarManageSectionsNotebook: Notebook?

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
                    .foregroundStyle(noteStore.favoritedNotes.isEmpty ? Color(uiColor: .secondaryLabel) : Color.yellow)

                Label("PDF Documents", systemImage: "doc.richtext")
                    .tag(LibrarySection.pdfLibrary)
                    .badge(pdfStore.records.count)

                Label("Documents", systemImage: "doc.fill")
                    .tag(LibrarySection.documentLibrary)
                    .badge(documentStore.documents.count)
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
                        noteCount: noteStore.notes(inNotebook: notebook.id).count,
                        sectionCount: noteStore.sections(inNotebook: notebook.id).filter { $0.kind == .section }.count
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

                        Button {
                            sidebarManageSectionsNotebook = notebook
                        } label: {
                            Label("Manage Sections…", systemImage: "list.bullet.indent")
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
                HStack(spacing: 12) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    EditButton()
                }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
        .sheet(item: $sidebarManageSectionsNotebook) { notebook in
            ManageSectionsSheet(notebookID: notebook.id)
        }
    }
}

// MARK: - Notebook sidebar row

private struct NotebookSidebarRow: View {
    let notebook: Notebook
    let noteCount: Int
    let sectionCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // Mini cover swatch
            RoundedRectangle(cornerRadius: 5)
                .fill(notebook.cover.gradient)
                .frame(width: 28, height: 36)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                )
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(noteCount) note\(noteCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if sectionCount > 0 {
                        Text("· \(sectionCount) section\(sectionCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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

    /// Sentinel UUID used to track collapse state of the "Unsectioned" group.
    private static let unsectionedSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @State private var showMoveSheet: Note?
    @State private var noteToRename: Note?
    @State private var renameText = ""
    @State private var showNoteCreationSheet = false
    @State private var showNotebookWizard = false
    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""
    @State private var sectionToRename: NotebookSection?
    @State private var sectionRenameText = ""
    @State private var collapsedSections: Set<UUID> = []
    @State private var showManageSections = false

    /// All notes for non-notebook views (flat).
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
        case .pdfLibrary:
            return []
        case .documentLibrary:
            return []
        }
    }

    /// Sections for this notebook (empty for non-notebook views).
    private var notebookSections: [NotebookSection] {
        guard let nbID = notebookIDForSection else { return [] }
        return noteStore.sections(inNotebook: nbID)
    }

    /// Notes not assigned to any section within this notebook.
    private var unsectionedNotes: [Note] {
        guard let nbID = notebookIDForSection else { return [] }
        return noteStore.unsectionedPages(inNotebook: nbID)
    }

    /// Whether this notebook has any sections defined.
    private var hasSections: Bool {
        !notebookSections.isEmpty
    }

    private var sectionTitle: String {
        switch section {
        case .allNotes:           return "All Notes"
        case .recents:            return "Recents"
        case .favorites:          return "Favorites"
        case .notebook(let id):
            return noteStore.notebooks.first { $0.id == id }?.name ?? "Notebook"
        case .pdfLibrary:         return "PDF Documents"
        case .documentLibrary:    return "Documents"
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
            } else if case .notebook = section, hasSections {
                sectionGroupedContent
            } else {
                flatGridContent
            }
        }
        .navigationTitle(sectionTitle)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                notebookToolbarMenu
            }
            if let nb = notebookForSection {
                ToolbarItem(placement: .navigationBarLeading) {
                    NotebookCoverBadge(cover: nb.cover)
                }
            }
        }
        .sheet(isPresented: $showNoteCreationSheet) {
            NoteCreationSheet(
                notebookID: notebookIDForSection,
                onCreated: { id in selectedNoteID = id }
            )
        }
        .sheet(isPresented: $showNotebookWizard) {
            NotebookCreationWizard()
        }
        .sheet(item: $showMoveSheet) { note in
            MoveNoteSheet(note: note)
        }
        .sheet(isPresented: $showManageSections) {
            if let nbID = notebookIDForSection {
                ManageSectionsSheet(notebookID: nbID)
            }
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
        .alert("New Section", isPresented: $showNewSectionAlert) {
            TextField("Section name", text: $newSectionName)
                .submitLabel(.done)
            Button("Create") {
                let name = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let nbID = notebookIDForSection {
                    noteStore.addSection(toNotebook: nbID, name: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Section", isPresented: Binding(
            get: { sectionToRename != nil },
            set: { if !$0 { sectionToRename = nil } }
        )) {
            TextField("Name", text: $sectionRenameText)
                .submitLabel(.done)
            Button("Rename") {
                if let s = sectionToRename, !sectionRenameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    noteStore.renameSection(id: s.id, name: sectionRenameText.trimmingCharacters(in: .whitespaces))
                }
                sectionToRename = nil
            }
            Button("Cancel", role: .cancel) { sectionToRename = nil }
        }
    }

    // MARK: Toolbar menu

    @ViewBuilder
    private var notebookToolbarMenu: some View {
        Menu {
            Button {
                quickNote()
            } label: {
                Label("Quick Note", systemImage: "square.and.pencil")
            }

            Button {
                showNoteCreationSheet = true
            } label: {
                Label("New Note…", systemImage: "doc.badge.plus")
            }

            Divider()

            if notebookIDForSection != nil {
                Button {
                    newSectionName = ""
                    showNewSectionAlert = true
                } label: {
                    Label("New Section", systemImage: "folder.badge.plus")
                }

                Button {
                    guard let nbID = notebookIDForSection else { return }
                    noteStore.addSectionDivider(toNotebook: nbID)
                } label: {
                    Label("Add Divider", systemImage: "minus")
                }

                if hasSections {
                    Button {
                        showManageSections = true
                    } label: {
                        Label("Manage Sections…", systemImage: "list.bullet.indent")
                    }
                }

                Divider()
            }

            Button {
                showNotebookWizard = true
            } label: {
                Label("New Notebook…", systemImage: "book.closed.fill")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("New")
    }

    // MARK: Flat grid (non-notebook views)

    private var flatGridContent: some View {
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

    // MARK: Section-grouped content (notebook views with sections)

    private var sectionGroupedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Unsectioned notes ──────────────────────────────────
                if !unsectionedNotes.isEmpty {
                    SectionHeaderView(
                        title: "Unsectioned",
                        noteCount: unsectionedNotes.count,
                        isCollapsed: collapsedSections.contains(Self.unsectionedSentinel),
                        systemImage: "tray",
                        onToggle: {
                            if collapsedSections.contains(Self.unsectionedSentinel) {
                                collapsedSections.remove(Self.unsectionedSentinel)
                            } else {
                                collapsedSections.insert(Self.unsectionedSentinel)
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    if !collapsedSections.contains(Self.unsectionedSentinel) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(unsectionedNotes) { note in
                                NoteCardView(note: note, isSelected: selectedNoteID == note.id)
                                    .onTapGesture { selectedNoteID = note.id }
                                    .contextMenu { noteContextMenu(for: note) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }

                // ── Each section ───────────────────────────────────────
                ForEach(notebookSections) { nbSection in
                    if nbSection.kind == .divider {
                        // Visual divider
                        SectionDividerView(label: nbSection.name)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contextMenu {
                                Button(role: .destructive) {
                                    noteStore.deleteSection(id: nbSection.id)
                                } label: {
                                    Label("Remove Divider", systemImage: "trash")
                                }
                            }
                    } else {
                        let sectionNotes = noteStore.pages(inSection: nbSection.id)

                        SectionHeaderView(
                            title: nbSection.name,
                            noteCount: sectionNotes.count,
                            isCollapsed: collapsedSections.contains(nbSection.id),
                            systemImage: "folder.fill",
                            onToggle: {
                                if collapsedSections.contains(nbSection.id) {
                                    collapsedSections.remove(nbSection.id)
                                } else {
                                    collapsedSections.insert(nbSection.id)
                                }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .contextMenu {
                            Button {
                                sectionToRename = nbSection
                                sectionRenameText = nbSection.name
                            } label: {
                                Label("Rename Section", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                noteStore.deleteSection(id: nbSection.id, movePagesToNotebook: true)
                            } label: {
                                Label("Delete Section (Keep Notes)", systemImage: "trash")
                            }

                            Button(role: .destructive) {
                                noteStore.deleteSection(id: nbSection.id, movePagesToNotebook: false)
                            } label: {
                                Label("Delete Section & Notes", systemImage: "trash.fill")
                            }
                        }

                        if !collapsedSections.contains(nbSection.id) {
                            if sectionNotes.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No notes in this section")
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                                .padding(.horizontal, 20)
                            } else {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(sectionNotes) { note in
                                        NoteCardView(note: note, isSelected: selectedNoteID == note.id)
                                            .onTapGesture { selectedNoteID = note.id }
                                            .contextMenu { noteContextMenu(for: note) }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: Note context menu

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

        // Section-aware move menu (only within notebook context)
        if notebookIDForSection != nil, hasSections {
            Menu {
                // Move to unsectioned
                if note.sectionID != nil {
                    Button {
                        noteStore.movePage(
                            id: note.id,
                            toSection: nil,
                            atIndex: unsectionedNotes.count
                        )
                    } label: {
                        Label("Unsectioned", systemImage: "tray")
                    }
                }

                // Move to each section
                ForEach(notebookSections.filter { $0.kind == .section }) { nbSection in
                    if note.sectionID != nbSection.id {
                        Button {
                            noteStore.movePage(
                                id: note.id,
                                toSection: nbSection.id,
                                atIndex: noteStore.pages(inSection: nbSection.id).count
                            )
                        } label: {
                            Label(nbSection.name, systemImage: "folder")
                        }
                    }
                }
            } label: {
                Label("Move to Section…", systemImage: "arrow.right.doc.on.clipboard")
            }
        }

        Divider()

        Button(role: .destructive) {
            if selectedNoteID == note.id { selectedNoteID = nil }
            noteStore.deleteNotes(ids: [note.id])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Quick Note — creates a note instantly with the notebook's paper settings (or blank for unfiled).
    /// GoodNotes equivalent: "Quick Note" from the "+" menu.
    private func quickNote() {
        let nbID = notebookIDForSection
        // Inherit paper settings from the notebook when inside one.
        let nb = nbID.flatMap { id in noteStore.notebooks.first { $0.id == id } }
        let note = noteStore.addNote(
            inNotebook: nbID,
            pageType: nb?.pageType,
            paperMaterial: nb?.paperMaterial
        )
        selectedNoteID = note.id
    }

    private var notebookIDForSection: UUID? {
        if case .notebook(let id) = section { return id }
        return nil
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
            Button(action: quickNote) {
                Label("Quick Note", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            Button {
                showNoteCreationSheet = true
            } label: {
                Label("New Note…", systemImage: "doc.badge.plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondaryLabel).opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
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
        case .pdfLibrary: return "doc.richtext"
        case .documentLibrary: return "doc.fill"
        }
    }

    private var emptyTitle: String {
        switch section {
        case .allNotes:  return "No Notes Yet"
        case .recents:   return "No Recent Notes"
        case .favorites: return "No Favorites Yet"
        case .notebook:  return "Empty Notebook"
        case .pdfLibrary: return "No PDFs Yet"
        case .documentLibrary: return "No Documents Yet"
        }
    }

    private var emptySubtitle: String {
        switch section {
        case .allNotes:  return "Tap the pencil button to write your first note."
        case .recents:   return "Notes you open recently will appear here."
        case .favorites: return "Tap ★ in a note's menu to collect favorites here."
        case .notebook:  return "Tap the pencil button to add notes to this notebook."
        case .pdfLibrary: return "Import a PDF document to get started."
        case .documentLibrary: return "Import a document to get started."
        }
    }
}

// MARK: - Section header view

private struct SectionHeaderView: View {
    let title: String
    let noteCount: Int
    let isCollapsed: Bool
    let systemImage: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))

                Text("\(noteCount)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .secondaryLabel).opacity(0.12), in: Capsule())

                Spacer()

                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(noteCount) notes, \(isCollapsed ? "collapsed" : "expanded")")
    }
}

// MARK: - Section divider view

private struct SectionDividerView: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Manage sections sheet

private struct ManageSectionsSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let notebookID: UUID

    @State private var sectionToRename: NotebookSection?
    @State private var renameText = ""
    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""

    private var sections: [NotebookSection] {
        noteStore.sections(inNotebook: notebookID)
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.isEmpty {
                    emptySectionsPlaceholder
                } else {
                    populatedSectionsList
                }
            }
            .navigationTitle("Manage Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { manageSectionsToolbar }
            .alert("New Section", isPresented: $showNewSectionAlert) {
                newSectionAlertContent
            }
            .alert("Rename Section", isPresented: Binding(
                get: { sectionToRename != nil },
                set: { if !$0 { sectionToRename = nil } }
            )) {
                renameSectionAlertContent
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Extracted subviews

    private var emptySectionsPlaceholder: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("No Sections")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Add sections to organize notes within this notebook.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.vertical, 16)
        }
    }

    private var populatedSectionsList: some View {
        Section {
            ForEach(sections) { nbSection in
                sectionRow(nbSection)
            }
            .onMove { from, to in
                noteStore.reorderSections(inNotebook: notebookID, fromOffsets: from, toOffset: to)
            }
        } header: {
            Text("Sections")
        } footer: {
            Text("Drag to reorder. Long-press for rename/delete options.")
        }
    }

    private func sectionRow(_ nbSection: NotebookSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: nbSection.kind == .divider ? "minus" : "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(nbSection.kind == .divider ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 24)

            sectionRowLabel(nbSection)

            Spacer()
        }
        .contextMenu {
            sectionContextMenu(nbSection)
        }
    }

    @ViewBuilder
    private func sectionRowLabel(_ nbSection: NotebookSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if nbSection.kind == .divider {
                Text(nbSection.name.isEmpty ? "Divider" : nbSection.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(nbSection.name)
                    .font(.subheadline.weight(.medium))
                let count = noteStore.pages(inSection: nbSection.id).count
                Text("\(count) note\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sectionContextMenu(_ nbSection: NotebookSection) -> some View {
        if nbSection.kind == .section {
            Button {
                sectionToRename = nbSection
                renameText = nbSection.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                noteStore.deleteSection(id: nbSection.id, movePagesToNotebook: true)
            } label: {
                Label("Delete (Keep Notes)", systemImage: "trash")
            }
        }

        Button(role: .destructive) {
            noteStore.deleteSection(id: nbSection.id, movePagesToNotebook: false)
        } label: {
            Label(nbSection.kind == .divider ? "Remove Divider" : "Delete Section & Notes", systemImage: "trash.fill")
        }
    }

    @ToolbarContentBuilder
    private var manageSectionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    newSectionName = ""
                    showNewSectionAlert = true
                } label: {
                    Label("New Section", systemImage: "folder.badge.plus")
                }
                Button {
                    noteStore.addSectionDivider(toNotebook: notebookID)
                } label: {
                    Label("Add Divider", systemImage: "minus")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
        }
    }

    @ViewBuilder
    private var newSectionAlertContent: some View {
        TextField("Section name", text: $newSectionName)
            .submitLabel(.done)
        Button("Create") {
            let name = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                noteStore.addSection(toNotebook: notebookID, name: name)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var renameSectionAlertContent: some View {
        TextField("Name", text: $renameText)
            .submitLabel(.done)
        Button("Rename") {
            if let s = sectionToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                noteStore.renameSection(id: s.id, name: renameText.trimmingCharacters(in: .whitespaces))
            }
            sectionToRename = nil
        }
        Button("Cancel", role: .cancel) { sectionToRename = nil }
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
                    .foregroundStyle(.white.opacity(0.85))
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
                    isSelected ? Color.accentColor : Color(uiColor: .label).opacity(0.07),
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
                    isSelected ? Color.accentColor : Color(uiColor: .label).opacity(0.07),
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
                    .foregroundStyle(Color(uiColor: .label))
                }

                if !noteStore.notebooks.isEmpty {
                    Section("Notebooks") {
                        ForEach(noteStore.notebooks) { notebook in
                            notebookRow(notebook)
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

    @ViewBuilder
    private func notebookRow(_ notebook: Notebook) -> some View {
        let nbSections = noteStore.sections(inNotebook: notebook.id).filter { $0.kind == .section }
        let isCurrentNotebook = note.notebookID == notebook.id

        if nbSections.isEmpty {
            // Simple notebook row (no sections)
            Button {
                noteStore.moveNote(id: note.id, toNotebook: notebook.id)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    notebookSwatch(notebook)
                    Text(notebook.name)
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer()
                    if isCurrentNotebook && note.sectionID == nil {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        } else {
            // Expandable notebook with sections
            DisclosureGroup {
                // Unsectioned option
                Button {
                    noteStore.moveNote(id: note.id, toNotebook: notebook.id)
                    // Also clear section if moving within same notebook
                    if note.notebookID == notebook.id {
                        noteStore.movePage(
                            id: note.id,
                            toSection: nil,
                            atIndex: noteStore.unsectionedPages(inNotebook: notebook.id).count
                        )
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Unsectioned")
                            .foregroundStyle(Color(uiColor: .label))
                        Spacer()
                        if isCurrentNotebook && note.sectionID == nil {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(nbSections) { nbSection in
                    Button {
                        // Move to notebook first (if different), then to section
                        if note.notebookID != notebook.id {
                            noteStore.moveNote(id: note.id, toNotebook: notebook.id)
                        }
                        noteStore.movePage(
                            id: note.id,
                            toSection: nbSection.id,
                            atIndex: noteStore.pages(inSection: nbSection.id).count
                        )
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(nbSection.name)
                                .foregroundStyle(Color(uiColor: .label))
                            Spacer()
                            if note.sectionID == nbSection.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    notebookSwatch(notebook)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notebook.name)
                            .foregroundStyle(Color(uiColor: .label))
                        Text("\(nbSections.count) section\(nbSections.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func notebookSwatch(_ notebook: Notebook) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(notebook.cover.gradient)
            .frame(width: 28, height: 36)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            )
    }
}
