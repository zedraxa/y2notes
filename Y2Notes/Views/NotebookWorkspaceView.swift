import SwiftUI

/// Multi-tab workspace that replaces the ShelfView detail column.
///
/// **Architecture**:
/// - `NotebookTabBar` at the top shows open tabs with accent colours.
/// - `TabContentView` below renders the active tab's content view.
/// - Only one content view is live at a time — switching tabs destroys the
///   old view and creates a new one (Option B from the design doc).
///
/// **Performance**: A 200ms crossfade masks the ~100ms view recreation cost.
/// The floating toolbar stays in place during switches (it's shared globally).
///
/// **Future split-view**: This container can be embedded in each side of a
/// split layout to support side-by-side editing.
struct NotebookWorkspaceView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore: PDFStore
    @EnvironmentObject var documentStore: DocumentStore
    @Environment(TabWorkspaceStore.self) private var workspace
    /// Callback to show the shelf/picker for opening new content.
    var onOpenShelf: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBarSection
            tabContentSection
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: workspace.tabs.count)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: workspace.activeTabID)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBarSection: some View {
        if workspace.tabs.count > 1 {
            NotebookTabBar(onNewTab: onOpenShelf)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContentSection: some View {
        if let tab = workspace.activeTab {
            tabContentView(for: tab)
                .id(tab.id) // Force recreation on tab switch
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        } else {
            emptyWorkspace
        }
    }

    @ViewBuilder
    private func tabContentView(for tab: TabSession) -> some View {
        switch tab.content {
        case .notebook(let id):
            notebookContent(id: id, tab: tab)
        case .note(let id):
            noteContent(id: id, tab: tab)
        case .pdf(let id):
            pdfContent(id: id, tab: tab)
        case .document(let id):
            documentContent(id: id, tab: tab)
        }
    }

    // MARK: - Content Type Renderers

    @ViewBuilder
    private func notebookContent(id: UUID, tab: TabSession) -> some View {
        if let notebook = noteStore.notebooks.first(where: { $0.id == id }) {
            NotebookReaderView(notebook: notebook, tabID: tab.id)
        } else {
            deletedContentPlaceholder(tab: tab)
        }
    }

    @ViewBuilder
    private func noteContent(id: UUID, tab: TabSession) -> some View {
        if let note = noteStore.notes.first(where: { $0.id == id }) {
            NoteEditorView(note: note, tab: tab)
        } else {
            deletedContentPlaceholder(tab: tab)
        }
    }

    @ViewBuilder
    private func pdfContent(id: UUID, tab: TabSession) -> some View {
        if let record = pdfStore.records.first(where: { $0.id == id }) {
            PDFViewerView(record: record, tab: tab, onOpenCompanionNote: { noteID in
                openCompanionNote(noteID)
            })
        } else {
            deletedContentPlaceholder(tab: tab)
        }
    }

    @ViewBuilder
    private func documentContent(id: UUID, tab: TabSession) -> some View {
        if let doc = documentStore.documents.first(where: { $0.id == id }) {
            DocumentViewerView(
                document: doc,
                fileURL: documentStore.storedURL(for: doc),
                onOpenCompanionNote: { noteID in
                    openCompanionNote(noteID)
                }
            )
        } else {
            deletedContentPlaceholder(tab: tab)
        }
    }

    /// Opens a companion note in a new tab.
    private func openCompanionNote(_ noteID: UUID) {
        guard let note = noteStore.notes.first(where: { $0.id == noteID }) else { return }
        workspace.openTab(
            .note(id: noteID),
            displayName: note.title.isEmpty ? "Untitled Note" : note.title,
            accentColor: [0.45, 0.45, 0.5]
        )
    }

    // MARK: - Deleted Content

    @ViewBuilder
    private func deletedContentPlaceholder(tab: TabSession) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("\"\(tab.displayName)\" was deleted")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            // Auto-close after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { workspace.closeTab(tab.id) }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyWorkspace: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("No notebook open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Open Notebook", action: onOpenShelf)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
