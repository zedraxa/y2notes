import SwiftUI

// MARK: - CommandPaletteView

/// Searchable overlay for quick navigation and actions.
///
/// Inspired by:
/// - **VS Code** — Command Palette (⌘⇧P) for instant access to any action
/// - **Sublime Text** — Goto Anything for fuzzy file/symbol search
/// - **Raycast** — Extensible launcher with categorised results
///
/// Present as a `.sheet` or `.overlay` from any top-level view.
struct CommandPaletteView: View {

    /// All available actions (rebuilt each time the palette opens).
    let actions: [QuickAction]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .background(Color(.systemBackground))
            .navigationTitle(NSLocalizedString("CommandPalette.Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("General.Cancel", comment: "")) { dismiss() }
                }
            }
        }
        .onAppear { isSearchFocused = true }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                NSLocalizedString("CommandPalette.Placeholder", comment: ""),
                text: $query
            )
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .submitLabel(.done)
            .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("CommandPalette.ClearSearch", comment: ""))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var filteredActions: [QuickAction] {
        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter {
            $0.title.lowercased().contains(lowered)
            || $0.subtitle.lowercased().contains(lowered)
            || $0.category.rawValue.lowercased().contains(lowered)
        }
    }

    private var groupedActions: [(QuickAction.Category, [QuickAction])] {
        let grouped = Dictionary(grouping: filteredActions, by: \.category)
        return QuickAction.Category.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }

    private var resultsList: some View {
        Group {
            if filteredActions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groupedActions, id: \.0) { category, items in
                        Section(category.rawValue) {
                            ForEach(items) { action in
                                actionRow(action)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func actionRow(_ action: QuickAction) -> some View {
        Button {
            dismiss()
            // Small delay lets the sheet dismiss before the action fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                action.action()
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.body)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: action.systemImage)
                    .foregroundStyle(.accent)
            }
        }
        .accessibilityLabel("\(action.title). \(action.subtitle)")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("CommandPalette.NoResults", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}
