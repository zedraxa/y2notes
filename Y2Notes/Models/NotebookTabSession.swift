import Foundation

// MARK: - Notebook Tab

/// Represents a single open notebook tab in the workspace.
///
/// Each tab stores the notebook's identity and the last-known navigation state
/// so switching back to a previously open tab restores the exact position.
/// The model is `Codable` for persistence across app relaunches.
struct NotebookTab: Identifiable, Codable, Equatable {
    /// Unique tab instance identifier (not the notebook's ID — the same notebook
    /// can theoretically be opened in multiple tabs, though the UI prevents it).
    let id: UUID
    /// The notebook this tab is displaying.
    let notebookID: UUID
    /// Display name cached from the notebook for tab-bar rendering without
    /// requiring a store lookup.
    var displayName: String
    /// Cover color components [r, g, b] for the tab's accent tint.
    var coverColor: [Double]
    /// The page index the user was viewing when this tab was last active.
    var lastPageIndex: Int
    /// Timestamp of the last interaction with this tab — used for LRU eviction.
    var lastActiveDate: Date

    init(
        id: UUID = UUID(),
        notebookID: UUID,
        displayName: String,
        coverColor: [Double] = [0.4, 0.4, 0.8],
        lastPageIndex: Int = 0,
        lastActiveDate: Date = Date()
    ) {
        self.id = id
        self.notebookID = notebookID
        self.displayName = displayName
        self.coverColor = coverColor
        self.lastPageIndex = lastPageIndex
        self.lastActiveDate = lastActiveDate
    }
}

// MARK: - Notebook Tab Session

/// Manages the collection of open notebook tabs, the active tab, and
/// persistence across relaunches.
///
/// **State ownership**: This is an `@Observable` class owned at the app level
/// (injected via `.environment`). Individual notebook views read `activeTabID`
/// to decide whether they are the frontmost tab.
///
/// **Persistence**: Tabs are serialised to UserDefaults on every mutation so
/// the workspace survives force-quit and relaunch. The serialised data is
/// lightweight (UUIDs + page indices, no drawing data).
///
/// **Caching strategy**: Only the active tab's notebook is fully loaded in
/// memory (PKCanvasView, PKDrawing, page background). Suspended tabs keep
/// their `NotebookTab` metadata and a cached thumbnail. When the user switches
/// tabs, the outgoing notebook's drawing is saved and its canvas is released;
/// the incoming notebook is loaded from the NoteStore/PDF cache.
@Observable
final class NotebookTabSession {

    // MARK: - Published State

    /// Ordered list of open tabs. The tab bar renders these left-to-right.
    var tabs: [NotebookTab] = [] {
        didSet { persistTabs() }
    }

    /// The tab currently displayed in the workspace. `nil` when no notebooks
    /// are open (shows the shelf / empty state).
    var activeTabID: UUID? {
        didSet { persistTabs() }
    }

    /// Maximum number of simultaneously open tabs. Prevents runaway memory.
    static let maxTabs = 8

    // MARK: - Init

    init() {
        loadTabs()
    }

    // MARK: - Tab Management

    /// Opens a notebook in a new tab, or switches to it if already open.
    /// Returns the tab that is now active.
    @discardableResult
    func openNotebook(
        id notebookID: UUID,
        displayName: String,
        coverColor: [Double] = [0.4, 0.4, 0.8]
    ) -> NotebookTab {
        // If already open, just switch to it
        if let existing = tabs.first(where: { $0.notebookID == notebookID }) {
            activeTabID = existing.id
            // Update last-active timestamp
            if let idx = tabs.firstIndex(where: { $0.id == existing.id }) {
                tabs[idx].lastActiveDate = Date()
            }
            return existing
        }

        // Evict oldest tab if at capacity
        if tabs.count >= Self.maxTabs {
            evictOldestTab()
        }

        let tab = NotebookTab(
            notebookID: notebookID,
            displayName: displayName,
            coverColor: coverColor
        )
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    /// Closes a tab by its ID. If the closed tab was active, switches to the
    /// nearest sibling (right, then left, then nil).
    func closeTab(id tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasActive = activeTabID == tabID
        tabs.remove(at: idx)

        if wasActive {
            if tabs.isEmpty {
                activeTabID = nil
            } else {
                // Prefer the tab that was to the right, else the one to the left
                let newIdx = min(idx, tabs.count - 1)
                activeTabID = tabs[newIdx].id
            }
        }
    }

    /// Moves a tab from one position to another (for drag-to-reorder).
    func moveTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination <= tabs.count else { return }
        let tab = tabs.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        tabs.insert(tab, at: min(adjustedDestination, tabs.count))
    }

    /// Updates the saved page index for a tab (called when the user navigates
    /// pages within a notebook).
    func updatePageIndex(_ pageIndex: Int, forTab tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].lastPageIndex = pageIndex
        tabs[idx].lastActiveDate = Date()
    }

    /// The currently active tab, if any.
    var activeTab: NotebookTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    // MARK: - Eviction

    /// Removes the least-recently-used tab that is not the active tab.
    private func evictOldestTab() {
        guard let oldest = tabs
            .filter({ $0.id != activeTabID })
            .min(by: { $0.lastActiveDate < $1.lastActiveDate })
        else { return }
        closeTab(id: oldest.id)
    }

    // MARK: - Persistence

    private static let persistenceKey = "y2notes.workspace.tabs"
    private static let activeTabKey = "y2notes.workspace.activeTab"

    private func persistTabs() {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        if let activeTabID {
            UserDefaults.standard.set(activeTabID.uuidString, forKey: Self.activeTabKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeTabKey)
        }
    }

    private func loadTabs() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Self.persistenceKey),
           let loaded = try? JSONDecoder().decode([NotebookTab].self, from: data) {
            tabs = loaded
        }
        if let str = ud.string(forKey: Self.activeTabKey),
           let uuid = UUID(uuidString: str),
           tabs.contains(where: { $0.id == uuid }) {
            activeTabID = uuid
        } else {
            activeTabID = tabs.first?.id
        }
    }
}
