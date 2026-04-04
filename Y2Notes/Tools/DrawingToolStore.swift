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

    @Published var activeOpacity: Double = 1.0 {
        didSet { UserDefaults.standard.set(activeOpacity, forKey: Keys.opacity) }
    }

    @Published var recentColors: [UIColor] = []

    @Published var presets: [ToolPreset] = [] {
        didSet { persistPresets() }
    }

    /// The paper material of the note currently open in the editor.
    /// Set by `NoteEditorView` on `.onAppear` and when the note changes.
    /// **Not persisted** — it is always derived from the active notebook's
    /// `paperMaterial` property and reset to `.standard` when no note is open.
    @Published var currentPaperMaterial: PaperMaterial = .standard

    // MARK: - Floating Toolbar State

    /// Opacity of the floating toolbar capsule. Animated down to 0.3 during
    /// active Pencil contact and back to 1.0 when the stroke ends.
    /// **Not persisted** — always starts at 1.0.
    @Published var toolbarOpacity: Double = 1.0

    /// User preference: whether the toolbar is manually minimized / auto-hidden.
    /// Persisted so the user's choice survives app restarts.
    @Published var isToolbarMinimized: Bool = false {
        didSet { UserDefaults.standard.set(isToolbarMinimized, forKey: Keys.toolbarMinimized) }
    }

    // MARK: - Computed Properties

    /// The PencilKit tool corresponding to the current state.
    /// Shape tool returns a standard pen so the canvas behaves normally while
    /// the shape overlay captures the gesture.
    ///
    /// When `currentPaperMaterial.inkAlphaMultiplier` is below 1.0 the active
    /// ink color's alpha is scaled down accordingly — this produces a subtle
    /// "absorption" effect that makes ink look slightly less sharp on textured
    /// or matte paper surfaces, matching the feel of real paper tooth.
    var pkTool: PKTool {
        switch activeTool {
        case .pen:
            return PKInkingTool(.pen, color: inkColor, width: activeWidth)
        case .pencil:
            return PKInkingTool(.pencil, color: inkColor, width: activeWidth)
        case .highlighter:
            return PKInkingTool(.marker, color: inkColor.withAlphaComponent(0.4), width: activeWidth * 3.0)
        case .fountainPen:
            if #available(iOS 17, *) {
                return PKInkingTool(.fountainPen, color: inkColor, width: activeWidth)
            } else {
                return PKInkingTool(.pen, color: inkColor, width: activeWidth)
            }
        case .eraser:
            return PKEraserTool(eraserMode.pkEraserType)
        case .lasso:
            return PKLassoTool()
        case .shape:
            // The shape overlay intercepts all input; the canvas uses a pen as fallback.
            return PKInkingTool(.pen, color: inkColor, width: activeWidth)
        }
    }

    /// Active ink color adjusted for the current paper material's absorption.
    /// Eraser and lasso tools are not affected.
    private var inkColor: UIColor {
        let multiplier = currentPaperMaterial.inkAlphaMultiplier
        guard multiplier < 1.0 else { return activeColor }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        activeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r, green: g, blue: b, alpha: a * CGFloat(multiplier))
    }

    /// Convenience: only presets the user has starred.
    var favoritePresets: [ToolPreset] { presets.filter(\.isFavorite) }

    // MARK: - Recent Colors

    /// Maximum number of recent colours to keep.
    private static let maxRecentColors = 8

    /// Adds a colour to the recent-colour strip, removing duplicates and trimming
    /// the oldest entry when the limit is reached.
    func addRecentColor(_ color: UIColor) {
        recentColors.removeAll { isSameColor($0, color) }
        recentColors.insert(color, at: 0)
        if recentColors.count > Self.maxRecentColors {
            recentColors = Array(recentColors.prefix(Self.maxRecentColors))
        }
    }

    private func isSameColor(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        b.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return abs(ar - br) < 0.02 && abs(ag - bg) < 0.02 && abs(ab - bb) < 0.02
    }

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
        static let opacity    = "y2notes.tool.opacity"
        static let toolbarMinimized = "y2notes.tool.toolbarMinimized"
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

        let o = ud.double(forKey: Keys.opacity)
        if o > 0 { activeOpacity = o }

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

        isToolbarMinimized = ud.bool(forKey: Keys.toolbarMinimized)
    }
}
