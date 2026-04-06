import Foundation
import CoreGraphics

// MARK: - BorderStyle

/// Visual border treatment applied to an image on the canvas.
enum BorderStyle: String, Codable, Equatable, CaseIterable {
    case none
    case thin
    case rounded
    case shadow
}

// MARK: - ImageObject

/// Metadata for an image embedded on the canvas.
///
/// The actual pixel data is stored externally in
/// `Documents/NoteMedia/{noteID}/{objectID}.jpg` and managed by
/// ``MediaFileManager``.  Only a compact thumbnail is kept inline for
/// quick display without disk I/O on every render pass.
struct ImageObject: Codable, Equatable {
    /// External file path managed by ``MediaFileManager``.
    /// Relative to the app's Documents directory.
    var relativePath: String
    /// Original filename from the photo library or file picker.
    var originalFilename: String?
    /// Cropped region within the original image, in normalised coordinates (0…1).
    /// Nil means no crop applied.
    var cropRect: CGRect?
    /// Visual border treatment around the image.
    var borderStyle: BorderStyle
    /// Overall opacity (0.0 = transparent, 1.0 = opaque).
    var opacity: CGFloat
    /// JPEG-compressed thumbnail for quick display (≤ 200×200 px).
    var thumbnailData: Data?

    init(
        relativePath: String,
        originalFilename: String? = nil,
        cropRect: CGRect? = nil,
        borderStyle: BorderStyle = .none,
        opacity: CGFloat = 1.0,
        thumbnailData: Data? = nil
    ) {
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.cropRect = cropRect
        self.borderStyle = borderStyle
        self.opacity = opacity
        self.thumbnailData = thumbnailData
    }

    // MARK: Codable — CGRect is not Codable by default

    enum CodingKeys: String, CodingKey {
        case relativePath, originalFilename, borderStyle, opacity, thumbnailData
        case cropX, cropY, cropWidth, cropHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename)
        borderStyle = try c.decodeIfPresent(BorderStyle.self, forKey: .borderStyle) ?? .none
        opacity = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        thumbnailData = try c.decodeIfPresent(Data.self, forKey: .thumbnailData)

        if let x = try c.decodeIfPresent(CGFloat.self, forKey: .cropX),
           let y = try c.decodeIfPresent(CGFloat.self, forKey: .cropY),
           let w = try c.decodeIfPresent(CGFloat.self, forKey: .cropWidth),
           let h = try c.decodeIfPresent(CGFloat.self, forKey: .cropHeight) {
            cropRect = CGRect(x: x, y: y, width: w, height: h)
        } else {
            cropRect = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(relativePath, forKey: .relativePath)
        try c.encodeIfPresent(originalFilename, forKey: .originalFilename)
        try c.encode(borderStyle, forKey: .borderStyle)
        try c.encode(opacity, forKey: .opacity)
        try c.encodeIfPresent(thumbnailData, forKey: .thumbnailData)

        if let r = cropRect {
            try c.encode(r.origin.x, forKey: .cropX)
            try c.encode(r.origin.y, forKey: .cropY)
            try c.encode(r.size.width, forKey: .cropWidth)
            try c.encode(r.size.height, forKey: .cropHeight)
        }
    }
}
