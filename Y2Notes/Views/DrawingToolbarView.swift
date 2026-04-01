import SwiftUI
import PencilKit

/// Compact horizontal tool palette embedded between the title bar and canvas.
///
/// Shows tool buttons, colour swatch, width control, and a horizontally
/// scrollable presets strip. Contextual sub-pickers appear for the eraser
/// (pixel/stroke mode) and shape tool (line/rectangle/circle/arrow).
struct DrawingToolbarView: View {
    @ObservedObject var toolStore: DrawingToolStore

    @State private var showWidthPopover   = false
    @State private var showSaveAlert      = false
    @State private var showPresetManager  = false
    @State private var newPresetName      = ""

    // MARK: - Color Binding

    /// Bridges UIColor ↔ SwiftUI Color for the system ColorPicker.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: toolStore.activeColor) },
            set: { toolStore.activeColor = UIColor($0) }
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
            if !toolStore.presets.isEmpty {
                rowDivider
                presetsStrip
            }
        }
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

            // Width indicator — tap to reveal slider
            Button {
                showWidthPopover.toggle()
            } label: {
                widthSwatch
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showWidthPopover) {
                widthPopover
            }
            .disabled(!toolStore.activeTool.isInking)
            .opacity(toolStore.activeTool.isInking ? 1 : 0.35)
            .accessibilityLabel("Stroke width \(Int(toolStore.activeWidth))pt")

            Spacer(minLength: 8)

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
                .fill(Color(uiColor: toolStore.activeColor))
                .frame(
                    width: min(28, CGFloat(toolStore.activeWidth) * 2 + 4),
                    height: min(28, CGFloat(toolStore.activeWidth) * 2 + 4)
                )
        }
    }

    // MARK: - Width Popover

    private var widthPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stroke Width")
                .font(.headline)
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
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray6))
                    Circle()
                        .fill(Color(uiColor: toolStore.activeColor))
                        .frame(
                            width:  min(44, CGFloat(toolStore.activeWidth) * 2.2),
                            height: min(44, CGFloat(toolStore.activeWidth) * 2.2)
                        )
                }
                .frame(width: 240, height: 52)
                Spacer()
            }
            HStack {
                Spacer()
                Text("\(Int(toolStore.activeWidth)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Presets Strip

    private var presetsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(toolStore.presets) { preset in
                    presetChip(preset)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }

    private func presetChip(_ preset: ToolPreset) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(uiColor: preset.uiColor))
                .frame(width: 9, height: 9)
            Text(preset.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if preset.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
        .onTapGesture {
            toolStore.applyPreset(preset)
        }
        .contextMenu {
            Button {
                toolStore.toggleFavorite(presetID: preset.id)
            } label: {
                Label(
                    preset.isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: preset.isFavorite ? "star.slash" : "star"
                )
            }
            Divider()
            Button(role: .destructive) {
                toolStore.deletePreset(id: preset.id)
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}

// MARK: - Preset Manager Sheet

/// Full-screen sheet for reordering, favouriting, and deleting saved presets.
private struct PresetManagerView: View {
    @ObservedObject var toolStore: DrawingToolStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if toolStore.presets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.dashed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Presets")
                            .font(.headline)
                        Text("Save a tool, colour, and width combo from the toolbar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(toolStore.presets) { preset in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(uiColor: preset.uiColor))
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.body)
                                Text("\(preset.tool.displayName) · \(Int(preset.width)) pt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                toolStore.toggleFavorite(presetID: preset.id)
                            } label: {
                                Image(systemName: preset.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(preset.isFavorite ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toolStore.applyPreset(preset)
                            dismiss()
                        }
                    }
                    .onDelete { toolStore.presets.remove(atOffsets: $0) }
                    .onMove  { toolStore.movePresets(from: $0, to: $1) }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
