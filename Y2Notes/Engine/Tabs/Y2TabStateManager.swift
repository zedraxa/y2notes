import Foundation
import os

// MARK: - Tab State

/// Represents a single open tab.
struct TabState: Codable, Hashable {
    let noteID: UUID
    var title: String
    var openedAt: Date

    func hash(into hasher: inout Hasher) { hasher.combine(noteID) }
    static func == (lhs: TabState, rhs: TabState) -> Bool { lhs.noteID == rhs.noteID }
}

// MARK: - Y2TabStateManager

/// Manages the ordered list of open note tabs and the active selection.
///
/// **Responsibilities:**
/// - Tracks which notes are open (ordered list of `TabState`).
/// - Tracks which note is currently active.
/// - Persists tab state across app launches via UserDefaults.
/// - Enforces a maximum tab count (oldest auto-closes if exceeded).
/// - Provides callbacks for tab lifecycle events.
///
/// **Thread safety:** All mutations must happen on the main thread.
final class Y2TabStateManager {

    // MARK: - Configuration

    /// Maximum simultaneous open tabs.
    static let maxTabs = 10

    /// UserDefaults key for persisting tab state.
    private static let persistenceKey = "y2notes.openTabs"
    private static let activeTabKey = "y2notes.activeTab"

    // MARK: - Properties

    private(set) var tabs: [TabState] = []
    private(set) var activeNoteID: UUID?
    private let logger = Logger(subsystem: "com.y2notes.app", category: "tabs")

    /// Called whenever the tab list or active selection changes.
    var onChange: (() -> Void)?

    // MARK: - Init

    init() {
        loadPersistedState()
    }

    // MARK: - Tab Operations

    /// Opens a note in a new tab (or switches to it if already open).
    func openTab(noteID: UUID, title: String) {
        if let existing = tabs.firstIndex(where: { $0.noteID == noteID }) {
            // Already open — just switch to it
            activeNoteID = noteID
            tabs[existing].title = title
        } else {
            // Enforce max tabs
            if tabs.count >= Self.maxTabs {
                let oldest = tabs.min(by: { $0.openedAt < $1.openedAt })
                if let oldest, oldest.noteID != activeNoteID {
                    closeTab(noteID: oldest.noteID)
                }
            }

            let tab = TabState(noteID: noteID, title: title, openedAt: .now)
            tabs.append(tab)
            activeNoteID = noteID
            logger.info("Opened tab: \(title) (\(noteID))")
        }

        persist()
        onChange?()
    }

    /// Closes a tab and selects an adjacent tab.
    func closeTab(noteID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.noteID == noteID }) else { return }
        tabs.remove(at: index)

        // Select adjacent tab if this was the active one
        if activeNoteID == noteID {
            if tabs.isEmpty {
                activeNoteID = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activeNoteID = tabs[newIndex].noteID
            }
        }

        logger.info("Closed tab: \(noteID)")
        persist()
        onChange?()
    }

    /// Switches to an existing tab.
    func selectTab(noteID: UUID) {
        guard tabs.contains(where: { $0.noteID == noteID }) else { return }
        activeNoteID = noteID
        persist()
        onChange?()
    }

    /// Reorders a tab from one position to another.
    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: min(destinationIndex, tabs.count))
        persist()
        onChange?()
    }

    /// Updates the title of an open tab.
    func updateTitle(noteID: UUID, title: String) {
        guard let index = tabs.firstIndex(where: { $0.noteID == noteID }) else { return }
        tabs[index].title = title
        onChange?()
    }

    /// Closes all tabs.
    func closeAllTabs() {
        tabs.removeAll()
        activeNoteID = nil
        persist()
        onChange?()
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(tabs) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
        if let activeID = activeNoteID {
            defaults.set(activeID.uuidString, forKey: Self.activeTabKey)
        } else {
            defaults.removeObject(forKey: Self.activeTabKey)
        }
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.persistenceKey),
           let decoded = try? JSONDecoder().decode([TabState].self, from: data) {
            tabs = decoded
        }

        if let idString = defaults.string(forKey: Self.activeTabKey),
           let uuid = UUID(uuidString: idString),
           tabs.contains(where: { $0.noteID == uuid }) {
            activeNoteID = uuid
        } else {
            activeNoteID = tabs.first?.noteID
        }
    }

    // MARK: - Query

    /// Returns the tab for a given note ID, if open.
    func tab(for noteID: UUID) -> TabState? {
        tabs.first(where: { $0.noteID == noteID })
    }

    /// Whether a note is currently open in a tab.
    func isOpen(noteID: UUID) -> Bool {
        tabs.contains(where: { $0.noteID == noteID })
    }
}
