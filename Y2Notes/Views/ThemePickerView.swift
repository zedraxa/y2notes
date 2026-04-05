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

                // Animated checkmark
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
                    .scaleEffect(isSelected ? 1.0 : 0.01)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
            if themeStore.autoScheduleEnabled {
                VStack(spacing: 8) {
                    scheduleRow(
                        icon: "sun.max.fill",
                        label: NSLocalizedString("ThemePicker.Day", comment: ""),
                        theme: $themeStore.dayTheme,
                        hourBinding: $themeStore.dayStartHour
                    )
                    scheduleRow(
                        icon: "moon.fill",
                        label: NSLocalizedString("ThemePicker.Night", comment: ""),
                        theme: $themeStore.nightTheme,
                        hourBinding: $themeStore.nightStartHour
                    )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: themeStore.autoScheduleEnabled)
    }

    private func scheduleRow(icon: String, label: String, theme: Binding<AppTheme>, hourBinding: Binding<Int>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)

            Spacer()

            Picker("", selection: theme) {
                ForEach(AppTheme.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("\(label) theme")

            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { h in
                    Text(formattedHour(h)).tag(h)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("\(label) start time")
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = hour
        let d = Calendar.current.date(from: comps) ?? Date()
        return fmt.string(from: d)
    }

    // MARK: - Category Section

    private func categorySection(_ category: ThemeCategory) -> some View {
        let themes = AppTheme.themes(in: category)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: category.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(category.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                    themeCard(theme)
                        .opacity(cardsAppeared ? 1 : 0)
                        .offset(y: cardsAppeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.8)
                            .delay(Double(index) * 0.04),
                            value: cardsAppeared
                        )
                }
            }
            .onAppear { cardsAppeared = true }
        }
    }

    // MARK: - Theme Card

    private func themeCard(_ theme: AppTheme) -> some View {
        let def = theme.definition
        let isSelected = (themeStore.autoScheduleEnabled ? themeStore.effectiveTheme : themeStore.selectedTheme) == theme

        return Button {
            selectionFeedback.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                themeStore.select(theme)
            }
        } label: {
            VStack(spacing: 0) {
                // Canvas preview
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(def.canvasBackgroundColor)
                        .frame(height: 68)

                    VStack(alignment: .leading, spacing: 4) {
                        // Simulated text lines
                        RoundedRectangle(cornerRadius: 2)
                            .fill(def.primaryTextColor)
                            .frame(width: 60, height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(def.secondaryTextColor)
                            .frame(width: 80, height: 4)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(def.accentColor)
                                .frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(def.accentColor.opacity(0.5))
                                .frame(width: 30, height: 4)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Toolbar preview strip
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(def.separatorSwiftUIColor)
                            .frame(width: 14, height: 3)
                    }
                    Spacer()
                    Circle()
                        .fill(def.accentColor)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(def.toolbarBackgroundColor)

                // Label
                HStack(spacing: 6) {
                    Image(systemName: theme.systemImage)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? def.accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isSelected)
                    Text(theme.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(uiColor: .label))

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(isSelected ? 1.0 : 0.01)
                        .opacity(isSelected ? 1 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(uiColor: .separator).opacity(0.3),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .black.opacity(0.05), radius: isSelected ? 4 : 2, y: 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(theme.isPremium)
        .opacity(theme.isPremium ? 0.5 : 1)
        .accessibilityLabel("\(theme.displayName) theme. \(theme.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
