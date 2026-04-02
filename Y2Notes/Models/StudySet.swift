import Foundation

// MARK: - Study card

/// A single flashcard that can be reviewed in a study session.
///
/// Cards can optionally link back to the source note that inspired them.
struct StudyCard: Identifiable, Codable, Hashable {
    let id: UUID
    /// The study set this card belongs to.
    var setID: UUID
    /// Optional back-reference to the source note (e.g., the page the card was extracted from).
    var noteID: UUID?
    /// The "question" side of the card (what is shown first).
    var front: String
    /// The "answer" side of the card (what is revealed on flip).
    var back: String
    /// Optional comma-separated tags (e.g., "chapter 1,key term").
    var tags: [String]
    var createdAt: Date
    var modifiedAt: Date

    init(
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

    init(from decoder: Decoder) throws {
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

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: StudyCard, rhs: StudyCard) -> Bool { lhs.id == rhs.id }
}

// MARK: - Study set

/// A named collection of flashcards.
struct StudySet: Identifiable, Codable, Hashable {
    let id: UUID
    /// Display name of the study set.
    var title: String
    /// Optional notebook this set is associated with.
    var notebookID: UUID?
    var createdAt: Date
    var modifiedAt: Date

    init(
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        notebookID = try c.decodeIfPresent(UUID.self, forKey: .notebookID)
        createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt = try c.decode(Date.self,   forKey: .modifiedAt)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: StudySet, rhs: StudySet) -> Bool { lhs.id == rhs.id }
}

// MARK: - Review rating

/// The learner's self-assessed difficulty rating for a card review.
/// Maps to the SM-2 quality grades 0–3 used in the spaced-repetition algorithm.
enum ReviewRating: Int, Codable, CaseIterable, Identifiable {
    /// Failed to recall — card is returned to the front of the queue.
    case again = 0
    /// Recalled with significant difficulty.
    case hard  = 1
    /// Recalled correctly with normal effort.
    case good  = 2
    /// Recalled instantly with no effort.
    case easy  = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    var systemImage: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard:  return "tortoise"
        case .good:  return "checkmark"
        case .easy:  return "bolt.fill"
        }
    }

    /// Accent colour for the rating button.
    var colorName: String {
        switch self {
        case .again: return "red"
        case .hard:  return "orange"
        case .good:  return "green"
        case .easy:  return "blue"
        }
    }
}

// MARK: - Card review progress (SM-2)

/// Per-card scheduling state produced by the SM-2 spaced-repetition algorithm.
///
/// **SM-2 algorithm summary (per Anki / SuperMemo):**
/// - `easeFactor` starts at 2.5 and is adjusted after each review.
/// - `interval` (days until next review) grows with successful reviews.
/// - A rating of `.again` resets progress to day 1.
///
/// **Extension point:**  A future agent can plug in an FSRS or custom SRS algorithm by
/// replacing the body of `applying(rating:)` without changing the storage schema.
struct StudyCardProgress: Identifiable, Codable {
    /// The card this progress record belongs to.
    let cardID: UUID

    var id: UUID { cardID }

    /// Number of successful reviews (used to determine initial ramp-up intervals).
    var reviewCount: Int

    /// Current inter-review interval in days.
    var interval: Int

    /// SM-2 ease factor (default 2.5; minimum 1.3).
    var easeFactor: Double

    /// Calendar date when this card is next due for review.
    var dueDate: Date

    /// Timestamp of the most recent review (nil if never reviewed).
    var lastReviewedAt: Date?

    init(cardID: UUID) {
        self.cardID       = cardID
        self.reviewCount  = 0
        self.interval     = 1
        self.easeFactor   = 2.5
        self.dueDate      = Date()
        self.lastReviewedAt = nil
    }

    // MARK: SM-2 scheduling

    /// Returns a new `StudyCardProgress` reflecting the given review rating.
    ///
    /// Callers should replace the stored value with the returned copy:
    /// ```swift
    /// store.recordReview(cardID: card.id, rating: .good)
    /// ```
    func applying(rating: ReviewRating, reviewedAt: Date = Date()) -> StudyCardProgress {
        var next = self
        next.lastReviewedAt = reviewedAt
        next.reviewCount += 1

        switch rating {
        case .again:
            // Reset — show again tomorrow.
            next.interval    = 1
            next.easeFactor  = max(1.3, easeFactor - 0.2)

        case .hard:
            // Grow slowly; penalise ease.
            let newInterval = max(1, Int((Double(interval) * 1.2).rounded()))
            next.interval   = newInterval
            next.easeFactor = max(1.3, easeFactor - 0.15)

        case .good:
            // Standard SM-2 growth.
            let newInterval: Int
            if reviewCount == 0 {
                newInterval = 1
            } else if reviewCount == 1 {
                newInterval = 6
            } else {
                newInterval = max(1, Int((Double(interval) * easeFactor).rounded()))
            }
            next.interval = newInterval
            // easeFactor unchanged on .good.

        case .easy:
            // Bonus multiplier; reward ease.
            let newInterval: Int
            if reviewCount == 0 {
                newInterval = 4
            } else {
                newInterval = max(1, Int((Double(interval) * easeFactor * 1.3).rounded()))
            }
            next.interval   = newInterval
            next.easeFactor = min(4.0, easeFactor + 0.1)
        }

        // Schedule due date based on the new interval.
        let calendar = Calendar.current
        next.dueDate = calendar.date(
            byAdding: .day,
            value: next.interval,
            to: reviewedAt
        ) ?? reviewedAt

        return next
    }

    /// True when this card is due for review today or is overdue.
    var isDueToday: Bool {
        dueDate <= Date()
    }
}
