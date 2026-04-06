import Foundation
import UIKit
import PencilKit

// MARK: - Page Direction

/// Direction of a page navigation request from the canvas.
enum PageDirection {
    case next
    case previous
}

// MARK: - CanvasDelegate

/// Communication protocol from `Y2CanvasViewController` back to its host (SwiftUI or UIKit).
///
/// All methods are called on the main thread.  The delegate should *not* perform
/// expensive work synchronously — queue persistence or analytics off-main.
///
/// This protocol decouples the canvas engine from the hosting layer so that the
/// same `Y2CanvasViewController` can be embedded in SwiftUI (via `Y2CanvasHostingView`)
/// or in a pure UIKit container without any code changes.
protocol CanvasDelegate: AnyObject {

    // MARK: - Drawing State

    /// The drawing data changed (stroke committed, erased, or undo/redo applied).
    ///
    /// - Parameter data: Encoded `PKDrawing` data suitable for persistence.
    ///   Matches the existing JSON-serialised format used by `NoteStore`.
    func canvasDidUpdateDrawing(data: Data)

    /// The canvas's undo manager state changed after a drawing mutation.
    ///
    /// - Parameters:
    ///   - canUndo: Whether the canvas's undo manager has undoable actions.
    ///   - canRedo: Whether the canvas's undo manager has redoable actions.
    func canvasDidChangeUndoState(canUndo: Bool, canRedo: Bool)

    /// The canvas requests an immediate disk flush (e.g. app backgrounding).
    func canvasRequestsSave()

    // MARK: - Navigation

    /// The user performed a page-change gesture (two-finger swipe or edge pan).
    ///
    /// - Parameter direction: The direction of the requested page change.
    func canvasRequestsPageChange(direction: PageDirection)

    /// The user pinched-in to request the page overview grid.
    func canvasRequestsPageOverview()

    // MARK: - Object Layer Changes

    /// Shape objects on the current page were modified.
    func canvasDidUpdateShapes(_ shapes: [ShapeInstance])

    /// Attachment objects on the current page were modified.
    func canvasDidUpdateAttachments(_ attachments: [AttachmentObject])

    /// Widget objects on the current page were modified.
    func canvasDidUpdateWidgets(_ widgets: [NoteWidget])

    /// Sticker objects on the current page were modified.
    func canvasDidUpdateStickers(_ stickers: [StickerInstance])

    /// Text objects on the current page were modified.
    func canvasDidUpdateTextObjects(_ textObjects: [TextObject])

    /// Embedded objects (images, audio clips, stickers, links, text blocks) changed.
    func canvasDidUpdateEmbeddedObjects(_ objects: [CanvasObjectWrapper])
}

// MARK: - Default Implementations

/// Optional delegate methods have default no-op implementations so
/// conformers only need to implement the callbacks they care about.
extension CanvasDelegate {
    func canvasRequestsSave() {}
    func canvasRequestsPageOverview() {}
    func canvasDidUpdateShapes(_ shapes: [ShapeInstance]) {}
    func canvasDidUpdateAttachments(_ attachments: [AttachmentObject]) {}
    func canvasDidUpdateWidgets(_ widgets: [NoteWidget]) {}
    func canvasDidUpdateStickers(_ stickers: [StickerInstance]) {}
    func canvasDidUpdateTextObjects(_ textObjects: [TextObject]) {}
    func canvasDidUpdateEmbeddedObjects(_ objects: [CanvasObjectWrapper]) {}
}
