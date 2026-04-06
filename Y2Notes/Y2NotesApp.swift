import SwiftUI

@main
struct Y2NotesApp: App {

    /// Single source of truth for all services.  Created once and owned for
    /// the lifetime of the app.  Engine / UIKit code accesses services via
    /// protocol-typed properties; SwiftUI views receive concrete stores
    /// through `.environmentObject()` until the full adapter migration.
    private let container = ServiceContainer()

    // Concrete stores pulled from the container for SwiftUI injection.
    // These will eventually be replaced by ObservableXxxStore adapters.
    @StateObject private var noteStore: NoteStore
    @StateObject private var toolStore: DrawingToolStore
    @StateObject private var syncEngine: GoogleDriveSyncEngine

    // Stores not yet managed by ServiceContainer keep direct init.
    @State private var tabSession = TabWorkspaceStore()

    init() {
        // Use concrete accessors — avoids force-casting from protocol types.
        _noteStore = StateObject(wrappedValue: container.concreteNoteStore)
        _toolStore = StateObject(wrappedValue: container.concreteToolStore)
        _syncEngine = StateObject(wrappedValue: container.concreteSyncEngine)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Core stores (protocol-backed, owned by ServiceContainer)
                .environmentObject(noteStore)
                .environmentObject(toolStore)
                .environmentObject(syncEngine)

                // Core services exposed as legacy store types
                .environmentObject(container.pdfStore)
                .environmentObject(container.documentStore)
                .environmentObject(container.stickerStore)
                .environmentObject(container.navigationStore)

                // Legacy stores that views still depend on by type.
                // These will be replaced by ObservableXxxStore adapters
                // once views are migrated to use the adapter types.
                .environmentObject(container.legacyThemeStore)
                .environmentObject(container.legacyInkEffectStore)
                .environmentObject(container.legacySettingsStore)

                .environment(tabSession)
                .handlesExternalEvents(preferring: Set<String>(), allowing: Set<String>(["*"]))
        }
        .handlesExternalEvents(matching: Set<String>(["*"]))
    }
}

// MARK: - NSUserActivity constants

extension NSUserActivity {
    /// Activity type for editing a specific note in a window.
    static let editNoteActivityType = "com.y2notes.edit-note"

    /// Create a user activity representing the currently edited note.
    /// Attach this to a window scene for Handoff and multi-window state restoration.
    static func editNote(noteID: UUID) -> NSUserActivity {
        let activity = NSUserActivity(activityType: editNoteActivityType)
        activity.title = "Edit Note"
        activity.userInfo = ["noteID": noteID.uuidString]
        activity.isEligibleForHandoff = true
        activity.targetContentIdentifier = noteID.uuidString
        return activity
    }
}

