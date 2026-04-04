import SwiftUI

/// Multi-tab notebook workspace that lets users work across several notebooks
/// without losing context.
///
/// **Architecture**:
/// - `NotebookTabBar` at the top shows open tabs with notebook accent colours.
/// - Below the tab bar, the active notebook's `NotebookReaderView` is shown.
/// - Inactive tabs preserve their page index in `NotebookTabSession` so
///   switching back restores position instantly.
/// - The floating toolbar and advanced inspector remain shared — they bind to
///   the global `DrawingToolStore` which is tool-state, not notebook-state.
///
/// **Performance**: Only one `NotebookReaderView` is live at a time. Switching
/// tabs saves the outgoing drawing and loads the incoming notebook from the
/// NoteStore cache. `NotebookReaderView` already handles page restoration via
/// `flatPageIndex`.
///
/// **Future split-view**: This container can be embedded in each side of a
/// `NavigationSplitView` to support side-by-side notebook editing.
struct NotebookWorkspaceView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(NotebookTabSession.self) private var tabSession
    /// Callback to show the shelf/notebook picker for opening a new tab.
    var onOpenShelf: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — only shown when more than 1 tab is open
            if tabSession.tabs.count > 1 {
                NotebookTabBar(onNewTab: onOpenShelf)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Active notebook content
            activeContent
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: tabSession.tabs.count)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: tabSession.activeTabID)
    }

    // MARK: - Active Content

    @ViewBuilder
    private var activeContent: some View {
        if let activeTab = tabSession.activeTab,
           let notebook = noteStore.notebooks.first(where: { $0.id == activeTab.notebookID }) {
            NotebookReaderView(notebook: notebook)
                .id(activeTab.id)
                .onDisappear {
                    // Page index is saved continuously via NotebookReaderView's
                    // onChange handler — this is a safety net.
                }
        } else {
            // No active tab — show a prompt to open a notebook
            emptyWorkspace
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
