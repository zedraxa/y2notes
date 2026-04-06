import XCTest
@testable import Y2Core

final class NoteEncodingTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Round-trip tests

    func testMinimalNoteRoundTrip() throws {
        let note = Note(title: "Hello")
        let data = try encoder.encode(note)
        let decoded = try decoder.decode(Note.self, from: data)
        XCTAssertEqual(decoded.id, note.id)
        XCTAssertEqual(decoded.title, note.title)
    }

    func testFieldsRoundTrip() throws {
        var note = Note(title: "Fields Test")
        note.isFavorite = true
        note.tags = ["math", "science"]
        note.typedText = "Some typed content"
        let data = try encoder.encode(note)
        let decoded = try decoder.decode(Note.self, from: data)
        XCTAssertEqual(decoded.isFavorite, true)
        XCTAssertEqual(decoded.tags, ["math", "science"])
        XCTAssertEqual(decoded.typedText, "Some typed content")
    }

    func testMultiPageRoundTrip() throws {
        var note = Note(title: "Multi-Page")
        note.pages = [Data([0x01]), Data([0x02]), Data([0x03])]
        let data = try encoder.encode(note)
        let decoded = try decoder.decode(Note.self, from: data)
        XCTAssertEqual(decoded.pages.count, 3)
        XCTAssertEqual(decoded.pages[0], Data([0x01]))
        XCTAssertEqual(decoded.pages[2], Data([0x03]))
    }

    func testPageCountMatchesPages() {
        var note = Note(title: "Count Check")
        note.pages = [Data(), Data(), Data()]
        XCTAssertEqual(note.pageCount, 3)
    }

    func testDrawingDataReadsFirstPage() {
        var note = Note(title: "First Page")
        let pageData = Data([0xAA, 0xBB])
        note.pages = [pageData, Data([0xCC])]
        XCTAssertEqual(note.drawingData, pageData)
    }

    func testDrawingDataFallsBackToEmptyData() {
        var note = Note(title: "Empty")
        note.pages = []
        XCTAssertEqual(note.drawingData, Data())
    }

    func testNotesArrayRoundTrip() throws {
        let notes = (0..<5).map { Note(title: "Note \($0)") }
        let data = try encoder.encode(notes)
        let decoded = try decoder.decode([Note].self, from: data)
        XCTAssertEqual(decoded.count, 5)
        for (original, restored) in zip(notes, decoded) {
            XCTAssertEqual(original.id, restored.id)
            XCTAssertEqual(original.title, restored.title)
        }
    }
}

// MARK: - SM-2 Algorithm Tests

final class SM2AlgorithmTests: XCTestCase {

    func testNewCardDefaults() {
        let card = Flashcard(front: "Q", back: "A")
        XCTAssertEqual(card.interval, 0)
        XCTAssertEqual(card.repetitions, 0)
        XCTAssertTrue(card.easeFactor >= 2.5 - 0.01)
    }

    func testStudySetRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var set = StudySet(title: "Math")
        set.cards.append(Flashcard(front: "2+2", back: "4"))
        set.cards.append(Flashcard(front: "3×3", back: "9"))

        let data = try encoder.encode(set)
        let decoded = try decoder.decode(StudySet.self, from: data)
        XCTAssertEqual(decoded.title, "Math")
        XCTAssertEqual(decoded.cards.count, 2)
        XCTAssertEqual(decoded.cards[0].front, "2+2")
    }
}
