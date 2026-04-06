import Foundation
import CoreGraphics

// MARK: - LinkDisplayStyle

/// Visual presentation of a link on the canvas.
enum LinkDisplayStyle: String, Codable, Equatable, CaseIterable {
    /// Compact pill showing favicon + truncated title (default).
    case chip
    /// Expanded card with preview image, title, and domain.
    case card
    /// Plain underlined text link.
    case inline
}

// MARK: - LinkObject

/// Metadata for a web or in-app link embedded on the canvas.
///
/// Preview metadata (title, favicon) is fetched once by ``Y2LinkMetadataFetcher``
/// and stored here so the link renders offline without additional network requests.
struct LinkObject: Codable, Equatable {
    /// The destination URL.
    var urlString: String
    /// Resolved URL built from ``urlString``.
    var url: URL? { URL(string: urlString) }
    /// Open Graph or HTML page title.
    var title: String?
    /// Small favicon PNG data (≤ 32×32 px, JPEG or PNG).
    var faviconData: Data?
    /// Link preview hero image (og:image), JPEG-compressed ≤ 480px wide.
    var previewImageData: Data?
    /// Root domain extracted from the URL for display (e.g. "github.com").
    var displayDomain: String?
    /// How the link should be visually presented on the canvas.
    var displayStyle: LinkDisplayStyle

    init(
        urlString: String,
        title: String? = nil,
        faviconData: Data? = nil,
        previewImageData: Data? = nil,
        displayDomain: String? = nil,
        displayStyle: LinkDisplayStyle = .chip
    ) {
        self.urlString = urlString
        self.title = title
        self.faviconData = faviconData
        self.previewImageData = previewImageData
        self.displayDomain = displayDomain
        self.displayStyle = displayStyle
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case urlString, title, faviconData, previewImageData, displayDomain, displayStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try c.decode(String.self, forKey: .urlString)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        faviconData = try c.decodeIfPresent(Data.self, forKey: .faviconData)
        previewImageData = try c.decodeIfPresent(Data.self, forKey: .previewImageData)
        displayDomain = try c.decodeIfPresent(String.self, forKey: .displayDomain)
        displayStyle = try c.decodeIfPresent(LinkDisplayStyle.self, forKey: .displayStyle) ?? .chip
    }
}
