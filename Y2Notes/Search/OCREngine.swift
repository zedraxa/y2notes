import Vision
import PencilKit
import UIKit

// MARK: - OCREngine

/// Runs on-device handwriting recognition on a `PKDrawing` using the Vision framework.
///
/// `recognizeText(in:pageSize:)` renders the drawing to a raster image and submits it
/// to `VNRecognizeTextRequest` with the "accurate" recognition level and language
/// correction enabled.  Results from all strokes across the canvas are joined into a
/// single string that `NoteStore` stores in `Note.ocrText` for use by `SearchService`
/// and the in-document find bar.
///
/// **Threading:** All work is dispatched on a background `Task.detached` with
/// `.utility` priority.  The async entry point suspends the caller until the
/// Vision pass completes and then returns on the caller's executor.
final class OCREngine {

    // MARK: - Public API

    /// Recognises all handwriting in `drawing` rendered at `pageSize`.
    ///
    /// - Parameters:
    ///   - drawing:  The PencilKit drawing to analyse.
    ///   - pageSize: The canonical canvas size used to produce a stable rendering
    ///               that matches how the user sees their strokes.
    /// - Returns: Recognised words separated by spaces, or an empty string when
    ///   the drawing has no strokes or Vision finds nothing.
    static func recognizeText(in drawing: PKDrawing, pageSize: CGSize) async -> String {
        // Skip the expensive Vision pass when there is nothing to recognise.
        guard !drawing.strokes.isEmpty else { return "" }

        return await Task.detached(priority: .utility) {
            let renderRect = CGRect(origin: .zero, size: pageSize)
            // Scale 1× for recognition — Vision operates on the pixel grid, not pt.
            let image = drawing.image(from: renderRect, scale: 1.0)
            guard let cgImage = image.cgImage else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // 0.01 captures very small handwriting; lower values increase false-positives.
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            guard let observations = request.results else { return "" }
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }.value
    }

    // MARK: - Multi-page recognition

    /// Recognises handwriting across all pages of a note and returns each page's
    /// text joined with a newline separator.
    ///
    /// - Parameters:
    ///   - pages:    The `pages` array from a `Note` (each element is serialised `PKDrawing` data).
    ///   - pageSize: Canvas size used when rendering strokes for recognition.
    /// - Returns: Combined recognised text, or an empty string when all pages are blank.
    static func recognizeText(inPages pages: [Data], pageSize: CGSize) async -> String {
        var results: [String] = []
        for pageData in pages {
            guard !pageData.isEmpty,
                  let drawing = try? PKDrawing(data: pageData),
                  !drawing.strokes.isEmpty else { continue }
            let text = await recognizeText(in: drawing, pageSize: pageSize)
            if !text.isEmpty {
                results.append(text)
            }
        }
        return results.joined(separator: "\n")
    }
}
