import Combine
import Foundation
import UIKit

// MARK: - ToolStateProvider

/// Framework-agnostic protocol for the active drawing tool state.
///
/// Provides reactive access to the current tool, color, width, and opacity
/// without depending on SwiftUI or PencilKit. The concrete PencilKit tool
/// conversion lives in the adapter or store layer.
protocol ToolStateProvider: AnyObject {

    // MARK: - Reactive state

    var activeToolPublisher: AnyPublisher<DrawingTool, Never> { get }
    var activeColorPublisher: AnyPublisher<UIColor, Never> { get }
    var activeWidthPublisher: AnyPublisher<Double, Never> { get }
    var activeOpacityPublisher: AnyPublisher<Double, Never> { get }

    // MARK: - Current values

    var activeTool: DrawingTool { get set }
    var activeColor: UIColor { get set }
    var activeWidth: Double { get set }
    var activeOpacity: Double { get set }
    var eraserSubType: EraserSubType { get set }
    var activeShapeType: ShapeType { get set }
    var activePenSubType: PenSubType { get set }
    var recentColors: [UIColor] { get }
    var presets: [ToolPreset] { get }

    // MARK: - Ephemeral UI state

    var hasActiveSelection: Bool { get set }
    var isFocusModeActive: Bool { get set }
    var isMagicModeActive: Bool { get set }
    var isStudyModeActive: Bool { get set }

    // MARK: - Actions

    func addRecentColor(_ color: UIColor)
    func saveCurrentAsPreset(name: String)
    func applyPreset(_ preset: ToolPreset)
    func deletePreset(id: UUID)

    // MARK: - Configuration

    var widthRange: ClosedRange<CGFloat> { get }
    func clampWidthToPersonality()
}
