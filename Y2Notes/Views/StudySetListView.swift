import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showStats = false

    private var displayedSets: [StudySet] {
        if let nbID = notebookID {
            return noteStore.studySets
                .filter { $0.notebookID == nbID }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        }
        return noteStore.studySets.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var totalDue: Int {
        noteStore.studySets.reduce(0) { $0 + noteStore.dueCards(inSet: $1.id).count }
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Study Statistics")

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
        .sheet(isPresented: $showStats) {
            NavigationStack {
                StudyStatsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showStats = false }
                        }
                    }
            }
        }
    }

    // MARK: List

    private var setList: some View {
        List {
            // Due-today summary banner
            if totalDue > 0 {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(totalDue) card\(totalDue == 1 ? "" : "s") due today")
                                .font(.body.weight(.medium))
                            Text("Review now to keep your streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
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

    private var masteredCount: Int {
        noteStore.studyCards.filter { $0.setID == set.id }
            .filter { noteStore.progress(for: $0.id).masteryLevel == .mastered }
            .count
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
                    if masteredCount > 0 {
                        Text("· \(masteredCount) mastered")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
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
    @State private var showBulkImport = false
    @State private var showStudySession = false
    @State private var showTestSession = false
    @State private var showSetStats = false
    @State private var showTestFileImport = false
    @State private var cardToEdit: StudyCard?
    @State private var filterTag: String?

    private var cards: [StudyCard] {
        var result = noteStore.cards(inSet: studySet.id)
        if let tag = filterTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        return result
    }

    private var dueCount: Int {
        noteStore.dueCards(inSet: studySet.id).count
    }

    private var testQuestionCount: Int {
        noteStore.testQuestions(inSet: studySet.id).count
    }

    /// All unique tags across cards in this set.
    private var allTags: [String] {
        let tagSets = noteStore.studyCards
            .filter { $0.setID == studySet.id }
            .flatMap(\.tags)
        return Array(Set(tagSets)).sorted()
    }

    var body: some View {
        Group {
            if cards.isEmpty && filterTag == nil {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle(studySet.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !noteStore.cards(inSet: studySet.id).isEmpty {
                    Button {
                        showStudySession = true
                    } label: {
                        Label("Study", systemImage: "play.fill")
                    }
                    .disabled(dueCount == 0)
                    .accessibilityLabel(dueCount == 0 ? "No cards due" : "Start study session")
                }
                if testQuestionCount > 0 {
                    Button {
                        showTestSession = true
                    } label: {
                        Label("Test", systemImage: "checklist")
                    }
                    .accessibilityLabel("Start multiple-choice test")
                }

                Menu {
                    Button {
                        showAddCard = true
                    } label: {
                        Label("Add Card", systemImage: "plus")
                    }
                    Button {
                        showBulkImport = true
                    } label: {
                        Label("Bulk Import", systemImage: "doc.text")
                    }
                    Button {
                        showTestFileImport = true
                    } label: {
                        Label("Import Test File", systemImage: "doc.badge.plus")
                    }
                    Divider()
                    Button {
                        showSetStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet(setID: studySet.id, onSave: { front, back, tags in
                noteStore.addCard(toSet: studySet.id, front: front, back: back, tags: tags)
            })
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportSheet(setID: studySet.id)
        }
        .sheet(isPresented: $showTestFileImport) {
            TestFileImportSheet(setID: studySet.id)
        }
        .sheet(item: $cardToEdit) { card in
            EditCardSheet(card: card)
        }
        .sheet(isPresented: $showSetStats) {
            NavigationStack {
                StudyStatsView(studySetID: studySet.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSetStats = false }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showStudySession) {
            StudySessionView(studySet: studySet)
        }
        .fullScreenCover(isPresented: $showTestSession) {
            StudyTestSessionView(studySet: studySet)
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
                                    .foregroundStyle(Color(uiColor: .label))
                                Text("\(dueCount) card\(dueCount == 1 ? "" : "s") due today")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if testQuestionCount > 0 {
                Section {
                    Button {
                        showTestSession = true
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.blue, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start Multiple-Choice Test")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color(uiColor: .label))
                                Text("\(testQuestionCount) question\(testQuestionCount == 1 ? "" : "s") available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Tag filter chips
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tagChip(label: "All", isSelected: filterTag == nil) {
                                filterTag = nil
                            }
                            ForEach(allTags, id: \.self) { tag in
                                tagChip(label: tag, isSelected: filterTag == tag) {
                                    filterTag = filterTag == tag ? nil : tag
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }

            Section("Cards (\(cards.count))") {
                ForEach(cards) { card in
                    CardRow(card: card, progress: noteStore.progress(for: card.id))
                        .contentShape(Rectangle())
                        .onTapGesture { cardToEdit = card }
                        .contextMenu {
                            Button {
                                cardToEdit = card
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                noteStore.deleteCard(id: card.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    offsets.map { cards[$0].id }.forEach { noteStore.deleteCard(id: $0) }
                }
            }
        }
    }

    private func tagChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : Color(uiColor: .label))
        }
        .buttonStyle(.plain)
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

            HStack(spacing: 12) {
                Button {
                    showAddCard = true
                } label: {
                    Label("Add Card", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)

                Button {
                    showBulkImport = true
                } label: {
                    Label("Bulk Import", systemImage: "doc.text")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondaryLabel).opacity(0.12), in: Capsule())
                        .foregroundStyle(Color(uiColor: .label))
                }
                .buttonStyle(.plain)

                Button {
                    showTestFileImport = true
                } label: {
                    Label("Import Test File", systemImage: "doc.badge.plus")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
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
                // Mastery badge
                let mastery = progress.masteryLevel
                Label(mastery.displayName, systemImage: mastery.systemImage)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(masteryColor(mastery).opacity(0.12), in: Capsule())
                    .foregroundStyle(masteryColor(mastery))

                if progress.isDueToday && progress.reviewCount > 0 {
                    Text("Due")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                } else if progress.reviewCount > 0 {
                    Text("Due \(progress.dueDate, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Tags
                ForEach(card.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(uiColor: .secondaryLabel).opacity(0.08), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if card.tags.count > 2 {
                    Text("+\(card.tags.count - 2)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func masteryColor(_ level: MasteryLevel) -> Color {
        switch level {
        case .newCard:   return .blue
        case .learning:  return .orange
        case .reviewing: return .purple
        case .mastered:  return .green
        }
    }
}

// MARK: - Add card sheet

private struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    let setID: UUID
    let onSave: (String, String, [String]) -> Void

    @State private var front = ""
    @State private var back = ""
    @State private var tagsText = ""
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
                Section {
                    TextField("Tags (comma separated)", text: $tagsText)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("e.g. chapter 1, key term, formula")
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
                        let tags = tagsText.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave(
                            front.trimmingCharacters(in: .whitespacesAndNewlines),
                            back.trimmingCharacters(in: .whitespacesAndNewlines),
                            tags
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

// MARK: - Edit card sheet

private struct EditCardSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let card: StudyCard

    @State private var front: String
    @State private var back: String
    @State private var tagsText: String

    init(card: StudyCard) {
        self.card = card
        _front = State(initialValue: card.front)
        _back = State(initialValue: card.back)
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
    }

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
                }
                Section("Back") {
                    TextEditor(text: $back)
                        .frame(minHeight: 80)
                }
                Section {
                    TextField("Tags (comma separated)", text: $tagsText)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("e.g. chapter 1, key term, formula")
                }

                // Card progress info
                let progress = noteStore.progress(for: card.id)
                Section("Progress") {
                    LabeledContent("Reviews", value: "\(progress.reviewCount)")
                    LabeledContent("Interval", value: "\(progress.interval) day\(progress.interval == 1 ? "" : "s")")
                    LabeledContent("Ease Factor", value: String(format: "%.2f", progress.easeFactor))
                    LabeledContent("Mastery", value: progress.masteryLevel.displayName)
                    if let lastReview = progress.lastReviewedAt {
                        LabeledContent("Last Reviewed", value: lastReview, format: .dateTime)
                    }
                    LabeledContent("Next Due", value: progress.dueDate, format: .dateTime)
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
                        noteStore.updateCard(id: card.id, front: trimmedFront, back: trimmedBack)

                        let tags = tagsText.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        noteStore.updateCardTags(id: card.id, tags: tags)

                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Bulk import sheet

private struct BulkImportSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let setID: UUID

    @State private var bulkText = ""
    @State private var importedCount: Int?

    private var previewLines: [(front: String, back: String)] {
        bulkText.components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "::")
                guard parts.count >= 2 else { return nil }
                let f = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let b = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !f.isEmpty, !b.isEmpty else { return nil }
                return (front: f, back: b)
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $bulkText)
                        .frame(minHeight: 160)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Cards")
                } footer: {
                    Text("One card per line. Separate front and back with \"::\"\nExample: What is 2+2? :: 4")
                }

                if !previewLines.isEmpty {
                    Section("Preview (\(previewLines.count) card\(previewLines.count == 1 ? "" : "s"))") {
                        ForEach(previewLines.prefix(5), id: \.front) { pair in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.front)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(pair.back)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if previewLines.count > 5 {
                            Text("… and \(previewLines.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let count = importedCount {
                    Section {
                        Label("Imported \(count) card\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let imported = noteStore.bulkImportCards(toSet: setID, text: bulkText)
                        importedCount = imported
                        if imported > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(previewLines.isEmpty)
                }
            }
        }
    }
}

// MARK: - Test file import sheet

private struct TestFileImportSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let setID: UUID

    @State private var showImporter = false
    @State private var fileName: String?
    @State private var importData: Data?
    @State private var payloadPreview: StudyTestImportPayload?
    @State private var errorMessage: String?
    @State private var importSummary: StudyTestImportSummary?

    private let importSuccessDelay: TimeInterval = 0.8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label(fileName ?? "Choose JSON File", systemImage: "doc")
                    }
                } header: {
                    Text("File")
                } footer: {
                    Text("Use JSON schema version 1 with set metadata and questions (prompt, options, correctOptionIndex, explanation).")
                }

                if let errorMessage {
                    Section("Validation Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let payloadPreview {
                    Section("Preview") {
                        LabeledContent("Title", value: payloadPreview.set.title)
                        if let description = payloadPreview.set.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Questions", value: "\(payloadPreview.questions.count)")
                    }

                    Section("Sample Questions") {
                        ForEach(Array(payloadPreview.questions.prefix(3).enumerated()), id: \.offset) { _, question in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(question.prompt)
                                    .font(.subheadline.weight(.medium))
                                Text("Options: \(question.options.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let summary = importSummary {
                    Section("Import Result") {
                        Text("Added: \(summary.addedCount)")
                        Text("Skipped: \(summary.skippedCount)")
                        Text("Invalid: \(summary.invalidCount)")
                        ForEach(summary.messages, id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import Test File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        guard let importData else { return }
                        let summary = noteStore.importTestQuestions(toSet: setID, jsonData: importData)
                        importSummary = summary
                        if summary.invalidCount == 0 && summary.addedCount > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + importSuccessDelay) { dismiss() }
                        }
                    }
                    .disabled(importData == nil || payloadPreview == nil)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    do {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        let data = try Data(contentsOf: url)
                        fileName = url.lastPathComponent
                        importData = data
                        switch noteStore.testImportPreview(from: data) {
                        case let .success(payload):
                            payloadPreview = payload
                            errorMessage = nil
                        case let .failure(error):
                            payloadPreview = nil
                            errorMessage = error.localizedDescription
                        }
                    } catch {
                        payloadPreview = nil
                        errorMessage = error.localizedDescription
                    }
                case let .failure(error):
                    payloadPreview = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
