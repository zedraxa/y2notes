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

    @State private var panelAppeared = false

    var body: some View {
        Group {
            if expandedTool.isInking {
                inkingExpansion
            } else if expandedTool == .eraser {
                eraserExpansion
            } else if expandedTool == .shape {
                shapeExpansion
            } else if expandedTool == .text {
                textExpansion
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
        .onAppear { resetTimeout() }
        .scaleEffect(panelAppeared ? 1.0 : 0.92)
        .opacity(panelAppeared ? 1.0 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: panelAppeared)
        .onAppear {
            panelAppeared = true
            resetTimeout()
        }
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
            ForEach(Array(toolStore.recentColors.prefix(6).enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(Color(uiColor: color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: isSameColor(color, toolStore.activeColor) ? 2 : 0)
                    )
                    .scaleEffect(isSameColor(color, toolStore.activeColor) ? 1.12 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: toolStore.activeColor)
                    .onTapGesture {
                        selectionFeedback.selectionChanged()
                        toolStore.activeColor = color
                        resetTimeout()
                    }
                    .accessibilityLabel(NSLocalizedString("ToolExpansion.RecentColor", comment: "Recent colour swatch"))
                    .opacity(panelAppeared ? 1 : 0)
                    .scaleEffect(panelAppeared ? 1.0 : 0.6)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.75)
                            .delay(Double(index) * 0.04),
                        value: panelAppeared
                    )
            }

            Spacer(minLength: 4)

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .opacity(panelAppeared ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.25), value: panelAppeared)
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
                    selectionFeedback.selectionChanged()
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
                                selectionFeedback.selectionChanged()
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
