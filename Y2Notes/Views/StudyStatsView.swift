import SwiftUI

// MARK: - Study statistics dashboard

/// Analytics dashboard showing review history, mastery distribution, accuracy,
/// daily streak, and per-set breakdowns.
struct StudyStatsView: View {
    @EnvironmentObject var noteStore: NoteStore

    /// When non-nil, show stats only for this study set.
    var studySetID: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                overviewCards
                masteryDistribution
                weeklyActivity
                testOverview
                weakQuestionSection
                testWeeklyTrend
                if studySetID == nil {
                    perSetBreakdown
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(studySetID == nil ? "Study Stats" : "Set Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed data

    private var relevantCards: [StudyCard] {
        if let setID = studySetID {
            return noteStore.studyCards.filter { $0.setID == setID }
        }
        return noteStore.studyCards
    }

    private var relevantProgress: [StudyCardProgress] {
        let cardIDs = Set(relevantCards.map(\.id))
        return noteStore.cardProgress.filter { cardIDs.contains($0.cardID) }
    }

    private var relevantHistory: [StudyReviewEntry] {
        let cardIDs = Set(relevantCards.map(\.id))
        return noteStore.reviewHistory.filter { cardIDs.contains($0.cardID) }
    }

    private var relevantTestQuestions: [StudyTestQuestion] {
        if let setID = studySetID {
            return noteStore.studyTestQuestions.filter { $0.setID == setID }
        }
        return noteStore.studyTestQuestions
    }

    private var relevantTestAttempts: [StudyTestAttempt] {
        let questionIDs = Set(relevantTestQuestions.map(\.id))
        return noteStore.studyTestAttempts.filter { questionIDs.contains($0.questionID) }
    }

    // MARK: - Overview cards

    private var overviewCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            statCard(
                title: "Total Cards",
                value: "\(relevantCards.count)",
                icon: "rectangle.on.rectangle.angled",
                color: .blue
            )
            statCard(
                title: "Due Today",
                value: "\(relevantProgress.filter(\.isDueToday).count)",
                icon: "clock.badge.exclamationmark",
                color: .orange
            )
            statCard(
                title: "Reviews",
                value: "\(relevantProgress.map(\.reviewCount).reduce(0, +))",
                icon: "checkmark.circle",
                color: .green
            )
            statCard(
                title: "Current Streak",
                value: "\(currentDayStreak) day\(currentDayStreak == 1 ? "" : "s")",
                icon: "flame.fill",
                color: .red
            )
            statCard(
                title: "Test Accuracy",
                value: testAccuracyPercentText,
                icon: "checklist",
                color: .blue
            )
            statCard(
                title: "Test Attempts",
                value: "\(relevantTestAttempts.count)",
                icon: "checkmark.circle.badge.questionmark",
                color: .indigo
            )
        }
    }

    private var testAccuracyPercentText: String {
        guard testTotalAttempts > 0 else { return "—" }
        return String(format: "%.0f%%", testAccuracyRatio * 100)
    }

    private var testAccuracyRatio: Double {
        accuracyRatio(correct: testCorrectAttempts, total: testTotalAttempts)
    }

    private var testTotalAttempts: Int { relevantTestAttempts.count }
    private var testCorrectAttempts: Int { relevantTestAttempts.filter(\.isCorrect).count }
    private var testIncorrectAttempts: Int { testTotalAttempts - testCorrectAttempts }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Mastery distribution

    private var masteryDistribution: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mastery Distribution")
                .font(.headline)

            let counts = masteryLevelCounts
            let total = max(relevantCards.count, 1)

            VStack(spacing: 8) {
                ForEach(MasteryLevel.allCases, id: \.self) { level in
                    let count = counts[level, default: 0]
                    let fraction = Double(count) / Double(total)

                    HStack(spacing: 12) {
                        Image(systemName: level.systemImage)
                            .font(.system(size: 14))
                            .foregroundStyle(masteryColor(level))
                            .frame(width: 20)

                        Text(level.displayName)
                            .font(.subheadline)
                            .frame(width: 72, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(uiColor: .secondaryLabel).opacity(0.1))
                                    .frame(height: 10)
                                Capsule()
                                    .fill(masteryColor(level))
                                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0), height: 10)
                            }
                        }
                        .frame(height: 10)

                        Text("\(count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var masteryLevelCounts: [MasteryLevel: Int] {
        var counts: [MasteryLevel: Int] = [:]
        for level in MasteryLevel.allCases {
            counts[level] = 0
        }
        for p in relevantProgress {
            counts[p.masteryLevel, default: 0] += 1
        }
        // Cards without progress records are "new"
        let trackedIDs = Set(relevantProgress.map(\.cardID))
        let untrackedCount = relevantCards.filter { !trackedIDs.contains($0.id) }.count
        counts[.newCard, default: 0] += untrackedCount
        return counts
    }

    private func masteryColor(_ level: MasteryLevel) -> Color {
        switch level {
        case .newCard:   return .blue
        case .learning:  return .orange
        case .reviewing: return .purple
        case .mastered:  return .green
        }
    }

    // MARK: - Weekly activity heatmap

    private var weeklyActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)

            let days = last7DaysActivity

            HStack(spacing: 4) {
                ForEach(days, id: \.date) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(activityColor(total: day.total))
                            .frame(height: 40)
                            .overlay(
                                Text("\(day.total)")
                                    .font(.caption2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(day.total > 0 ? .white : .secondary)
                            )
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private struct DayActivity {
        let date: Date
        let label: String
        let total: Int
    }

    private var last7DaysActivity: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let dayTotal = relevantHistory.filter {
                $0.reviewedAt >= dayStart && $0.reviewedAt < dayEnd
            }.count
            return DayActivity(
                date: date,
                label: offset == 0 ? "Today" : formatter.string(from: date),
                total: dayTotal
            )
        }
    }

    private func activityColor(total: Int) -> Color {
        if total == 0 { return Color(uiColor: .secondaryLabel).opacity(0.08) }
        if total < 5  { return .green.opacity(0.4) }
        if total < 15 { return .green.opacity(0.7) }
        return .green
    }

    // MARK: - Per-set breakdown

    private var perSetBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per Set")
                .font(.headline)

            if noteStore.studySets.isEmpty {
                Text("No study sets yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(noteStore.studySets) { set in
                    let cards = noteStore.studyCards.filter { $0.setID == set.id }
                    let due = noteStore.dueCards(inSet: set.id).count
                    let reviewed = cards.map { noteStore.progress(for: $0.id).reviewCount }.reduce(0, +)

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tint)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text("\(cards.count) cards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if due > 0 {
                                    Text("· \(due) due")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                                Text("· \(reviewed) reviews")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Test analytics

    private var testOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Multiple-Choice Tests")
                .font(.headline)

            if relevantTestQuestions.isEmpty {
                Text("No test questions imported yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                let accuracy = testAccuracyRatio * 100

                HStack(spacing: 12) {
                    testBadge(title: "Questions", value: "\(relevantTestQuestions.count)", color: .blue)
                    testBadge(title: "Correct", value: "\(testCorrectAttempts)", color: .green)
                    testBadge(title: "Wrong", value: "\(testIncorrectAttempts)", color: .red)
                    testBadge(title: "Accuracy", value: String(format: "%.0f%%", accuracy), color: .indigo)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func testBadge(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var weakQuestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weak Questions")
                .font(.headline)

            let weak = weakQuestions
            if weak.isEmpty {
                Text("No weak questions yet. Complete more test attempts to populate this section.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(weak) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.prompt)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text("Accuracy \(Int(item.accuracy * 100))% · \(item.attempts) attempt\(item.attempts == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var weakQuestions: [StudyTestWeakQuestion] {
        let grouped = Dictionary(grouping: relevantTestAttempts, by: \.questionID)
        return relevantTestQuestions.compactMap { question in
            guard let attempts = grouped[question.id], !attempts.isEmpty else { return nil }
            let total = attempts.count
            let accuracy = Double(attempts.filter(\.isCorrect).count) / Double(total)
            return StudyTestWeakQuestion(id: question.id, prompt: question.prompt, accuracy: accuracy, attempts: total)
        }
        .sorted {
            StudyTestWeakQuestion.ranksWeaker($0, than: $1)
        }
        .prefix(5)
        .map { $0 }
    }

    private func accuracyRatio(correct: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }

    private var testWeeklyTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Accuracy (Last 7 Days)")
                .font(.headline)

            let points = testTrendPoints
            HStack(spacing: 6) {
                ForEach(points, id: \.date) { point in
                    VStack(spacing: 4) {
                        let hasAttempts = point.attempts > 0
                        let fillColor: Color = hasAttempts
                            ? .blue.opacity(max(0.2, point.accuracy))
                            : Color(uiColor: .secondaryLabel).opacity(0.08)
                        let label = hasAttempts ? "\(Int(point.accuracy * 100))" : "—"
                        let labelColor: Color = hasAttempts ? .white : .secondary
                        RoundedRectangle(cornerRadius: 4)
                            .fill(fillColor)
                            .frame(height: 34)
                            .overlay(
                                Text(label)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(labelColor)
                            )
                        Text(shortDayLabel(from: point.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var testTrendPoints: [StudyTestDailyAccuracyPoint] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let attempts = relevantTestAttempts.filter { $0.answeredAt >= dayStart && $0.answeredAt < dayEnd }
            let total = attempts.count
            let accuracy = total > 0 ? Double(attempts.filter(\.isCorrect).count) / Double(total) : 0
            return StudyTestDailyAccuracyPoint(date: dayStart, attempts: total, accuracy: accuracy)
        }
    }

    private func shortDayLabel(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    // MARK: - Streak calculation

    /// Number of consecutive days ending today with at least one review.
    private var currentDayStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        while true {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let hasReview = relevantHistory.contains {
                $0.reviewedAt >= checkDate && $0.reviewedAt < dayEnd
            }
            if hasReview {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }
        return streak
    }
}
