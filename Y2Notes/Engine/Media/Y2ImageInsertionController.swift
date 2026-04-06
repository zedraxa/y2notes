import UIKit
import PhotosUI
import MobileCoreServices

// MARK: - Y2ImageInsertionDelegate

protocol Y2ImageInsertionDelegate: AnyObject {
    /// Called when one or more images are ready to be placed on the canvas.
    func imageInsertionController(
        _ controller: Y2ImageInsertionController,
        didPrepare objects: [CanvasObjectWrapper]
    )
}

// MARK: - Y2ImageInsertionController

/// Handles all image-sourcing paths: photo library, camera capture, and file import.
///
/// After the user selects image(s) each is:
/// 1. Resized to a maximum of 2048 px on the longest edge.
/// 2. Compressed as JPEG at 0.8 quality.
/// 3. Saved to `Documents/NoteMedia/{noteID}/{objectID}.jpg` via ``MediaFileManager``.
/// 4. Wrapped in a ``CanvasObjectWrapper`` centred on the visible canvas area.
///
/// Conforms to `PHPickerViewControllerDelegate`, `UIImagePickerControllerDelegate`,
/// and `UIDocumentPickerDelegate`.
final class Y2ImageInsertionController: NSObject {

    // MARK: - Config

    private let noteID: UUID
    private let visibleCanvasRect: CGRect
    weak var delegate: Y2ImageInsertionDelegate?
    weak var presentingViewController: UIViewController?

    // MARK: - Constants

    private enum Constants {
        static let maxLongEdge: CGFloat = 2048
        static let jpegQuality: CGFloat = 0.8
        static let defaultImageSize = CGSize(width: 300, height: 300)
    }

    // MARK: - Init

    init(noteID: UUID, visibleCanvasRect: CGRect) {
        self.noteID = noteID
        self.visibleCanvasRect = visibleCanvasRect
    }

    // MARK: - Public API

    /// Presents the PHPicker photo library UI.
    func presentPhotoLibraryPicker(from vc: UIViewController) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentingViewController = vc
        vc.present(picker, animated: true)
    }

    /// Presents the camera capture UI.
    func presentCamera(from vc: UIViewController) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presentingViewController = vc
        vc.present(picker, animated: true)
    }

    /// Presents the document (file) picker for image files.
    func presentFilePicker(from vc: UIViewController) {
        let types: [UTType] = [.png, .jpeg, .heic, .gif, .webP]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        presentingViewController = vc
        vc.present(picker, animated: true)
    }

    // MARK: - Processing

    private func processImages(_ images: [(UIImage, String?)]) {
        guard !images.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var wrappers: [CanvasObjectWrapper] = []
            var zOffset = 0

            for (image, filename) in images {
                let objectID = UUID()
                guard let compressed = self.compress(image: image) else { continue }
                let thumbnail = self.makeThumbnail(from: image)
                let relativePath = (try? MediaFileManager.shared.saveImage(
                    noteID: self.noteID,
                    objectID: objectID,
                    imageData: compressed
                )) ?? ""

                let imageObj = ImageObject(
                    relativePath: relativePath,
                    originalFilename: filename,
                    thumbnailData: thumbnail
                )
                let size = self.displaySize(for: image)
                let wrapper = CanvasObjectWrapper.makeImage(
                    imageObj,
                    centeredIn: self.visibleCanvasRect,
                    size: size
                )
                let shifted = CanvasObjectWrapper(
                    id: objectID,
                    frame: wrapper.frame.offsetBy(
                        dx: CGFloat(zOffset) * 10,
                        dy: CGFloat(zOffset) * 10
                    ),
                    zIndex: zOffset,
                    objectType: wrapper.objectType
                )
                wrappers.append(shifted)
                zOffset += 1
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.imageInsertionController(self, didPrepare: wrappers)
            }
        }
    }

    // MARK: - Image helpers

    private func compress(image: UIImage) -> Data? {
        let resized = resize(image: image, maxLongEdge: Constants.maxLongEdge)
        return resized.jpegData(compressionQuality: Constants.jpegQuality)
    }

    private func resize(image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func makeThumbnail(from image: UIImage) -> Data? {
        let maxDim: CGFloat = 200
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxDim ? maxDim / longEdge : 1
        let thumbSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: thumbSize)) }
        return thumb.jpegData(compressionQuality: 0.6)
    }

    private func displaySize(for image: UIImage) -> CGSize {
        let size = image.size
        let maxDim: CGFloat = 400
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDim else { return size }
        let scale = maxDim / longEdge
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension Y2ImageInsertionController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let group = DispatchGroup()
        var images: [(UIImage, String?)] = []
        let lock = NSLock()

        for result in results {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage {
                    let filename = result.itemProvider.suggestedName
                    lock.lock()
                    images.append((img, filename))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.processImages(images)
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension Y2ImageInsertionController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        processImages([(image, nil)])
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate

extension Y2ImageInsertionController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let images = urls.compactMap { url -> (UIImage, String?)? in
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return nil }
            return (image, url.lastPathComponent)
        }
        processImages(images)
    }
}

// MARK: - UTType compat

private extension UTType {
    static let heic = UTType("public.heic") ?? .image
    static let webP = UTType("public.webp") ?? .image
}
