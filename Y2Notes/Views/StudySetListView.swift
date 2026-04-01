import SwiftUI

// MARK: - Study set list

/// Displays all study sets, optionally filtered to a specific notebook.
/// From here users can create sets, navigate into a set's cards, and start a review session.
struct StudySetListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    /// When non-nil, only study sets linked to this notebook are shown.
    var notebookID: UUID?

    @State private var showNewSetAlert = false
    @State private var newSetTitle = ""
    @State private var setToRename: StudySet?
    @State private var renameText = ""

    private var displayedSets: [StudySet] {
        if let nbID = notebookID {
            return noteStore.studySets
                .filter { $0.notebookID == nbID }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        }
        return noteStore.studySets.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        Group {
            if displayedSets.isEmpty {
                emptyState
            } else {
                setList
            }
        }
        .navigationTitle("Study Sets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newSetTitle = ""
                    showNewSetAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Study Set")
            }
        }
        .alert("New Study Set", isPresented: $showNewSetAlert) {
            TextField("Set name", text: $newSetTitle)
                .submitLabel(.done)
            Button("Create") {
                let t = newSetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    noteStore.addStudySet(title: t, notebookID: notebookID)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Set", isPresented: Binding(
            get: { setToRename != nil },
            set: { if !$0 { setToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
                .submitLabel(.done)
            Button("Rename") {
                if let s = setToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    noteStore.renameStudySet(id: s.id, title: renameText.trimmingCharacters(in: .whitespaces))
                }
                setToRename = nil
            }
            Button("Cancel", role: .cancel) { setToRename = nil }
        }
    }

    // MARK: List

    private var setList: some View {
        List {
            ForEach(displayedSets) { set in
                NavigationLink(destination: StudyCardListView(studySet: set)) {
                    StudySetRow(set: set, noteStore: noteStore)
                }
                .contextMenu {
                    Button {
                        setToRename = set
                        renameText = set.title
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        noteStore.deleteStudySet(id: set.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { displayedSets[$0].id }.forEach {
                    noteStore.deleteStudySet(id: $0)
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No Study Sets Yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Create a set to start building flashcards from your notes.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button {
                newSetTitle = ""
                showNewSetAlert = true
            } label: {
                Label("New Study Set", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Study set row

private struct StudySetRow: View {
    let set: StudySet
    let noteStore: NoteStore

    private var totalCards: Int {
        noteStore.studyCards.filter { $0.setID == set.id }.count
    }

    private var dueCount: Int {
        noteStore.dueCards(inSet: set.id).count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon swatch
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(set.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(totalCards) card\(totalCards == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if dueCount > 0 {
                        Text("· \(dueCount) due")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Card list inside a study set

struct StudyCardListView: View {
    @EnvironmentObject var noteStore: NoteStore
    let studySet: StudySet

    @State private var showAddCard = false
    @State private var showStudySession = false
    @State private var newFront = ""
    @State private var newBack = ""

    private var cards: [StudyCard] {
        noteStore.cards(inSet: studySet.id)
    }

    private var dueCount: Int {
        noteStore.dueCards(inSet: studySet.id).count
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle(studySet.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !cards.isEmpty {
                    Button {
                        showStudySession = true
                    } label: {
                        Label("Study", systemImage: "play.fill")
                    }
                    .disabled(dueCount == 0)
                    .accessibilityLabel(dueCount == 0 ? "No cards due" : "Start study session")
                }
                Button {
                    newFront = ""
                    newBack = ""
                    showAddCard = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Card")
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet(setID: studySet.id, onSave: { front, back in
                noteStore.addCard(toSet: studySet.id, front: front, back: back)
            })
        }
        .fullScreenCover(isPresented: $showStudySession) {
            StudySessionView(studySet: studySet)
        }
    }

    // MARK: Card list

    private var cardList: some View {
        List {
            if dueCount > 0 {
                Section {
                    Button {
                        showStudySession = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.tint, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Review")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("\(dueCount) card\(dueCount == 1 ? "" : "s") due today")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Cards (\(cards.count))") {
                ForEach(cards) { card in
                    CardRow(card: card, progress: noteStore.progress(for: card.id))
                }
                .onDelete { offsets in
                    offsets.map { cards[$0].id }.forEach { noteStore.deleteCard(id: $0) }
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No Cards Yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Add your first flashcard to get started.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button {
                newFront = ""
                newBack = ""
                showAddCard = true
            } label: {
                Label("Add Card", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showAddCard) {
            AddCardSheet(setID: studySet.id, onSave: { front, back in
                noteStore.addCard(toSet: studySet.id, front: front, back: back)
            })
        }
    }
}

// MARK: - Card row

private struct CardRow: View {
    let card: StudyCard
    let progress: StudyCardProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .font(.body)
                .lineLimit(2)
            Text(card.back)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                if progress.reviewCount == 0 {
                    Text("New")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                } else if progress.isDueToday {
                    Text("Due")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                } else {
                    Text("Due \(progress.dueDate, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add card sheet

private struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    let setID: UUID
    let onSave: (String, String) -> Void

    @State private var front = ""
    @State private var back = ""
    @FocusState private var frontFocused: Bool

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Front") {
                    TextEditor(text: $front)
                        .frame(minHeight: 80)
                        .focused($frontFocused)
                }
                Section("Back") {
                    TextEditor(text: $back)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(
                            front.trimmingCharacters(in: .whitespacesAndNewlines),
                            back.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { frontFocused = true }
        }
    }
}
