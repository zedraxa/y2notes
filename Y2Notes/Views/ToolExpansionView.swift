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
            } else if expandedTool == .text {
                textExpansion
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

            // Width slider
            widthRow

            // Opacity slider
            opacityRow

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

    // MARK: - Text Expansion

    @ViewBuilder
    private var textExpansion: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Font family row
            HStack(spacing: 5) {
                ForEach(TextFontFamily.allCases) { family in
                    let selected = toolStore.activeTextFontFamily == family
                    Button {
                        selectionFeedback.selectionChanged()
                        toolStore.activeTextFontFamily = family
                        resetTimeout()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: family.systemImage)
                                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            Text(family.displayName)
                                .font(.system(size: 8, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            selected ? Color.accentColor.opacity(0.15) : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(family.displayName)
                }
            }

            // Font size row
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(toolStore.activeTextFontSize) },
                        set: { val in
                            toolStore.activeTextFontSize = CGFloat(val)
                            resetTimeout()
                        }
                    ),
                    in: 8...72,
                    step: 1
                ) { editing in
                    if !editing { lightImpact.impactOccurred(intensity: 0.4) }
                }
                .accessibilityLabel(NSLocalizedString("TextStyle.Size", comment: ""))
                Text("\(Int(toolStore.activeTextFontSize))pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            // Bold toggle + alignment picker
            HStack(spacing: 6) {
                // Bold
                let boldSelected = toolStore.activeTextBold
                Button {
                    selectionFeedback.selectionChanged()
                    toolStore.activeTextBold.toggle()
                    resetTimeout()
                } label: {
                    Image(systemName: "bold")
                        .font(.system(size: 13, weight: boldSelected ? .semibold : .regular))
                        .frame(width: 36, height: 28)
                        .background(
                            boldSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .foregroundStyle(boldSelected ? Color.accentColor : Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("TextStyle.Bold", comment: ""))

                Spacer()

                // Alignment picker
                ForEach(TextAlignmentType.allCases) { align in
                    let selected = toolStore.activeTextAlignment == align
                    Button {
                        selectionFeedback.selectionChanged()
                        toolStore.activeTextAlignment = align
                        resetTimeout()
                    } label: {
                        Image(systemName: align.systemImage)
                            .font(.system(size: 13))
                            .frame(width: 34, height: 28)
                            .background(
                                selected ? Color.accentColor.opacity(0.15) : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .label))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(align.accessibilityLabel)
                }
            }
        }
        .frame(maxWidth: 300)
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
