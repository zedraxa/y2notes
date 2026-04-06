import Foundation

// MARK: - Y2LinkMetadataFetcher

/// Fetches Open Graph and HTML metadata from a URL to populate ``LinkObject``.
///
/// Runs a single `URLSession` data task, parses the minimal HTML needed for
/// title, description, og:image, and favicon, then returns a ``LinkObject``.
final class Y2LinkMetadataFetcher {

    // MARK: - Constants

    private enum Constants {
        static let timeout: TimeInterval = 8
        static let maxPreviewImageBytes = 500_000
        static let faviconSize: CGFloat = 32
    }

    // MARK: - Public API

    typealias Completion = (Result<LinkObject, Error>) -> Void

    func fetch(url: URL, completion: @escaping Completion) {
        var request = URLRequest(url: url, timeoutInterval: Constants.timeout)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) Y2Notes/1.0",
                         forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                completion(.failure(FetchError.noData))
                return
            }
            var link = LinkObject(urlString: url.absoluteString, displayDomain: url.host)
            link.title = self?.extractOGContent(tag: "og:title", html: html)
                ?? self?.extractHTMLTitle(html: html)
            let ogImageURL = self?.extractOGContent(tag: "og:image", html: html)
                .flatMap { URL(string: $0) }

            // Fetch favicon and og:image concurrently.
            let group = DispatchGroup()
            let lock = NSLock()

            if let faviconURL = self?.faviconURL(for: url) {
                group.enter()
                URLSession.shared.dataTask(with: faviconURL) { data, _, _ in
                    if let data {
                        lock.lock()
                        link.faviconData = data
                        lock.unlock()
                    }
                    group.leave()
                }.resume()
            }

            if let imgURL = ogImageURL {
                group.enter()
                URLSession.shared.dataTask(with: imgURL) { data, _, _ in
                    if let data, data.count < Constants.maxPreviewImageBytes {
                        lock.lock()
                        link.previewImageData = data
                        lock.unlock()
                    }
                    group.leave()
                }.resume()
            }

            group.notify(queue: .global(qos: .utility)) {
                completion(.success(link))
            }
        }.resume()
    }

    // MARK: - HTML parsing

    private func extractOGContent(tag: String, html: String) -> String? {
        // Matches <meta property="og:title" content="..." /> in any attribute order.
        let pattern = #"<meta[^>]+property=["\']"# + tag + #"["\'][^>]+content=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            // Try reversed attribute order.
            let alt = #"<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']"# + tag + #"["\']"#
            guard let r2 = try? NSRegularExpression(pattern: alt, options: .caseInsensitive),
                  let m2 = r2.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m2.range(at: 1), in: html) else { return nil }
            return String(html[r]).htmlDecoded
        }
        return String(html[range]).htmlDecoded
    }

    private func extractHTMLTitle(html: String) -> String? {
        let pattern = #"<title[^>]*>([^<]+)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range]).htmlDecoded
    }

    private func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        return components.url
    }
}

// MARK: - Error

private enum FetchError: Error { case noData }

// MARK: - HTML decoding

private extension String {
    var htmlDecoded: String {
        var result = self
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
