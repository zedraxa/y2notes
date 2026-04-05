import SwiftUI

// MARK: - OpenSourceCreditsView

/// Acknowledgement view listing open-source projects and concepts
/// that inspired Y2Notes features.
///
/// No third-party libraries are bundled — this view credits the
/// *ideas and patterns* adopted from notable open-source projects.
struct OpenSourceCreditsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                introSection
                inspirationsSection
                patternsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Credits.Title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("General.Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        Section {
            Text(NSLocalizedString("Credits.Intro", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Inspirations

    private var inspirationsSection: some View {
        Section {
            ForEach(Inspiration.all) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(item.project)
                            .font(.body.weight(.semibold))
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(item.tint)
                    }
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Influenced: \(item.feature)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(NSLocalizedString("Credits.InspirationHeader", comment: ""))
        }
    }

    // MARK: - Patterns

    private var patternsSection: some View {
        Section {
            ForEach(Pattern.all) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(NSLocalizedString("Credits.PatternsHeader", comment: ""))
        } footer: {
            Text(NSLocalizedString("Credits.Footer", comment: ""))
                .font(.caption2)
        }
    }
}

// MARK: - Data Models

private struct Inspiration: Identifiable {
    let id: String
    let project: String
    let icon: String
    let tint: Color
    let description: String
    let feature: String

    static let all: [Inspiration] = [
        Inspiration(
            id: "obsidian",
            project: "Obsidian",
            icon: "diamond.fill",
            tint: .purple,
            description: "A knowledge base built on local Markdown files with a vibrant plugin ecosystem.",
            feature: "Writing Insights & Statistics dashboard"
        ),
        Inspiration(
            id: "vscode",
            project: "Visual Studio Code",
            icon: "chevron.left.forwardslash.chevron.right",
            tint: .blue,
            description: "Microsoft's extensible source-code editor, beloved for its Command Palette.",
            feature: "Command Palette (⌘K) quick-actions overlay"
        ),
        Inspiration(
            id: "excalidraw",
            project: "Excalidraw",
            icon: "pencil.and.scribble",
            tint: .orange,
            description: "Open-source virtual whiteboard for sketching hand-drawn-like diagrams.",
            feature: "Canvas interaction patterns and shape tool UX"
        ),
        Inspiration(
            id: "tldraw",
            project: "tldraw",
            icon: "scribble.variable",
            tint: .cyan,
            description: "A collaborative digital whiteboard with infinite canvas and real-time sync.",
            feature: "Floating toolbar capsule and selection handles"
        ),
        Inspiration(
            id: "joplin",
            project: "Joplin",
            icon: "note.text",
            tint: .teal,
            description: "Open-source note-taking and to-do app with sync and end-to-end encryption.",
            feature: "Notebook / section / note hierarchy and sync architecture"
        ),
        Inspiration(
            id: "anki",
            project: "Anki",
            icon: "rectangle.stack",
            tint: .green,
            description: "Intelligent flashcard program using the SM-2 spaced repetition algorithm.",
            feature: "SM-2 spaced repetition study system"
        ),
        Inspiration(
            id: "raycast",
            project: "Raycast",
            icon: "sparkle.magnifyingglass",
            tint: .pink,
            description: "Blazingly fast, totally extendable launcher for macOS.",
            feature: "Command Palette category layout and keyboard-first design"
        ),
        Inspiration(
            id: "iawriter",
            project: "iA Writer",
            icon: "textformat",
            tint: .gray,
            description: "Markdown editor focused on writing with beautiful typography and Focus Mode.",
            feature: "Focus Mode dimming, clean statistics display"
        ),
    ]
}

private struct Pattern: Identifiable {
    let id: String
    let name: String
    let detail: String

    static let all: [Pattern] = [
        Pattern(
            id: "mvvm",
            name: "MVVM with Environment Objects",
            detail: "Observable stores injected via SwiftUI environment — a pattern popularised by countless open-source SwiftUI samples."
        ),
        Pattern(
            id: "json-persistence",
            name: "JSON File Persistence",
            detail: "Simple Codable-based persistence to the app Documents directory, common in open-source iOS note apps."
        ),
        Pattern(
            id: "adaptive-perf",
            name: "Adaptive Performance Budgets",
            detail: "Device-capability tiering for effects intensity — a technique seen in open-source game engines and creative tools."
        ),
        Pattern(
            id: "command-pattern",
            name: "Command Pattern for Actions",
            detail: "Encapsulated actions with metadata, enabling the Command Palette — a fundamental pattern in VS Code and Sublime Text."
        ),
        Pattern(
            id: "contribution-graph",
            name: "Contribution Graph Heatmap",
            detail: "Daily activity heatmap modelled after GitHub's contribution graph, widely replicated in open-source dashboards."
        ),
    ]
}
