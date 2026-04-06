import UIKit

// MARK: - Y2ObjectSelectionHandler

/// Manages selection state for embedded canvas objects.
///
/// Responsibilities:
/// - Single-object selection (tap) and deselection (tap outside)
/// - Undo registration for every object mutation
/// - Copy/paste via `UIPasteboard`
/// - Forwarding move and delete events back to the overlay controller
final class Y2ObjectSelectionHandler: NSObject {

    // MARK: - Callbacks

    var onSelectionChanged: ((UUID?) -> Void)?
    var onObjectMoved: ((UUID, CGRect) -> Void)?
    var onObjectDeleted: ((UUID) -> Void)?

    // MARK: - State

    private(set) var selectedID: UUID?
    private weak var overlayView: UIView?

    // MARK: - Undo

    private var undoManager: UndoManager { UndoManager() }

    // MARK: - Init

    init(overlayView: UIView) {
        self.overlayView = overlayView
        super.init()
        attachDismissTapGesture()
    }

    // MARK: - Public API

    func select(id: UUID) {
        guard selectedID != id else { return }
        selectedID = id
        onSelectionChanged?(id)
    }

    func deselect() {
        guard selectedID != nil else { return }
        selectedID = nil
        onSelectionChanged?(nil)
    }

    // MARK: - Copy / Paste support

    /// Serialises the selected object wrapper to the pasteboard.
    func copySelectedObject(wrapper: CanvasObjectWrapper) {
        guard let data = try? JSONEncoder().encode(wrapper) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: "com.y2notes.canvasobject")
    }

    /// Returns a decoded `CanvasObjectWrapper` from the pasteboard if available.
    func pasteObject() -> CanvasObjectWrapper? {
        guard let data = UIPasteboard.general.data(forPasteboardType: "com.y2notes.canvasobject") else { return nil }
        var wrapper = try? JSONDecoder().decode(CanvasObjectWrapper.self, from: data)
        // Assign new UUID so paste creates a distinct object.
        if wrapper != nil {
            let offset: CGFloat = 20
            let shifted = CGRect(
                x: wrapper!.frame.origin.x + offset,
                y: wrapper!.frame.origin.y + offset,
                width: wrapper!.frame.size.width,
                height: wrapper!.frame.size.height
            )
            wrapper = CanvasObjectWrapper(
                id: UUID(),
                frame: shifted,
                rotation: wrapper!.rotation,
                zIndex: wrapper!.zIndex + 1,
                isLocked: wrapper!.isLocked,
                objectType: wrapper!.objectType
            )
        }
        return wrapper
    }

    // MARK: - Undo helpers

    /// Records an undo action for a move operation.
    func registerMoveUndo(
        id: UUID,
        previousFrame: CGRect,
        in manager: UndoManager
    ) {
        manager.registerUndo(withTarget: self) { [weak self] _ in
            self?.onObjectMoved?(id, previousFrame)
        }
        manager.setActionName("Move Object")
    }

    /// Records an undo action for an insert operation.
    func registerInsertUndo(id: UUID, in manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak self] _ in
            self?.onObjectDeleted?(id)
        }
        manager.setActionName("Insert Object")
    }

    /// Records an undo action for a delete operation.
    func registerDeleteUndo(wrapper: CanvasObjectWrapper, in manager: UndoManager) {
        let captured = wrapper
        manager.registerUndo(withTarget: self) { _ in
            // Caller is responsible for re-inserting the captured wrapper.
            _ = captured
        }
        manager.setActionName("Delete Object")
    }

    // MARK: - Dismiss gesture

    private func attachDismissTapGesture() {
        guard let view = overlayView else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapBackground(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func didTapBackground(_ g: UITapGestureRecognizer) {
        let point = g.location(in: overlayView)
        // Deselect if the tap did not land on a registered object view.
        let hitAnyObject = overlayView?.subviews.contains(where: { $0.frame.contains(point) }) ?? false
        if !hitAnyObject { deselect() }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension Y2ObjectSelectionHandler: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}
