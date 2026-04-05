import SwiftUI

// MARK: - Widget Picker

/// A compact picker sheet that lets the user choose which type of widget to
/// place on the current page.  Mirrors the visual weight of `StickerLibraryView`
/// — a short grid of labelled icons, no configuration required before placement.
struct WidgetPickerView: View {
    /// Called with the chosen `WidgetKind` when the user taps one.
    var onSelect: (WidgetKind) -> Void

    /// Dismisses the sheet after selection.
    @Environment(\.dismiss) private var dismiss

    // Layout: 2-column grid
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(WidgetKind.allCases, id: \.self) { kind in
                        widgetCard(for: kind)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func widgetCard(for kind: WidgetKind) -> some View {
        Button {
            onSelect(kind)
            dismiss()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor(for: kind).opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: iconName(for: kind))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accentColor(for: kind))
                }

                VStack(spacing: 3) {
                    Text(displayName(for: kind))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .label))

                    Text(subtitle(for: kind))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor(for: kind).opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accentColor(for: kind).opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayName(for: kind))
        .accessibilityHint(subtitle(for: kind))
    }

    // MARK: - Metadata

    private func iconName(for kind: WidgetKind) -> String {
        switch kind {
        case .checklist:        return "checklist.checked"
        case .quickTable:       return "tablecells.fill"
        case .calloutBox:       return "exclamationmark.bubble.fill"
        case .referenceCard:    return "doc.text.magnifyingglass"
        case .stickyNote:       return "note.text"
        case .flashcard:        return "rectangle.on.rectangle.angled.fill"
        case .progressTracker:  return "chart.bar.fill"
        }
    }

    private func displayName(for kind: WidgetKind) -> String {
        switch kind {
        case .checklist:        return "Checklist"
        case .quickTable:       return "Quick Table"
        case .calloutBox:       return "Callout Box"
        case .referenceCard:    return "Reference Card"
        case .stickyNote:       return "Sticky Note"
        case .flashcard:        return "Flashcard"
        case .progressTracker:  return "Progress"
        }
    }

    private func subtitle(for kind: WidgetKind) -> String {
        switch kind {
        case .checklist:        return "Track tasks & steps"
        case .quickTable:       return "Rows & columns"
        case .calloutBox:       return "Highlight key info"
        case .referenceCard:    return "Glanceable reference"
        case .stickyNote:       return "Quick coloured note"
        case .flashcard:        return "Front & back study card"
        case .progressTracker:  return "Track a goal"
        }
    }

    private func accentColor(for kind: WidgetKind) -> Color {
        switch kind {
        case .checklist:        return .green
        case .quickTable:       return .blue
        case .calloutBox:       return .orange
        case .referenceCard:    return .purple
        case .stickyNote:       return .yellow
        case .flashcard:        return .teal
        case .progressTracker:  return .indigo
        }
    }
}
