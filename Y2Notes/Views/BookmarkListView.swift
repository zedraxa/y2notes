import SwiftUI

// MARK: - BookmarkListView

/// A sheet listing all bookmarked pages for a notebook, with navigation, editing, and colour tags.
struct BookmarkListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var navigationStore: NavigationStore
    let notebook: Notebook
    /// Flat-page navigation callback — caller resolves the anchor to a flat index.
    let onJump: (NavigationAnchor) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var rowsAppeared = false
    private let colorCycleFeedback = UISelectionFeedbackGenerator()
    private let jumpFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            let items = navigationStore.bookmarks(for: notebook.id)
            if items.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString("Bookmarks.NoBookmarks", comment: ""),
                    systemImage: "bookmark",
                    description: Text(NSLocalizedString("Bookmarks.EmptyHint", comment: ""))
                )
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, bookmark in
                        bookmarkRow(bookmark)
                            .opacity(rowsAppeared ? 1 : 0)
                            .offset(y: rowsAppeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.05),
                                value: rowsAppeared
                            )
                    }
                    .onDelete { offsets in
                        let allBookmarks = navigationStore.bookmarks(for: notebook.id)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            for offset in offsets {
                                navigationStore.removeBookmark(id: allBookmarks[offset].id)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear { rowsAppeared = true }
            }
        }
        .navigationTitle(NSLocalizedString("Bookmarks.Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func bookmarkRow(_ bookmark: PageBookmark) -> some View {
        Button {
            jumpFeedback.impactOccurred()
            onJump(bookmark.anchor)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // Colour tab
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: bookmark.colorTag))
                    .frame(width: 6, height: 36)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bookmark.colorTag)

                VStack(alignment: .leading, spacing: 2) {
                    let displayLabel = bookmark.label.isEmpty
                        ? resolvedLabel(for: bookmark)
                        : bookmark.label
                    Text(displayLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    let detail = resolvedDetail(for: bookmark)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bookmark.label.isEmpty ? resolvedLabel(for: bookmark) : bookmark.label)
        .accessibilityHint(NSLocalizedString("Bookmarks.NavigateHint", comment: ""))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                navigationStore.removeBookmark(id: bookmark.id)
            } label: {
                Label(NSLocalizedString("Bookmarks.Delete", comment: ""), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            // Cycle colour tag
            Button {
                colorCycleFeedback.selectionChanged()
                let allColors = BookmarkColor.allCases
                if let idx = allColors.firstIndex(of: bookmark.colorTag) {
                    let next = allColors[(idx + 1) % allColors.count]
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        navigationStore.updateBookmarkColor(id: bookmark.id, colorTag: next)
                    }
                }
            } label: {
                Label(NSLocalizedString("Bookmarks.ChangeColor", comment: ""), systemImage: "paintpalette")
            }
            .tint(.orange)
            .accessibilityLabel(NSLocalizedString("Bookmarks.ChangeColor", comment: ""))
            .accessibilityHint(NSLocalizedString("Bookmarks.ColorHint", comment: ""))
        }
    }

    // MARK: - Helpers

    private func resolvedLabel(for bookmark: PageBookmark) -> String {
        if let note = noteStore.notes.first(where: { $0.id == bookmark.anchor.noteID }) {
            let pageNum = bookmark.anchor.pageIndex + 1
            if note.title.isEmpty || note.title == "New Note" {
                return "Page \(pageNum)"
            }
            return "\(note.title) — p.\(pageNum)"
        }
        return "Page"
    }

    private func resolvedDetail(for bookmark: PageBookmark) -> String {
        if let note = noteStore.notes.first(where: { $0.id == bookmark.anchor.noteID }),
           let sID = note.sectionID,
           let sec = noteStore.sections.first(where: { $0.id == sID }) {
            return sec.name
        }
        return ""
    }

    private func color(for tag: BookmarkColor) -> Color {
        switch tag {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        }
    }
}

// MARK: - RecentLocationsView

/// A compact popover listing recently visited pages for quick return navigation.
struct RecentLocationsView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var navigationStore: NavigationStore
    let notebook: Notebook
    let onJump: (NavigationAnchor) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var rowsRevealed = false

    var body: some View {
        let recents = navigationStore.recentLocations(for: notebook.id)
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Bookmarks.RecentPages", comment: ""))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if recents.isEmpty {
                Text(NSLocalizedString("Bookmarks.NoHistory", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(recents.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                onJump(entry.anchor)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Page \(entry.flatPageIndex + 1)")
                                            .font(.subheadline)
                                        Text(entry.visitedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(rowsRevealed ? 1 : 0)
                            .offset(x: rowsRevealed ? 0 : -8)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.04),
                                value: rowsRevealed
                            )

                            if entry.id != recents.last?.id {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onAppear { rowsRevealed = true }
            }
        }
        .frame(minWidth: 220)
        .padding(.bottom, 8)
    }
}
