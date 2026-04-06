import SwiftUI

// MARK: - Note flashcard creation sheet

/// Sheet presented from the note editor to create flashcards linked to the current note.
/// Users can pick an existing study set or create a new one, then add one or more cards.
struct NoteFlashcardSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var selectedSetID: UUID?
    @State private var showNewSetAlert = false
    @State private var newSetTitle = ""
    @State private var front = ""
    @State private var back = ""
    @State private var tagsText = ""
    @State private var cardsCreated = 0
    @FocusState private var frontFocused: Bool

    private var canSave: Bool {
        selectedSetID != nil &&
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pre-fill the back with the note's typed text if it's short enough to be useful.
    private var suggestedBack: String {
        let text = note.typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 200 ? text : ""
    }

    var body: some View {
        NavigationStack {
            Form {
                // Study set picker
                Section {
                    if noteStore.studySets.isEmpty {
                        Button {
                            showNewSetAlert = true
                        } label: {
                            Label("Create a Study Set First", systemImage: "plus.circle")
                        }
                    } else {
                        Picker("Study Set", selection: $selectedSetID) {
                            Text("Select a set…").tag(nil as UUID?)
                            ForEach(noteStore.studySets) { set in
                                Text(set.title).tag(set.id as UUID?)
                            }
                        }

                        Button {
                            showNewSetAlert = true
                        } label: {
                            Label("New Set", systemImage: "plus")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Study Set")
                }

                // Card content
                Section("Front (Question)") {
                    TextEditor(text: $front)
                        .frame(minHeight: 70)
                        .focused($frontFocused)
                }

                Section("Back (Answer)") {
                    TextEditor(text: $back)
                        .frame(minHeight: 70)
                }

                Section {
                    TextField("Tags (comma separated)", text: $tagsText)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("e.g. chapter 1, key term")
                }

                // Summary
                if cardsCreated > 0 {
                    Section {
                        Label(
                            "\(cardsCreated) card\(cardsCreated == 1 ? "" : "s") created from this note",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Create Flashcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Card") {
                        guard let setID = selectedSetID else { return }
                        let tags = tagsText.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        noteStore.addCard(
                            toSet: setID,
                            front: front.trimmingCharacters(in: .whitespacesAndNewlines),
                            back: back.trimmingCharacters(in: .whitespacesAndNewlines),
                            noteID: note.id,
                            tags: tags
                        )
                        cardsCreated += 1
                        // Clear for next card
                        front = ""
                        back = ""
                        frontFocused = true
                    }
                    .disabled(!canSave)
                }
            }
            .alert("New Study Set", isPresented: $showNewSetAlert) {
                TextField("Set name", text: $newSetTitle)
                    .submitLabel(.done)
                Button("Create") {
                    let t = newSetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        let newSet = noteStore.addStudySet(
                            title: t,
                            notebookID: note.notebookID
                        )
                        selectedSetID = newSet.id
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                // Auto-select the most recent study set linked to this notebook.
                if let notebookID = note.notebookID {
                    selectedSetID = noteStore.studySets
                        .first { $0.notebookID == notebookID }?.id
                }
                if selectedSetID == nil {
                    selectedSetID = noteStore.studySets.first?.id
                }
                // Pre-fill front with note title if non-empty
                if front.isEmpty, !note.title.isEmpty {
                    front = note.title
                }
                // Pre-fill back with typed text if short
                if back.isEmpty, !suggestedBack.isEmpty {
                    back = suggestedBack
                }
                frontFocused = true
            }
        }
    }
}
