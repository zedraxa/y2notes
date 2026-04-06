import Foundation
import os

// MARK: - ServiceContainer

/// Dependency injection container that owns all service instances.
///
/// Created once at app launch and provides typed access to every service.
/// Both SwiftUI views (via adapters) and UIKit / Engine code (via protocols)
/// consume services from this container.
///
/// ## Usage
///
/// ```swift
/// let container = ServiceContainer()
///
/// // Engine code (no SwiftUI):
/// let notes = container.noteRepository.notes
///
/// // SwiftUI adapter:
/// let adapter = ObservableNoteStore(repository: container.noteRepository)
/// ```
final class ServiceContainer {

    private let logger = Logger(subsystem: "com.y2notes", category: "ServiceContainer")

    // MARK: - Core services (protocol-typed)

    /// Note, notebook, and section CRUD.
    let noteRepository: NoteRepository

    /// Theme selection and auto-scheduling.
    let themeProvider: ThemeProvider

    /// Active drawing tool, colour, width, and presets.
    let toolStateProvider: ToolStateProvider

    /// Premium ink presets and writing FX.
    let inkEffectProvider: InkEffectProvider

    /// App-wide preferences (page defaults, accessibility, etc.).
    let settingsProvider: SettingsProvider

    /// Google Drive sync engine.
    let syncProvider: SyncProvider

    // MARK: - Legacy stores (kept for gradual migration)
    //
    // Views that haven't been updated to use adapters yet can access
    // the concrete stores through these properties.  Over time, these
    // should be replaced by protocol-typed access above.

    let pdfStore: PDFStore
    let documentStore: DocumentStore
    let stickerStore: StickerStore
    let navigationStore: NavigationStore

    /// Legacy theme store — views still reference `ThemeStore` by type.
    let legacyThemeStore: ThemeStore

    /// Legacy ink effect store — views still reference `InkEffectStore` by type.
    let legacyInkEffectStore: InkEffectStore

    /// Legacy settings store — views still reference `AppSettingsStore` by type.
    let legacySettingsStore: AppSettingsStore

    // MARK: - Concrete accessors (for SwiftUI @StateObject injection)
    //
    // These expose the underlying concrete types so that Y2NotesApp can
    // inject them via @StateObject without force-casting from protocols.
    // Remove these once views are migrated to use the adapter types.

    let concreteNoteStore: NoteStore
    let concreteToolStore: DrawingToolStore
    let concreteSyncEngine: GoogleDriveSyncEngine

    // MARK: - Init

    /// Creates all services and wires cross-dependencies.
    init() {
        // --- Core services (new Combine-only implementations) ---

        let theme = CoreThemeService()
        themeProvider = theme

        let settings = CoreSettingsService()
        settingsProvider = settings

        let ink = CoreInkEffectService()
        inkEffectProvider = ink

        // --- Existing stores bridged to protocols ---

        let sqliteDriver = SQLitePersistenceDriver()
        let notes = NoteStore(persistenceDriver: sqliteDriver)
        noteRepository = notes
        concreteNoteStore = notes

        let tools = DrawingToolStore()
        toolStateProvider = tools
        concreteToolStore = tools

        let sync = GoogleDriveSyncEngine()
        sync.noteStore = notes
        syncProvider = sync
        concreteSyncEngine = sync

        // --- Legacy stores (no protocol yet) ---

        pdfStore = PDFStore()
        documentStore = DocumentStore()
        stickerStore = StickerStore()
        navigationStore = NavigationStore()
        legacyThemeStore = ThemeStore()
        legacyInkEffectStore = InkEffectStore()
        legacySettingsStore = AppSettingsStore()

        logger.info("ServiceContainer initialised with all services.")
    }
}
