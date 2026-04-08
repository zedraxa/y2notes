import UIKit
import os

private let storeLogger = Logger(subsystem: "com.y2notes", category: "AttachmentStore")

/// Manages attachment file I/O, thumbnail generation, and image caching.
///
/// File layout:
/// ```
/// Documents/Attachments/{noteID}/{attachmentID}_thumb.jpg   — thumbnail (~15-30 KB)
/// Documents/Attachments/{noteID}/{attachmentID}.{ext}       — full content
/// ```
@MainActor
final class AttachmentStore: ObservableObject {

    // MARK: - Singleton

    static let shared = AttachmentStore()

    // MARK: - Caches

    /// Thumbnail cache – always loaded for visible attachments.
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 20 * 1024 * 1024 // 20 MB
        return cache
    }()

    /// Full-resolution cache – loaded on demand at high zoom.
    private let fullResCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = AttachmentConstants.maxFullResCache
        cache.totalCostLimit = 80 * 1024 * 1024 // 80 MB
        return cache
    }()

    // MARK: - File URLs

    /// Root directory for all attachment files.
    private var attachmentsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Attachments", isDirectory: true)
    }

    /// Per-note directory for attachment files.
    func noteDir(for noteID: UUID) -> URL {
        attachmentsDir.appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    /// Thumbnail file path.
    func thumbnailURL(noteID: UUID, attachmentID: UUID) -> URL {
        noteDir(for: noteID)
            .appendingPathComponent("\(attachmentID.uuidString)_thumb.jpg")
    }

    /// Full content file path.
    func contentURL(noteID: UUID, attachmentID: UUID, ext: String) -> URL {
        noteDir(for: noteID)
            .appendingPathComponent("\(attachmentID.uuidString).\(ext)")
    }

    // MARK: - Directory Management

    /// Ensures the per-note attachment directory exists.
    func ensureDirectory(for noteID: UUID) {
        let dir = noteDir(for: noteID)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Thumbnail Access

    /// Returns a cached thumbnail or loads it from disk. Returns `nil` if not yet generated.
    func thumbnail(for attachmentID: UUID, noteID: UUID) -> UIImage? {
        let key = attachmentID.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let url = thumbnailURL(noteID: noteID, attachmentID: attachmentID)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// Loads a thumbnail asynchronously, calling `completion` on the main queue.
    func loadThumbnailAsync(
        for attachmentID: UUID,
        noteID: UUID,
        completion: @escaping (UIImage?) -> Void
    ) {
        let key = attachmentID.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let url = self.thumbnailURL(noteID: noteID, attachmentID: attachmentID)
            let image: UIImage?
            if let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
                if let img = image {
                    self.thumbnailCache.setObject(img, forKey: key, cost: data.count)
                }
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    // MARK: - Full-Resolution Access

    /// Returns a cached full-res image, or `nil` if not loaded.
    func fullResImage(for attachmentID: UUID) -> UIImage? {
        let key = attachmentID.uuidString as NSString
        return fullResCache.object(forKey: key)
    }

    /// Loads the full-resolution image asynchronously.
    func loadFullResAsync(
        for attachmentID: UUID,
        noteID: UUID,
        ext: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        let key = attachmentID.uuidString as NSString
        if let cached = fullResCache.object(forKey: key) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let url = self.contentURL(noteID: noteID, attachmentID: attachmentID, ext: ext)
            let image: UIImage?
            if let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
                if let img = image {
                    self.fullResCache.setObject(img, forKey: key, cost: data.count)
                }
            } else {
                image = nil
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Evicts all full-resolution images from cache.
    func evictFullResCache() {
        fullResCache.removeAllObjects()
    }

    /// Evicts a specific full-res image.
    func evictFullRes(for attachmentID: UUID) {
        let key = attachmentID.uuidString as NSString
        fullResCache.removeObject(forKey: key)
    }

    // MARK: - Import & Thumbnail Generation

    /// Imports an image as an attachment. Writes the full image and generates a thumbnail.
    /// Returns a configured `AttachmentObject` ready to be placed on a page, or `nil` on failure.
    func importImage(
        _ image: UIImage,
        noteID: UUID,
        position: CGPoint
    ) -> AttachmentObject? {
        ensureDirectory(for: noteID)
        let attachID = UUID()

        // Determine file extension
        let ext = "jpg"

        // Write full resolution
        guard let fullData = image.jpegData(compressionQuality: 0.85) else {
            storeLogger.error("Failed to encode image for attachment \(attachID)")
            return nil
        }
        let fullURL = contentURL(noteID: noteID, attachmentID: attachID, ext: ext)
        do {
            try fullData.write(to: fullURL, options: .atomic)
        } catch {
            storeLogger.error("Failed to write attachment content: \(error.localizedDescription)")
            return nil
        }

        // Generate and write thumbnail
        let thumbImage = generateThumbnail(from: image)
        if let thumbData = thumbImage.jpegData(compressionQuality: AttachmentConstants.thumbnailQuality) {
            let thumbURL = thumbnailURL(noteID: noteID, attachmentID: attachID)
            try? thumbData.write(to: thumbURL, options: .atomic)
            thumbnailCache.setObject(thumbImage, forKey: attachID.uuidString as NSString, cost: thumbData.count)
        }

        // Compute display size preserving aspect ratio
        let aspectRatio = image.size.width / max(image.size.height, 1)
        let defaultW = AttachmentConstants.defaultSize.width
        let displaySize = CGSize(
            width: defaultW,
            height: defaultW / max(aspectRatio, 0.1)
        )

        return AttachmentObject(
            id: attachID,
            type: .image,
            frame: AttachmentFrame(position: position, size: displaySize),
            label: "",
            zIndex: 0,
            aspectRatio: aspectRatio,
            fileExtension: ext
        )
    }

    /// Imports a PDF file as an attachment. Renders the first page as thumbnail.
    func importPDF(
        from sourceURL: URL,
        noteID: UUID,
        position: CGPoint
    ) -> AttachmentObject? {
        ensureDirectory(for: noteID)
        let attachID = UUID()
        let ext = "pdf"

        // Copy PDF to attachment storage
        let destURL = contentURL(noteID: noteID, attachmentID: attachID, ext: ext)
        do {
            if sourceURL.startAccessingSecurityScopedResource() {
                defer { sourceURL.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        } catch {
            storeLogger.error("Failed to copy PDF: \(error.localizedDescription)")
            return nil
        }

        // Render first page as thumbnail
        var aspectRatio: CGFloat = 0.707 // A4 default
        if let pdfDoc = CGPDFDocument(destURL as CFURL),
           let page = pdfDoc.page(at: 1) {
            let mediaBox = page.getBoxRect(.mediaBox)
            aspectRatio = mediaBox.width / max(mediaBox.height, 1)
            let thumbImage = renderPDFPage(page, maxDimension: AttachmentConstants.thumbnailMaxDimension)
            if let thumbData = thumbImage.jpegData(compressionQuality: AttachmentConstants.thumbnailQuality) {
                let thumbURL = thumbnailURL(noteID: noteID, attachmentID: attachID)
                try? thumbData.write(to: thumbURL, options: .atomic)
                thumbnailCache.setObject(thumbImage, forKey: attachID.uuidString as NSString, cost: thumbData.count)
            }
        }

        let defaultW = AttachmentConstants.defaultSize.width
        let displaySize = CGSize(
            width: defaultW,
            height: defaultW / max(aspectRatio, 0.1)
        )

        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        return AttachmentObject(
            id: attachID,
            type: .pdf,
            frame: AttachmentFrame(position: position, size: displaySize),
            label: fileName,
            zIndex: 0,
            aspectRatio: aspectRatio,
            fileExtension: ext
        )
    }

    /// Creates a link attachment (no file stored, just metadata).
    func createLinkAttachment(
        urlString: String,
        label: String,
        position: CGPoint
    ) -> AttachmentObject {
        AttachmentObject(
            id: UUID(),
            type: .link,
            frame: AttachmentFrame(
                position: position,
                size: CGSize(width: 200, height: 80)
            ),
            label: label.isEmpty ? urlString : label,
            zIndex: 0,
            aspectRatio: 2.5,
            fileExtension: "",
            linkURL: urlString
        )
    }

    // MARK: - Deletion

    /// Removes attachment files from disk.
    func deleteAttachmentFiles(noteID: UUID, attachmentID: UUID, ext: String) {
        let thumbURL = thumbnailURL(noteID: noteID, attachmentID: attachmentID)
        try? FileManager.default.removeItem(at: thumbURL)
        if !ext.isEmpty {
            let fullURL = contentURL(noteID: noteID, attachmentID: attachmentID, ext: ext)
            try? FileManager.default.removeItem(at: fullURL)
        }
        thumbnailCache.removeObject(forKey: attachmentID.uuidString as NSString)
        fullResCache.removeObject(forKey: attachmentID.uuidString as NSString)
    }

    // MARK: - Private Helpers

    /// Generates a thumbnail from a source image, fitting within `thumbnailMaxDimension`.
    private func generateThumbnail(from source: UIImage) -> UIImage {
        let maxDim = AttachmentConstants.thumbnailMaxDimension
        let sourceSize = source.size
        let scale: CGFloat
        if sourceSize.width > sourceSize.height {
            scale = maxDim / sourceSize.width
        } else {
            scale = maxDim / sourceSize.height
        }
        if scale >= 1.0 { return source }
        let targetSize = CGSize(
            width: ceil(sourceSize.width * scale),
            height: ceil(sourceSize.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Renders a single PDF page to a UIImage.
    private func renderPDFPage(_ page: CGPDFPage, maxDimension: CGFloat) -> UIImage {
        let mediaBox = page.getBoxRect(.mediaBox)
        let scale: CGFloat
        if mediaBox.width > mediaBox.height {
            scale = maxDimension / mediaBox.width
        } else {
            scale = maxDimension / mediaBox.height
        }
        let targetSize = CGSize(
            width: ceil(mediaBox.width * scale),
            height: ceil(mediaBox.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.setFillColor(UIColor.white.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: targetSize))
            cgCtx.saveGState()
            cgCtx.translateBy(x: 0, y: targetSize.height)
            cgCtx.scaleBy(x: scale, y: -scale)
            cgCtx.drawPDFPage(page)
            cgCtx.restoreGState()
        }
    }
}
