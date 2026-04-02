import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var settingsStore: AppSettingsStore

    var body: some View {
        ZStack {
            ShelfView()
                .preferredColorScheme(themeStore.definition.colorScheme)
                .respectsReduceMotion()

            if !settingsStore.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(
            settingsStore.reduceMotion ? nil : .easeInOut(duration: 0.35),
            value: settingsStore.hasCompletedOnboarding
        )
    }
}
