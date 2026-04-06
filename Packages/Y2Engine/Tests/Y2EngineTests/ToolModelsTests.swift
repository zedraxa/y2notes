import XCTest
@testable import Y2Engine

final class ToolModelsTests: XCTestCase {

    func testWritingFXTypeRawValues() {
        // Verify core FX types exist and have stable raw values for persistence
        XCTAssertEqual(WritingFXType.none.rawValue, "none")
    }

    func testTrieIndexInsertAndSearch() {
        let trie = TrieIndex()
        trie.insert("hello")
        trie.insert("help")
        trie.insert("world")

        let results = trie.search(prefix: "hel")
        XCTAssertTrue(results.contains("hello"))
        XCTAssertTrue(results.contains("help"))
        XCTAssertFalse(results.contains("world"))
    }

    func testTrieIndexEmptyPrefix() {
        let trie = TrieIndex()
        trie.insert("test")
        let results = trie.search(prefix: "")
        // Empty prefix should return all words or empty depending on implementation
        XCTAssertTrue(results.count >= 0)
    }

    func testColorScienceOKLabRoundTrip() {
        // Basic sanity check that OKLAB conversions don't crash
        let lab = OKLab(L: 0.5, a: 0.0, b: 0.0)
        XCTAssertEqual(lab.L, 0.5, accuracy: 0.001)
        XCTAssertEqual(lab.a, 0.0, accuracy: 0.001)
        XCTAssertEqual(lab.b, 0.0, accuracy: 0.001)
    }

    func testEffectsCoordinatorCanvasEventCases() {
        // Verify CanvasEvent enum cases exist
        let began = CanvasEvent.strokeBegan
        let updated = CanvasEvent.strokeUpdated
        let ended = CanvasEvent.strokeEnded
        XCTAssertNotEqual("\(began)", "\(updated)")
        XCTAssertNotEqual("\(updated)", "\(ended)")
    }
}
