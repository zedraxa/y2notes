import SwiftUI

// MARK: - ThemePickerView

/// Modal sheet for selecting the app-wide theme.
/// Presented from the NoteListView toolbar.
struct ThemePickerView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var cardsAppeared = false

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let toggleFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: Schedule toggle
                    scheduleSection

                    // MARK: Theme grid by category
                    ForEach(ThemeCategory.allCases) { category in
                        categorySection(category)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle(NSLocalizedString("ThemePicker.Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { cardsAppeared = true }
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
    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(themeStore.autoScheduleEnabled ? Color.accentColor : .secondary)
                Text(NSLocalizedString("ThemePicker.AutoSchedule", comment: ""))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: $themeStore.autoScheduleEnabled)
                    .labelsHidden()
                    .onChange(of: themeStore.autoScheduleEnabled) { _, _ in
                        toggleFeedback.impactOccurred()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )

