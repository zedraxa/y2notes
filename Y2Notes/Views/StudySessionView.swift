import SwiftUI

// MARK: - Study session view

/// Full-screen active recall session over the due cards in a study set.
///
/// Displays one card at a time: front first, tap to reveal back, then rate difficulty.
/// Progress is persisted to `NoteStore` via SM-2 after each rating.
struct StudySessionView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let studySet: StudySet

    // The queue of cards to review in this session (due today + new).
    @State private var queue: [StudyCard] = []
    // Index of the card currently being shown.
    @State private var currentIndex: Int = 0
    // Whether the back of the card has been flipped up.
    @State private var isFlipped = false
    // Degree of the flip animation (0 = front, 180 = back).
    @State private var flipDegrees: Double = 0
    // Cards rated "Again" in this session (returned to the queue at the end).
    @State private var againCards: [StudyCard] = []
    // Number of cards completed (rated good/easy/hard) this session.
    @State private var completedCount = 0
    // True when the session queue is exhausted.
    @State private var sessionFinished = false
    // Per-rating counts for session summary.
    @State private var ratingCounts: [ReviewRating: Int] = [:]
    // Session start time for duration tracking.
    @State private var sessionStartTime: Date = Date()

    var body: some View {
        NavigationStack {
            Group {
                if sessionFinished {
                    finishedView
                } else if queue.isEmpty {
                    noDueCardsView
                } else {
                    cardView
                }
            }
            .navigationTitle(studySet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            sessionStartTime = Date()
            queue = noteStore.dueCards(inSet: studySet.id)
            if queue.isEmpty {
                // Include new (never-reviewed) cards that happen to not be "due" yet.
                queue = noteStore.cards(inSet: studySet.id).filter {
                    noteStore.progress(for: $0.id).reviewCount == 0
                }
            }
        }
    }

    // MARK: Card view

    @ViewBuilder
    private var cardView: some View {
        let card = queue[currentIndex]

        VStack(spacing: 0) {
            // ── Progress bar ──────────────────────────────────────────────
            progressBar
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            // ── Flashcard ─────────────────────────────────────────────────
            ZStack {
                cardFace(text: card.front, isFront: true)
                    .opacity(isFlipped ? 0 : 1)
                cardFace(text: card.back, isFront: false)
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(.degrees(flipDegrees), axis: (x: 0, y: 1, z: 0))
            .onTapGesture { flipCard() }
            .frame(maxWidth: 600)
            .padding(.horizontal)

            Spacer()

            // ── Rating buttons (only after flip) ─────────────────────────
            if isFlipped {
                ratingButtons(for: card)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            } else {
                tapHint
                    .padding(.bottom, 32)
            }
        }
        .animation(.spring(duration: 0.3), value: isFlipped)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Card face

    private func cardFace(text: String, isFront: Bool) -> some View {
        VStack(spacing: 12) {
            Text(isFront ? "QUESTION" : "ANSWER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(1)

            ScrollView {
                Text(text.isEmpty ? (isFront ? "No front text" : "No back text") : text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 280)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: Rating buttons

    private func ratingButtons(for card: StudyCard) -> some View {
        HStack(spacing: 12) {
            ForEach(ReviewRating.allCases) { rating in
                Button {
                    rate(card: card, rating: rating)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: rating.systemImage)
                            .font(.system(size: 18, weight: .medium))
                        Text(rating.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ratingColor(rating).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(ratingColor(rating))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ratingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return .green
        case .easy:  return .blue
        }
    }

    // MARK: Tap hint

    private var tapHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.caption)
            Text("Tap card to reveal answer")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: Progress bar

    private var progressBar: some View {
        let total = max(queue.count, 1)
        let fraction = Double(completedCount) / Double(total + completedCount)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(completedCount) of \(completedCount + queue.count) reviewed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(queue.count) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .secondaryLabel).opacity(0.15))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(geo.size.width * fraction, 0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: No cards due

    private var noDueCardsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.tint)
            Text("All Caught Up!")
                .font(.title2.weight(.medium))
            Text("No cards are due right now. Come back later or add more cards to the set.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Finished

    private var finishedView: some View {
        let duration = Int(Date().timeIntervalSince(sessionStartTime))
        let minutes = duration / 60
        let seconds = duration % 60
        let totalRatings = ratingCounts.values.reduce(0, +)
        let goodOrBetter = (ratingCounts[.good, default: 0] + ratingCounts[.easy, default: 0])
        let accuracy = totalRatings > 0 ? Double(goodOrBetter) / Double(totalRatings) * 100 : 0

        return ScrollView {
            VStack(spacing: 24) {
                // Celebration
                Image(systemName: "star.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                Text("Session Complete!")
                    .font(.title.weight(.bold))
                Text("You reviewed \(completedCount) card\(completedCount == 1 ? "" : "s").")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                // Session stats
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    sessionStatCard(
                        title: "Duration",
                        value: minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s",
                        icon: "timer",
                        color: .blue
                    )
                    sessionStatCard(
                        title: "Accuracy",
                        value: String(format: "%.0f%%", accuracy),
                        icon: "target",
                        color: accuracy >= 80 ? .green : .orange
                    )
                }
                .padding(.horizontal)

                // Rating breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rating Breakdown")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        ForEach(ReviewRating.allCases) { rating in
                            let count = ratingCounts[rating, default: 0]
                            VStack(spacing: 4) {
                                Image(systemName: rating.systemImage)
                                    .font(.system(size: 16))
                                    .foregroundStyle(ratingColor(rating))
                                Text("\(count)")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                Text(rating.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(ratingColor(rating).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                }

                if !againCards.isEmpty {
                    Text("\(againCards.count) card\(againCards.count == 1 ? "" : "s") marked \"Again\" — review them again tomorrow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func sessionStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Actions

    private func flipCard() {
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 20)) {
            flipDegrees += 180
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isFlipped.toggle()
        }
    }

    private func rate(card: StudyCard, rating: ReviewRating) {
        noteStore.recordReview(cardID: card.id, rating: rating)
        ratingCounts[rating, default: 0] += 1

        if rating == .again {
            againCards.append(card)
        } else {
            completedCount += 1
        }

        // Advance to next card.
        var next = queue
        next.remove(at: currentIndex)
        if next.isEmpty {
            // Re-queue "again" cards for a second pass.
            if !againCards.isEmpty {
                next = againCards
                againCards = []
                currentIndex = 0
            } else {
                sessionFinished = true
                queue = []
                return
            }
        }
        queue = next
        currentIndex = min(currentIndex, queue.count - 1)

        // Reset flip state for the next card.
        isFlipped = false
        flipDegrees = 0
    }
}
