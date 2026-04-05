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
                    let note = noteStore.addNote(forDocument: doc)
                    tabSession.openTab(
                        .note(id: note.id),
                        displayName: note.title,
                        accentColor: [0.3, 0.5, 0.7]
                    )
                }
            }
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

            Divider()

            Button {
                showPDFImporter = true
            } label: {
                Label("Import PDF…", systemImage: "doc.fill")
            }

            Button {
                showDocImporter = true
            } label: {
                Label("Import Document…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("New")
    }

    private var importNotesToolbarMenu: some View {
        let orphanCount = noteStore.orphanedImportNotes(
            livePDFIDs: Set(pdfStore.records.map(\.id)),
            liveDocumentIDs: Set(documentStore.documents.map(\.id))
        ).count
        return Menu {
            Menu {
                ForEach(ImportNotesSortOrder.allCases) { order in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            importNotesSortOrder = order
                        }
                    } label: {
                        Label(order.label, systemImage: order.systemImage)
                    }
                }
            } label: {
                Label(NSLocalizedString("Import.SortBy", comment: ""), systemImage: "arrow.up.arrow.down")
            }

            Menu {
                ForEach(ImportNotesSourceFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            importNotesSourceFilter = filter
                        }
                    } label: {
                        HStack {
                            Text(filter.label)
                            if importNotesSourceFilter == filter {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(NSLocalizedString("Import.FilterBy", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
            }

            if orphanCount > 0 {
                Divider()
                Button(role: .destructive) {
                    showCleanUpOrphansAlert = true
                } label: {
                    Label(
                        String(format: NSLocalizedString("Import.CleanUpOrphans", comment: ""), orphanCount),
                        systemImage: "trash"
                    )
                }
            }
        } label: {
            Image(systemName: importNotesSourceFilter == .all
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(NSLocalizedString("Import.SortAndFilter", comment: ""))
    }

    // MARK: Flat grid (non-notebook views)

    private var flatGridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Notebook shelf — show notebook covers at the top in "All Notes" view
                if case .allNotes = section, !noteStore.notebooks.isEmpty {
                    notebookShelfRow
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        NoteCardView(note: note, isSelected: selectedNoteID == note.id)
                            .onTapGesture { selectedNoteID = note.id }
                            .contextMenu { noteContextMenu(for: note) }
                            .opacity(gridAppeared ? 1 : 0)
                            .offset(y: gridAppeared ? 0 : 14)
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.82)
                                    .delay(Double(index) * 0.03),
                                value: gridAppeared
                            )
                    }
                }
                .padding(20)
                .onAppear { gridAppeared = true }
            }
        }
    }

    // MARK: Notebook shelf row (cover cards)

    /// Horizontal scrollable row of notebook covers displayed at the top
    /// of the "All Notes" grid, simulating a shelf of real notebooks.
    @ViewBuilder
    private var notebookShelfRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notebooks")
                    .font(.headline)
                Spacer()
                // Sort picker
                Menu {
                    ForEach(NotebookSortOrder.allCases, id: \.self) { order in
                        Button {
                            notebookSortOrderRaw = order.rawValue
                        } label: {
                            Label(order.displayName, systemImage: order.systemImage)
                            if order == notebookSortOrder {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    showNotebookWizard = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(sortedNotebooks) { nb in
                        NotebookCoverCard(
                            notebook: nb,
                            pageCount: noteStore.notes(inNotebook: nb.id)
                                .reduce(0) { $0 + $1.pageCount }
                        )
                        .onTapGesture {
                            noteStore.updateNotebookLastOpened(id: nb.id)
                            onOpenNotebook?(nb.id)
                        }
                        .contextMenu {
                            notebookCoverCardContextMenu(for: nb)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
    }

    /// Notebooks sorted by the current `notebookSortOrder`, with pinned ones always first.
    private var sortedNotebooks: [Notebook] {
        let pinned = noteStore.notebooks.filter { $0.isPinned }
        let unpinned = noteStore.notebooks.filter { !$0.isPinned }

        func sorted(_ list: [Notebook]) -> [Notebook] {
            switch notebookSortOrder {
            case .name:
                return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .modified:
                return list.sorted { $0.modifiedAt > $1.modifiedAt }
            case .created:
                return list.sorted { $0.createdAt > $1.createdAt }
            case .lastOpened:
                return list.sorted { lhs, rhs in
                    switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
                    case let (l?, r?): return l > r
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return lhs.modifiedAt > rhs.modifiedAt
                    }
                }
            case .pageCount:
                return list.sorted {
                    noteStore.notes(inNotebook: $0.id).reduce(0) { $0 + $1.pageCount } >
                    noteStore.notes(inNotebook: $1.id).reduce(0) { $0 + $1.pageCount }
                }
            }
        }

        return sorted(pinned) + sorted(unpinned)
    }

    @ViewBuilder
    private func notebookCoverCardContextMenu(for nb: Notebook) -> some View {
        Button {
            noteStore.toggleNotebookPin(id: nb.id)
        } label: {
            Label(
                nb.isPinned ? "Unpin" : "Pin",
                systemImage: nb.isPinned ? "pin.slash" : "pin"
            )
        }

        Menu {
            ForEach(NotebookColorTag.allCases, id: \.self) { tag in
                Button {
                    noteStore.updateNotebookColorTag(id: nb.id, colorTag: tag)
                } label: {
                    if nb.colorTag == tag {
                        Label(tag.displayName, systemImage: "checkmark.circle.fill")
                    } else if tag == .none {
                        Label(tag.displayName, systemImage: "circle.slash")
                    } else {
                        Text(tag.displayName)
                    }
                }
            }
        } label: {
            Label("Colour Tag", systemImage: "circle.fill")
        }

        Divider()

        Button {
            noteStore.duplicateNotebook(id: nb.id)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            noteStore.toggleNotebookLock(id: nb.id)
        } label: {
            Label(
                nb.isLocked ? "Unlock" : "Lock",
                systemImage: nb.isLocked ? "lock.open" : "lock"
            )
        }

        Divider()

        Button(role: .destructive) {
            noteStore.deleteNotebook(id: nb.id)
        } label: {
            Label("Delete", systemImage: "trash")
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if collapsedSections.contains(Self.unsectionedSentinel) {
                                    collapsedSections.remove(Self.unsectionedSentinel)
                                } else {
                                    collapsedSections.insert(Self.unsectionedSentinel)
                                }
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if collapsedSections.contains(nbSection.id) {
                                        collapsedSections.remove(nbSection.id)
                                    } else {
                                        collapsedSections.insert(nbSection.id)
                                    }
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
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 28, weight: .ultraLight))
                                        .foregroundStyle(.quaternary)
                                    Text("No notes in this section")
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
                                .transition(.opacity.combined(with: .move(edge: .top)))
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

        // ── Tags & Colour Label ───────────────────────────────────────────
        Button {
            tagPickerNote = note
        } label: {
            Label("Tags…", systemImage: "tag")
        }

        Menu {
            // Clear label
            if note.colorLabel != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    noteStore.updateColorLabel(for: note.id, colorLabel: nil)
                } label: {
                    Label("None", systemImage: "xmark.circle")
                }
                Divider()
            }
            ForEach(NoteColorLabel.allCases) { label in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    noteStore.updateColorLabel(
                        for: note.id,
                        colorLabel: note.colorLabel == label ? nil : label
                    )
                } label: {
                    HStack {
                        Text(label.displayName)
                        if note.colorLabel == label {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Color Label", systemImage: "circle.fill")
        }

        Divider()

        Button {
            versionHistoryNote = note
        } label: {
            Label("Version History", systemImage: "clock.arrow.circlepath")
        }

        Divider()

        Button(role: .destructive) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if selectedNoteID == note.id { selectedNoteID = nil }
            noteStore.deleteNotes(ids: [note.id])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Quick Note — creates a note instantly with the notebook's paper settings (or blank for unfiled).
    /// GoodNotes equivalent: "Quick Note" from the "+" menu.
    private func quickNote() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        case .importNotes: return "paperclip"
        case .notebook:  return "book.closed"
        case .tag:       return "tag"
        case .pdfLibrary: return "doc.richtext"
        case .documentLibrary: return "doc.fill"
        case .importNotes: return "paperclip"
        }
    }

    private var emptyTitle: String {
        switch section {
        case .allNotes:  return "No Notes Yet"
        case .recents:   return "No Recent Notes"
        case .favorites: return "No Favorites Yet"
        case .importNotes: return "No Import Notes Yet"
        case .notebook:  return "Empty Notebook"
        case .tag(let t): return "No Notes Tagged with \"#\(t)\""
        case .pdfLibrary: return "No PDFs Yet"
        case .documentLibrary: return "No Documents Yet"
        }
    }

    private var emptySubtitle: String {
        switch section {
        case .allNotes:  return "Tap the pencil button to write your first note."
        case .recents:   return "Notes you open recently will appear here."
        case .favorites: return "Tap ★ in a note's menu to collect favorites here."
        case .importNotes: return "Import a PDF or document to create a companion note."
        case .notebook:  return "Tap the pencil button to add notes to this notebook."
        case .tag(let t): return "Add the tag \"#\(t)\" to notes from their context menu."
        case .pdfLibrary: return "Import a PDF document to get started."
        case .documentLibrary: return "Import a document to get started."
        case .importNotes: return "Create a companion note from a PDF or document viewer."
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
    var customCoverData: Data?
    var coverTexture: CoverTexture = .smooth

    var body: some View {
        ZStack {
            if let data = customCoverData,
               let uiImg = UIImage(data: data) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 28)
                    .clipped()
            } else {
                cover.gradient
            }

            CoverTextureOverlay(
                texture: coverTexture,
                size: CGSize(width: 22, height: 28),
                intensity: 0.7
            )

            Image(systemName: "book.closed.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 22, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

// MARK: - Shimmer loading placeholder

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemFill)
                LinearGradient(
                    colors: [.clear, Color(uiColor: .secondarySystemBackground).opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.55)
                .offset(x: (geo.size.width * 1.55) * phase - geo.size.width * 0.28)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - Shimmer loading placeholder

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemFill)
                LinearGradient(
                    colors: [.clear, Color(uiColor: .secondarySystemBackground).opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.55)
                .offset(x: (geo.size.width * 1.55) * phase - geo.size.width * 0.28)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - Note card

private struct NoteCardView: View {
    let note: Note
    let isSelected: Bool

    @State private var thumbnail: UIImage?
    @GestureState private var isPressing: Bool = false
    @State private var selectionFeedback = UISelectionFeedbackGenerator()

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
                        .transition(.opacity.animation(.easeIn(duration: 0.25)))
                } else if note.drawingData.isEmpty {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                } else {
                    ShimmerView()
                }

                // Color label stripe — top-right corner dot
                if let label = note.colorLabel {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(label.color)
                                .frame(width: 11, height: 11)
                                .shadow(color: label.color.opacity(0.5), radius: 3, y: 1)
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                // Import-linked badge — top-left corner paperclip
                if note.linkedPDFID != nil || note.linkedDocumentID != nil {
                    VStack {
                        HStack {
                            Image(systemName: "paperclip")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.accentColor.opacity(0.85)))
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)

            // Color label bar — bottom of the thumbnail area
            if let label = note.colorLabel {
                label.color
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }

            Divider()

            // Footer
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(note.title.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if note.linkedPDFID != nil || note.linkedDocumentID != nil {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if note.isFavorited {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(note.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Tag chips (up to 2, then overflow count)
                if !note.tags.isEmpty {
                    TagChipsRow(tags: note.tags, maxVisible: 2)
                        .padding(.top, 2)
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
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.28) : .black.opacity(0.06),
            radius: isSelected ? 10 : 5,
            y: isSelected ? 0 : 2
        )
        .scaleEffect(isPressing ? 0.95 : (isSelected ? 1.02 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressing) { _, state, _ in state = true }
                .onEnded { _ in selectionFeedback.selectionChanged() }
        )
        .onAppear { selectionFeedback.prepare() }
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

// MARK: - Import-linked notes grid

/// A simple grid that shows only notes linked to PDFs or imported documents.
/// Used when the user selects the "Import Notes" section in the sidebar.
private struct ImportLinkedNotesView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedNoteID: UUID?

    var body: some View {
        Group {
            if noteStore.importLinkedNotes.isEmpty {
                emptyState
            } else {
                noteGrid
            }
        }
        .navigationTitle("Import Notes")
    }

    private var noteGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220))], spacing: 16) {
                ForEach(noteStore.importLinkedNotes) { note in
                    NoteCardView(note: note, isSelected: selectedNoteID == note.id)
                        .onTapGesture { selectedNoteID = note.id }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperclip")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Import Notes Yet")
                .font(.title3.weight(.semibold))
            Text("Create a companion note from a PDF or document viewer\nto see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tag chips row

/// Renders up to `maxVisible` tag pills and an overflow "+N" chip.
private struct TagChipsRow: View {
    let tags: [String]
    var maxVisible: Int = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(maxVisible), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }
            if tags.count > maxVisible {
                Text("+\(tags.count - maxVisible)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .secondaryLabel).opacity(0.10), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Notebook cover card (shelf display)

/// Rich notebook cover card that looks like a physical notebook on a shelf.
/// Shows the gradient cover with texture overlay, embossed title, page edge
/// effect, and a subtle 3D perspective tilt.
private struct NotebookCoverCard: View {
    let notebook: Notebook
    let pageCount: Int

    @State private var isPressed = false

    private let coverWidth: CGFloat = 120
    private let coverHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Page edge (visible pages on the right of the book)
                CoverPageEdge(height: coverHeight)
                    .offset(x: 2)

                // Book cover
                ZStack(alignment: .bottomLeading) {
                    // Main cover surface
                    coverSurface
                        .frame(width: coverWidth, height: coverHeight)
                        .clipShape(
                            .rect(
                                topLeadingRadius: 4,
                                bottomLeadingRadius: 4,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )

                    // Texture overlay
                    CoverTextureOverlay(
                        texture: notebook.coverTexture,
                        size: CGSize(width: coverWidth, height: coverHeight)
                    )
                    .clipShape(
                        .rect(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 10,
                            topTrailingRadius: 10
                        )
                    )

                    // Spine with stitching
                    ZStack {
                        LinearGradient(
                            colors: [.white.opacity(0.18), .black.opacity(0.06), .clear],
                            startPoint: .leading,
                            endPoint: .init(x: 0.15, y: 0)
                        )
                        .frame(width: coverWidth, height: coverHeight)

                        CoverSpineStitching(height: coverHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 1)
                    }
                    .clipShape(
                        .rect(topLeadingRadius: 4, bottomLeadingRadius: 4)
                    )
                    .frame(width: coverWidth, height: coverHeight)

                    // Book icon + page count + embossed title
                    VStack(alignment: .leading, spacing: 4) {
                        // Embossed title at top
                        if !notebook.name.isEmpty {
                            CoverEmbossedTitle(text: notebook.name, maxWidth: coverWidth - 20)
                                .padding(.top, 14)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Spacer()

                        Image(systemName: "book.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(pageCount) page\(pageCount == 1 ? "" : "s")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(10)
                }
            }
            // 3D book shadow
            .shadow(color: .black.opacity(0.22), radius: 8, x: 2, y: 5)
            .shadow(color: .black.opacity(0.06), radius: 1, x: 1, y: 1)
            // Subtle 3D perspective tilt
            .rotation3DEffect(
                .degrees(isPressed ? 0 : 2),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.5
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)

            // Notebook name
            Text(notebook.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: coverWidth + 8, alignment: .leading)
                .padding(.top, 6)
                .foregroundStyle(.primary)
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    @ViewBuilder
    private var coverSurface: some View {
        if let data = notebook.customCoverData,
           let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
                .frame(width: coverWidth, height: coverHeight)
                .clipped()
        } else {
            notebook.cover.gradient
        }
    }
}

// MARK: - PDF library (middle column)

private struct PDFLibraryView: View {
    @EnvironmentObject var pdfStore: PDFStore
    @EnvironmentObject var noteStore: NoteStore
    @Binding var selectedPDFID: UUID?

    /// Callback invoked with a companion note's ID so the parent can open it in a tab.
    var onOpenCompanionNote: ((UUID) -> Void)?

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
                            PDFCardView(
                                record: record,
                                isSelected: selectedPDFID == record.id,
                                hasCompanionNote: noteStore.hasCompanionNote(forPDF: record.id)
                            )
                                .onTapGesture { selectedPDFID = record.id }
                                .contextMenu {
                                    if noteStore.hasCompanionNote(forPDF: record.id),
                                       let existing = noteStore.notes(forPDF: record.id).first {
                                        Button {
                                            onOpenCompanionNote?(existing.id)
                                        } label: {
                                            Label("Open Companion Note", systemImage: "note.text")
                                        }
                                    } else {
                                        Button {
                                            let note = noteStore.addNote(
                                                forPDF: record.id,
                                                title: "\(record.title) — Notes"
                                            )
                                            onOpenCompanionNote?(note.id)
                                        } label: {
                                            Label("Create Companion Note", systemImage: "note.text.badge.plus")
                                        }
                                    }

                                    Divider()

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
                    let note = noteStore.addNote(forPDF: record)
                    tabSession.openTab(
                        .note(id: note.id),
                        displayName: note.title,
                        accentColor: [0.8, 0.3, 0.3]
                    )
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
    var hasCompanionNote: Bool = false

    private static let companionBadgeColor = Color(red: 0.8, green: 0.3, blue: 0.3)

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
                // Companion-note badge — top-right corner
                if hasCompanionNote {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "note.text")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Self.companionBadgeColor.opacity(0.9)))
                                .padding(6)
                        }
                        Spacer()
                    }
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



// MARK: - Tag picker sheet

/// GoodNotes / Apple Notes–style tag picker sheet.
/// Lets the user toggle existing tags on/off and create new tags for a note.
private struct TagPickerSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let note: Note

    @State private var newTagText = ""
    @State private var searchText = ""

    private var noteTags: Set<String> {
        Set(noteStore.notes.first(where: { $0.id == note.id })?.tags ?? [])
    }

    private var filteredTags: [String] {
        if searchText.isEmpty { return noteStore.allTags }
        return noteStore.allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── New tag ──────────────────────────────────────────
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                            .font(.body)
                        TextField("New tag…", text: $newTagText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit { commitNewTag() }
                        if !newTagText.isEmpty {
                            Button {
                                commitNewTag()
                            } label: {
                                Text("Add")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Create New Tag")
                }

                // ── Existing tags ─────────────────────────────────────
                if !noteStore.allTags.isEmpty {
                    Section {
                        ForEach(filteredTags, id: \.self) { tag in
                            let isActive = noteTags.contains(tag)
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if isActive {
                                    noteStore.removeTag(tag, from: note.id)
                                } else {
                                    noteStore.addTag(tag, to: note.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isActive ? .tint : .secondary)
                                        .font(.body)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("#\(tag)")
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("\(noteStore.notes(withTag: tag).count) note\(noteStore.notes(withTag: tag).count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("All Tags")
                    }
                } else if newTagText.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "tag")
                                    .font(.system(size: 32, weight: .ultraLight))
                                    .foregroundStyle(.tertiary)
                                Text("No Tags Yet")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Type a name above to create your first tag.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tags")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func commitNewTag() {
        let trimmed = newTagText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        noteStore.addTag(trimmed, to: note.id)
        newTagText = ""
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
