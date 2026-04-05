import SwiftUI
import PencilKit

/// Compact horizontal tool palette embedded between the title bar and canvas.
///
/// Shows tool buttons, colour swatch, width/opacity control, and a horizontally
/// scrollable presets strip. Contextual sub-pickers appear for the eraser
/// (pixel/stroke mode) and shape tool (line/rectangle/circle/arrow).
///
/// An ink-effects button (✦ wand icon) opens `InkEffectPickerView` when
/// `inkStore` is provided.  The button is omitted if `inkStore` is nil so
/// the base drawing path is unaffected by the premium ink system. A "sliders"
/// button on the far right opens the AdvancedToolsPanel inspector when provided.
struct DrawingToolbarView: View {
    @ObservedObject var toolStore: DrawingToolStore
    /// Optional — nil disables the ink-effects button entirely.
    var inkStore: InkEffectStore? = nil
    /// Called when the user taps the inspector toggle button.
    var onOpenInspector: (() -> Void)? = nil

    @State private var showStrokePopover = false
    @State private var showSaveAlert = false
    @State private var showPresetManager = false
    @State private var showInkPicker = false
    @State private var newPresetName = ""

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
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if toolStore.activeTool == .shape {
                rowDivider
                shapeSubPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !toolStore.presets.isEmpty {
                rowDivider
                presetsStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toolStore.activeTool)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toolStore.presets.isEmpty)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .alert("Save Preset", isPresented: $showSaveAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                toolStore.saveCurrentAsPreset(name: newPresetName)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Save the current tool, colour, and width as a reusable preset.")
        }
        .sheet(isPresented: $showPresetManager) {
            PresetManagerView(toolStore: toolStore)
        }
        .sheet(isPresented: $showInkPicker) {
            if let inkStore {
                InkEffectPickerView(inkStore: inkStore)
            }
        }
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

            // Ink effects button — only shown when InkEffectStore is available
            if let inkStore {
                inkEffectsButton(inkStore: inkStore)
            }

            // Manage / add preset buttons
            Button {
                newPresetName = toolStore.activeTool.displayName
                showSaveAlert = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save as preset")

            Button {
                showPresetManager = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage presets")

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

    // MARK: - Ink Effects Button

    @ViewBuilder
    private func inkEffectsButton(inkStore: InkEffectStore) -> some View {
        let isActive = inkStore.activePreset != nil
        Button {
            showInkPicker = true
        } label: {
            Image(systemName: isActive ? "wand.and.stars.inverse" : "wand.and.stars")
                .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                .frame(width: 32, height: 32)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .foregroundStyle(isActive ? Color.accentColor : Color(uiColor: .secondaryLabel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Ink effects: \(inkStore.activePreset?.name ?? "")" : "Ink effects")
    }

    // MARK: - Tool Button

    @ViewBuilder
    private func toolButton(_ tool: DrawingTool) -> some View {
        let isActive = toolStore.activeTool == tool
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.prepare()
            impact.impactOccurred()
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
                .foregroundStyle(isActive ? Color.accentColor : Color(uiColor: .secondaryLabel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
    }

    // MARK: - Width Swatch

    private var widthSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(uiColor: .secondaryLabel).opacity(0.3), lineWidth: 1)
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
                        .accessibilityLabel("Stroke width")
                        .accessibilityValue("\(String(format: "%.1f", toolStore.activeWidth)) points")
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
                        .accessibilityLabel("Stroke opacity")
                        .accessibilityValue("\(Int(toolStore.activeOpacity * 100)) percent")
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
            Text("Type:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(EraserSubType.allCases, id: \.rawValue) { sub in
                let isSelected = toolStore.eraserSubType == sub
                Button {
                    toolStore.eraserSubType = sub
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sub.systemImage)
                            .font(.caption2)
                        Text(sub.displayName)
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
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.displayName) eraser")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shape.displayName) shape")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Presets Strip

    private var presetsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(toolStore.presets) { preset in
                    Button {
                        toolStore.applyPreset(preset)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(uiColor: preset.uiColor))
                                .frame(width: 12, height: 12)
                            Text(preset.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}

// MARK: - Preset Manager View

/// Sheet for managing (reordering / deleting) saved tool presets.
struct PresetManagerView: View {
    @ObservedObject var toolStore: DrawingToolStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(toolStore.presets) { preset in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(uiColor: preset.uiColor))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.body)
                            Text("\(preset.tool.displayName) · \(Int(preset.width))pt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preset.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            toolStore.deletePreset(id: preset.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toolStore.toggleFavorite(presetID: preset.id)
                        } label: {
                            Label(
                                preset.isFavorite ? "Unfavourite" : "Favourite",
                                systemImage: preset.isFavorite ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
                }
                .onMove { toolStore.movePresets(from: $0, to: $1) }
            }
            .navigationTitle("Manage Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
    }
}
