import SwiftUI

/// Sheet-style picker that lets users browse ink families and select a premium
/// `InkPreset` (or clear the active preset to return to the base tool system).
///
/// Opened from `DrawingToolbarView` via the ink-effects button.
struct InkEffectPickerView: View {

    @ObservedObject var inkStore: InkEffectStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFamily: InkFamily = .standard

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !inkStore.isEffectsSupported {
                    compatibilityBanner
                }
                fxToggleRow
                Divider()
                familySelector
                Divider()
                presetGrid
            }
            .navigationTitle("Ink Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("None") {
                        inkStore.clearPreset()
                        dismiss()
                    }
                    .foregroundStyle(inkStore.activePreset == nil ? .primary : .secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Compatibility Banner

    private var compatibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.callout)
            Text("Writing effects are not available on this device.")
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemYellow).opacity(0.15))
    }

    // MARK: - FX Toggle Row

    private var fxToggleRow: some View {
        HStack {
            Label("Writing Effects", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
            Spacer()
            Toggle("", isOn: $inkStore.fxEnabled)
                .labelsHidden()
                .disabled(!inkStore.isEffectsSupported)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Family Selector

    private var familySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InkFamily.allCases) { family in
                    Button {
                        selectedFamily = family
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: family.systemImage)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(
                                    selectedFamily == family
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.systemGray6)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(family.displayName)
                                .font(.caption2)
                        }
                        .foregroundStyle(selectedFamily == family ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Preset Grid

    private var presetGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]
        let presets = inkStore.allPresets.filter { $0.family == selectedFamily }

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(presets) { preset in
                    InkPresetCard(
                        preset: preset,
                        isActive: inkStore.activePreset?.id == preset.id,
                        fxSupported: inkStore.isEffectsSupported
                    ) {
                        inkStore.selectPreset(preset)
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Preset Card

private struct InkPresetCard: View {
    let preset: InkPreset
    let isActive: Bool
    let fxSupported: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Colour swatch
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: preset.uiColor))
                    .frame(height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )

                // Name + family tag
                Text(preset.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // FX badge row
                HStack(spacing: 4) {
                    if preset.writingFX != .none {
                        HStack(spacing: 3) {
                            Image(systemName: preset.writingFX.systemImage)
                                .font(.caption2)
                            Text(preset.writingFX.displayName)
                                .font(.caption2)
                        }
                        .foregroundStyle(fxBadgeColor(for: preset.writingFX))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            fxBadgeColor(for: preset.writingFX).opacity(0.12),
                            in: Capsule()
                        )
                    }

                    // Trait badges (dry / wet / sheen)
                    if preset.traits.isDry {
                        traitBadge("Dry")
                    } else if preset.traits.wetness > 0.5 {
                        traitBadge("Wet")
                    }
                    if preset.traits.sheenAmount > 0.3 {
                        traitBadge("Sheen")
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func fxBadgeColor(for fx: WritingFXType) -> Color {
        switch fx {
        case .fire:    return .orange
        case .glitch:  return .purple
        case .sparkle: return .yellow
        case .ripple:  return .blue
        case .none:    return .secondary
        }
    }

    private func traitBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(.systemGray5), in: Capsule())
    }
}
