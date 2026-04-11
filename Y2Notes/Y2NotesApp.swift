import SwiftUI

@main
struct Y2NotesApp: App {

    /// Single source of truth for all services.  Created once and owned for
    /// the lifetime of the app.  Engine / UIKit code accesses services via
    /// protocol-typed properties; SwiftUI views receive concrete stores
    /// through `.environmentObject()` until the full adapter migration.
    private let container: ServiceContainer

    // Concrete stores pulled from the container for SwiftUI injection.
    // These will eventually be replaced by ObservableXxxStore adapters.
    @StateObject private var noteStore: NoteStore
    @StateObject private var toolStore: DrawingToolStore
    @StateObject private var syncEngine: GoogleDriveSyncEngine

    // Stores not yet managed by ServiceContainer keep direct init.
    @State private var tabSession = TabWorkspaceStore()

    init() {
        // Capture as a local so the StateObject @escaping autoclosures do not
        // capture mutating `self` (Swift 6 strict-concurrency requirement).
        let container = ServiceContainer()
        self.container = container
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

                // Multi-window state restoration: advertise the current note
                // being edited so that each window can be restored independently.
                .userActivity(NSUserActivity.editNoteActivityType) { activity in
                    if let noteID = noteStore.activeNoteID {
                        activity.userInfo = ["noteID": noteID.uuidString]
                        activity.isEligibleForHandoff = true
                        activity.targetContentIdentifier = noteID.uuidString
                        activity.needsSave = true
                    }
                }
                .onContinueUserActivity(NSUserActivity.editNoteActivityType) { activity in
                    guard let noteIDString = activity.userInfo?["noteID"] as? String,
                          let noteID = UUID(uuidString: noteIDString) else { return }
                    // Navigate to the note in this window's tab session.
                    container.navigationStore.navigateToNote(id: noteID)
                }
                .onAppear {
                    // Phase 5: Record app launch completion
                    Task { @MainActor in
                        PerformanceMonitor.shared.recordAppLaunched()
                        PerformanceMonitor.shared.recordSessionStart()
                    }
                }
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

