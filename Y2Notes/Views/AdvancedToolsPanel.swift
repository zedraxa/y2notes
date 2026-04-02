import SwiftUI
import PencilKit

/// Right-side inspector panel that slides in over the canvas.
///
/// Provides detailed tool selection, stroke width/opacity tuning, a curated
/// colour palette with recent-colour history, contextual eraser/shape pickers,
/// and a full preset management grid with inline authoring.
///
/// Present this inside a ZStack overlay in NoteEditorView, bound to a
/// `@State var showAdvancedPanel: Bool`.
struct AdvancedToolsPanel: View {
    @ObservedObject var toolStore: DrawingToolStore
    @Binding var isPresented: Bool

    @State private var showCustomToolAuthoring = false
    @State private var presetToEdit: ToolPreset? = nil
    @State private var showDeletePresetAlert = false
    @State private var presetToDelete: ToolPreset? = nil
    @State private var showSavePresetAlert = false
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
            panelHeader
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    activeToolSection
                    sectionDivider
                    strokeSection
                    sectionDivider
                    colorSection
                    if toolStore.activeTool == .eraser {
                        sectionDivider
                        eraserSection
                    }
                    if toolStore.activeTool == .shape {
                        sectionDivider
                        shapeSection
                    }
                    sectionDivider
                    presetsSection
                }
            }
        }
        .frame(width: 304)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, x: -4, y: 0)
        // Alerts are attached at the top level so they are always in the hierarchy.
        .alert("Save Preset", isPresented: $showSavePresetAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                toolStore.saveCurrentAsPreset(name: newPresetName)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Save current tool, colour, width, and opacity.")
        }
        .alert("Delete Preset?", isPresented: $showDeletePresetAlert) {
            Button("Delete", role: .destructive) {
                if let p = presetToDelete { toolStore.deletePreset(id: p.id) }
                presetToDelete = nil
            }
            Button("Cancel", role: .cancel) { presetToDelete = nil }
        } message: {
            if let p = presetToDelete {
                Text("\"\(p.name)\" will be removed permanently.")
            }
        }
        .sheet(isPresented: $showCustomToolAuthoring) {
            CustomToolAuthoringView(toolStore: toolStore, editingPreset: presetToEdit)
                .onDisappear { presetToEdit = nil }
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Inspector")
                .font(.headline)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Section Helpers

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Active Tool Section

    private var activeToolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tool")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(DrawingTool.allCases) { tool in
                    toolGridButton(tool)
                }
            }
        }
        .padding(16)
    }

    private func toolGridButton(_ tool: DrawingTool) -> some View {
        let isActive = toolStore.activeTool == tool
        return Button {
            toolStore.activeTool = tool
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                    .frame(height: 22)
                Text(tool.displayName)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
    }

    // MARK: - Stroke Section

    private var strokeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Stroke")

            // Width slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Width")
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", toolStore.activeWidth)) pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Slider(value: $toolStore.activeWidth, in: 1...30, step: 0.5)
                    .disabled(!toolStore.activeTool.isInking)
                    .opacity(toolStore.activeTool.isInking ? 1 : 0.4)
            }

            // Opacity slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opacity")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(toolStore.activeOpacity * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Slider(value: $toolStore.activeOpacity, in: 0.05...1.0, step: 0.05)
                    .disabled(!toolStore.activeTool.isInking)
                    .opacity(toolStore.activeTool.isInking ? 1 : 0.4)
            }

            // Live stroke preview
            strokePreviewCanvas
        }
        .padding(16)
    }

    private var strokePreviewCanvas: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 16, y: midY + 6))
            path.addCurve(
                to: CGPoint(x: size.width - 16, y: midY - 6),
                control1: CGPoint(x: size.width * 0.3, y: midY - 14),
                control2: CGPoint(x: size.width * 0.7, y: midY + 14)
            )
            let strokeColor = Color(uiColor: toolStore.activeColor)
                .opacity(toolStore.activeOpacity)
            context.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: min(CGFloat(toolStore.activeWidth), 20), lineCap: .round)
            )
        }
        .frame(height: 44)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Color Section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Color")

            // Active color + full picker
            HStack(spacing: 12) {
                ColorPicker("Active Color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.35)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Color")
                        .font(.subheadline.weight(.medium))
                    Text("Tap to open color picker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Recent colors
            if !toolStore.recentColors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionSubLabel("Recent")
                    HStack(spacing: 6) {
                        ForEach(toolStore.recentColors.indices, id: \.self) { idx in
                            colorSwatch(toolStore.recentColors[idx], size: 28)
                        }
                        Spacer()
                    }
                }
            }

            // Curated palette
            VStack(alignment: .leading, spacing: 6) {
                sectionSubLabel("Palette")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                    spacing: 6
                ) {
                    ForEach(curatedColors.indices, id: \.self) { idx in
                        colorSwatch(curatedColors[idx], size: 28)
                    }
                }
            }
        }
        .padding(16)
    }

    private func sectionSubLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.3)
    }

    private func colorSwatch(_ color: UIColor, size: CGFloat) -> some View {
        let isSelected = isSameColor(color, toolStore.activeColor)
        return Button {
            toolStore.activeColor = color
            toolStore.addRecentColor(color)
        } label: {
            Circle()
                .fill(Color(uiColor: color))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color(.systemGray3),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select color")
    }

    private func isSameColor(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        b.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return abs(ar - br) < 0.02 && abs(ag - bg) < 0.02 && abs(ab - bb) < 0.02
    }

    // 24-colour curated palette (6 columns × 4 rows)
    private let curatedColors: [UIColor] = [
        .black, .darkGray, .gray, .lightGray,
        .white, .systemBrown,
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemMint, .systemTeal,
        .systemCyan, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink,
        UIColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1),
        UIColor(red: 0.10, green: 0.40, blue: 0.80, alpha: 1),
        UIColor(red: 0.00, green: 0.50, blue: 0.30, alpha: 1),
        UIColor(red: 0.50, green: 0.00, blue: 0.50, alpha: 1),
        UIColor(red: 0.90, green: 0.60, blue: 0.00, alpha: 1),
        UIColor(red: 0.20, green: 0.60, blue: 0.80, alpha: 1),
        UIColor(red: 0.40, green: 0.80, blue: 0.40, alpha: 1),
    ]

    // MARK: - Eraser Section

    private var eraserSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Eraser Mode")
            HStack(spacing: 8) {
                ForEach(EraserMode.allCases, id: \.rawValue) { mode in
                    let isSelected = toolStore.eraserMode == mode
                    Button {
                        toolStore.eraserMode = mode
                    } label: {
                        Text(mode.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Shape Section

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Shape")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(ShapeType.allCases, id: \.rawValue) { shape in
                    let isSelected = toolStore.activeShapeType == shape
                    Button {
                        toolStore.activeShapeType = shape
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: shape.systemImage)
                                .font(.system(size: 18))
                                .frame(height: 22)
                            Text(shape.displayName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                sectionHeader("Presets")
                Spacer()
                // Save current settings as a preset
                Button {
                    newPresetName = toolStore.activeTool.displayName
                    showSavePresetAlert = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save current as preset")

                // Open Custom Tool Authoring for a new blank preset
                Button {
                    presetToEdit = nil
                    showCustomToolAuthoring = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Circle())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new preset")
            }

            if toolStore.presets.isEmpty {
                Text("No presets yet.\nSave your current settings or tap + to author a custom preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(toolStore.presets) { preset in
                        presetCard(preset)
                    }
                }
            }
        }
        .padding(16)
    }

    private func presetCard(_ preset: ToolPreset) -> some View {
        Button {
            toolStore.applyPreset(preset)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(uiColor: preset.uiColor).opacity(preset.opacity))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text("\(preset.tool.displayName) · \(Int(preset.width))pt · \(Int(preset.opacity * 100))%")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if preset.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toolStore.toggleFavorite(presetID: preset.id)
            } label: {
                Label(
                    preset.isFavorite ? "Unfavourite" : "Favourite",
                    systemImage: preset.isFavorite ? "star.slash" : "star"
                )
            }
            Button {
                presetToEdit = preset
                showCustomToolAuthoring = true
            } label: {
                Label("Edit Preset", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                presetToDelete = preset
                showDeletePresetAlert = true
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
        }
    }
}
