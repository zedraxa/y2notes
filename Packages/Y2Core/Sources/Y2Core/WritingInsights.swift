import Foundation

// MARK: - WritingInsights

public struct WritingInsights {

    // MARK: Aggregate Counts

    public let totalNotes: Int
    public let totalNotebooks: Int
    public let totalPages: Int
    public let totalWords: Int
    public let totalCharacters: Int

    // MARK: Streaks

    public let currentStreak: Int
    public let longestStreak: Int

    // MARK: Per-Notebook Stats

    public let perNotebook: [UUID: NotebookStat]

    // MARK: Activity Heatmap

    public let dailyActivity: [Date: Int]

    // MARK: Averages

    public let averagePagesPerNote: Double
    public let averageWordsPerNote: Double

    // MARK: Trend Analysis

    public let activityTrend: TrendAnalyser.TrendResult
    public let wordCountStats: DescriptiveStats?
    public let anomalousDays: [Date]

    public init(
        totalNotes: Int,
        totalNotebooks: Int,
        totalPages: Int,
        totalWords: Int,
        totalCharacters: Int,
        currentStreak: Int,
        longestStreak: Int,
        perNotebook: [UUID: NotebookStat],
        dailyActivity: [Date: Int],
        averagePagesPerNote: Double,
        averageWordsPerNote: Double,
        activityTrend: TrendAnalyser.TrendResult,
        wordCountStats: DescriptiveStats?,
        anomalousDays: [Date]
    ) {
        self.totalNotes = totalNotes
        self.totalNotebooks = totalNotebooks
        self.totalPages = totalPages
        self.totalWords = totalWords
        self.totalCharacters = totalCharacters
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.perNotebook = perNotebook
        self.dailyActivity = dailyActivity
        self.averagePagesPerNote = averagePagesPerNote
        self.averageWordsPerNote = averageWordsPerNote
        self.activityTrend = activityTrend
        self.wordCountStats = wordCountStats
        self.anomalousDays = anomalousDays
    }
}

// MARK: - NotebookStat

public struct NotebookStat: Identifiable {
    public let id: UUID
    public let name: String
    public let noteCount: Int
    public let pageCount: Int
    public let wordCount: Int

    public init(id: UUID, name: String, noteCount: Int, pageCount: Int, wordCount: Int) {
        self.id = id
        self.name = name
        self.noteCount = noteCount
        self.pageCount = pageCount
        self.wordCount = wordCount
    }
}

// MARK: - WritingInsightsBuilder

public enum WritingInsightsBuilder {

    // MARK: Public

    public static func build(
        notes: [Note],
        notebooks: [Notebook]
    ) -> WritingInsights {
        let totalNotes = notes.count
        let totalNotebooks = notebooks.count
        let totalPages = notes.reduce(0) { $0 + max($1.pages.count, 1) }

        var totalWords = 0
        var totalCharacters = 0
        for note in notes {
            let text = combinedText(for: note)
            totalCharacters += text.count
            totalWords += wordCount(of: text)
        }

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

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let modDates = notes.map { calendar.startOfDay(for: $0.modifiedAt) }

        let (current, longest) = computeStreaks(dates: modDates, today: today, calendar: calendar)
        let dailyActivity = computeDailyActivity(dates: modDates, today: today, calendar: calendar)

        let avgPages = totalNotes > 0 ? Double(totalPages) / Double(totalNotes) : 0
        let avgWords = totalNotes > 0 ? Double(totalWords) / Double(totalNotes) : 0

        let sortedDays: [Date] = (0..<activityWindowDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -(activityWindowDays - 1 - offset), to: today)
        }
        let activitySeries = sortedDays.map { Double(dailyActivity[$0] ?? 0) }
        let activityTrend = TrendAnalyser.analyse(dailyValues: activitySeries)

        let wordCounts = notes.map { Double(wordCount(of: combinedText(for: $0))) }
        let wordCountStats = DescriptiveStats.compute(wordCounts)

        let anomalies = AnomalyDetector.detect(values: activitySeries, threshold: 2.0)
        let anomalousDays = anomalies.map { sortedDays[$0.index] }

        // Suppress unused variable warning
        _ = notebookMap

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
