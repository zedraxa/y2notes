import SwiftUI

// MARK: - SettingsView

/// App-wide settings screen with organised sections.
///
/// Every setting here has a real effect on app behaviour — no dead toggles.
/// Accessible from the sidebar gear icon in ShelfView.
struct SettingsView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var settingsStore: AppSettingsStore
    @EnvironmentObject var toolStore: DrawingToolStore
    @EnvironmentObject var noteStore: NoteStore

    @Environment(\.dismiss) private var dismiss

    @State private var showDiagnostics = false
    @State private var showResetConfirmation = false
    @State private var showWritingInsights = false
    @State private var showOpenSourceCredits = false
    @State private var settingsAppeared = false

    private let toggleFeedback = UIImpactFeedbackGenerator(style: .light)
    private let resetFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                documentDefaultsSection
                toolPreferencesSection
                effectsSection
                accessibilitySection
                insightsSection
                aboutSection
                resetSection
            }
            .onAppear { settingsAppeared = true }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: themeStore.autoScheduleEnabled)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: themeStore.selectedTheme)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .sheet(isPresented: $showWritingInsights) {
                WritingInsightsView()
            }
            .sheet(isPresented: $showOpenSourceCredits) {
                OpenSourceCreditsView()
            }
            .confirmationDialog(
                "Reset All Settings",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset to Defaults", role: .destructive) {
                    resetFeedback.notificationOccurred(.warning)
                    settingsStore.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset document defaults, tool preferences, and accessibility settings to their original values. Your notes and notebooks will not be affected.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: Binding(
                get: { themeStore.selectedTheme },
                set: { themeStore.select($0) }
            )) {
                ForEach(AppTheme.allCases) { theme in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.definition.canvasBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color(uiColor: .secondaryLabel).opacity(0.25), lineWidth: 0.5)
                            )
                            .frame(width: 24, height: 18)
                        Label(theme.displayName, systemImage: theme.systemImage)
                    }
                    .tag(theme)
                }
            }
            .accessibilityLabel("App theme")

            // Active theme indicator when scheduling is on.
            if themeStore.autoScheduleEnabled {
                HStack {
                    Label("Active", systemImage: "clock.arrow.2.circlepath")
                        .font(.subheadline)
                    Spacer()
                    Text(themeStore.effectiveTheme.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Auto-schedule active. Current theme is \(themeStore.effectiveTheme.displayName).")
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Colour palette preview.
            let def = themeStore.definition
            HStack(spacing: 6) {
                Text("Palette")
                Spacer()
                paletteCircle(def.canvasBackgroundColor, border: true)
                paletteCircle(def.primaryTextColor)
                paletteCircle(def.secondaryTextColor)
                paletteCircle(def.accentColor)
                paletteCircle(def.toolbarBackgroundColor, border: true)
                paletteCircle(def.surfaceSwiftUIColor, border: true)
            }
            .accessibilityHidden(true)
