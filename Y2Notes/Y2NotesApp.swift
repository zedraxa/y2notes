import SwiftUI

@main
struct Y2NotesApp: App {
    @StateObject private var noteStore   = NoteStore()
    @StateObject private var themeStore  = ThemeStore()
    @StateObject private var toolStore   = DrawingToolStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteStore)
                .environmentObject(themeStore)
                .environmentObject(toolStore)
        }
    }
}
