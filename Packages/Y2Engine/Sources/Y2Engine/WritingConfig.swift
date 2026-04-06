import Foundation
import UIKit
import PencilKit

// MARK: - Tool Personality

/// Defines the "personality" of each drawing tool — how it responds to pressure,
/// velocity, tilt, and what visual/haptic character it projects.
///
/// PencilKit handles the actual rendering pipeline internally, but we control:
/// - Width ranges (min/max bounds for each tool)
/// - The default width for new users
/// - How the tool maps to PKInkingTool ink types
/// - UI hints (smoothing label, line character description)
///
/// **Design philosophy**: Each tool should feel distinct in the user's hand.
/// A pen is precise and snappy. A pencil is textured and forgiving. A highlighter
/// is broad and transparent. A fountain pen is expressive and calligraphic.
public struct ToolPersonality {
    /// Minimum width the user can select in the toolbar slider (points).
    public let minWidth: CGFloat
    /// Maximum width the user can select in the toolbar slider (points).
    public let maxWidth: CGFloat
    /// Default width for first-time users (points).
    public let defaultWidth: CGFloat
    /// Step increment for the width slider.
    public let widthStep: CGFloat
    /// Human-readable description of the tool's character.
    public let characterDescription: String
    /// Whether this tool benefits from PencilKit's altitude-based variation.
    public let usesTiltShading: Bool
    /// Whether this tool benefits from barrel-roll modulation (Pencil Pro).
    public let usesBarrelRoll: Bool
    /// Opacity multiplier for the tool (1.0 = full opacity, <1 = transparent).
    public let opacityMultiplier: CGFloat
    /// Width multiplier applied to the user-selected width before passing to PKInkingTool.
    /// Highlighter uses 3× to produce broad strokes.
    public let widthMultiplier: CGFloat
    /// The PencilKit ink type for this tool.
    public let pkInkType: PKInkingTool.InkType
}

// MARK: - Tool Personalities

extension ToolPersonality {

    /// **Pen** — Precise, consistent, confident.
    ///
    /// The workhorse tool. Pressure produces modest width variation (1–4×).
    /// Lines are crisp with minimal smoothing. Feels like a good ballpoint:
    /// you put it down, it writes exactly where you point it.
    public static let pen = ToolPersonality(
        minWidth: 0.5,
        maxWidth: 8.0,
        defaultWidth: 2.5,
        widthStep: 0.5,
        characterDescription: "Crisp, precise lines with moderate pressure response",
        usesTiltShading: false,
        usesBarrelRoll: false,
        opacityMultiplier: 1.0,
        widthMultiplier: 1.0,
        pkInkType: .pen
    )

    /// **Pencil** — Textured, soft, sketchable.
    ///
    /// Emulates a graphite pencil. PencilKit provides altitude-based shading
    /// natively — tilting produces broad, light strokes. Pressure variation is
    /// gentler than pen. Lines have visible grain/texture at lower pressures.
    public static let pencil = ToolPersonality(
        minWidth: 0.5,
        maxWidth: 12.0,
        defaultWidth: 3.0,
        widthStep: 0.5,
        characterDescription: "Soft, textured strokes with tilt shading",
        usesTiltShading: true,
        usesBarrelRoll: false,
        opacityMultiplier: 1.0,
        widthMultiplier: 1.0,
        pkInkType: .pencil
    )

    /// **Highlighter** — Broad, transparent, overlay.
    ///
    /// Wide, semi-transparent strokes that overlay existing content without
    /// obscuring it. Uses `.marker` ink type with forced 40% alpha. Width is
    /// multiplied 3× from the user-selected value so a "3pt" highlighter
    /// actually produces a 9pt-wide translucent band.
    public static let highlighter = ToolPersonality(
        minWidth: 2.0,
        maxWidth: 15.0,
        defaultWidth: 5.0,
        widthStep: 1.0,
        characterDescription: "Broad, transparent overlay for marking text",
        usesTiltShading: false,
        usesBarrelRoll: false,
        opacityMultiplier: 0.4,
        widthMultiplier: 3.0,
        pkInkType: .marker
    )

    /// **Fountain Pen** — Expressive, calligraphic, responsive.
    ///
    /// Produces dramatic thick-thin variation based on pressure, velocity, and
    /// (on Pencil Pro) barrel-roll angle. The tool with the widest personality —
    /// it rewards slow, deliberate strokes with rich line weight variation.
    /// Falls back to `.pen` on iOS < 17 where `.fountainPen` isn't available.
    public static let fountainPen: ToolPersonality = {
        if #available(iOS 17, *) {
            return ToolPersonality(
                minWidth: 0.5,
                maxWidth: 10.0,
                defaultWidth: 3.0,
                widthStep: 0.5,
                characterDescription: "Calligraphic strokes with dramatic pressure and roll variation",
                usesTiltShading: false,
                usesBarrelRoll: true,
                opacityMultiplier: 1.0,
                widthMultiplier: 1.0,
                pkInkType: .fountainPen
            )
        } else {
            // Fallback: behaves like pen on older iOS
            return ToolPersonality(
                minWidth: 0.5,
                maxWidth: 10.0,
                defaultWidth: 3.0,
                widthStep: 0.5,
                characterDescription: "Calligraphic strokes with pressure variation",
                usesTiltShading: false,
                usesBarrelRoll: false,
                opacityMultiplier: 1.0,
                widthMultiplier: 1.0,
                pkInkType: .pen
            )
        }
    }()

    /// Returns the personality for a given `DrawingTool`.
    public static func personality(for tool: DrawingTool) -> ToolPersonality? {
        switch tool {
        case .pen:          return .pen
        case .pencil:       return .pencil
        case .highlighter:  return .highlighter
        case .fountainPen:  return .fountainPen
        case .eraser, .lasso, .shape, .sticker, .text:
            return nil  // Non-inking tools have no personality
        }
    }
}

// MARK: - Writing Interaction Config

/// Global configuration constants for the writing interaction layer.
/// These values tune how writing coexists with navigation, how latency is
/// perceived, and what performance guardrails are in place.
public enum WritingConfig {

    // MARK: - Zoom Behaviour

    /// When `true`, the canvas zoom scale is locked while the user is actively
    /// writing (between `canvasViewDidBeginUsingTool` and `canvasViewDidEndUsingTool`).
    /// This prevents accidental zoom drift from multi-touch during writing.
    public static let lockZoomDuringWriting = true

    /// Minimum time (seconds) the canvas must be idle after a stroke ends
    /// before zoom/scroll gestures are re-enabled. Prevents accidental zoom
    /// when lifting the hand between quick successive strokes.
    public static let postStrokeZoomLockDelay: TimeInterval = 0.15

    /// Tolerance for detecting zoom drift during a locked stroke. If the zoom
    /// scale changes by more than this amount while pinch gestures are disabled,
    /// the zoom is clamped back to the pre-stroke level.  0.01 (1%) is small
    /// enough to catch any multi-touch interference but avoids unnecessary
    /// corrections from floating-point rounding.
    public static let zoomDriftTolerance: CGFloat = 0.01

    // MARK: - Finger Rejection

    /// Minimum number of points a finger touch must produce before it's considered
    /// intentional drawing input (when `drawingPolicy == .anyInput`). Helps reject
    /// accidental palm touches that produce 1–2 contact points before lifting.
    public static let fingerMinPointThreshold = 3

    /// Delay (seconds) after Pencil contact ends before finger input is re-enabled
    /// for drawing. When the system detects Apple Pencil, finger touches within
    /// this window are treated as palm/rest contacts rather than drawing input.
    /// Only applies when `drawingPolicy == .pencilOnly`.
    public static let postPencilFingerGuardDelay: TimeInterval = 0.3

    // MARK: - Latency Perception

    /// Whether to use `PKCanvasView.drawingGestureRecognizer.allowedTouchTypes`
    /// to restrict to `.pencil` touches when `pencilOnly` mode is active.
    /// This lets PKCanvasView's first-touch discrimination kick in faster because
    /// it doesn't need to wait to distinguish pencil from finger.
    public static let useTouchTypeFiltering = true

    /// Debounce interval (seconds) between the last drawing change and the
    /// scheduled disk save. Shorter = more responsive "saved" feedback but
    /// more disk writes. Longer = fewer writes but risk of data loss.
    public static let saveDebounceInterval: TimeInterval = 0.8

    /// Debounce interval (seconds) for rapid tab switches before persisting
    /// tab state. Prevents excessive JSON serialization when scrubbing through tabs.
    public static let tabSwitchSaveDebounce: TimeInterval = 1.5

    // MARK: - Performance Guardrails

    /// Maximum number of strokes per page before the canvas shows a subtle
    /// warning indicator. Beyond this point rendering performance may degrade
    /// on lower-tier devices.
    public static let strokeCountWarningThreshold = 2000

    /// Hard limit: if a page exceeds this stroke count, auto-save triggers
    /// immediately and a "flatten older strokes" suggestion appears.
    public static let strokeCountHardLimit = 5000

    /// Maximum drawing data size (bytes) per page before a performance warning.
    /// ~10MB covers most complex drawings; beyond this the serialization cost
    /// on tab switch becomes noticeable.
    public static let maxDrawingDataSize = 10_000_000

    // MARK: - Toolbar Behaviour

    /// Duration (seconds) of continuous drawing before the floating toolbar
    /// fades to reduced opacity. Keeps the toolbar out of the way during
    /// extended writing but visible enough to find.
    public static let toolbarFadeDelay: TimeInterval = 1.5

    /// The reduced opacity the toolbar fades to during active drawing.
    public static let toolbarFadedOpacity: Double = 0.3

    /// Duration (seconds) after stroke ends before toolbar restores to full opacity.
    public static let toolbarRestoreDelay: TimeInterval = 0.5

    /// Opacity the toolbar restores to after drawing ends.
    public static let toolbarFullOpacity: Double = 1.0

    // MARK: - Hold-to-Straighten

    /// Duration (seconds) the pen must be held still at the end of a stroke
    /// for the stroke to be automatically replaced with a clean straight line.
    /// Matches Apple Notes' "draw and hold" timing.
    public static let holdToStraightenDelay: TimeInterval = 0.8

    /// Minimum stroke length (points in canvas coordinates) required before
    /// hold-to-straighten activates. Short taps and dots are left untouched.
    public static let holdToStraightenMinLength: CGFloat = 15

    /// Maximum number of control points used when rebuilding a stroke as a
    /// straight line. Capped to keep the point cloud lightweight; PencilKit
    /// interpolates between control points, so 40 is more than sufficient.
    public static let holdToStraightenMaxPoints: Int = 40

    // MARK: - Transition Effects

    /// Duration of the crossfade animation when switching between tabs.
    public static let tabSwitchCrossfadeDuration: TimeInterval = 0.2

    /// Duration of the page-turn crossfade within a notebook.
    public static let pageTurnCrossfadeDuration: TimeInterval = 0.15
}

// MARK: - Palm Guard State

/// Tracks the timing of Apple Pencil contact to implement a finger rejection
/// guard window. After pencil contact ends, finger touches are suppressed
/// for `postPencilFingerGuardDelay` seconds to prevent accidental palm marks.
///
/// Usage: The CanvasView coordinator updates this on pencil begin/end events,
/// and checks it before allowing finger input in `.anyInput` mode.
public final class PalmGuardState {
    /// Timestamp of the last Apple Pencil stroke end.
    public private(set) var lastPencilEndTime: Date?

    /// Records that a pencil stroke just ended.
    public func pencilStrokeEnded() {
        lastPencilEndTime = Date()
    }

    /// Returns `true` if we're still within the finger rejection guard window.
    public var isInGuardWindow: Bool {
        guard let endTime = lastPencilEndTime else { return false }
        return Date().timeIntervalSince(endTime) < WritingConfig.postPencilFingerGuardDelay
    }

    /// Resets the guard state (e.g., when switching to `.anyInput` mode).
    public func reset() {
        lastPencilEndTime = nil
    }
}

// MARK: - Stroke Performance Monitor

/// Lightweight monitor that tracks stroke count and drawing data size per page.
/// Reports warnings when thresholds are exceeded so the UI can show subtle hints.
@MainActor
public final class StrokePerformanceMonitor: ObservableObject {
    @Published private(set) var strokeCount: Int = 0
    @Published private(set) var drawingDataSize: Int = 0
    @Published private(set) var isNearWarningThreshold = false
    @Published private(set) var isOverHardLimit = false

    public func update(strokeCount: Int, dataSize: Int) {
        self.strokeCount = strokeCount
        self.drawingDataSize = dataSize
        self.isNearWarningThreshold = strokeCount >= WritingConfig.strokeCountWarningThreshold
        self.isOverHardLimit = strokeCount >= WritingConfig.strokeCountHardLimit
    }

    public func reset() {
        strokeCount = 0
        drawingDataSize = 0
        isNearWarningThreshold = false
        isOverHardLimit = false
    }
}
