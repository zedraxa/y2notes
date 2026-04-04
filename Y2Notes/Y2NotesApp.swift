import SwiftUI

@main
struct Y2NotesApp: App {
    @StateObject private var noteStore     = NoteStore()
    @StateObject private var themeStore    = ThemeStore()
    @StateObject private var toolStore     = DrawingToolStore()
    @StateObject private var pdfStore      = PDFStore()
    @StateObject private var inkStore      = InkEffectStore()
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var syncEngine    = GoogleDriveSyncEngine()
    @StateObject private var documentStore = DocumentStore()
    @StateObject private var stickerStore  = StickerStore()
    @StateObject private var navigationStore = NavigationStore()
    @State private var tabSession          = TabWorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteStore)
                .environmentObject(themeStore)
                .environmentObject(toolStore)
                .environmentObject(pdfStore)
                .environmentObject(inkStore)
                .environmentObject(settingsStore)
                .environmentObject(syncEngine)
                .environmentObject(documentStore)
                .environmentObject(stickerStore)
                .environmentObject(navigationStore)
                .environment(tabSession)
                .onAppear {
                    syncEngine.noteStore = noteStore
                }
        }
    }
}
