import SwiftUI
import PencilKit

/// Tier 2 inline expansion panel that fans out from the active tool button.
///
/// Shows contextual controls depending on the expanded tool:
/// - **Inking tools** (pen/pencil/highlighter/fountain pen): colour strip + width slider + opacity
/// - **Eraser**: pixel / stroke mode toggle
/// - **Shape**: shape type picker (line / rectangle / circle / arrow)
///
/// Dismisses automatically when the user taps outside, begins drawing, or
/// after a 3-second inactivity timeout.
struct ToolExpansionView: View {
    @ObservedObject var toolStore: DrawingToolStore
    let expandedTool: DrawingTool
    var onDismiss: () -> Void

    // MARK: - State

    @State private var dismissTask: Task<Void, Never>?

    // MARK: - Haptics

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Color Binding

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: toolStore.activeColor) },
            set: { newColor in
                let uiColor = UIColor(newColor)
                toolStore.activeColor = uiColor
                toolStore.addRecentColor(uiColor)
                resetTimeout()
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if expandedTool.isInking {
                inkingExpansion
            } else if expandedTool == .eraser {
                eraserExpansion
            } else if expandedTool == .shape {
                shapeExpansion
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
        .onAppear { resetTimeout() }
        .onDisappear { dismissTask?.cancel() }
    }

    // MARK: - Inking Expansion

    @ViewBuilder
    private var inkingExpansion: some View {
        VStack(spacing: 10) {
            // Recent colour strip + system picker
            colorStrip

            // One-tap width shortcuts
            quickWidthRow

            // Width slider
            widthRow

            // Opacity slider
            opacityRow

            // Starred presets strip (shown when the user has favourites)
            favoritePresetsStrip

            // Pen sub-type picker (only for the pen tool)
            if expandedTool == .pen {
                penSubTypeRow
            }
        }
        .frame(maxWidth: 280)
    }

    @ViewBuilder
    private var colorStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(toolStore.recentColors.prefix(6).enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(Color(uiColor: color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: isSameColor(color, toolStore.activeColor) ? 2 : 0)
                    )
                    .onTapGesture {
                        selectionFeedback.selectionChanged()
                        toolStore.activeColor = color
                        resetTimeout()
                    }
                    .accessibilityLabel(NSLocalizedString("ToolExpansion.RecentColor", comment: "Recent colour swatch"))
            }

            Spacer(minLength: 4)

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var widthRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.diagonal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: $toolStore.activeWidth, in: 1...30, step: 0.5) { editing in
                if !editing {
                    lightImpact.impactOccurred(intensity: 0.4)
                    resetTimeout()
                }
            }
            .accessibilityLabel(NSLocalizedString("ToolExpansion.Width", comment: "Stroke width slider"))
            .accessibilityValue("\(String(format: "%.0f", toolStore.activeWidth)) pt")
            Text("\(String(format: "%.0f", toolStore.activeWidth))pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var opacityRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: $toolStore.activeOpacity, in: 0.05...1.0, step: 0.05) { editing in
                if !editing {
                    lightImpact.impactOccurred(intensity: 0.4)
                    resetTimeout()
                }
            }
            .accessibilityLabel(NSLocalizedString("ToolExpansion.Opacity", comment: "Opacity slider"))
            .accessibilityValue("\(Int(toolStore.activeOpacity * 100))%")
            Text("\(Int(toolStore.activeOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Quick Width Row

    /// Four one-tap width shortcuts that snap the active width to a common value.
    /// Labels and values adapt between regular inking tools and the highlighter.
    @ViewBuilder
    private var quickWidthRow: some View {
        HStack(spacing: 4) {
            ForEach(quickWidthPresets, id: \.label) { preset in
                let isNear = abs(toolStore.activeWidth - preset.value) < 0.75
                Button {
                    toolStore.activeWidth = preset.value
                    resetTimeout()
                } label: {
                    Text(preset.label)
                        .font(.system(size: 11, weight: isNear ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(isNear ? Color.accentColor.opacity(0.15) : Color(.systemGray5),
                                    in: Capsule())
                        .foregroundStyle(isNear ? Color.accentColor : Color(uiColor: .secondaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct WidthPreset {
        let label: String
        let value: Double
    }

    private var quickWidthPresets: [WidthPreset] {
        if expandedTool == .highlighter {
            return [
                WidthPreset(label: "Thin",  value: 3),
                WidthPreset(label: "Mid",   value: 6),
                WidthPreset(label: "Wide",  value: 10),
                WidthPreset(label: "XL",    value: 15),
            ]
        }
        return [
            WidthPreset(label: "Fine",  value: 1),
            WidthPreset(label: "Med",   value: 3),
            WidthPreset(label: "Thick", value: 6),
            WidthPreset(label: "Bold",  value: 10),
        ]
    }

    // MARK: - Favourite Presets Strip

    /// Horizontally scrollable row of starred presets shown at the bottom of the
    /// inking expansion. Lets users apply a favourite without opening the inspector.
    @ViewBuilder
    private var favoritePresetsStrip: some View {
        let favorites = toolStore.favoritePresets
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Presets")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(favorites) { preset in
                            Button {
                                toolStore.applyPreset(preset)
                                resetTimeout()
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(uiColor: preset.uiColor)
                                            .opacity(preset.opacity))
                                        .frame(width: 9, height: 9)
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(.systemGray5), in: Capsule())
                                .foregroundStyle(Color(uiColor: .label))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - Pen Sub-Type Row

    @ViewBuilder
    private var penSubTypeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("ToolExpansion.PenType", comment: "Pen type section header"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PenSubType.allCases) { sub in
                        let isSelected = toolStore.activePenSubType == sub
                        Button {
                            selectionFeedback.selectionChanged()
                            toolStore.activePenSubType = sub
                            resetTimeout()
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: sub.systemImage)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .frame(height: 16)
                                Text(sub.displayName)
                                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.systemGray5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .foregroundStyle(
                                isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sub.displayName): \(sub.tagline)")
                    }
                }
            }
        }
    }

    // MARK: - Eraser Expansion

    @ViewBuilder
    private var eraserExpansion: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sub-type row
            HStack(spacing: 6) {
                ForEach(EraserSubType.allCases, id: \.rawValue) { sub in
                    let isSelected = toolStore.eraserSubType == sub
                    Button {
                        selectionFeedback.selectionChanged()
                        toolStore.eraserSubType = sub
                        resetTimeout()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: sub.systemImage)
                                .font(.system(size: 13))
                            Text(sub.displayName)
                                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                        }
                        .frame(width: 50, height: 42)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Width slider — only for pixel-mode sub-types
            if toolStore.eraserSubType.supportsWidthAdjustment {
                HStack(spacing: 6) {
                    Image(systemName: "eraser")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $toolStore.eraserWidth,
                        in: toolStore.eraserSubType.minWidth...toolStore.eraserSubType.maxWidth,
                        step: 1
                    ) { editing in
                        if !editing {
                            lightImpact.impactOccurred(intensity: 0.4)
                            resetTimeout()
                        }
                    }
                    .accessibilityLabel(NSLocalizedString("ToolExpansion.EraserWidth", comment: "Eraser width slider"))
                    .accessibilityValue("\(Int(toolStore.eraserWidth)) pt")
                    Text("\(Int(toolStore.eraserWidth))pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Shape Expansion

    @ViewBuilder
    private var shapeExpansion: some View {
        HStack(spacing: 6) {
            ForEach(ShapeType.allCases, id: \.rawValue) { shape in
                let isSelected = toolStore.activeShapeType == shape
                Button {
                    selectionFeedback.selectionChanged()
                    toolStore.activeShapeType = shape
                    resetTimeout()
                } label: {
                    Image(systemName: shape.systemImage)
                        .font(.system(size: 14))
                        .frame(width: 36, height: 32)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shape.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: - Helpers

    private func resetTimeout() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private func isSameColor(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        b.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return abs(ar - br) < 0.02 && abs(ag - bg) < 0.02 && abs(ab - bb) < 0.02
    }
}
