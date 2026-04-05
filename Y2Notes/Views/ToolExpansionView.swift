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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        toolStore.activeColor = color
                        resetTimeout()
                    }
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
                if !editing { resetTimeout() }
            }
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
                if !editing { resetTimeout() }
            }
            Text("\(Int(toolStore.activeOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
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
                        if !editing { resetTimeout() }
                    }
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
            }
        }
    }

    // MARK: - Text Expansion

    @ViewBuilder
    private var textExpansion: some View {
        VStack(spacing: 8) {
            // Font size slider
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(
                    value: $toolStore.activeTextFontSize,
                    in: TextObjectConstants.minFontSize...TextObjectConstants.maxFontSize,
                    step: 1
                )
                .frame(minWidth: 120)
                .onChange(of: toolStore.activeTextFontSize) { _, _ in resetTimeout() }
                Text("\(Int(toolStore.activeTextFontSize))pt")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 32)
            }

            // Alignment buttons
            HStack(spacing: 4) {
                alignmentButton(0, icon: "text.alignleft")
                alignmentButton(1, icon: "text.aligncenter")
                alignmentButton(2, icon: "text.alignright")
            }
        }
        .frame(maxWidth: 280)
    }

    private func alignmentButton(_ rawValue: Int, icon: String) -> some View {
        let isSelected = toolStore.activeTextAlignmentRaw == rawValue
        return Button {
            toolStore.activeTextAlignmentRaw = rawValue
            resetTimeout()
        } label: {
            Image(systemName: icon)
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
