import SwiftUI

/// Notebook-style tab bar that sits between the navigation bar and the canvas.
///
/// **Visual design**: A thin 36pt strip with soft, rounded tab cards tinted by
/// each tab's accent colour. The active tab appears "pulled forward" (slightly
/// taller, opaque background, semibold text, close button visible). Inactive
/// tabs are shorter, translucent, and calmer — no visible close buttons.
///
/// **Interactions**:
/// - Tap to switch tabs (spring animation)
/// - Long-press + drag to reorder
/// - Swipe-left or close button to dismiss a tab
/// - Context menu: Close / Close Other Tabs
/// - "+" button to open new content from the shelf
///
/// **Anti-browser**: no sharp rectangular tabs, no tab count badge, no ×
/// buttons on inactive tabs. The colour accent stripe mirrors the notebook
/// identity bar used in NotebookReaderView.
struct NotebookTabBar: View {
    @Environment(TabWorkspaceStore.self) private var workspace
    @EnvironmentObject var toolStore: DrawingToolStore
    var onNewTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabCard(tab, index: index)
                }
                newTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .background(
            Color(uiColor: .systemGroupedBackground)
                .opacity(0.6)
                .overlay(alignment: .bottom) {
                    // Subtle gradient fade into the canvas area
                    LinearGradient(
                        colors: [.clear, Color(uiColor: .systemGroupedBackground).opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 4)
                    .offset(y: 4)
                }
        )
    }

    // MARK: - Tab Card

    @ViewBuilder
    private func tabCard(_ tab: TabSession, index: Int) -> some View {
        let isActive = workspace.activeTabID == tab.id
        let accent = tabAccentColor(tab)

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                workspace.switchTo(tab.id)
            }
        } label: {
            HStack(spacing: 5) {
                // Accent stripe — mirrors the notebook identity bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3, height: 16)

                // Icon for content type
                Image(systemName: tab.content.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? accent : Color(uiColor: .tertiaryLabel))
                    .overlay(alignment: .topTrailing) {
                        // Recording badge — red dot when recording is active on this tab
                        if isActive && toolStore.isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -3)
                        }
                    }

                // Title
                Text(tab.displayName)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 120)
                    .foregroundStyle(
                        isActive ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel)
                    )

                // Close button — only visible on the active tab
                if isActive {
                    closeButton(for: tab)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tabBackground(isActive: isActive, accent: accent))
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
        .dropDestination(for: String.self) { items, _ in
            guard let sourceStr = items.first,
                  let source = Int(sourceStr),
                  source != index else { return false }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                workspace.reorderTab(from: source, to: index)
            }
            return true
        }
        .contextMenu {
            Button("Close Tab", systemImage: "xmark") {
                withAnimation { workspace.closeTab(tab.id) }
            }
            Button("Close Other Tabs", systemImage: "xmark.square") {
                withAnimation { workspace.closeOtherTabs(except: tab.id) }
            }
        }
    }

    // MARK: - Close Button

    private func closeButton(for tab: TabSession) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                workspace.closeTab(tab.id)
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
        .accessibilityLabel("Open new tab")
    }

    // MARK: - Helpers

    private func tabAccentColor(_ tab: TabSession) -> Color {
        guard tab.accentColor.count >= 3 else { return .accentColor }
        return Color(
            red: tab.accentColor[0],
            green: tab.accentColor[1],
            blue: tab.accentColor[2]
        )
    }

    @ViewBuilder
    private func tabBackground(isActive: Bool, accent: Color) -> some View {
        if isActive {
            // Active: opaque with very subtle accent tint
            Color(uiColor: .systemBackground)
                .overlay(accent.opacity(0.05))
        } else {
            Color(uiColor: .secondarySystemBackground)
                .opacity(0.5)
        }
    }
}
