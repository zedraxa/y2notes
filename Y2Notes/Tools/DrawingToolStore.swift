import Foundation
import PencilKit
import UIKit

/// Observable store that manages the active drawing tool, colour, stroke width,
/// eraser mode, shape type, and saved presets. All state is persisted to
/// UserDefaults so settings survive app restarts.
///
/// Inject this as an @EnvironmentObject in the app shell and read it in
/// NoteEditorView / DrawingToolbarView.
final class DrawingToolStore: ObservableObject {

    // MARK: - Published State

    @Published var activeTool: DrawingTool = .pen {
        didSet { UserDefaults.standard.set(activeTool.rawValue, forKey: Keys.tool) }
    }

    @Published var activeColor: UIColor = .black {
        didSet { persistColor() }
    }

    @Published var activeWidth: Double = 3.0 {
        didSet { UserDefaults.standard.set(activeWidth, forKey: Keys.width) }
    }

    @Published var eraserMode: EraserMode = .bitmap {
        didSet { UserDefaults.standard.set(eraserMode.rawValue, forKey: Keys.eraserMode) }
    }

    @Published var activeShapeType: ShapeType = .rectangle {
        didSet { UserDefaults.standard.set(activeShapeType.rawValue, forKey: Keys.shapeType) }
    }

    @Published var presets: [ToolPreset] = [] {
        didSet { persistPresets() }
    }

    // MARK: - Computed Properties

    /// The PencilKit tool corresponding to the current state.
    /// Shape tool returns a standard pen so the canvas behaves normally while
    /// the shape overlay captures the gesture.
    var pkTool: PKTool {
        switch activeTool {
        case .pen:
            return PKInkingTool(.pen, color: activeColor, width: activeWidth)
        case .pencil:
            return PKInkingTool(.pencil, color: activeColor, width: activeWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: activeColor.withAlphaComponent(0.4), width: activeWidth * 3.0)
        case .fountainPen:
            if #available(iOS 17, *) {
                return PKInkingTool(.fountainPen, color: activeColor, width: activeWidth)
            } else {
                return PKInkingTool(.pen, color: activeColor, width: activeWidth)
            }
        case .eraser:
            return PKEraserTool(eraserMode.pkEraserType)
        case .lasso:
            return PKLassoTool()
        case .shape:
            // The shape overlay intercepts all input; the canvas uses a pen as fallback.
            return PKInkingTool(.pen, color: activeColor, width: activeWidth)
        }
    }

    /// Convenience: only presets the user has starred.
    var favoritePresets: [ToolPreset] { presets.filter(\.isFavorite) }

    // MARK: - Init

    init() {
        loadAll()
        if presets.isEmpty { seedDefaultPresets() }
    }

    // MARK: - Preset Management

    /// Saves the current tool/colour/width combo as a named preset.
    func saveCurrentAsPreset(name: String) {
        let resolved = name.trimmingCharacters(in: .whitespaces)
        let preset = ToolPreset(
            name: resolved.isEmpty ? activeTool.displayName : resolved,
            tool: activeTool,
            color: activeColor,
            width: activeWidth
        )
        presets.append(preset)
    }

    /// Restores the tool, colour, and width from a saved preset.
    func applyPreset(_ preset: ToolPreset) {
        activeTool   = preset.tool
        activeColor  = preset.uiColor
        activeWidth  = preset.width
    }

    /// Toggles the favourite star on a preset.
    func toggleFavorite(presetID: UUID) {
        guard let idx = presets.firstIndex(where: { $0.id == presetID }) else { return }
        presets[idx].isFavorite.toggle()
    }

    /// Permanently removes a preset.
    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    /// Reorders presets (for drag-to-reorder in the management sheet).
    func movePresets(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Default Presets

    private func seedDefaultPresets() {
        presets = [
            ToolPreset(name: "Fine Pen",        tool: .pen,         color: .black,        width: 2,  isFavorite: true),
            ToolPreset(name: "Medium Pen",       tool: .pen,         color: .black,        width: 5,  isFavorite: true),
            ToolPreset(name: "Pencil",           tool: .pencil,      color: .darkGray,     width: 3,  isFavorite: false),
            ToolPreset(name: "Yellow Highlight", tool: .highlighter, color: .systemYellow, width: 8,  isFavorite: true),
            ToolPreset(name: "Blue Pen",         tool: .pen,         color: .systemBlue,   width: 2,  isFavorite: false),
            ToolPreset(name: "Red Pen",          tool: .pen,         color: .systemRed,    width: 2,  isFavorite: false),
        ]
    }

    // MARK: - Persistence Keys

    private enum Keys {
        static let tool       = "y2notes.tool.active"
        static let colorR     = "y2notes.tool.colorR"
        static let colorG     = "y2notes.tool.colorG"
        static let colorB     = "y2notes.tool.colorB"
        static let colorA     = "y2notes.tool.colorA"
        static let width      = "y2notes.tool.width"
        static let eraserMode = "y2notes.tool.eraserMode"
        static let shapeType  = "y2notes.tool.shapeType"
        static let presets    = "y2notes.tool.presets"
    }

    // MARK: - Persistence Helpers

    private func persistColor() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        activeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ud = UserDefaults.standard
        ud.set(Double(r), forKey: Keys.colorR)
        ud.set(Double(g), forKey: Keys.colorG)
        ud.set(Double(b), forKey: Keys.colorB)
        ud.set(Double(a), forKey: Keys.colorA)
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: Keys.presets)
    }

    private func loadAll() {
        let ud = UserDefaults.standard

        if let raw = ud.string(forKey: Keys.tool), let tool = DrawingTool(rawValue: raw) {
            activeTool = tool
        }

        let r = ud.double(forKey: Keys.colorR)
        let g = ud.double(forKey: Keys.colorG)
        let b = ud.double(forKey: Keys.colorB)
        let a = ud.double(forKey: Keys.colorA)
        if a > 0 {
            activeColor = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        }

        let w = ud.double(forKey: Keys.width)
        if w > 0 { activeWidth = w }

        if let raw = ud.string(forKey: Keys.eraserMode), let mode = EraserMode(rawValue: raw) {
            eraserMode = mode
        }

        if let raw = ud.string(forKey: Keys.shapeType), let shape = ShapeType(rawValue: raw) {
            activeShapeType = shape
        }

        if let data = ud.data(forKey: Keys.presets),
           let loaded = try? JSONDecoder().decode([ToolPreset].self, from: data) {
            presets = loaded
        }
    }
}
