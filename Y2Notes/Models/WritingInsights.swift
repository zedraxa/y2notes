import Foundation

// MARK: - WritingInsights

/// Aggregated writing statistics computed from NoteStore data.
///
/// Inspired by the Obsidian Stats community plugin, iA Writer's
/// document statistics, and GitHub's contribution-graph heatmap.
/// All computation is synchronous and off-main-queue safe.
struct WritingInsights {

    // MARK: Aggregate Counts

    /// Total number of notes across all notebooks.
    let totalNotes: Int

    /// Total number of notebooks.
    let totalNotebooks: Int

    /// Total number of pages across all notes.
    let totalPages: Int

    /// Estimated total word count derived from typed text and OCR text.
    let totalWords: Int

    /// Estimated total character count.
    let totalCharacters: Int

    // MARK: Streaks

    /// Number of consecutive calendar days (up to today) with at least
    /// one note modified.
    let currentStreak: Int

    /// Longest consecutive-day editing streak ever recorded.
    let longestStreak: Int

    // MARK: Per-Notebook Stats

    /// Note and page count grouped by notebook. Key is notebook ID.
    let perNotebook: [UUID: NotebookStat]

    // MARK: Activity Heatmap

    /// Number of note modifications per calendar day for the last 90 days.
    /// Key is the date (midnight-aligned, user calendar).
    let dailyActivity: [Date: Int]

    // MARK: Averages

    /// Average number of pages per note (rounded to one decimal).
    let averagePagesPerNote: Double

    /// Average word count per note.
    let averageWordsPerNote: Double

    // MARK: Trend Analysis (powered by InsightsAnalytics)

    /// Linear trend direction for daily activity over the heatmap window.
    let activityTrend: TrendAnalyser.TrendResult

    /// Descriptive statistics over daily word-count estimates.
    let wordCountStats: DescriptiveStats?

    /// Anomalous days — dates where activity deviated unusually from the mean.
    let anomalousDays: [Date]
}

// MARK: - NotebookStat

/// Per-notebook aggregate.
struct NotebookStat: Identifiable {
    let id: UUID
    let name: String
    let noteCount: Int
    let pageCount: Int
    let wordCount: Int
}

// MARK: - WritingInsightsBuilder

/// Builds a ``WritingInsights`` snapshot from live NoteStore data.
enum WritingInsightsBuilder {

    // MARK: Public

    /// Compute a full insights snapshot from the given collections.
    static func build(
        notes: [Note],
        notebooks: [Notebook]
    ) -> WritingInsights {
        let totalNotes = notes.count
        let totalNotebooks = notebooks.count
        let totalPages = notes.reduce(0) { $0 + max($1.pages.count, 1) }

        // Word / character estimation
        var totalWords = 0
        var totalCharacters = 0
        for note in notes {
            let text = combinedText(for: note)
            totalCharacters += text.count
            totalWords += wordCount(of: text)
        }

        // Per-notebook
        let notebookMap = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0) })
        var perNotebook: [UUID: NotebookStat] = [:]
        for notebook in notebooks {
            let notebookNotes = notes.filter { $0.notebookID == notebook.id }
            let pages = notebookNotes.reduce(0) { $0 + max($1.pages.count, 1) }
            let words = notebookNotes.reduce(0) { $0 + wordCount(of: combinedText(for: $1)) }
            perNotebook[notebook.id] = NotebookStat(
                id: notebook.id,
                name: notebook.name,
                noteCount: notebookNotes.count,
                pageCount: pages,
                wordCount: words
            )
        }

        // Streaks + activity
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let modDates = notes.map { calendar.startOfDay(for: $0.modifiedAt) }

        let (current, longest) = computeStreaks(dates: modDates, today: today, calendar: calendar)
        let dailyActivity = computeDailyActivity(dates: modDates, today: today, calendar: calendar)

        // Averages
        let avgPages = totalNotes > 0 ? Double(totalPages) / Double(totalNotes) : 0
        let avgWords = totalNotes > 0 ? Double(totalWords) / Double(totalNotes) : 0

        // --- InsightsAnalytics: trend + stats ---
        // Build a 90-day daily activity series (ordered oldest → newest).
        let sortedDays: [Date] = (0..<activityWindowDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -(activityWindowDays - 1 - offset), to: today)
        }
        let activitySeries = sortedDays.map { Double(dailyActivity[$0] ?? 0) }
        let activityTrend = TrendAnalyser.analyse(dailyValues: activitySeries)

        // Descriptive stats on per-note word counts.
        let wordCounts = notes.map { Double(wordCount(of: combinedText(for: $0))) }
        let wordCountStats = DescriptiveStats.compute(wordCounts)

        // Detect anomalous activity days (z-score > 2.0 = unusually high or low).
        let anomalies = AnomalyDetector.detect(values: activitySeries, threshold: 2.0)
        let anomalousDays = anomalies.map { sortedDays[$0.index] }

        return WritingInsights(
            totalNotes: totalNotes,
            totalNotebooks: totalNotebooks,
            totalPages: totalPages,
            totalWords: totalWords,
            totalCharacters: totalCharacters,
            currentStreak: current,
            longestStreak: longest,
            perNotebook: perNotebook,
            dailyActivity: dailyActivity,
            averagePagesPerNote: (avgPages * 10).rounded() / 10,
            averageWordsPerNote: (avgWords * 10).rounded() / 10,
            activityTrend: activityTrend,
            wordCountStats: wordCountStats,
            anomalousDays: anomalousDays
        )
    }

    // MARK: - Private Helpers

    private static func combinedText(for note: Note) -> String {
        [note.typedText, note.ocrText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func wordCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }

    private static func computeStreaks(
        dates: [Date],
        today: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        let unique = Set(dates).sorted(by: >)
        guard !unique.isEmpty else { return (0, 0) }

        var current = 0
        var longest = 0
        var streak = 1

        // Current streak: consecutive days ending today or yesterday.
        let reference = unique.first!
        let dayDiff = calendar.dateComponents([.day], from: reference, to: today).day ?? 0
        if dayDiff <= 1 {
            current = 1
            var prev = reference
            for date in unique.dropFirst() {
                let gap = calendar.dateComponents([.day], from: date, to: prev).day ?? 0
                if gap == 1 {
                    current += 1
                    prev = date
                } else {
                    break
                }
            }
        }

        // Longest streak
        var prev = unique[0]
        for date in unique.dropFirst() {
            let gap = calendar.dateComponents([.day], from: date, to: prev).day ?? 0
            if gap == 1 {
                streak += 1
            } else {
                longest = max(longest, streak)
                streak = 1
            }
            prev = date
        }
        longest = max(longest, streak)

        return (current, longest)
    }

    /// Number of days in the activity heatmap window.
    private static let activityWindowDays = 90

    private static func computeDailyActivity(
        dates: [Date],
        today: Date,
        calendar: Calendar
    ) -> [Date: Int] {
        guard let windowStart = calendar.date(byAdding: .day, value: -(activityWindowDays - 1), to: today) else {
            return [:]
        }
        var counts: [Date: Int] = [:]
        for date in dates where date >= windowStart {
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += 1
        }
        return counts
    }
}
