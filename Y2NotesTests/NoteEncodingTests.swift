import XCTest
@testable import Y2Notes

// MARK: - NoteEncodingTests

/// Encoding / decoding round-trip tests for the `Note` model.
///
/// These are the highest-priority tests in the codebase because data corruption
/// is the worst possible bug.  Every `Codable` field change to `Note` should be
/// accompanied by a test here.
final class NoteEncodingTests: XCTestCase {

    // MARK: - Encoder/decoder helpers

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func roundTrip(_ note: Note) throws -> Note {
        let data = try encoder.encode(note)
        return try decoder.decode(Note.self, from: data)
    }

    // MARK: - Basic round-trip

    func testMinimalNoteRoundTrip() throws {
        let original = Note(title: "Hello")
        let decoded  = try roundTrip(original)

        XCTAssertEqual(decoded.id,    original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.pages.count, 1)
        XCTAssertTrue(decoded.pages[0].isEmpty)
        XCTAssertFalse(decoded.isFavorited)
        XCTAssertTrue(decoded.tags.isEmpty)
    }

    func testFieldsRoundTrip() throws {
        let id         = UUID()
        let created    = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let modified   = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let pageData   = Data([0x01, 0x02, 0x03])

        let original = Note(
            id:          id,
            title:       "Lecture Notes",
            createdAt:   created,
            modifiedAt:  modified,
            drawingData: pageData,
            isFavorited: true,
            typedText:   "Hello world",
            ocrText:     "Hello world (OCR)",
            tags:        ["lecture", "physics"]
        )

        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.id,           id)
        XCTAssertEqual(decoded.title,        "Lecture Notes")
        XCTAssertEqual(decoded.isFavorited,  true)
        XCTAssertEqual(decoded.typedText,    "Hello world")
        XCTAssertEqual(decoded.ocrText,      "Hello world (OCR)")
        XCTAssertEqual(decoded.tags,         ["lecture", "physics"])
        XCTAssertEqual(decoded.pages[0],     pageData)
        // Dates round-trip with ISO 8601 — compare seconds to avoid sub-millisecond drift.
        XCTAssertEqual(decoded.createdAt.timeIntervalSinceReferenceDate,
                       created.timeIntervalSinceReferenceDate,
                       accuracy: 1.0)
        XCTAssertEqual(decoded.modifiedAt.timeIntervalSinceReferenceDate,
                       modified.timeIntervalSinceReferenceDate,
                       accuracy: 1.0)
    }

    // MARK: - Multi-page

    func testMultiPageRoundTrip() throws {
        let page0 = Data([0xAA])
        let page1 = Data([0xBB])
        let page2 = Data([0xCC])

        let original = Note(title: "Multi", pages: [page0, page1, page2])
        let decoded  = try roundTrip(original)

        XCTAssertEqual(decoded.pages.count, 3)
        XCTAssertEqual(decoded.pages[0], page0)
        XCTAssertEqual(decoded.pages[1], page1)
        XCTAssertEqual(decoded.pages[2], page2)
    }

    func testPageCountMatchesPages() throws {
        let original = Note(title: "Three Pages", pages: [Data(), Data(), Data()])
        let decoded  = try roundTrip(original)
        XCTAssertEqual(decoded.pageCount, 3)
    }

    // MARK: - Legacy single-page migration

    /// Notes saved before multi-page support used a top-level `drawingData` key.
    /// The decoder must migrate this into `pages[0]`.
    func testLegacySinglePageMigration() throws {
        let drawingBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Legacy Note",
            "createdAt": "2024-01-01T00:00:00Z",
            "modifiedAt": "2024-01-02T00:00:00Z",
            "drawingData": "\(drawingBytes.base64EncodedString())",
            "isFavorited": false,
            "sortOrder": 0,
            "templateID": "builtin.blank",
            "typedText": "",
            "ocrText": "",
            "tags": []
        }
        """.data(using: .utf8)!

        let note = try decoder.decode(Note.self, from: legacyJSON)
        XCTAssertEqual(note.pages.count, 1,
                       "Legacy note must be migrated to single-element pages array")
        XCTAssertEqual(note.pages[0], drawingBytes,
                       "Migrated page[0] must equal original drawingData")
    }

    // MARK: - drawingData computed property

    func testDrawingDataReadsFirstPage() throws {
        let firstPage  = Data([0x01])
        let secondPage = Data([0x02])
        let note       = Note(title: "Two pages", pages: [firstPage, secondPage])
        XCTAssertEqual(note.drawingData, firstPage)
    }

    func testDrawingDataFallsBackToEmptyData() {
        var note = Note(title: "Edge case")
        // Forcefully empty pages to simulate an unexpected edge case.
        note.pages = []
        XCTAssertEqual(note.drawingData, Data(),
                       "drawingData must never crash on empty pages")
    }

    // MARK: - Array-safe helpers

    func testPageTypeForPageBoundsCheck() {
        let note = Note(title: "Test")
        // No per-page overrides set — should fall back to note-level (nil).
        XCTAssertNil(note.pageType(forPage: 0))
        XCTAssertNil(note.pageType(forPage: 99))
        XCTAssertNil(note.pageType(forPage: -1))
    }

    func testStickersForPageOutOfBoundsReturnsEmpty() {
        let note = Note(title: "No Stickers")
        XCTAssertTrue(note.stickers(forPage: 0).isEmpty)
        XCTAssertTrue(note.stickers(forPage: 99).isEmpty)
    }

    // MARK: - Array of notes round-trip

    func testNotesArrayRoundTrip() throws {
        let notes = (0..<5).map { i in
            Note(title: "Note \(i)", isFavorited: i % 2 == 0)
        }
        let data    = try encoder.encode(notes)
        let decoded = try decoder.decode([Note].self, from: data)

        XCTAssertEqual(decoded.count, notes.count)
        for (original, dec) in zip(notes, decoded) {
            XCTAssertEqual(dec.id,          original.id)
            XCTAssertEqual(dec.title,       original.title)
            XCTAssertEqual(dec.isFavorited, original.isFavorited)
        }
    }
}
