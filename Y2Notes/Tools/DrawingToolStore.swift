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

    /// The active eraser personality. Changing this resets `eraserWidth` to the
    /// sub-type's default so the first interaction always feels right.
    @Published var eraserSubType: EraserSubType = .standard {
        didSet {
            UserDefaults.standard.set(eraserSubType.rawValue, forKey: Keys.eraserSubType)
            // Snap width to the new sub-type's default when the sub-type changes.
            if oldValue != eraserSubType {
                eraserWidth = eraserSubType.defaultWidth
            }
        }
    }

    /// Tip width in points for the active eraser sub-type.
    /// Only meaningful for bitmap (pixel) sub-types; vector sub-types ignore it.
    @Published var eraserWidth: CGFloat = EraserSubType.standard.defaultWidth {
        didSet { UserDefaults.standard.set(Double(eraserWidth), forKey: Keys.eraserWidth) }
    }

    /// Derived eraser mode (bitmap vs. vector) from the active sub-type.
    /// Retained as a computed property for backward-compatibility with call sites
    /// that still read `eraserMode`.
    var eraserMode: EraserMode { eraserSubType.eraserMode }

    @Published var activeShapeType: ShapeType = .rectangle {
        didSet { UserDefaults.standard.set(activeShapeType.rawValue, forKey: Keys.shapeType) }
    }

    @Published var activeOpacity: Double = 1.0 {
        didSet { UserDefaults.standard.set(activeOpacity, forKey: Keys.opacity) }
    }

    /// The physical character of the pen tool (ballpoint, gel, felt-tip, etc.).
    /// Only applied when `activeTool == .pen`.  Persisted to UserDefaults.
    @Published var activePenSubType: PenSubType = .ballpoint {
        didSet { UserDefaults.standard.set(activePenSubType.rawValue, forKey: Keys.penSubType) }
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

    /// True when the lasso tool is active and the user has selected strokes on
    /// the canvas. Set by the CanvasView coordinator when PencilKit reports a
    /// non-empty tool selection. Causes the floating toolbar to morph into
    /// selection-action mode (cut / copy / delete / recolor).
    /// **Not persisted** — always starts as false.
    @Published var hasActiveSelection: Bool = false

    // MARK: - Sticker State

    /// Whether the sticker library bottom sheet is presented.
    /// **Not persisted** — always starts as false.
    @Published var isStickerLibraryPresented: Bool = false

    /// The ID of the currently selected sticker on the canvas (for manipulation).
    /// **Not persisted** — always starts as nil.
    @Published var activeStickerSelection: UUID?

    // MARK: - Shape Object State

    /// The ID of the currently selected shape object on the canvas.
    /// **Not persisted** — always starts as nil.
    @Published var activeShapeSelection: UUID?

    /// Convenience: true when any shape is selected (used by toolbar morphing).
    var hasActiveShapeSelection: Bool { activeShapeSelection != nil }

    // MARK: - Attachment State

    /// The ID of the currently selected attachment on the canvas.
    /// **Not persisted** — always starts as nil.
    @Published var activeAttachmentSelection: UUID?

    /// Convenience: true when any attachment is selected.
    var hasActiveAttachmentSelection: Bool { activeAttachmentSelection != nil }

    /// Whether the attachment source picker sheet is presented.
    @Published var isAttachmentPickerPresented: Bool = false

    // MARK: - Widget State

    /// The ID of the currently selected widget on the canvas.
    /// **Not persisted** — always starts as nil.
    @Published var activeWidgetSelection: UUID?

    /// Convenience: true when any widget is selected.
    var hasActiveWidgetSelection: Bool { activeWidgetSelection != nil }

    /// Whether the widget picker menu is presented.
    /// **Not persisted** — always starts false.
    @Published var isWidgetPickerPresented: Bool = false

    // MARK: - Recording State

    /// Whether an audio recording is currently in progress.
    /// Drives the toolbar mic→stop morph. **Not persisted** — always starts false.
    @Published var isRecording: Bool = false

    /// Whether the recording session list sheet is presented.
    /// **Not persisted** — always starts false.
    @Published var isRecordingSessionListPresented: Bool = false

    /// The live recording session (mirrors AudioRecordingStore.activeSession).
    /// **Not persisted** — always starts nil.
    @Published var activeRecordingSession: AudioSession?

    // MARK: - Expansion Region State

    /// The ID of the expansion region currently being edited, or nil for the main page.
    /// **Not persisted** — always starts nil.
    @Published var activeExpansionRegionID: UUID?

    /// Whether edge-pull handles are shown on the current page.
    /// **Not persisted** — always starts true (handles visible when editing).
    @Published var isExpansionHandleVisible: Bool = true

    /// Which edge is currently being dragged to create/resize an expansion.
    /// **Not persisted** — always starts nil (no drag in progress).
    @Published var expansionDragEdge: ExpansionEdge?

    /// Whether focus mode is active — dims surroundings, adds vignette,
    /// reduces toolbar opacity, and shows a soft page glow to boost immersion.
    /// **Not persisted** — always starts false (normal UI).
    @Published var isFocusModeActive: Bool = false

    /// The currently active ambient environment scene (rain, lo-fi, night).
    /// `nil` means no ambient scene is active.
    /// **Not persisted** — always starts nil.
    @Published var activeAmbientScene: AmbientScene?

    /// Whether ambient soundscapes are enabled.
    /// When `false` the `AmbientEnvironmentEngine` plays no audio even if a
    /// scene is active.  **Not persisted** — defaults to `true`.
    @Published var isAmbientSoundEnabled: Bool = true

    /// Whether "Magic Mode" is active — writing particles, keyword glow,
    /// underline highlight animation.
    /// Persisted in UserDefaults — default off.
    @Published var isMagicModeActive: Bool = false {
        didSet { UserDefaults.standard.set(isMagicModeActive, forKey: Keys.magicModeActive) }
    }

    /// Whether "Study Mode" is active — heading glow, checklist completion
    /// animation, timer completion pulse.
    /// Persisted in UserDefaults — default off.
    @Published var isStudyModeActive: Bool = false {
        didSet { UserDefaults.standard.set(isStudyModeActive, forKey: Keys.studyModeActive) }
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
            // Apply the pen sub-type's width multiplier so each character feels
            // physically distinct (e.g. felt-tip is 1.6× broader by default).
            let penWidth = activeWidth * Double(activePenSubType.widthMultiplier)
            return PKInkingTool(.pen, color: inkColor, width: penWidth)
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
            return makeEraserTool()
        case .lasso:
            return PKLassoTool()
        case .shape:
            // The shape overlay intercepts all input; the canvas uses a pen as fallback.
            return PKInkingTool(.pen, color: inkColor, width: activeWidth)
        case .sticker:
            // The sticker overlay handles interaction; canvas uses lasso as fallback
            // so accidental touches don't create ink strokes.
            return PKLassoTool()
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

    /// Constructs the `PKEraserTool` for the current sub-type and width.
    /// Centralises eraser tool construction so callers (pkTool, Pencil delegate)
    /// always produce an identical result.
    func makeEraserTool() -> PKEraserTool {
        if #available(iOS 16.4, *) {
            return PKEraserTool(eraserSubType.eraserMode.pkEraserType, width: eraserWidth)
        }
        return PKEraserTool(eraserSubType.eraserMode.pkEraserType)
    }

    /// Convenience: only presets the user has starred.
    var favoritePresets: [ToolPreset] { presets.filter(\.isFavorite) }

    // MARK: - Tool Personality Helpers

    /// The personality of the currently active tool (nil for eraser/lasso).
    var activePersonality: ToolPersonality? {
        ToolPersonality.personality(for: activeTool)
    }

    /// Width range for the current tool, derived from its personality.
    /// Returns a sensible default range for non-inking tools.
    var widthRange: ClosedRange<CGFloat> {
        guard let p = activePersonality else { return 1...20 }
        return p.minWidth...p.maxWidth
    }

    /// Clamps `activeWidth` to the personality range when switching tools.
    /// Call this after changing `activeTool` to ensure the width is valid.
    func clampWidthToPersonality() {
        guard let p = activePersonality else { return }
        let clamped = min(max(activeWidth, Double(p.minWidth)), Double(p.maxWidth))
        if clamped != activeWidth { activeWidth = clamped }
    }

    /// The `WritingEffectConfig` for the current pen state.
    ///
    /// When the active tool is `.pen` the config is derived from `activePenSubType`
    /// (pressure curve, ink flow, taper, pooling).  For all other tools the
    /// default config is returned so the pipeline stays dormant.
    ///
    /// Pass this to `WritingEffectsPipeline.configure(config:color:)` whenever
    /// the tool or sub-type changes.
    var writingEffectConfig: WritingEffectConfig {
        guard activeTool == .pen else { return .default }
        return activePenSubType.makeWritingEffectConfig()
    }

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
            width: activeWidth,
            penSubType: activeTool == .pen ? activePenSubType : nil
        )
        presets.append(preset)
    }

    /// Restores the tool, colour, width, and — for pen presets — sub-type from a saved preset.
    func applyPreset(_ preset: ToolPreset) {
        activeTool   = preset.tool
        activeColor  = preset.uiColor
        activeWidth  = preset.width
        if preset.tool == .pen, let sub = preset.penSubType {
            activePenSubType = sub
        }
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
        static let eraserMode = "y2notes.tool.eraserMode"   // legacy key, no longer written
        static let eraserSubType = "y2notes.tool.eraserSubType"
        static let eraserWidth   = "y2notes.tool.eraserWidth"
        static let shapeType  = "y2notes.tool.shapeType"
        static let presets    = "y2notes.tool.presets"
        static let opacity    = "y2notes.tool.opacity"
        static let toolbarMinimized = "y2notes.tool.toolbarMinimized"
        static let penSubType = "y2notes.tool.penSubType"
        static let magicModeActive  = "y2notes.tool.magicModeActive"
        static let studyModeActive  = "y2notes.tool.studyModeActive"
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

        if let raw = ud.string(forKey: Keys.eraserSubType), let sub = EraserSubType(rawValue: raw) {
            eraserSubType = sub
        } else if let raw = ud.string(forKey: Keys.eraserMode) {
            // Migrate old eraserMode value to the nearest EraserSubType.
            switch raw {
            case "vector": eraserSubType = .stroke
            case "bitmap": eraserSubType = .standard
            default:       break
            }
        }

        let ew = ud.double(forKey: Keys.eraserWidth)
        if ew > 0 { eraserWidth = CGFloat(ew) }

        if let raw = ud.string(forKey: Keys.shapeType), let shape = ShapeType(rawValue: raw) {
            activeShapeType = shape
        }

        if let data = ud.data(forKey: Keys.presets),
           let loaded = try? JSONDecoder().decode([ToolPreset].self, from: data) {
            presets = loaded
        }

        isToolbarMinimized = ud.bool(forKey: Keys.toolbarMinimized)

        if let raw = ud.string(forKey: Keys.penSubType), let sub = PenSubType(rawValue: raw) {
            activePenSubType = sub
        }

        // Magic & Study mode (default off — bool(forKey:) returns false for missing keys).
        isMagicModeActive = ud.bool(forKey: Keys.magicModeActive)
        isStudyModeActive = ud.bool(forKey: Keys.studyModeActive)
    }
}
