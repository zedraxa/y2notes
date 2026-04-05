import SwiftUI

// MARK: - DiagnosticsView

/// Recovery, debug, and support surface.
///
/// Shows storage statistics, theme contrast validation across all themes,
/// data integrity checks, and provides an export-diagnostics action.
struct DiagnosticsView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore: PDFStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var settingsStore: AppSettingsStore

    @Environment(\.dismiss) private var dismiss

    @State private var diagnosticText: String = ""
    @State private var showShareSheet = false
    @State private var showOnboardingReset = false

    var body: some View {
        NavigationStack {
            List {
                storageSection
                contrastValidationSection
                dataIntegritySection
                actionsSection
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Re-show Onboarding",
                isPresented: $showOnboardingReset,
                titleVisibility: .visible
            ) {
                Button("Reset Onboarding") {
                    settingsStore.hasCompletedOnboarding = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The onboarding flow will appear again the next time you open Y2Notes.")
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section("Storage") {
            row("Notes", value: "\(noteStore.notes.count)")
            row("Notebooks", value: "\(noteStore.notebooks.count)")
            row("Sections", value: "\(noteStore.sections.count)")
            row("Study Sets", value: "\(noteStore.studySets.count)")
            row("Study Cards", value: "\(noteStore.studyCards.count)")
            row("PDF Documents", value: "\(pdfStore.records.count)")
            row("Notes Data", value: formattedSize(for: "y2notes_notes.json"))
            row("Notebooks Data", value: formattedSize(for: "y2notes_notebooks.json"))
        }
    }

    // MARK: - Contrast Validation

    private var contrastValidationSection: some View {
        Section {
            ForEach(AppTheme.allCases) { theme in
                let def = theme.definition
                HStack {
                    Image(systemName: theme.systemImage)
                        .frame(width: 24)
                    Text(theme.displayName)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        contrastBadge(
                            label: "Primary",
                            ratio: def.primaryTextContrastRatio,
                            passes: ContrastChecker.meetsAA(foreground: def.primaryText, background: def.canvasBackground)
                        )
                        contrastBadge(
                            label: "Secondary",
                            ratio: def.secondaryTextContrastRatio,
                            passes: ContrastChecker.meetsAA(foreground: def.secondaryText, background: def.canvasBackground, isLargeText: true)
                        )
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(theme.displayName) theme. Primary contrast ratio \(String(format: "%.1f", def.primaryTextContrastRatio)) to 1. \(def.meetsWCAGAA ? "Passes" : "Fails") WCAG AA."
                )
            }
        } header: {
            Text("Theme Contrast Validation")
        } footer: {
            Text("WCAG 2.1 AA requires ≥ 4.5:1 for normal text and ≥ 3:1 for large text.")
        }
    }

    // MARK: - Data Integrity

    private var dataIntegritySection: some View {
        Section("Data Integrity") {
            let orphanedNotes = noteStore.notes.filter { note in
                if let nbID = note.notebookID {
                    return !noteStore.notebooks.contains { $0.id == nbID }
                }
                return false
            }

            row("Save State", value: saveStateText)
            row("Orphaned Notes", value: "\(orphanedNotes.count)")

            if !orphanedNotes.isEmpty {
                Text("Some notes reference notebooks that no longer exist. These notes are still accessible under All Notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                diagnosticText = buildDiagnosticReport()
                showShareSheet = true
            } label: {
                Label("Copy Diagnostic Report", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Copy diagnostic report to clipboard")

            Button {
                showOnboardingReset = true
            } label: {
                Label("Re-show Onboarding", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset onboarding so it shows again on next launch")

            Button {
                noteStore.save()
            } label: {
                Label("Force Save Now", systemImage: "arrow.down.doc")
            }
            .accessibilityLabel("Force save all data to disk immediately")
        }
    }

    // MARK: - Helpers

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(title): \(value)")
    }

    private func contrastBadge(label: String, ratio: Double, passes: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f:1", ratio))
                .font(.caption2.monospacedDigit())
            Image(systemName: passes ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(passes ? .green : .red)
        }
    }

    private var saveStateText: String {
        switch noteStore.saveState {
        case .idle:   return "Idle"
        case .saving: return "Saving…"
        case .saved:  return "Saved"
        case .error:  return "Error"
        }
    }

    private func formattedSize(for filename: String) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = docs?.appendingPathComponent(filename),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return "—"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func buildDiagnosticReport() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var lines: [String] = []
        lines.append("Y2Notes Diagnostic Report")
        lines.append("========================")
        lines.append("Version: \(version) (\(build))")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Device: \(UIDevice.current.model)")
        lines.append("System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        lines.append("")
        lines.append("Storage:")
        lines.append("  Notes: \(noteStore.notes.count)")
        lines.append("  Notebooks: \(noteStore.notebooks.count)")
        lines.append("  Sections: \(noteStore.sections.count)")
        lines.append("  Study Sets: \(noteStore.studySets.count)")
        lines.append("  Study Cards: \(noteStore.studyCards.count)")
        lines.append("  PDFs: \(pdfStore.records.count)")
        lines.append("")
        lines.append("Theme: \(themeStore.selectedTheme.displayName)")
        if themeStore.autoScheduleEnabled {
            lines.append("Auto-Schedule: ON (Day: \(themeStore.dayTheme.displayName), Night: \(themeStore.nightTheme.displayName))")
            lines.append("Effective Theme: \(themeStore.effectiveTheme.displayName)")
        }
        lines.append("Save State: \(saveStateText)")
        lines.append("")
        lines.append("Contrast Validation:")
        for theme in AppTheme.allCases {
            let def = theme.definition
            let status = def.meetsWCAGAA ? "PASS" : "FAIL"
            lines.append("  \(theme.displayName): Primary \(String(format: "%.1f", def.primaryTextContrastRatio)):1, Secondary \(String(format: "%.1f", def.secondaryTextContrastRatio)):1 [\(status)]")
        }

        let report = lines.joined(separator: "\n")
        UIPasteboard.general.string = report
        return report
    }
}
