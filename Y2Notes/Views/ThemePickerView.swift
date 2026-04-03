import SwiftUI

// MARK: - ThemePickerView

/// Modal sheet for selecting the app-wide theme.
/// Presented from the NoteListView toolbar.
struct ThemePickerView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

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
        Button {
            themeStore.select(theme)
        } label: {
            HStack(spacing: 14) {
                // Colour swatch preview
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.definition.canvasBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(uiColor: .secondaryLabel).opacity(0.25), lineWidth: 0.5)
                    )
                    .frame(width: 36, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: theme.systemImage)
                            .font(.body)
                            .foregroundStyle(themeStore.selectedTheme == theme ? Color.accentColor : Color(uiColor: .secondaryLabel))
                        Text(theme.displayName)
                            .foregroundStyle(Color(uiColor: .label))
                    }
                    if theme.isPremium {
                        Text("Premium")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if themeStore.selectedTheme == theme {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(theme.isPremium)
        .opacity(theme.isPremium ? 0.5 : 1)
    }
}
