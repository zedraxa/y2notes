import Foundation

// MARK: - QuickAction

/// A single executable action surfaced in the Command Palette.
///
/// Inspired by VS Code's Command Palette (⌘⇧P), Sublime Text's
/// Goto Anything, and Raycast's extensible launcher.
struct QuickAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let category: Category
    let action: () -> Void

    /// Grouping categories displayed as section headers.
    enum Category: String, CaseIterable, Identifiable {
        case navigation  = "Navigation"
        case create      = "Create"
        case tool        = "Tools"
        case appearance  = "Appearance"
        case effect      = "Effects"
        case study       = "Study"

        var id: String { rawValue }
    }
}

// MARK: - QuickActionRegistry

/// Builds the canonical list of quick actions from current app state.
///
/// Each action closes the palette and performs a side-effect through
/// the supplied closures. The registry is rebuilt every time the
/// palette opens so that dynamic state (e.g. current theme, effect)
/// is always fresh.
enum QuickActionRegistry {

    /// Assemble all available actions.
    ///
    /// - Parameters:
    ///   - onNewNote: Create a new note.
    ///   - onNewNotebook: Create a new notebook.
    ///   - onOpenSettings: Present the settings sheet.
    ///   - onOpenSearch: Present universal search.
    ///   - onOpenStudy: Navigate to the study section.
    ///   - onToggleFocusMode: Toggle focus mode.
    ///   - onToggleMagicMode: Toggle magic mode.
    ///   - onToggleStudyMode: Toggle study mode.
    ///   - onCycleTheme: Advance to the next theme.
    ///   - onShowInsights: Open writing insights.
    static func actions(
        onNewNote: @escaping () -> Void,
        onNewNotebook: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenSearch: @escaping () -> Void,
        onOpenStudy: @escaping () -> Void,
        onToggleFocusMode: @escaping () -> Void,
        onToggleMagicMode: @escaping () -> Void,
        onToggleStudyMode: @escaping () -> Void,
        onCycleTheme: @escaping () -> Void,
        onShowInsights: @escaping () -> Void
    ) -> [QuickAction] {
        [
            // Navigation
            QuickAction(
                id: "nav.search",
                title: "Search Notes",
                subtitle: "Full-text search across all notes",
                systemImage: "magnifyingglass",
                category: .navigation,
                action: onOpenSearch
            ),
            QuickAction(
                id: "nav.settings",
                title: "Open Settings",
                subtitle: "Appearance, tools, accessibility",
                systemImage: "gear",
                category: .navigation,
                action: onOpenSettings
            ),
            QuickAction(
                id: "nav.insights",
                title: "Writing Insights",
                subtitle: "View writing statistics and streaks",
                systemImage: "chart.bar.xaxis",
                category: .navigation,
                action: onShowInsights
            ),

            // Create
            QuickAction(
                id: "create.note",
                title: "New Note",
                subtitle: "Create a blank note",
                systemImage: "square.and.pencil",
                category: .create,
                action: onNewNote
            ),
            QuickAction(
                id: "create.notebook",
                title: "New Notebook",
                subtitle: "Create a new notebook",
                systemImage: "book.closed",
                category: .create,
                action: onNewNotebook
            ),

            // Tools
            QuickAction(
                id: "tool.focus",
                title: "Toggle Focus Mode",
                subtitle: "Dim distractions and enter focus",
                systemImage: "moon.fill",
                category: .tool,
                action: onToggleFocusMode
            ),

            // Effects
            QuickAction(
                id: "effect.magic",
                title: "Toggle Magic Mode",
                subtitle: "Writing particles and keyword glow",
                systemImage: "wand.and.stars",
                category: .effect,
                action: onToggleMagicMode
            ),

            // Appearance
            QuickAction(
                id: "appearance.theme",
                title: "Cycle Theme",
                subtitle: "Switch to the next app theme",
                systemImage: "paintpalette",
                category: .appearance,
                action: onCycleTheme
            ),

            // Study
            QuickAction(
                id: "study.sets",
                title: "Study Sets",
                subtitle: "Open flashcard study sets",
                systemImage: "graduationcap",
                category: .study,
                action: onOpenStudy
            ),
            QuickAction(
                id: "study.mode",
                title: "Toggle Study Mode",
                subtitle: "Heading glow and checklist pulse",
                systemImage: "graduationcap.fill",
                category: .study,
                action: onToggleStudyMode
            ),
        ]
    }
}
