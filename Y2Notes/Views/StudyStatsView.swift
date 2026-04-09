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
        }
    }

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
