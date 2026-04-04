import Foundation
import UIKit

// MARK: - Tab Content

/// What a tab displays. The tab bar doesn't care about the content type —
/// notebooks, notes, PDFs, and documents all share the same lifecycle.
enum TabContent: Codable, Equatable {
    case notebook(id: UUID)
    case note(id: UUID)
    case pdf(id: UUID)
    case document(id: UUID)

    /// The content's unique identifier regardless of type.
    var contentID: UUID {
        switch self {
        case .notebook(let id), .note(let id), .pdf(let id), .document(let id):
            return id
        }
    }

    /// SF Symbol name for display in the tab bar.
    var iconName: String {
        switch self {
        case .notebook: return "book.closed"
        case .note:     return "doc.text"
        case .pdf:      return "doc.richtext"
        case .document: return "doc"
        }
    }
}

// MARK: - Tab Session

/// Represents a single open tab in the workspace.
///
/// Each tab stores its content identity and the last-known navigation state
/// so switching back restores the exact position. `Codable` for persistence.
struct TabSession: Identifiable, Codable, Equatable {
    /// Unique tab instance identifier.
    let id: UUID
    /// What content this tab is displaying.
    var content: TabContent
    /// Cached display name for the tab bar (avoids store lookups).
    var displayName: String
    /// Accent color components [r, g, b] in 0…1 for the tab's tint.
    var accentColor: [Double]
    /// Current page (flat index for notebooks, page index for notes).
    var pageIndex: Int
    /// Active section tab (notebooks only).
    var sectionID: UUID?
    /// Canvas zoom level.
    var zoomScale: Double
    /// Canvas scroll position.
    var contentOffsetX: Double
    var contentOffsetY: Double
    /// Whether the right-side inspector panel was open.
    var showAdvancedPanel: Bool
    /// Timestamp of the last interaction — used for LRU eviction.
    var lastActiveAt: Date
    /// When the tab was created.
    let createdAt: Date

    init(
        id: UUID = UUID(),
        content: TabContent,
        displayName: String,
        accentColor: [Double] = [0.4, 0.4, 0.8],
        pageIndex: Int = 0,
        sectionID: UUID? = nil,
        zoomScale: Double = 1.0,
        contentOffsetX: Double = 0,
        contentOffsetY: Double = 0,
        showAdvancedPanel: Bool = false
    ) {
        self.id = id
        self.content = content
        self.displayName = displayName
        self.accentColor = accentColor
        self.pageIndex = pageIndex
        self.sectionID = sectionID
        self.zoomScale = zoomScale
        self.contentOffsetX = contentOffsetX
        self.contentOffsetY = contentOffsetY
        self.showAdvancedPanel = showAdvancedPanel
        self.lastActiveAt = Date()
        self.createdAt = Date()
    }

    /// Convenience: CGPoint form of scroll offset.
    var contentOffset: CGPoint {
        get { CGPoint(x: contentOffsetX, y: contentOffsetY) }
        set { contentOffsetX = newValue.x; contentOffsetY = newValue.y }
    }
}

// MARK: - Tab Workspace Store

/// Manages the collection of open tabs, the active tab, persistence,
/// and the warm-tab memory cache.
///
/// **State ownership**: `@Observable` class owned at the app level,
/// injected via `.environment()`. Content views read `activeTabID`
/// and report state changes back through `updateTabState(...)`.
///
/// **Persistence**: Tabs are serialised to `y2notes_tabs.json` in the
/// Documents directory on every mutation, matching the existing
/// `y2notes_notes.json` / `y2notes_notebooks.json` pattern.
///
/// **Caching**: Only the active tab's content view is mounted.
/// The 2 most-recently-used suspended tabs keep serialised drawing
/// data in memory (`warmCache`); others load from disk on resume.
@Observable
final class TabWorkspaceStore {

    // MARK: - State

    /// Ordered list of open tabs (matches visual tab bar order).
    var tabs: [TabSession] = [] {
        didSet { persist() }
    }

    /// The tab currently displayed. `nil` = no content open.
    var activeTabID: UUID? {
        didSet { persist() }
    }

    /// Soft limit — after this, oldest tab is evicted on new open.
    static let softMaxTabs = 8
    /// Hard limit — beyond this, oldest suspended tab is auto-closed.
    static let hardMaxTabs = 12

    // MARK: - Derived

    /// The currently active tab session, if any.
    var activeTab: TabSession? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    /// The active tab's content, if any.
    var activeContent: TabContent? { activeTab?.content }

    // MARK: - Warm Cache

    /// Serialised PKDrawing data for recently-suspended tabs.
    /// Key = tab ID. Kept for the 2 most-recently-used non-active tabs.
    private var warmCache: [UUID: Data] = [:]
    private static let warmCacheLimit = 2

    /// Thumbnail images for tab bar display.
    let thumbnailCache = NSCache<NSUUID, UIImage>()

    // MARK: - Init

    init() {
        thumbnailCache.countLimit = 20
        load()
    }

    // MARK: - Open

    /// Opens content in a new tab, or switches to it if already open.
    @discardableResult
    func openTab(
        _ content: TabContent,
        displayName: String,
        accentColor: [Double] = [0.4, 0.4, 0.8]
    ) -> UUID {
        // Dedup: if already open, switch to it
        if let existing = tabs.first(where: { $0.content == content }) {
            switchTo(existing.id)
            return existing.id
        }

        // Evict if at soft limit
        if tabs.count >= Self.softMaxTabs {
            evictOldestTab()
        }

        let tab = TabSession(
            content: content,
            displayName: displayName,
            accentColor: accentColor
        )
        tabs.append(tab)
        activeTabID = tab.id
        return tab.id
    }

    // MARK: - Close

    /// Closes a tab. If it was active, switches to the nearest sibling.
    func closeTab(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasActive = activeTabID == tabID
        tabs.remove(at: idx)
        warmCache.removeValue(forKey: tabID)
        thumbnailCache.removeObject(forKey: tabID as NSUUID)

        if wasActive {
            if tabs.isEmpty {
                activeTabID = nil
            } else {
                let newIdx = min(idx, tabs.count - 1)
                activeTabID = tabs[newIdx].id
            }
        }
    }

    /// Closes all tabs except the specified one.
    func closeOtherTabs(except keepID: UUID) {
        let idsToClose = tabs.filter { $0.id != keepID }.map(\.id)
        for id in idsToClose { closeTab(id) }
    }

    // MARK: - Switch

    /// Switches to a specific tab, updating last-active timestamp.
    func switchTo(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        tabs[idx].lastActiveAt = Date()
    }

    // MARK: - Reorder

    /// Moves a tab from one position to another (drag-to-reorder).
    func reorderTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination <= tabs.count else { return }
        let tab = tabs.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        tabs.insert(tab, at: min(adjusted, tabs.count))
    }

    // MARK: - State Updates

    /// Updates persisted navigation state for a tab (page, zoom, scroll, panel).
    func updateTabState(
        _ tabID: UUID,
        pageIndex: Int? = nil,
        sectionID: UUID?? = nil,
        zoomScale: Double? = nil,
        contentOffset: CGPoint? = nil,
        showAdvancedPanel: Bool? = nil
    ) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let p = pageIndex            { tabs[idx].pageIndex = p }
        if let s = sectionID            { tabs[idx].sectionID = s }
        if let z = zoomScale            { tabs[idx].zoomScale = z }
        if let o = contentOffset        { tabs[idx].contentOffset = o }
        if let a = showAdvancedPanel    { tabs[idx].showAdvancedPanel = a }
        tabs[idx].lastActiveAt = Date()
    }

    // MARK: - Warm Cache

    /// Stores serialised drawing data for a suspended tab.
    func suspendTab(_ tabID: UUID, drawingData: Data) {
        warmCache[tabID] = drawingData
        trimWarmCache()
    }

    /// Retrieves warm-cached drawing data, or `nil` if evicted to cold.
    func resumeTabData(_ tabID: UUID) -> Data? {
        warmCache[tabID]
    }

    /// Drops all warm caches (e.g. on memory warning).
    func flushWarmCache() {
        warmCache.removeAll()
    }

    private func trimWarmCache() {
        guard warmCache.count > Self.warmCacheLimit else { return }
        // Keep only the most-recently-active tabs' data
        let recentTabIDs = Set(
            tabs
                .filter { $0.id != activeTabID }
                .sorted { $0.lastActiveAt > $1.lastActiveAt }
                .prefix(Self.warmCacheLimit)
                .map(\.id)
        )
        for key in warmCache.keys where !recentTabIDs.contains(key) {
            warmCache.removeValue(forKey: key)
        }
    }

    // MARK: - Eviction

    private func evictOldestTab() {
        guard let oldest = tabs
            .filter({ $0.id != activeTabID })
            .min(by: { $0.lastActiveAt < $1.lastActiveAt })
        else { return }
        closeTab(oldest.id)
    }

    // MARK: - Validation

    /// Removes tabs whose content no longer exists in the stores.
    /// Called on app launch after stores have loaded.
    func validateTabs(
        notebookIDs: Set<UUID>,
        noteIDs: Set<UUID>,
        pdfIDs: Set<UUID>,
        documentIDs: Set<UUID>
    ) {
        let invalidIDs = tabs.filter { tab in
            switch tab.content {
            case .notebook(let id): return !notebookIDs.contains(id)
            case .note(let id):     return !noteIDs.contains(id)
            case .pdf(let id):      return !pdfIDs.contains(id)
            case .document(let id): return !documentIDs.contains(id)
            }
        }.map(\.id)

        for id in invalidIDs { closeTab(id) }
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("y2notes_tabs.json")
    }

    /// Codable wrapper for the full tab bar state.
    private struct TabBarState: Codable {
        var tabs: [TabSession]
        var activeTabID: UUID?
        var lastSavedAt: Date
    }

    private func persist() {
        let state = TabBarState(
            tabs: tabs,
            activeTabID: activeTabID,
            lastSavedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let state = try? JSONDecoder().decode(TabBarState.self, from: data)
        else {
            // Migrate from legacy UserDefaults-based storage if present
            migrateFromLegacyStorage()
            return
        }
        tabs = state.tabs
        if let id = state.activeTabID, tabs.contains(where: { $0.id == id }) {
            activeTabID = id
        } else {
            activeTabID = tabs.first?.id
        }
    }

    /// One-time migration from the old `NotebookTabSession` UserDefaults keys.
    private func migrateFromLegacyStorage() {
        let ud = UserDefaults.standard
        let legacyKey = "y2notes.workspace.tabs"
        let legacyActiveKey = "y2notes.workspace.activeTab"

        // Old format: [NotebookTab] with notebookID/displayName/coverColor/lastPageIndex
        struct LegacyTab: Codable {
            let id: UUID
            let notebookID: UUID
            var displayName: String
            var coverColor: [Double]
            var lastPageIndex: Int
            var lastActiveDate: Date
        }

        if let data = ud.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([LegacyTab].self, from: data) {
            tabs = legacy.map { old in
                TabSession(
                    id: old.id,
                    content: .notebook(id: old.notebookID),
                    displayName: old.displayName,
                    accentColor: old.coverColor,
                    pageIndex: old.lastPageIndex
                )
            }
            if let str = ud.string(forKey: legacyActiveKey),
               let uuid = UUID(uuidString: str),
               tabs.contains(where: { $0.id == uuid }) {
                activeTabID = uuid
            } else {
                activeTabID = tabs.first?.id
            }
            // Persist in new format and remove legacy keys
            persist()
            ud.removeObject(forKey: legacyKey)
            ud.removeObject(forKey: legacyActiveKey)
        }
    }

    // MARK: - Compatibility Shim

    /// Convenience for notebook tabs — matches the old `openNotebook(...)` API
    /// used by ShelfView so callers don't need to change their call sites.
    @discardableResult
    func openNotebook(
        id notebookID: UUID,
        displayName: String,
        coverColor: [Double] = [0.4, 0.4, 0.8]
    ) -> UUID {
        openTab(
            .notebook(id: notebookID),
            displayName: displayName,
            accentColor: coverColor
        )
    }
}

// MARK: - Legacy Type Aliases

/// Backwards-compatible alias so existing code compiles during migration.
typealias NotebookTabSession = TabWorkspaceStore
/// Backwards-compatible alias for the old tab model name.
typealias NotebookTab = TabSession
