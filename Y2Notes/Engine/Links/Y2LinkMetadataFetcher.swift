import Foundation
import WebKit

// MARK: - Y2LinkMetadataFetcher

/// Fetches Open Graph and HTML metadata from a URL using a headless `WKWebView`
/// for richer JavaScript-rendered metadata extraction.
///
/// Falls back to a lightweight `URLSession`-based HTML parse when `WKWebView`
/// is unavailable (e.g. background context).
final class Y2LinkMetadataFetcher: NSObject {

    // MARK: - Constants

    private enum Constants {
        static let timeout: TimeInterval = 10
        static let maxPreviewImageBytes = 500_000
        static let faviconSize: CGFloat = 32
        /// JavaScript that extracts OG/meta tags after the page has rendered.
        static let extractionJS = """
        (function() {
            function og(p) {
                var el = document.querySelector('meta[property="' + p + '"]')
                     || document.querySelector('meta[name="' + p + '"]');
                return el ? el.getAttribute('content') || '' : '';
            }
            function meta(n) {
                var el = document.querySelector('meta[name="' + n + '"]');
                return el ? el.getAttribute('content') || '' : '';
            }
            return JSON.stringify({
                title: og('og:title') || document.title || '',
                description: og('og:description') || meta('description') || '',
                image: og('og:image'),
                favicon: (function() {
                    var link = document.querySelector('link[rel~="icon"]')
                            || document.querySelector('link[rel="shortcut icon"]');
                    return link ? link.href : '';
                })()
            });
        })();
        """
    }

    // MARK: - Internal state

    private var webView: WKWebView?
    private var pendingCompletion: Completion?
    private var pendingURL: URL?
    private var timeoutWorkItem: DispatchWorkItem?

    // MARK: - Public API

    typealias Completion = (Result<LinkObject, Error>) -> Void

    /// Fetch metadata from `url`.  Uses a headless WKWebView on the main thread
    /// to support JavaScript-rendered pages, with URLSession fallback.
    func fetch(url: URL, completion: @escaping Completion) {
        if Thread.isMainThread {
            startWKWebViewFetch(url: url, completion: completion)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startWKWebViewFetch(url: url, completion: completion)
            }
        }
    }

    // MARK: - WKWebView fetch

    private func startWKWebViewFetch(url: URL, completion: @escaping Completion) {
        pendingCompletion = completion
        pendingURL = url

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) Y2Notes/1.0"
        self.webView = wv

        let request = URLRequest(url: url, timeoutInterval: Constants.timeout)
        wv.load(request)

        // Safety timeout — tear down if page never finishes loading.
        let timeout = DispatchWorkItem { [weak self] in
            self?.fallbackToURLSession(url: url, completion: completion)
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.timeout, execute: timeout)
    }

    private func extractMetadata() {
        guard let wv = webView, let url = pendingURL, let completion = pendingCompletion else { return }
        timeoutWorkItem?.cancel()

        wv.evaluateJavaScript(Constants.extractionJS) { [weak self] result, error in
            guard let self else { return }
            self.tearDownWebView()

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                // Fall back to URLSession parse if JS extraction fails.
                self.fallbackToURLSession(url: url, completion: completion)
                return
            }

            var link = LinkObject(urlString: url.absoluteString, displayDomain: url.host)
            let title = meta["title"]?.nilIfEmpty
            link.title = title
            link.linkDescription = meta["description"]?.nilIfEmpty

            // Fetch favicon and og:image concurrently.
            let group = DispatchGroup()
            let lock = NSLock()

            let faviconURLString = meta["favicon"]?.nilIfEmpty
            let ogImageURLString = meta["image"]?.nilIfEmpty

            if let favStr = faviconURLString, let favURL = URL(string: favStr, relativeTo: url) {
                group.enter()
                URLSession.shared.dataTask(with: favURL.absoluteURL) { data, _, _ in
                    if let data {
                        lock.lock()
                        link.faviconData = data
                        lock.unlock()
                    }
                    group.leave()
                }.resume()
            } else if let defaultFav = self.faviconURL(for: url) {
                group.enter()
                URLSession.shared.dataTask(with: defaultFav) { data, _, _ in
                    if let data {
                        lock.lock()
                        link.faviconData = data
                        lock.unlock()
                    }
                    group.leave()
                }.resume()
            }

            if let imgStr = ogImageURLString, let imgURL = URL(string: imgStr, relativeTo: url) {
                group.enter()
                URLSession.shared.dataTask(with: imgURL.absoluteURL) { data, _, _ in
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
        }
    }

    private func tearDownWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        pendingCompletion = nil
        pendingURL = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    // MARK: - URLSession fallback

    private func fallbackToURLSession(url: URL, completion: @escaping Completion) {
        tearDownWebView()

        var request = URLRequest(url: url, timeoutInterval: Constants.timeout)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) Y2Notes/1.0",
                         forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
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
            link.linkDescription = self?.extractOGContent(tag: "og:description", html: html)
                ?? self?.extractMetaDescription(html: html)
            let ogImageURL = self?.extractOGContent(tag: "og:image", html: html)
                .flatMap { URL(string: $0) }

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

    // MARK: - HTML parsing (fallback)

    private func extractOGContent(tag: String, html: String) -> String? {
        let pattern = #"<meta[^>]+property=["\']"# + tag + #"["\'][^>]+content=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
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

    private func extractMetaDescription(html: String) -> String? {
        let pattern = #"<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            let alt = #"<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']description["\']"#
            guard let r2 = try? NSRegularExpression(pattern: alt, options: .caseInsensitive),
                  let m2 = r2.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m2.range(at: 1), in: html) else { return nil }
            return String(html[r]).htmlDecoded
        }
        return String(html[range]).htmlDecoded
    }

    private func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        return components.url
    }
}

// MARK: - WKNavigationDelegate

extension Y2LinkMetadataFetcher: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Small delay to allow JS-rendered content to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.extractMetadata()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let url = pendingURL, let completion = pendingCompletion else { return }
        fallbackToURLSession(url: url, completion: completion)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let url = pendingURL, let completion = pendingCompletion else { return }
        fallbackToURLSession(url: url, completion: completion)
    }
}

// MARK: - Error

private enum FetchError: Error { case noData }

// MARK: - String helpers

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

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
