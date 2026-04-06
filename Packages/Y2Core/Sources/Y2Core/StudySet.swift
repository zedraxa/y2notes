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
