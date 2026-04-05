import SwiftUI

// MARK: - ThemePickerView

/// Modal sheet for selecting the app-wide theme.
/// Presented from the NoteListView toolbar.
struct ThemePickerView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppTheme.allCases) { theme in
                        themeRow(theme)
                    }
                } footer: {
                    Text("The canvas background updates immediately. App chrome follows the selected colour scheme.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Row builder

    private func themeRow(_ theme: AppTheme) -> some View {
        let isSelected = themeStore.selectedTheme == theme
        return Button {
            selectionFeedback.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                themeStore.select(theme)
            }
        } label: {
            HStack(spacing: 14) {
                // Colour swatch — larger for easy preview
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.definition.canvasBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.25),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                    .frame(width: 48, height: 36)
                    .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 4, y: 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: theme.systemImage)
                            .font(.body)
                            .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                            .animation(.easeInOut(duration: 0.2), value: isSelected)
                        Text(theme.displayName)
                            .foregroundStyle(Color(uiColor: .label))
                    }
                    if theme.isPremium {
                        Text("Premium")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(theme.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Animated checkmark
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
                    .scaleEffect(isSelected ? 1.0 : 0.01)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(theme.isPremium)
        .opacity(theme.isPremium ? 0.5 : 1)
    }
}
