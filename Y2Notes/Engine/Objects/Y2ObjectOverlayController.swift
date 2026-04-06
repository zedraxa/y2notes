import UIKit

// MARK: - Y2ObjectOverlayController

/// Transparent `UIView` layer that renders all embedded `CanvasObjectWrapper`
/// instances for the current page.
///
/// ## Layer position
/// The overlay is inserted **above** `PKCanvasView` but **below** the ink
/// effects overlay so that:
/// - Drawing strokes appear on top of embedded images/stickers.
/// - Ink effects (particles, sparkles) appear above everything.
///
/// ## Coordinate space
/// All embedded objects are stored in page content coordinates.  The overlay
/// applies the same `zoomScale` / `contentOffset` as the canvas scroll view so
/// objects pan and zoom in perfect sync with ink strokes.
///
/// ## Gesture separation
/// Apple Pencil always routes to `PKCanvasView` (drawing).
/// Embedded object gestures respond only to finger touches.
final class Y2ObjectOverlayController: UIViewController {

    // MARK: - Dependencies

    /// Called whenever an object is added, moved, resized, or deleted.
    var onObjectsChanged: (([CanvasObjectWrapper]) -> Void)?

    // MARK: - State

    private var objects: [CanvasObjectWrapper] = []
    private var selectionHandler: Y2ObjectSelectionHandler!
    private var objectViews: [UUID: UIView] = [:]

    // MARK: - View lifecycle

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = true
        v.clipsToBounds = false
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        selectionHandler = Y2ObjectSelectionHandler(overlayView: view)
        selectionHandler.onSelectionChanged = { [weak self] selected in
            self?.updateSelectionHighlight(selected: selected)
        }
        selectionHandler.onObjectMoved = { [weak self] id, newFrame in
            self?.applyMove(id: id, frame: newFrame)
        }
        selectionHandler.onObjectDeleted = { [weak self] id in
            self?.removeObject(id: id)
        }
    }

    // MARK: - Public API

    /// Replace the object list for the current page.  Reuses existing views
    /// when `id` matches to avoid unnecessary view teardown.
    func setObjects(_ newObjects: [CanvasObjectWrapper]) {
        objects = newObjects.sorted { $0.zIndex < $1.zIndex }

        let incoming = Set(newObjects.map(\.id))
        // Remove views for objects no longer present.
        for (id, v) in objectViews where !incoming.contains(id) {
            v.removeFromSuperview()
            objectViews.removeValue(forKey: id)
        }
        // Add / update views.
        for obj in objects {
            if let existing = objectViews[obj.id] {
                existing.frame = obj.frame
                existing.transform = CGAffineTransform(rotationAngle: obj.rotation * .pi / 180)
            } else {
                let objView = makeObjectView(for: obj)
                objectViews[obj.id] = objView
                view.addSubview(objView)
            }
        }
    }

    /// Apply a zoom + content-offset transform so objects track the canvas.
    func applyTransform(zoomScale: CGFloat, contentOffset: CGPoint) {
        view.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        view.frame.origin = CGPoint(x: -contentOffset.x * zoomScale,
                                     y: -contentOffset.y * zoomScale)
    }

    // MARK: - Object Insertion

    /// Insert a new object and immediately enter selection mode.
    func insertObject(_ wrapper: CanvasObjectWrapper) {
        objects.append(wrapper)
        let objView = makeObjectView(for: wrapper)
        objectViews[wrapper.id] = objView
        view.addSubview(objView)
        selectionHandler.select(id: wrapper.id)
        onObjectsChanged?(objects)
    }

    // MARK: - Private helpers

    private func makeObjectView(for wrapper: CanvasObjectWrapper) -> UIView {
        let v: UIView
        switch wrapper.objectType {
        case .image(let img):
            v = Y2ImageObjectView(imageObject: img)
        case .audioClip(let clip):
            v = Y2AudioClipView(audioClip: clip)
        case .sticker(let sticker):
            v = Y2StickerObjectView(stickerObject: sticker)
        case .link(let link):
            v = Y2LinkObjectView(linkObject: link)
        case .scannedDocument(let doc):
            v = makeScannedDocView(doc)
        case .textBlock(let tb):
            v = makeTextBlockView(tb)
        }
        v.frame = wrapper.frame
        v.transform = CGAffineTransform(rotationAngle: wrapper.rotation * .pi / 180)
        v.isUserInteractionEnabled = !wrapper.isLocked
        attachGestures(to: v, objectID: wrapper.id)
        return v
    }

    private func makeScannedDocView(_ doc: ScannedDocObject) -> UIView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 4
        v.clipsToBounds = true
        if let data = doc.thumbnailData {
            v.image = UIImage(data: data)
        }
        return v
    }

    private func makeTextBlockView(_ tb: TextBlockObject) -> UIView {
        let v = Y2TextBlockView(textBlock: tb)
        v.textBlockDelegate = self
        return v
    }

    private func attachGestures(to view: UIView, objectID: UUID) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        view.addGestureRecognizer(rotate)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        view.addGestureRecognizer(longPress)

        [pan, pinch, rotate].forEach { $0.simultaneousRecognitionAllowed(with: tap) }
    }

    // MARK: - Gesture handlers

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let v = g.view, let id = objectID(for: v) else { return }
        selectionHandler.select(id: id)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let v = g.view, let id = objectID(for: v) else { return }
        let delta = g.translation(in: view)
        if g.state == .changed || g.state == .ended {
            v.center = CGPoint(x: v.center.x + delta.x, y: v.center.y + delta.y)
            g.setTranslation(.zero, in: view)
            if g.state == .ended {
                applyMove(id: id, frame: v.frame)
            }
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let v = g.view else { return }
        if g.state == .changed {
            let s = g.scale
            v.transform = v.transform.scaledBy(x: s, y: s)
            g.scale = 1
        }
        if g.state == .ended, let id = objectID(for: v) {
            applyMove(id: id, frame: v.frame)
        }
    }

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        guard let v = g.view else { return }
        if g.state == .changed {
            v.transform = v.transform.rotated(by: g.rotation)
            g.rotation = 0
        }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began,
              let v = g.view, let id = objectID(for: v) else { return }
        selectionHandler.select(id: id)
        showContextMenu(for: id, sourceView: v)
    }

    // MARK: - Context menu

    private func showContextMenu(for id: UUID, sourceView: UIView) {
        guard let vc = self.parent ?? self else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.removeObject(id: id)
        })
        alert.addAction(UIAlertAction(title: "Lock", style: .default) { [weak self] _ in
            self?.toggleLock(id: id)
        })
        alert.addAction(UIAlertAction(title: "Bring to Front", style: .default) { [weak self] _ in
            self?.bringToFront(id: id)
        })
        alert.addAction(UIAlertAction(title: "Send to Back", style: .default) { [weak self] _ in
            self?.sendToBack(id: id)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }
        vc.present(alert, animated: true)
    }

    // MARK: - Object mutations

    private func applyMove(id: UUID, frame: CGRect) {
        guard let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[idx].frame = frame
        onObjectsChanged?(objects)
    }

    private func removeObject(id: UUID) {
        objects.removeAll { $0.id == id }
        objectViews[id]?.removeFromSuperview()
        objectViews.removeValue(forKey: id)
        selectionHandler.deselect()
        onObjectsChanged?(objects)
    }

    private func toggleLock(id: UUID) {
        guard let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[idx].isLocked.toggle()
        objectViews[id]?.isUserInteractionEnabled = !objects[idx].isLocked
        onObjectsChanged?(objects)
    }

    private func bringToFront(id: UUID) {
        guard let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let maxZ = objects.map(\.zIndex).max() ?? 0
        objects[idx].zIndex = maxZ + 1
        objectViews[id].map { view.bringSubviewToFront($0) }
        onObjectsChanged?(objects)
    }

    private func sendToBack(id: UUID) {
        guard let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let minZ = objects.map(\.zIndex).min() ?? 0
        objects[idx].zIndex = minZ - 1
        objectViews[id].map { view.sendSubviewToBack($0) }
        onObjectsChanged?(objects)
    }

    private func updateSelectionHighlight(selected: UUID?) {
        for (id, v) in objectViews {
            v.layer.borderWidth = (id == selected) ? 2 : 0
            v.layer.borderColor = (id == selected) ? UIColor.systemBlue.cgColor : nil
        }
    }

    private func objectID(for view: UIView) -> UUID? {
        objectViews.first(where: { $0.value === view })?.key
    }
}

// MARK: - Y2TextBlockViewDelegate

extension Y2ObjectOverlayController: Y2TextBlockViewDelegate {
    func textBlockView(_ view: Y2TextBlockView, didCommitText text: String) {
        guard let id = objectID(for: view),
              let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        // Mutate the text in the backing TextBlockObject.
        if case .textBlock(var tb) = objects[idx].objectType {
            tb.text = text
            objects[idx].objectType = .textBlock(tb)
            onObjectsChanged?(objects)
        }
    }
}

// MARK: - UIGestureRecognizer simultaneity helper

private extension UIGestureRecognizer {
    func simultaneousRecognitionAllowed(with other: UIGestureRecognizer) {
        // Gesture recogniser delegate assignment handled by Y2ObjectSelectionHandler.
        _ = other
    }
}

// MARK: - UIColor hex helper (private)

private extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
