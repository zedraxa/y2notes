// swiftlint:disable file_length
import SwiftUI
import PencilKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Library section

enum LibrarySection: Hashable {
    case allNotes
    case recents
    case favorites
    /// Notes linked to imported PDFs or documents.
    case importNotes
    case notebook(UUID)
    case pdfLibrary
    case documentLibrary
    case importNotes
    /// Filter to notes that carry a specific tag.
    case tag(String)
}

// MARK: - Import Notes sort / filter

enum ImportNotesSortOrder: String, CaseIterable, Identifiable {
    case modifiedAt, createdAt, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .modifiedAt: return NSLocalizedString("Import.SortModified", comment: "")
        case .createdAt:  return NSLocalizedString("Import.SortCreated", comment: "")
        case .name:       return NSLocalizedString("Import.SortName", comment: "")
        }
    }
    var systemImage: String {
        switch self {
        case .modifiedAt: return "clock"
        case .createdAt:  return "calendar"
        case .name:       return "textformat"
        }
    }
}

enum ImportNotesSourceFilter: String, CaseIterable, Identifiable {
    case all, pdf, document
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return NSLocalizedString("Import.FilterAll", comment: "")
        case .pdf:      return NSLocalizedString("Import.FilterPDFs", comment: "")
        case .document: return NSLocalizedString("Import.FilterDocuments", comment: "")
        }
    }
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
    @Environment(TabWorkspaceStore.self) private var tabSession

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
                DocumentLibraryView(selectedDocumentID: $selectedDocumentID)
            } else if case .importNotes = selectedSection {
                ImportLinkedNotesView(selectedNoteID: $selectedNoteID)
            } else {
                NoteGridView(
                    section: selectedSection ?? .allNotes,
                    selectedNoteID: $selectedNoteID,
                    onOpenNotebook: { nbID in
                        selectedNoteID = nil
                        selectedSection = .notebook(nbID)
                        // Register the notebook as an open tab
                        if let nb = noteStore.notebooks.first(where: { $0.id == nbID }) {
                            tabSession.openNotebook(
                                id: nbID,
                                displayName: nb.name,
                                coverColor: nb.cover.rgbComponents
                            )
                        }
                    }
                )
            }
        } detail: {
            NotebookWorkspaceView(onOpenShelf: {
                columnVisibility = .all
            })
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
            case .importNotes:
                selectedPDFID  = nil
                selectedDocumentID = nil
            case .notebook:
                // Notebook tabs are already opened in onOpenNotebook
                selectedPDFID  = nil
                selectedDocumentID = nil
            case .tag:
                selectedPDFID  = nil
                selectedDocumentID = nil
            default:
                selectedPDFID  = nil
                selectedDocumentID = nil
            }
        }
        // When a note is selected in the sidebar/grid, open it as a tab.
        .onChange(of: selectedNoteID) { _, newID in
            guard let id = newID,
                  let note = noteStore.notes.first(where: { $0.id == id }) else { return }
            tabSession.openTab(
                .note(id: id),
                displayName: note.title.isEmpty ? "Untitled Note" : note.title,
                accentColor: [0.45, 0.45, 0.5]
            )
        }
        // When a PDF is selected, open it as a tab.
        .onChange(of: selectedPDFID) { _, newID in
            guard let id = newID,
                  let record = pdfStore.records.first(where: { $0.id == id }) else { return }
            tabSession.openTab(
                .pdf(id: id),
                displayName: record.title,
                accentColor: [0.8, 0.3, 0.3]
            )
        }
        // When a document is selected, open it as a tab.
        .onChange(of: selectedDocumentID) { _, newID in
            guard let id = newID,
                  let doc = documentStore.documents.first(where: { $0.id == id }) else { return }
            tabSession.openTab(
                .document(id: id),
                displayName: doc.displayName,
                accentColor: [0.3, 0.5, 0.7]
            )
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
    @EnvironmentObject var toolStore: DrawingToolStore
    @EnvironmentObject var themeStore: ThemeStore
    @Binding var selectedSection: LibrarySection?

    @State private var showNewNotebookSheet = false
    @State private var notebookToRename: Notebook?
    @State private var renameText = ""
    @State private var showLibrarySearch = false
    @State private var showSettings = false
    @State private var sidebarManageSectionsNotebook: Notebook?
    @State private var showCommandPalette = false
    @State private var showWritingInsights = false

    // Binding passed down from ShelfView so tapping a search result selects the note.
    var onSelectNote: (UUID) -> Void

    // swiftlint:disable:next function_body_length
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

                if !noteStore.importLinkedNotes.isEmpty {
                    Label("Import Notes", systemImage: "paperclip")
                        .tag(LibrarySection.importNotes)
                        .badge(noteStore.importLinkedNotes.count)
                }

                Label("PDF Documents", systemImage: "doc.richtext")
                    .tag(LibrarySection.pdfLibrary)
                    .badge(pdfStore.records.count)

                Label("Documents", systemImage: "doc.fill")
                    .tag(LibrarySection.documentLibrary)
                    .badge(documentStore.documents.count)

                Label("Import Notes", systemImage: "paperclip")
                    .tag(LibrarySection.importNotes)
                    .badge(noteStore.importLinkedNotes.count)
            }

            // ── Tags ─────────────────────────────────────────────────────
            if !noteStore.allTags.isEmpty {
                Section("Tags") {
                    ForEach(noteStore.allTags, id: \.self) { tag in
                        Label {
                            Text(tag)
                        } icon: {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.tint)
                        }
                        .tag(LibrarySection.tag(tag))
                        .badge(noteStore.notes(withTag: tag).count)
                    }
                }
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

                        Menu {
                            ForEach(CoverTexture.allCases) { tex in
                                Button {
                                    noteStore.updateNotebookTexture(id: notebook.id, texture: tex)
                                } label: {
                                    Label(tex.displayName, systemImage: tex.systemImage)
                                }
                            }
                        } label: {
                            Label("Cover Texture", systemImage: "rectangle.pattern.checkered")
                        }

                        Button {
                            sidebarManageSectionsNotebook = notebook
                        } label: {
                            Label("Manage Sections…", systemImage: "list.bullet.indent")
                        }

                        Button {
                            noteStore.duplicateNotebook(id: notebook.id)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button {
                            noteStore.toggleNotebookLock(id: notebook.id)
                        } label: {
                            Label(
                                notebook.isLocked ? "Unlock" : "Lock",
                                systemImage: notebook.isLocked ? "lock.open" : "lock"
                            )
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
                if syncEngine.authManager.isAuthenticated {
                    NavigationLink(destination: GoogleDriveFileBrowserView()) {
                        Label {
                            Text("My Drive")
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                        }
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
                        showCommandPalette = true
                    } label: {
                        Image(systemName: "command")
                    }
                    .accessibilityLabel("Command Palette")
                    .keyboardShortcut("k", modifiers: .command)
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
            NotebookQuickCreator()
        }
        .sheet(isPresented: $showLibrarySearch) {
            UniversalSearchView(
                currentNotebookID: nil,
                onSelectNote: onSelectNote,
                onJumpToAnchor: { anchor in
                    // From the shelf, select the note. Page-level navigation happens
                    // once the notebook reader opens and resolves the anchor.
                    onSelectNote(anchor.noteID)
                }
            )
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
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(actions: buildQuickActions())
        }
        .sheet(isPresented: $showWritingInsights) {
            WritingInsightsView()
        }
    }

    // MARK: - Command Palette Actions

    private func buildQuickActions() -> [QuickAction] {
        QuickActionRegistry.actions(
            onNewNote: { noteStore.addNote() },
            onNewNotebook: { showNewNotebookSheet = true },
            onOpenSettings: { showSettings = true },
            onOpenSearch: { showLibrarySearch = true },
            onOpenStudy: { selectedSection = .allNotes },
            onToggleFocusMode: { toolStore.isFocusModeActive.toggle() },
            onToggleMagicMode: { toolStore.isMagicModeActive.toggle() },
            onToggleStudyMode: { toolStore.isStudyModeActive.toggle() },
            onCycleTheme: { themeStore.cycleToNext() },
            onShowInsights: { showWritingInsights = true }
        )
    }
}

// MARK: - Notebook sidebar row

private struct NotebookSidebarRow: View {
    let notebook: Notebook
    let noteCount: Int
    let sectionCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // Mini cover swatch with texture + custom photo
            ZStack {
                if let data = notebook.customCoverData,
                   let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 36)
                        .clipped()
                } else {
                    notebook.cover.gradient
                }

                CoverTextureOverlay(
                    texture: notebook.coverTexture,
                    size: CGSize(width: 28, height: 36),
                    intensity: 0.7
                )

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 28, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(notebook.name)
                        .font(.body)
                        .lineLimit(1)
                    if notebook.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Locked")
                    }
                }
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

// MARK: - Notebook sort order

/// Sort options for the horizontal notebook shelf row.
enum NotebookSortOrder: String, CaseIterable {
    case name        = "name"
    case modified    = "modified"
    case created     = "created"
    case lastOpened  = "lastOpened"
    case pageCount   = "pageCount"

    var displayName: String {
        switch self {
        case .name:       return NSLocalizedString("Notebook.Sort.Name",        comment: "")
        case .modified:   return NSLocalizedString("Notebook.Sort.Modified",    comment: "")
        case .created:    return NSLocalizedString("Notebook.Sort.Created",     comment: "")
        case .lastOpened: return NSLocalizedString("Notebook.Sort.LastOpened",  comment: "")
        case .pageCount:  return NSLocalizedString("Notebook.Sort.PageCount",   comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .name:       return "textformat.abc"
        case .modified:   return "pencil"
        case .created:    return "calendar"
        case .lastOpened: return "eye"
        case .pageCount:  return "doc.plaintext"
        }
    }
}

// MARK: - Note grid (middle column)

struct NoteGridView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore: PDFStore
    @EnvironmentObject var documentStore: DocumentStore
    @Environment(TabWorkspaceStore.self) private var tabSession
    let section: LibrarySection
    @Binding var selectedNoteID: UUID?
    /// Called when the user taps a notebook cover in the shelf row.
    var onOpenNotebook: ((UUID) -> Void)?

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
    @State private var showDocImporter = false
    @State private var showPDFImporter = false
    @State private var versionHistoryNote: Note?
    @State private var tagPickerNote: Note?
    @State private var importNotesSortOrder: ImportNotesSortOrder = .modifiedAt
    @State private var importNotesSourceFilter: ImportNotesSourceFilter = .all
    @State private var showCleanUpOrphansAlert = false
    @State private var gridAppeared = false
    @AppStorage("y2notes.notebookSortOrder") private var notebookSortOrderRaw: String = NotebookSortOrder.modified.rawValue

    private var notebookSortOrder: NotebookSortOrder {
        NotebookSortOrder(rawValue: notebookSortOrderRaw) ?? .modified
    }

    /// All notes for non-notebook views (flat).
    private var notes: [Note] {
        switch section {
        case .allNotes:
            return noteStore.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        case .recents:
            return noteStore.recentNotes
        case .favorites:
            return noteStore.favoritedNotes
        case .importNotes:
            let filtered: [Note]
            switch importNotesSourceFilter {
            case .all:      filtered = noteStore.importLinkedNotes
            case .pdf:      filtered = noteStore.importLinkedNotes.filter { $0.linkedPDFID != nil }
            case .document: filtered = noteStore.importLinkedNotes.filter { $0.linkedDocumentID != nil }
            }
            switch importNotesSortOrder {
            case .modifiedAt: return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
            case .createdAt:  return filtered.sorted { $0.createdAt > $1.createdAt }
            case .name:       return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        case .notebook(let id):
            return noteStore.notes(inNotebook: id).sorted { $0.modifiedAt > $1.modifiedAt }
        case .tag(let tag):
            return noteStore.notes(withTag: tag).sorted { $0.modifiedAt > $1.modifiedAt }
        case .pdfLibrary:
            return []
        case .documentLibrary:
            return []
        case .importNotes:
            return noteStore.importLinkedNotes
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
        case .importNotes:        return "Import Notes"
        case .notebook(let id):
            return noteStore.notebooks.first { $0.id == id }?.name ?? "Notebook"
        case .tag(let tag):       return "#\(tag)"
        case .pdfLibrary:         return "PDF Documents"
        case .documentLibrary:    return "Documents"
        case .importNotes:        return "Import Notes"
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
            if case .importNotes = section {
                ToolbarItem(placement: .navigationBarTrailing) {
                    importNotesToolbarMenu
                }
            }
            if let nb = notebookForSection {
                ToolbarItem(placement: .navigationBarLeading) {
                    NotebookCoverBadge(
                        cover: nb.cover,
                        customCoverData: nb.customCoverData,
                        coverTexture: nb.coverTexture
                    )
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
            NotebookQuickCreator()
        }
        .sheet(item: $showMoveSheet) { note in
            MoveNoteSheet(note: note)
        }
        .sheet(item: $versionHistoryNote) { note in
            VersionHistoryView(noteID: note.id)
                .environmentObject(noteStore)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $tagPickerNote) { note in
            TagPickerSheet(note: note)
                .environmentObject(noteStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        .alert(
            NSLocalizedString("Import.CleanUpOrphansTitle", comment: ""),
            isPresented: $showCleanUpOrphansAlert
        ) {
            Button(NSLocalizedString("Import.CleanUpOrphansConfirm", comment: ""), role: .destructive) {
                noteStore.removeOrphanedImportLinks(
                    livePDFIDs: Set(pdfStore.records.map(\.id)),
                    liveDocumentIDs: Set(documentStore.documents.map(\.id))
                )
            }
            Button(NSLocalizedString("Common.Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Import.CleanUpOrphansMessage", comment: ""))
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let record = pdfStore.importPDF(from: url) {
                    tabSession.openTab(
                        .pdf(id: record.id),
                        displayName: record.title,
                        accentColor: [0.8, 0.3, 0.3]
                    )
                    let note = noteStore.addNote(forPDF: record)
                    tabSession.openTab(
                        .note(id: note.id),
                        displayName: note.title,
                        accentColor: [0.8, 0.3, 0.3]
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showDocImporter,
            allowedContentTypes: ImportedDocumentType.allUTTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let imported = documentStore.importDocuments(from: urls)
                if let doc = imported.first {
                    tabSession.openTab(
                        .document(id: doc.id),
                        displayName: doc.displayName,
                        accentColor: [0.3, 0.5, 0.7]
                    )
