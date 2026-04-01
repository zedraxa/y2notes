import SwiftUI
import PencilKit

/// Compact horizontal tool palette embedded between the title bar and canvas.
///
/// Shows tool buttons, colour swatch, width/opacity control, and an optional
/// contextual sub-picker for eraser mode or shape type. A "sliders" button on
/// the far right opens the AdvancedToolsPanel inspector when provided.
struct DrawingToolbarView: View {
    @ObservedObject var toolStore: DrawingToolStore

    /// Called when the user taps the inspector toggle button.
    var onOpenInspector: (() -> Void)? = nil

    @State private var showStrokePopover = false

    // MARK: - Color Binding

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: toolStore.activeColor) },
            set: { newColor in
                let uiColor = UIColor(newColor)
                toolStore.activeColor = uiColor
                toolStore.addRecentColor(uiColor)
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if toolStore.activeTool == .eraser {
                rowDivider
                eraserSubPicker
            } else if toolStore.activeTool == .shape {
                rowDivider
                shapeSubPicker
            }
        }
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 0) {
            // Tool buttons
            HStack(spacing: 2) {
                ForEach(DrawingTool.allCases) { tool in
                    toolButton(tool)
                }
            }

            Divider()
                .frame(height: 26)
                .padding(.horizontal, 8)

            // Colour swatch — system ColorPicker
            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 34)
                .accessibilityLabel("Stroke colour")
                .disabled(!toolStore.activeTool.isInking)
                .opacity(toolStore.activeTool.isInking ? 1 : 0.35)

            // Width/opacity indicator — tap to reveal popover
            Button {
                showStrokePopover.toggle()
            } label: {
                widthSwatch
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showStrokePopover) {
                strokeSettingsPopover
            }
            .disabled(!toolStore.activeTool.isInking)
            .opacity(toolStore.activeTool.isInking ? 1 : 0.35)
            .accessibilityLabel("Stroke width \(Int(toolStore.activeWidth))pt, opacity \(Int(toolStore.activeOpacity * 100))%")

            Spacer(minLength: 8)

            // Inspector toggle
            if onOpenInspector != nil {
                Divider()
                    .frame(height: 26)
                    .padding(.horizontal, 6)

                Button {
                    onOpenInspector?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Inspector")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Tool Button

    @ViewBuilder
    private func toolButton(_ tool: DrawingTool) -> some View {
        let isActive = toolStore.activeTool == tool
        Button {
            toolStore.activeTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .frame(width: 36, height: 36)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
    }

    // MARK: - Width Swatch

    private var widthSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                .frame(width: 36, height: 36)
            Circle()
                .fill(Color(uiColor: toolStore.activeColor).opacity(toolStore.activeOpacity))
                .frame(
                    width: min(28, CGFloat(toolStore.activeWidth) * 2 + 4),
                    height: min(28, CGFloat(toolStore.activeWidth) * 2 + 4)
                )
        }
    }

    // MARK: - Stroke Settings Popover

    private var strokeSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stroke")
                .font(.headline)

            // Width
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Width")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", toolStore.activeWidth)) pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text("1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $toolStore.activeWidth, in: 1...30, step: 0.5)
                        .frame(minWidth: 200)
                    Text("30")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Opacity
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opacity")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(toolStore.activeOpacity * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text("5%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $toolStore.activeOpacity, in: 0.05...1.0, step: 0.05)
                        .frame(minWidth: 200)
                    Text("100%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Live preview dot
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                    let dotSize = min(44, CGFloat(toolStore.activeWidth) * 2.4)
                    Circle()
                        .fill(Color(uiColor: toolStore.activeColor).opacity(toolStore.activeOpacity))
                        .frame(width: dotSize, height: dotSize)
                }
                .frame(width: 240, height: 52)
                Spacer()
            }
        }
        .padding(18)
    }

    // MARK: - Eraser Sub-picker

    private var eraserSubPicker: some View {
        HStack(spacing: 6) {
            Text("Mode:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(EraserMode.allCases, id: \.rawValue) { mode in
                let isSelected = toolStore.eraserMode == mode
                Button {
                    toolStore.eraserMode = mode
                } label: {
                    Text(mode.displayName)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray5)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Shape Sub-picker

    private var shapeSubPicker: some View {
        HStack(spacing: 6) {
            Text("Shape:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(ShapeType.allCases, id: \.rawValue) { shape in
                let isSelected = toolStore.activeShapeType == shape
                Button {
                    toolStore.activeShapeType = shape
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: shape.systemImage)
                            .font(.system(size: 11))
                        Text(shape.displayName)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color(.systemGray5)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}
