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

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                documentDefaultsSection
                toolPreferencesSection
                accessibilitySection
                insightsSection
                aboutSection
            }
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
                    Label(theme.displayName, systemImage: theme.systemImage)
                        .tag(theme)
                }
            }
            .accessibilityLabel("App theme")

            // Contrast badge for current theme
            let def = themeStore.definition
            HStack {
                Text("Contrast")
                Spacer()
                if def.meetsWCAGAA {
                    Label("AA Pass", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Low Contrast", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityLabel(
                def.meetsWCAGAA
                    ? "Current theme passes WCAG double-A contrast requirements"
                    : "Current theme has low contrast. Consider choosing a different theme."
            )
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Document Defaults

    private var documentDefaultsSection: some View {
        Section {
            Picker("Page Type", selection: $settingsStore.defaultPageType) {
                ForEach(PageType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImage).tag(type)
                }
            }
            .accessibilityLabel("Default page type for new notebooks")

            Picker("Page Size", selection: $settingsStore.defaultPageSize) {
                ForEach(PageSize.allCases) { size in
                    Text("\(size.displayName) — \(size.subtitle)").tag(size)
                }
            }
            .accessibilityLabel("Default page size for new notebooks")

            Picker("Orientation", selection: $settingsStore.defaultOrientation) {
                ForEach(PageOrientation.allCases) { orientation in
                    Label(orientation.displayName, systemImage: orientation.systemImage).tag(orientation)
                }
            }
            .accessibilityLabel("Default page orientation for new notebooks")

            Picker("Paper Material", selection: $settingsStore.defaultPaperMaterial) {
                ForEach(PaperMaterial.allCases) { material in
                    Text(material.displayName).tag(material)
                }
            }
            .accessibilityLabel("Default paper material for new notebooks")
        } header: {
            Text("Document Defaults")
        } footer: {
            Text("These defaults apply when creating new notebooks. Existing notebooks are not affected.")
        }
    }

    // MARK: - Tool Preferences

    private var toolPreferencesSection: some View {
        Section {
            Picker("Active Tool", selection: $toolStore.activeTool) {
                ForEach(DrawingTool.allCases) { tool in
                    Label(tool.displayName, systemImage: tool.systemImage).tag(tool)
                }
            }
            .accessibilityLabel("Active drawing tool")

            HStack {
                Text("Active Stroke Width")
                Spacer()
                Text(String(format: "%.1f pt", toolStore.activeWidth))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $toolStore.activeWidth, in: 1...20, step: 0.5) {
                Text("Active Stroke Width")
            }
            .accessibilityLabel("Active stroke width, \(String(format: "%.1f", toolStore.activeWidth)) points")

            Toggle(isOn: $settingsStore.pencilOnlyDrawing) {
                Label("Pencil-Only Drawing", systemImage: "pencil.tip")
            }
            .accessibilityLabel("Pencil-only drawing. When enabled, finger input pans and zooms instead of drawing.")
        } header: {
            Text("Tool Preferences")
        }
    }

    // MARK: - Accessibility

    private var accessibilitySection: some View {
        Section {
            Toggle(isOn: $settingsStore.reduceMotion) {
                Label("Reduce Motion", systemImage: "figure.walk.motion")
            }
            .accessibilityLabel("Reduce motion. Disables animations throughout the app.")

            Toggle(isOn: $settingsStore.highContrastMode) {
                Label("Increase Contrast", systemImage: "circle.lefthalf.filled")
            }
            .accessibilityLabel("Increase contrast mode for improved visibility.")

            HStack {
                Text("Autosave Interval")
                Spacer()
                Text("\(Int(settingsStore.autosaveInterval))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settingsStore.autosaveInterval, in: 10...300, step: 10) {
                Text("Autosave Interval")
            }
            .accessibilityLabel("Autosave interval, \(Int(settingsStore.autosaveInterval)) seconds")
        } header: {
            Text("Accessibility")
        } footer: {
            Text("Reduce Motion suppresses transitions. Increase Contrast enhances borders and text weight.")
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        Section {
            Button {
                showWritingInsights = true
            } label: {
                Label("Writing Insights", systemImage: "chart.bar.xaxis")
            }
            .accessibilityLabel("Open writing insights dashboard")
        } header: {
            Text("Insights")
        } footer: {
            Text("View writing statistics, streaks, and activity inspired by open-source analytics tools.")
        }
    }

    // MARK: - About & Support

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("App version \(appVersion)")

            Button {
                showDiagnostics = true
            } label: {
                Label("Diagnostics & Support", systemImage: "wrench.and.screwdriver")
            }
            .accessibilityLabel("Open diagnostics and support")

            Button {
                showOpenSourceCredits = true
            } label: {
                Label("Open Source Inspirations", systemImage: "heart.text.square")
            }
            .accessibilityLabel("View open source inspirations and credits")

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset all settings to defaults")
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
