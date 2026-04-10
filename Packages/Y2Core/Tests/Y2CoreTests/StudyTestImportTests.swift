import XCTest
@testable import Y2Core

final class StudyTestImportTests: XCTestCase {

    func testImportPayloadValidationSucceedsForValidV1File() throws {
        let payload = StudyTestImportPayload(
            version: 1,
            set: .init(title: "Biology"),
            questions: [
                .init(
                    prompt: "What is ATP?",
                    options: ["A nucleotide", "A protein", "A lipid"],
                    correctOptionIndex: 0,
                    explanation: "ATP is a nucleotide.",
                    tags: ["bio"],
                    source: "chapter-1"
                )
            ]
        )

        let validated = try payload.validatedQuestions()
        XCTAssertEqual(validated.count, 1)
        XCTAssertEqual(validated[0].correctOptionIndex, 0)
    }

    func testImportPayloadValidationRejectsInvalidAnswerIndex() {
        let payload = StudyTestImportPayload(
            version: 1,
            set: .init(title: "Biology"),
            questions: [
                .init(prompt: "Cell?", options: ["A", "B"], correctOptionIndex: 2)
            ]
        )

        XCTAssertThrowsError(try payload.validatedQuestions()) { error in
            XCTAssertEqual(error as? StudyTestImportValidationError, .invalidCorrectOptionIndex(question: 1))
        }
    }

    func testImportPayloadValidationRejectsUnsupportedVersion() {
        let payload = StudyTestImportPayload(
            version: 2,
            set: .init(title: "Biology"),
            questions: [
                .init(prompt: "Cell?", options: ["A", "B"], correctOptionIndex: 1)
            ]
        )

        XCTAssertThrowsError(try payload.validatedQuestions()) { error in
            XCTAssertEqual(error as? StudyTestImportValidationError, .unsupportedVersion(2))
        }
    }

    func testStudyTestQuestionBackwardCompatibleDecodeDefaultsDates() throws {
        let setID = UUID()
        let questionID = UUID()
        let json = """
        {
          "id":"\(questionID.uuidString)",
          "setID":"\(setID.uuidString)",
          "prompt":"Which one is correct?",
          "options":["A","B","C"],
          "correctOptionIndex":1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StudyTestQuestion.self, from: json)
        XCTAssertEqual(decoded.id, questionID)
        XCTAssertEqual(decoded.setID, setID)
        XCTAssertEqual(decoded.correctOptionIndex, 1)
        XCTAssertEqual(decoded.modifiedAt, decoded.createdAt)
        XCTAssertTrue(decoded.explanation == nil)
    }
}
