import Foundation

// MARK: - QuickAction

public struct QuickAction: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let category: Category
    public let action: () -> Void

    public enum Category: String, CaseIterable, Identifiable {
        case navigation  = "Navigation"
        case create      = "Create"
        case tool        = "Tools"
        case appearance  = "Appearance"
        case effect      = "Effects"
        case study       = "Study"

        public var id: String { rawValue }
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        category: Category,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.action = action
    }
}

// MARK: - QuickActionRegistry

public enum QuickActionRegistry {

    public static func actions(
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
            QuickAction(
                id: "tool.focus",
                title: "Toggle Focus Mode",
                subtitle: "Dim distractions and enter focus",
                systemImage: "moon.fill",
                category: .tool,
                action: onToggleFocusMode
            ),
            QuickAction(
                id: "effect.magic",
                title: "Toggle Magic Mode",
                subtitle: "Writing particles and keyword glow",
                systemImage: "wand.and.stars",
                category: .effect,
                action: onToggleMagicMode
            ),
            QuickAction(
                id: "appearance.theme",
                title: "Cycle Theme",
                subtitle: "Switch to the next app theme",
                systemImage: "paintpalette",
                category: .appearance,
                action: onCycleTheme
            ),
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
