import Foundation

// MARK: - Study card

/// A single flashcard that can be reviewed in a study session.
public struct StudyCard: Identifiable, Codable, Hashable {
    public let id: UUID
    public var setID: UUID
    public var noteID: UUID?
    public var front: String
    public var back: String
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        setID: UUID,
        noteID: UUID? = nil,
        front: String,
        back: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.setID = setID
        self.noteID = noteID
        self.front = front
        self.back = back
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: Codable — backward-compatible decoder
    enum CodingKeys: String, CodingKey {
        case id, setID, noteID, front, back, tags, createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        setID      = try c.decode(UUID.self,   forKey: .setID)
        noteID     = try c.decodeIfPresent(UUID.self,     forKey: .noteID)
        front      = try c.decode(String.self, forKey: .front)
        back       = try c.decode(String.self, forKey: .back)
        tags       = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt = try c.decode(Date.self,   forKey: .modifiedAt)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: StudyCard, rhs: StudyCard) -> Bool { lhs.id == rhs.id }
}

// MARK: - Study set

/// A named collection of flashcards.
public struct StudySet: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var notebookID: UUID?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notebookID: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notebookID = notebookID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notebookID, createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        notebookID = try c.decodeIfPresent(UUID.self, forKey: .notebookID)
        createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt = try c.decode(Date.self,   forKey: .modifiedAt)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: StudySet, rhs: StudySet) -> Bool { lhs.id == rhs.id }
}

// MARK: - Review rating

/// The learner's self-assessed difficulty rating for a card review.
public enum ReviewRating: Int, Codable, CaseIterable, Identifiable {
    case again = 0
    case hard  = 1
    case good  = 2
    case easy  = 3

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    public var systemImage: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard:  return "tortoise"
        case .good:  return "checkmark"
        case .easy:  return "bolt.fill"
        }
    }

    public var colorName: String {
        switch self {
        case .again: return "red"
        case .hard:  return "orange"
        case .good:  return "green"
        case .easy:  return "blue"
        }
    }
}

// MARK: - Study review entry

/// A single review event, persisted for analytics and streak tracking.
public struct StudyReviewEntry: Identifiable, Codable {
    public let id: UUID
    public let cardID: UUID
    public let setID: UUID
    public let rating: ReviewRating
    public let reviewedAt: Date

    public init(id: UUID = UUID(), cardID: UUID, setID: UUID, rating: ReviewRating, reviewedAt: Date = Date()) {
        self.id = id
        self.cardID = cardID
        self.setID = setID
        self.rating = rating
        self.reviewedAt = reviewedAt
    }
}

// MARK: - Mastery level

/// Categorises a card's learning stage based on its SM-2 scheduling state.
public enum MasteryLevel: String, Codable, CaseIterable {
    case newCard    = "new"
    case learning   = "learning"
    case reviewing  = "reviewing"
    case mastered   = "mastered"

    public var displayName: String {
        switch self {
        case .newCard:   return "New"
        case .learning:  return "Learning"
        case .reviewing: return "Reviewing"
        case .mastered:  return "Mastered"
        }
    }

    public var systemImage: String {
        switch self {
        case .newCard:   return "sparkle"
        case .learning:  return "book"
        case .reviewing: return "arrow.triangle.2.circlepath"
        case .mastered:  return "checkmark.seal.fill"
        }
    }

    public var colorName: String {
        switch self {
        case .newCard:   return "blue"
        case .learning:  return "orange"
        case .reviewing: return "purple"
        case .mastered:  return "green"
        }
    }
}

// MARK: - Card review progress (SM-2)

/// Per-card scheduling state produced by the SM-2 spaced-repetition algorithm.
public struct StudyCardProgress: Identifiable, Codable {
    public let cardID: UUID

    public var id: UUID { cardID }

    public var reviewCount: Int
    public var interval: Int
    public var easeFactor: Double
    public var dueDate: Date
    public var lastReviewedAt: Date?
    public var currentStreak: Int
    public var bestStreak: Int

    public init(cardID: UUID) {
        self.cardID       = cardID
        self.reviewCount  = 0
        self.interval     = 1
        self.easeFactor   = 2.5
        self.dueDate      = Date()
        self.lastReviewedAt = nil
        self.currentStreak  = 0
        self.bestStreak     = 0
    }

    // MARK: Backward-compatible decoder

    enum CodingKeys: String, CodingKey {
        case cardID, reviewCount, interval, easeFactor, dueDate, lastReviewedAt
        case currentStreak, bestStreak
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardID         = try c.decode(UUID.self, forKey: .cardID)
        reviewCount    = try c.decode(Int.self, forKey: .reviewCount)
        interval       = try c.decode(Int.self, forKey: .interval)
        easeFactor     = try c.decode(Double.self, forKey: .easeFactor)
        dueDate        = try c.decode(Date.self, forKey: .dueDate)
        lastReviewedAt = try c.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        currentStreak  = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak     = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
    }

    public var masteryLevel: MasteryLevel {
        if reviewCount == 0 { return .newCard }
        if interval >= 21 { return .mastered }
        if interval >= 6 { return .reviewing }
        return .learning
    }

    // MARK: SM-2 scheduling

    public func applying(rating: ReviewRating, reviewedAt: Date = Date()) -> StudyCardProgress {
        var next = self
        next.lastReviewedAt = reviewedAt
        next.reviewCount += 1

        switch rating {
        case .again:
            next.interval    = 1
            next.easeFactor  = max(1.3, easeFactor - 0.2)

        case .hard:
            let newInterval = max(1, Int((Double(interval) * 1.2).rounded()))
            next.interval   = newInterval
            next.easeFactor = max(1.3, easeFactor - 0.15)

        case .good:
            let newInterval: Int
            if reviewCount == 0 {
                newInterval = 1
            } else if reviewCount == 1 {
                newInterval = 6
            } else {
                newInterval = max(1, Int((Double(interval) * easeFactor).rounded()))
            }
            next.interval = newInterval

        case .easy:
            let newInterval: Int
            if reviewCount == 0 {
                newInterval = 4
            } else {
                newInterval = max(1, Int((Double(interval) * easeFactor * 1.3).rounded()))
            }
            next.interval   = newInterval
            next.easeFactor = min(4.0, easeFactor + 0.1)
        }

        let calendar = Calendar.current
        next.dueDate = calendar.date(
            byAdding: .day,
            value: next.interval,
            to: reviewedAt
        ) ?? reviewedAt

        return next
    }

    /// True when this card is due for review today or is overdue.
    public var isDueToday: Bool {
        dueDate <= Date()
    }
}

// MARK: - Study test (multiple choice)

public struct StudyTestQuestion: Identifiable, Codable, Hashable {
    public let id: UUID
    public var setID: UUID
    public var noteID: UUID?
    public var prompt: String
    public var options: [String]
    public var correctOptionIndex: Int
    public var explanation: String?
    public var tags: [String]
    public var source: String?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        setID: UUID,
        noteID: UUID? = nil,
        prompt: String,
        options: [String],
        correctOptionIndex: Int,
        explanation: String? = nil,
        tags: [String] = [],
        source: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.setID = setID
        self.noteID = noteID
        self.prompt = prompt
        self.options = options
        self.correctOptionIndex = correctOptionIndex
        self.explanation = explanation
        self.tags = tags
        self.source = source
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, setID, noteID, prompt, options, correctOptionIndex, explanation
        case tags, source, createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        setID = try c.decode(UUID.self, forKey: .setID)
        noteID = try c.decodeIfPresent(UUID.self, forKey: .noteID)
        prompt = try c.decode(String.self, forKey: .prompt)
        options = try c.decode([String].self, forKey: .options)
        correctOptionIndex = try c.decode(Int.self, forKey: .correctOptionIndex)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try c.decodeIfPresent(String.self, forKey: .source)
        // Backward compatibility: if old payloads only carried `modifiedAt`, use it.
        // If neither timestamp exists (legacy/import edge case), default to decode time.
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? c.decodeIfPresent(Date.self, forKey: .modifiedAt)
            ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }
}

public struct StudyTestAttempt: Identifiable, Codable, Hashable {
    public let id: UUID
    public let questionID: UUID
    public let setID: UUID
    public let selectedOptionIndex: Int?
    public let isCorrect: Bool
    public let answeredAt: Date
    public let durationSeconds: TimeInterval?

    public init(
        id: UUID = UUID(),
        questionID: UUID,
        setID: UUID,
        selectedOptionIndex: Int?,
        isCorrect: Bool,
        answeredAt: Date = Date(),
        durationSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.questionID = questionID
        self.setID = setID
        self.selectedOptionIndex = selectedOptionIndex
        self.isCorrect = isCorrect
        self.answeredAt = answeredAt
        self.durationSeconds = durationSeconds
    }
}

public struct StudyTestQuestionStats: Equatable {
    public let questionID: UUID
    public let attempts: Int
    public let correctAttempts: Int
    public let incorrectAttempts: Int
    public let accuracy: Double
    public let lastAttemptedAt: Date?

    public init(
        questionID: UUID,
        attempts: Int,
        correctAttempts: Int,
        incorrectAttempts: Int,
        accuracy: Double,
        lastAttemptedAt: Date?
    ) {
        self.questionID = questionID
        self.attempts = attempts
        self.correctAttempts = correctAttempts
        self.incorrectAttempts = incorrectAttempts
        self.accuracy = accuracy
        self.lastAttemptedAt = lastAttemptedAt
    }
}

public struct StudyTestWeakQuestion: Identifiable, Equatable {
    public let id: UUID
    public let prompt: String
    public let accuracy: Double
    public let attempts: Int

    public init(id: UUID, prompt: String, accuracy: Double, attempts: Int) {
        self.id = id
        self.prompt = prompt
        self.accuracy = accuracy
        self.attempts = attempts
    }
}

public extension StudyTestWeakQuestion {
    static func ranksWeaker(_ lhs: StudyTestWeakQuestion, than rhs: StudyTestWeakQuestion) -> Bool {
        if lhs.accuracy == rhs.accuracy {
            return lhs.attempts > rhs.attempts
        }
        return lhs.accuracy < rhs.accuracy
    }
}

public struct StudyTestDailyAccuracyPoint: Equatable {
    public let date: Date
    public let attempts: Int
    public let accuracy: Double

    public init(date: Date, attempts: Int, accuracy: Double) {
        self.date = date
        self.attempts = attempts
        self.accuracy = accuracy
    }
}

public struct StudyTestSetStats: Equatable {
    public let setID: UUID
    public let questionCount: Int
    public let totalAttempts: Int
    public let correctAttempts: Int
    public let incorrectAttempts: Int
    public let accuracy: Double
    public let weakQuestions: [StudyTestWeakQuestion]
    public let dailyTrend: [StudyTestDailyAccuracyPoint]

    public init(
        setID: UUID,
        questionCount: Int,
        totalAttempts: Int,
        correctAttempts: Int,
        incorrectAttempts: Int,
        accuracy: Double,
        weakQuestions: [StudyTestWeakQuestion],
        dailyTrend: [StudyTestDailyAccuracyPoint]
    ) {
        self.setID = setID
        self.questionCount = questionCount
        self.totalAttempts = totalAttempts
        self.correctAttempts = correctAttempts
        self.incorrectAttempts = incorrectAttempts
        self.accuracy = accuracy
        self.weakQuestions = weakQuestions
        self.dailyTrend = dailyTrend
    }
}

public enum StudyTestImportValidationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case emptyQuestions
    case emptyPrompt(question: Int)
    case insufficientOptions(question: Int)
    case emptyOption(question: Int, option: Int)
    case invalidCorrectOptionIndex(question: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "Unsupported import version \(version)."
        case .emptyQuestions:
            return "Import file has no questions."
        case let .emptyPrompt(question):
            return "Question \(question) is missing a prompt."
        case let .insufficientOptions(question):
            return "Question \(question) must have at least 2 options."
        case let .emptyOption(question, option):
            return "Question \(question) option \(option) is empty."
        case let .invalidCorrectOptionIndex(question):
            return "Question \(question) has an invalid answer key index."
        }
    }
}

public struct StudyTestImportPayload: Codable {
    public struct SetMetadata: Codable {
        public var title: String
        public var description: String?

        public init(title: String, description: String? = nil) {
            self.title = title
            self.description = description
        }
    }

    public struct Question: Codable {
        public var prompt: String
        public var options: [String]
        public var correctOptionIndex: Int
        public var explanation: String?
        public var tags: [String]?
        public var source: String?
        public var noteID: UUID?

        public init(
            prompt: String,
            options: [String],
            correctOptionIndex: Int,
            explanation: String? = nil,
            tags: [String]? = nil,
            source: String? = nil,
            noteID: UUID? = nil
        ) {
            self.prompt = prompt
            self.options = options
            self.correctOptionIndex = correctOptionIndex
            self.explanation = explanation
            self.tags = tags
            self.source = source
            self.noteID = noteID
        }
    }

    public var version: Int
    public var set: SetMetadata
    public var questions: [Question]

    public init(version: Int = 1, set: SetMetadata, questions: [Question]) {
        self.version = version
        self.set = set
        self.questions = questions
    }

    public func validatedQuestions() throws -> [Question] {
        guard version == 1 else {
            throw StudyTestImportValidationError.unsupportedVersion(version)
        }
        guard !questions.isEmpty else {
            throw StudyTestImportValidationError.emptyQuestions
        }

        for (questionIndex, question) in questions.enumerated() {
            let row = questionIndex + 1
            if question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw StudyTestImportValidationError.emptyPrompt(question: row)
            }
            if question.options.count < 2 {
                throw StudyTestImportValidationError.insufficientOptions(question: row)
            }
            for (optionIndex, option) in question.options.enumerated() {
                if option.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw StudyTestImportValidationError.emptyOption(question: row, option: optionIndex + 1)
                }
            }
            if question.correctOptionIndex < 0 || question.correctOptionIndex >= question.options.count {
                throw StudyTestImportValidationError.invalidCorrectOptionIndex(question: row)
            }
        }
        return questions
    }
}

public struct StudyTestImportSummary: Equatable {
    public let addedCount: Int
    public let skippedCount: Int
    public let invalidCount: Int
    public let messages: [String]

    public init(addedCount: Int, skippedCount: Int, invalidCount: Int, messages: [String]) {
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.invalidCount = invalidCount
        self.messages = messages
    }
}
