import UIKit
import PencilKit

// MARK: - PencilActionDelegate

/// Actions dispatched by PencilInteractionCoordinator to the hosting canvas.
///
/// All methods are called on the main thread.
protocol PencilActionDelegate: AnyObject {
    /// Pencil double-tap or squeeze action: switch to / toggle the eraser tool.
    func pencilDidRequestSwitchToEraser()

    /// Pencil double-tap or squeeze action: switch back to the previously active inking tool.
    func pencilDidRequestSwitchToPreviousTool()

    /// Pencil double-tap or squeeze action: display the contextual tool palette.
    /// - Parameter anchorPoint: Pencil tip position in the *canvas* coordinate space.
    func pencilDidRequestContextualPalette(at anchorPoint: CGPoint)

    /// Pencil double-tap or squeeze action: trigger undo.
    func pencilDidRequestUndo()

    /// Pencil double-tap or squeeze action: trigger redo.
    func pencilDidRequestRedo()

    /// Apple Pencil hover position changed.
    /// - Parameters:
    ///   - position: Current hover location in canvas coordinates, or `nil` when hover ends.
    ///   - altitude: Pencil altitude angle in radians (0 = flat, π/2 = perpendicular).
    ///   - azimuth:  Pencil azimuth angle in radians.
    func pencilHoverChanged(position: CGPoint?, altitude: CGFloat, azimuth: CGFloat)

    /// Barrel-roll angle changed (Apple Pencil Pro, iOS 17.5+).
    /// - Parameter angle: Roll in radians; 0 = neutral orientation.
    func pencilBarrelRollChanged(angle: CGFloat)
}

// MARK: - PencilInteractionCoordinator

/// Attaches Apple Pencil interaction layers to a `PKCanvasView`.
///
/// **Feature availability summary**
/// | Feature          | Pencil model       | Min OS     |
/// |------------------|--------------------|------------|
/// | Double-tap       | Pencil 2nd gen+    | iOS 12.1   |
/// | Preferred action | any                | iOS 12.1   |
/// | Squeeze          | Pencil Pro         | iOS 17.5   |
/// | Hover preview    | M2+ iPad / device  | iOS 16.1   |
/// | Barrel roll      | Pencil Pro         | iOS 17.5   |
///
/// All features degrade gracefully on unsupported hardware or OS versions.
final class PencilInteractionCoordinator: NSObject {

    // MARK: Properties

    weak var delegate: PencilActionDelegate?

    /// Most recent pencil contact/hover position in the canvas coordinate space.
    private(set) var lastPencilPosition: CGPoint = .zero

    private weak var canvas: PKCanvasView?

    // MARK: Attachment

    /// Wire all pencil interactions to `canvas`. Call once from `makeUIView`.
    func attach(to canvas: PKCanvasView) {
        self.canvas = canvas
        attachPencilInteraction(to: canvas)
        attachHoverRecognizer(to: canvas)
        attachBarrelRollObserver(to: canvas)
    }

    // MARK: - UIPencilInteraction (double-tap + squeeze)

    private func attachPencilInteraction(to view: UIView) {
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        view.addInteraction(interaction)
    }

    // MARK: - Hover (iOS 16.1+)

    private func attachHoverRecognizer(to view: UIView) {
        guard #available(iOS 16.1, *) else { return }
        // UIHoverGestureRecognizer gained altitudeAngle / azimuthAngle(in:) in iOS 16.1,
        // enabling Apple Pencil hover detection on M2+ iPad Pro.
        let recognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        recognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(recognizer)
    }

    @available(iOS 16.1, *)
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let canvas = canvas else { return }
        switch gesture.state {
        case .began, .changed:
            let position = gesture.location(in: canvas)
            lastPencilPosition = position
            let altitude = gesture.altitudeAngle
            let azimuth  = gesture.azimuthAngle(in: canvas)
            delegate?.pencilHoverChanged(position: position, altitude: altitude, azimuth: azimuth)
        case .ended, .cancelled, .failed:
            delegate?.pencilHoverChanged(position: nil, altitude: 0, azimuth: 0)
        default:
            break
        }
    }

    // MARK: - Barrel Roll (Apple Pencil Pro, iOS 17.5+)

    private func attachBarrelRollObserver(to view: UIView) {
        guard #available(iOS 17.5, *) else { return }
        let observer = PencilBarrelRollObserver()
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan   = false
        observer.delaysTouchesEnded   = false
        observer.onBarrelRoll = { [weak self] angle, position in
            self?.lastPencilPosition = position
            self?.delegate?.pencilBarrelRollChanged(angle: angle)
        }
        view.addGestureRecognizer(observer)
    }

    // MARK: - Preferred Action Dispatch

    private func dispatch(preferredAction: UIPencilPreferredAction) {
        switch preferredAction {
        case .switchEraser:
            delegate?.pencilDidRequestSwitchToEraser()
        case .switchPrevious:
            delegate?.pencilDidRequestSwitchToPreviousTool()
        case .showColorPalette:
            delegate?.pencilDidRequestContextualPalette(at: lastPencilPosition)
        case .ignore:
            break
        @unknown default:
            // A new system action added in a future OS; treat as "show contextual palette"
            // so the user gets a useful response regardless.
            delegate?.pencilDidRequestContextualPalette(at: lastPencilPosition)
        }
    }
}

// MARK: - UIPencilInteractionDelegate

extension PencilInteractionCoordinator: UIPencilInteractionDelegate {

    // Double-tap — Apple Pencil 2nd gen+, iOS 12.1+ (within our iOS 16 deployment target).
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        dispatch(preferredAction: UIPencilInteraction.preferredTapAction)
    }

    // Squeeze — Apple Pencil Pro, iOS 17.5+.
    @available(iOS 17.5, *)
    func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        // Only act on the terminal phase so the action fires exactly once per squeeze.
        guard squeeze.phase == .ended else { return }
        dispatch(preferredAction: UIPencilInteraction.preferredSqueezeAction)
    }
}

// MARK: - PencilBarrelRollObserver

/// A passive UIGestureRecognizer that reads `UITouch.rollAngle` from Apple Pencil Pro
/// touches without consuming or cancelling them.  Always ends in `.failed` so
/// PKCanvasView wins every gesture competition.
///
/// Available iOS 17.5+ (Apple Pencil Pro introduces barrel roll hardware support).
@available(iOS 17.5, *)
private final class PencilBarrelRollObserver: UIGestureRecognizer {

    /// Reports `(rollAngle, positionInView)` whenever a pencil touch updates roll.
    var onBarrelRoll: ((CGFloat, CGPoint) -> Void)?

    // Never prevent other recognizers from recognising.
    override func canPreventGestureRecognizer(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePreventedBy(_ other: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of other: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        inspectForRoll(touches)
        // Stay .possible so touchesMoved continues to arrive.
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        inspectForRoll(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    private func inspectForRoll(_ touches: Set<UITouch>) {
        guard let view = view else { return }
        for touch in touches where touch.type == .pencil {
            let angle    = touch.rollAngle
            let position = touch.location(in: view)
            onBarrelRoll?(angle, position)
        }
    }
}
