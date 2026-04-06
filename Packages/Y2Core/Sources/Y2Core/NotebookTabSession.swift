import Foundation
import UIKit

// MARK: - Tab Content

public enum TabContent: Codable, Equatable {
    case notebook(id: UUID)
    case note(id: UUID)
    case pdf(id: UUID)
    case document(id: UUID)

    public var contentID: UUID {
        switch self {
        case .notebook(let id), .note(let id), .pdf(let id), .document(let id):
            return id
        }
    }

    public var iconName: String {
        switch self {
        case .notebook: return "book.closed"
        case .note:     return "doc.text"
        case .pdf:      return "doc.richtext"
        case .document: return "doc"
        }
    }
}

// MARK: - Tab Session

public struct TabSession: Identifiable, Codable, Equatable {
    public let id: UUID
    public var content: TabContent
    public var displayName: String
    public var accentColor: [Double]
    public var pageIndex: Int
    public var sectionID: UUID?
    public var zoomScale: Double
    public var contentOffsetX: Double
    public var contentOffsetY: Double
    public var showAdvancedPanel: Bool
    public var lastActiveAt: Date
    public let createdAt: Date

    public init(
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

    public var contentOffset: CGPoint {
        get { CGPoint(x: contentOffsetX, y: contentOffsetY) }
        set { contentOffsetX = newValue.x; contentOffsetY = newValue.y }
    }
}

// MARK: - Tab Workspace Store

@Observable
public final class TabWorkspaceStore {

    // MARK: - State

    public var tabs: [TabSession] = [] {
        didSet { persist() }
    }

    public var activeTabID: UUID? {
        didSet { persist() }
    }

    public static let softMaxTabs = 8
    public static let hardMaxTabs = 12

    // MARK: - Derived

    public var activeTab: TabSession? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    public var activeContent: TabContent? { activeTab?.content }

    // MARK: - Warm Cache

    private var warmCache: [UUID: Data] = [:]
    private static let warmCacheLimit = 2

    public let thumbnailCache = NSCache<NSUUID, UIImage>()

    // MARK: - Init

    public init() {
        thumbnailCache.countLimit = 20
        load()
    }

    // MARK: - Open

    @discardableResult
    public func openTab(
        _ content: TabContent,
        displayName: String,
        accentColor: [Double] = [0.4, 0.4, 0.8]
    ) -> UUID {
        if let existing = tabs.first(where: { $0.content == content }) {
            switchTo(existing.id)
            return existing.id
        }

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

    public func closeTab(_ tabID: UUID) {
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

    public func closeOtherTabs(except keepID: UUID) {
        let idsToClose = tabs.filter { $0.id != keepID }.map(\.id)
        for id in idsToClose { closeTab(id) }
    }

    // MARK: - Switch

    public func switchTo(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        tabs[idx].lastActiveAt = Date()
    }

    // MARK: - Reorder

    public func reorderTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination <= tabs.count else { return }
        let tab = tabs.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        tabs.insert(tab, at: min(adjusted, tabs.count))
    }

    // MARK: - State Updates

    public func updateTabState(
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

    public func suspendTab(_ tabID: UUID, drawingData: Data) {
        warmCache[tabID] = drawingData
        trimWarmCache()
    }

    public func resumeTabData(_ tabID: UUID) -> Data? {
        warmCache[tabID]
    }

    public func flushWarmCache() {
        warmCache.removeAll()
    }

    private func trimWarmCache() {
        guard warmCache.count > Self.warmCacheLimit else { return }
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

    public func validateTabs(
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

    private func migrateFromLegacyStorage() {
        let ud = UserDefaults.standard
        let legacyKey = "y2notes.workspace.tabs"
        let legacyActiveKey = "y2notes.workspace.activeTab"

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
            persist()
            ud.removeObject(forKey: legacyKey)
            ud.removeObject(forKey: legacyActiveKey)
        }
    }

    // MARK: - Compatibility Shim

    @discardableResult
    public func openNotebook(
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

public typealias NotebookTabSession = TabWorkspaceStore
public typealias NotebookTab = TabSession
