import SwiftUI

/// Notebook-style tab bar that sits between the navigation bar and the canvas.
///
/// **Visual design**: Each tab is a thin rounded-top card with the notebook's
/// cover colour as an accent stripe. The active tab appears "pulled forward"
/// (slightly taller, opaque background). Inactive tabs are shorter with a
/// translucent background. This avoids the browser-tab look by using soft
/// rounded shapes and notebook accent colours instead of sharp rectangles.
///
/// **Interactions**:
/// - Tap to switch tabs
/// - Long-press + drag to reorder
/// - Swipe-left or close button to dismiss a tab
/// - "+" button to open a new notebook from the shelf
struct NotebookTabBar: View {
    @Environment(NotebookTabSession.self) private var tabSession
    var onNewTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(tabSession.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabCard(tab, index: index)
                }

                // New tab button
                newTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .background(Color(uiColor: .systemGroupedBackground).opacity(0.6))
    }

    // MARK: - Tab Card

    @ViewBuilder
    private func tabCard(_ tab: NotebookTab, index: Int) -> some View {
        let isActive = tabSession.activeTabID == tab.id
        let accentColor = tabAccentColor(tab)

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                tabSession.activeTabID = tab.id
            }
        } label: {
            HStack(spacing: 5) {
                // Notebook accent stripe
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3, height: 16)

                Text(tab.displayName)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))

                // Close button (only on active tab to keep it calm)
                if isActive {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            tabSession.closeTab(id: tab.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .frame(width: 16, height: 16)
                            .background(Color(uiColor: .systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? AnyShapeStyle(Color(uiColor: .systemBackground))
                    : AnyShapeStyle(Color(uiColor: .secondarySystemBackground).opacity(0.5))
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 8,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 8
                )
            )
            .shadow(color: isActive ? .black.opacity(0.05) : .clear, radius: 2, y: -1)
        }
        .buttonStyle(.plain)
        .draggable(String(index)) {
            Text(tab.displayName)
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            Button("Close Tab", systemImage: "xmark") {
                withAnimation { tabSession.closeTab(id: tab.id) }
            }
            Button("Close Other Tabs", systemImage: "xmark.square") {
                withAnimation {
                    let otherIDs = tabSession.tabs.filter { $0.id != tab.id }.map(\.id)
                    for id in otherIDs { tabSession.closeTab(id: id) }
                }
            }
        }
    }

    // MARK: - New Tab Button

    private var newTabButton: some View {
        Button(action: onNewTab) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open notebook")
    }

    // MARK: - Helpers

    private func tabAccentColor(_ tab: NotebookTab) -> Color {
        guard tab.coverColor.count >= 3 else { return .accentColor }
        return Color(
            red: tab.coverColor[0],
            green: tab.coverColor[1],
            blue: tab.coverColor[2]
        )
    }
}
