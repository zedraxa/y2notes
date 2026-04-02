import SwiftUI
import PencilKit

/// Full-form view for creating a new tool preset or editing an existing one.
///
/// Shown as a sheet from AdvancedToolsPanel. All field changes are applied only
/// when the user taps "Save"; cancelling discards all edits.
struct CustomToolAuthoringView: View {
    @ObservedObject var toolStore: DrawingToolStore
    var editingPreset: ToolPreset?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedTool: DrawingTool
    @State private var selectedColor: Color
    @State private var width: Double
    @State private var opacity: Double
    @State private var isFavorite: Bool

    init(toolStore: DrawingToolStore, editingPreset: ToolPreset? = nil) {
        self.toolStore = toolStore
        self.editingPreset = editingPreset
        if let preset = editingPreset {
            _name          = State(initialValue: preset.name)
            _selectedTool  = State(initialValue: preset.tool)
            _selectedColor = State(initialValue: Color(uiColor: preset.uiColor))
            _width         = State(initialValue: preset.width)
            _opacity       = State(initialValue: preset.opacity)
            _isFavorite    = State(initialValue: preset.isFavorite)
        } else {
            _name          = State(initialValue: toolStore.activeTool.displayName)
            _selectedTool  = State(initialValue: toolStore.activeTool)
            _selectedColor = State(initialValue: Color(uiColor: toolStore.activeColor))
            _width         = State(initialValue: toolStore.activeWidth)
            _opacity       = State(initialValue: toolStore.activeOpacity)
            _isFavorite    = State(initialValue: false)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                toolTypeSection
                propertiesSection
                previewSection
            }
            .navigationTitle(editingPreset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        savePreset()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        Section {
            TextField("Preset name", text: $name)
            Toggle(isOn: $isFavorite) {
                Label("Favourite", systemImage: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .primary)
            }
            .tint(.yellow)
        } header: {
            Text("Identity")
        }
    }

    // MARK: - Tool Type Section

    private var toolTypeSection: some View {
        Section {
            Picker("Tool", selection: $selectedTool) {
                ForEach(DrawingTool.allCases) { tool in
                    Label(tool.displayName, systemImage: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Tool Type")
        }
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        Section {
            ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Width")
                    Spacer()
                    Text("\(String(format: "%.1f", width)) pt")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.monospacedDigit())
                }
                Slider(value: $width, in: 1...30, step: 0.5)
                    .disabled(!selectedTool.isInking)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int(opacity * 100))%")
                        .foregroundStyle(.secondary)
                        .font(.subheadline.monospacedDigit())
                }
                Slider(value: $opacity, in: 0.05...1.0, step: 0.05)
                    .disabled(!selectedTool.isInking)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Properties")
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            strokePreviewCanvas
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Text("Stroke Preview")
        } footer: {
            Text("Preview shows approximate stroke appearance at the configured width and opacity.")
        }
    }

    private var strokePreviewCanvas: some View {
        let inkColor = UIColor(selectedColor).withAlphaComponent(CGFloat(opacity))
        return Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 20, y: midY + 8))
            path.addCurve(
                to: CGPoint(x: size.width - 20, y: midY - 8),
                control1: CGPoint(x: size.width * 0.25, y: midY - 20),
                control2: CGPoint(x: size.width * 0.75, y: midY + 20)
            )
            context.stroke(
                path,
                with: .color(Color(uiColor: inkColor)),
                style: StrokeStyle(
                    lineWidth: min(CGFloat(width), 20),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .frame(height: 80)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Save

    private func savePreset() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? selectedTool.displayName : trimmed
        let uiColor = UIColor(selectedColor)

        if let existing = editingPreset,
           let idx = toolStore.presets.firstIndex(where: { $0.id == existing.id }) {
            // Update existing preset in-place, preserving its UUID.
            toolStore.presets[idx] = ToolPreset(
                id: existing.id,
                name: finalName,
                tool: selectedTool,
                color: uiColor,
                width: width,
                opacity: opacity,
                isFavorite: isFavorite
            )
        } else {
            toolStore.presets.append(ToolPreset(
                name: finalName,
                tool: selectedTool,
                color: uiColor,
                width: width,
                opacity: opacity,
                isFavorite: isFavorite
            ))
        }
    }
}
