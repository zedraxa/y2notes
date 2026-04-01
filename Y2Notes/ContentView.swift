import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeStore: ThemeStore

    var body: some View {
        ShelfView()
            .preferredColorScheme(themeStore.definition.colorScheme)
    }
}
