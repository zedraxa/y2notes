import SwiftUI

// MARK: - WritingInsightsView

/// Dashboard showing writing statistics, streaks, and activity heatmap.
///
/// Inspired by:
/// - **Obsidian Stats Plugin** — note counts, word counts, writing streaks
/// - **iA Writer** — clean typography and focused document statistics
/// - **GitHub Contribution Graph** — daily activity heatmap
struct WritingInsightsView: View {

    @EnvironmentObject var noteStore: NoteStore

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summaryCardsGrid
                    streakSection
                    activityHeatmap
                    notebookBreakdown
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(NSLocalizedString("Insights.Title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("General.Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Computed Insights

    private var insights: WritingInsights {
        WritingInsightsBuilder.build(
            notes: noteStore.notes,
            notebooks: noteStore.notebooks
        )
    }

    // MARK: - Summary Cards

    private var summaryCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            statCard(
                title: NSLocalizedString("Insights.TotalNotes", comment: ""),
                value: "\(insights.totalNotes)",
                icon: "doc.text",
                tint: .blue
            )
            statCard(
                title: NSLocalizedString("Insights.TotalPages", comment: ""),
                value: "\(insights.totalPages)",
                icon: "doc.on.doc",
                tint: .indigo
            )
            statCard(
                title: NSLocalizedString("Insights.TotalWords", comment: ""),
                value: formattedNumber(insights.totalWords),
                icon: "textformat.abc",
                tint: .purple
            )
            statCard(
                title: NSLocalizedString("Insights.Notebooks", comment: ""),
                value: "\(insights.totalNotebooks)",
                icon: "books.vertical",
                tint: .orange
            )
            statCard(
                title: NSLocalizedString("Insights.AvgPages", comment: ""),
                value: String(format: "%.1f", insights.averagePagesPerNote),
                icon: "chart.bar",
                tint: .teal
            )
            statCard(
                title: NSLocalizedString("Insights.AvgWords", comment: ""),
                value: formattedNumber(Int(insights.averageWordsPerNote)),
                icon: "chart.line.uptrend.xyaxis",
                tint: .mint
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title.bold())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Insights.Streaks", comment: ""))
                .font(.headline)

            HStack(spacing: 16) {
                streakBadge(
                    label: NSLocalizedString("Insights.CurrentStreak", comment: ""),
                    days: insights.currentStreak,
                    icon: "flame.fill",
                    tint: .orange
                )
                streakBadge(
                    label: NSLocalizedString("Insights.LongestStreak", comment: ""),
                    days: insights.longestStreak,
                    icon: "trophy.fill",
                    tint: .yellow
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func streakBadge(
        label: String,
        days: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading) {
                Text("\(days)")
                    .font(.title2.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(days) days")
    }

    // MARK: - Activity Heatmap

    private var activityHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Insights.Activity", comment: ""))
                .font(.headline)
            Text(NSLocalizedString("Insights.ActivitySubtitle", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)

            heatmapGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A 13-week (91-day) heatmap grid rendered as colored squares.
    private var heatmapGrid: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activity = insights.dailyActivity

        // Build 91 days of data (13 full weeks).
        let days: [Date] = (0..<91).compactMap { offset in
            calendar.date(byAdding: .day, value: -(90 - offset), to: today)
        }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 13),
            spacing: 3
        ) {
            ForEach(days, id: \.self) { day in
                let count = activity[day] ?? 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatmapColor(for: count))
                    .frame(width: 14, height: 14)
                    .accessibilityLabel(heatmapAccessibilityLabel(date: day, count: count))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0: return Color(.systemGray5)
        case 1: return .green.opacity(0.3)
        case 2...3: return .green.opacity(0.55)
        case 4...6: return .green.opacity(0.75)
        default: return .green
        }
    }

    private func heatmapAccessibilityLabel(date: Date, count: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateStr = formatter.string(from: date)
        return count == 0
            ? "\(dateStr): no edits"
            : "\(dateStr): \(count) edit\(count == 1 ? "" : "s")"
    }

    // MARK: - Notebook Breakdown

    private var notebookBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Insights.PerNotebook", comment: ""))
                .font(.headline)

            let stats = Array(insights.perNotebook.values)
                .sorted { $0.noteCount > $1.noteCount }

            if stats.isEmpty {
                Text(NSLocalizedString("Insights.NoNotebooks", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(stats) { stat in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(stat.noteCount) notes · \(stat.pageCount) pages · \(formattedNumber(stat.wordCount)) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        notebookBar(stat: stat)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func notebookBar(stat: NotebookStat) -> some View {
        let maxNotes = insights.perNotebook.values.map(\.noteCount).max() ?? 1
        let fraction = maxNotes > 0 ? CGFloat(stat.noteCount) / CGFloat(maxNotes) : 0

        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.6))
            .frame(width: max(4, fraction * 80), height: 16)
            .accessibilityHidden(true)
    }

    // MARK: - Formatting

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
