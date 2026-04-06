import SwiftUI

// MARK: - Widget Editor

/// Full-content editor sheet for any NoteWidget type.
/// Presented when the user taps "Edit" in WidgetHandlesView.
struct WidgetEditorView: View {
    @State private var widget: NoteWidget
    var onSave: (NoteWidget) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Haptics

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let successFeedback = UINotificationFeedbackGenerator()

    init(widget: NoteWidget, onSave: @escaping (NoteWidget) -> Void) {
        self._widget = State(initialValue: widget)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                contentSection
            }
            .navigationTitle(editorTitle(for: widget.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        successFeedback.notificationOccurred(.success)
                        onSave(widget)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Content dispatch

    @ViewBuilder
    private var contentSection: some View {
        switch widget.payload {
        case .checklist(let title, let items):
            checklistSection(title: title, items: items)
        case .quickTable(let title, let columns, let rows, let cells, let hasHeaderRow):
            tableSection(title: title, columns: columns, rows: rows, cells: cells, hasHeaderRow: hasHeaderRow)
        case .calloutBox(let title, let body, let style):
            calloutSection(title: title, body: body, style: style)
        case .referenceCard(let title, let body):
            referenceSection(title: title, body: body)
        case .stickyNote(let body, let color):
            stickyNoteSection(body: body, color: color)
        case .flashcard(let front, let back, let isFlipped, let confidenceLevel):
            flashcardSection(front: front, back: back, isFlipped: isFlipped, confidenceLevel: confidenceLevel)
        case .progressTracker(let title, let current, let total):
            progressSection(title: title, current: current, total: total)
        }
    }

    // MARK: - Checklist

    @ViewBuilder
    private func checklistSection(title: String, items: [ChecklistItem]) -> some View {
        Section("Title") {
            TextField("Checklist title", text: Binding(
                get: { title },
                set: { widget.payload = .checklist(title: $0, items: items) }
            ))
        }
        Section {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Button {
                        selectionFeedback.selectionChanged()
                        toggleItem(item, in: items, title: title)
                    } label: {
                        Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isChecked ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isChecked
                        ? NSLocalizedString("WidgetEditor.ItemChecked", comment: "Checked")
                        : NSLocalizedString("WidgetEditor.ItemUnchecked", comment: "Unchecked"))
                    .accessibilityHint(NSLocalizedString("WidgetEditor.ToggleHint", comment: "Toggle completion"))

                    TextField("Item text", text: itemTextBinding(item, items: items, title: title))
                        .strikethrough(item.isChecked, color: .secondary)

                    Spacer()

                    Menu {
                        ForEach(ChecklistPriority.allCases, id: \.self) { p in
                            Button {
                                selectionFeedback.selectionChanged()
                                setPriority(p, on: item, in: items, title: title)
                            } label: {
                                Label(p.displayName, systemImage: p.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: item.priority.iconName)
                            .foregroundStyle(priorityColor(item.priority))
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("WidgetEditor.Priority", comment: "Priority: ") + item.priority.displayName)
                }
            }
            .onDelete { offsets in
                var updated = items
                updated.remove(atOffsets: offsets)
                widget.payload = .checklist(title: title, items: updated)
            }
            .onMove { from, to in
                var updated = items
                updated.move(fromOffsets: from, toOffset: to)
                widget.payload = .checklist(title: title, items: updated)
            }

            Button {
                var updated = items
                updated.append(ChecklistItem())
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    widget.payload = .checklist(title: title, items: updated)
                }
                selectionFeedback.selectionChanged()
            } label: {
                Label(NSLocalizedString("WidgetEditor.AddItem", comment: "Add Item"), systemImage: "plus.circle.fill")
            }
            .accessibilityHint(NSLocalizedString("WidgetEditor.AddItemHint", comment: "Adds a new checklist item"))
        } header: {
            Text("Items")
        }
    }

    private func toggleItem(_ item: ChecklistItem, in items: [ChecklistItem], title: String) {
        var updated = items
        if let idx = updated.firstIndex(where: { $0.id == item.id }) {
            updated[idx].isChecked.toggle()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            widget.payload = .checklist(title: title, items: updated)
        }
    }

    private func itemTextBinding(_ item: ChecklistItem, items: [ChecklistItem], title: String) -> Binding<String> {
        Binding(
            get: { item.text },
            set: { newText in
                var updated = items
                if let idx = updated.firstIndex(where: { $0.id == item.id }) {
                    updated[idx].text = newText
                }
                widget.payload = .checklist(title: title, items: updated)
            }
        )
    }

    private func setPriority(_ priority: ChecklistPriority, on item: ChecklistItem,
                              in items: [ChecklistItem], title: String) {
        var updated = items
        if let idx = updated.firstIndex(where: { $0.id == item.id }) {
            updated[idx].priority = priority
        }
        widget.payload = .checklist(title: title, items: updated)
    }

    private func priorityColor(_ priority: ChecklistPriority) -> Color {
        switch priority {
        case .none:   return .secondary
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }

    // MARK: - Quick Table

    @ViewBuilder
    private func tableSection(title: String, columns: Int, rows: Int,
                               cells: [TableCell], hasHeaderRow: Bool) -> some View {
        Section("Options") {
            TextField("Table title", text: Binding(
                get: { title },
                set: { widget.payload = .quickTable(title: $0, columns: columns, rows: rows,
                                                     cells: cells, hasHeaderRow: hasHeaderRow) }
            ))
            Toggle("Header Row", isOn: Binding(
                get: { hasHeaderRow },
                set: { widget.payload = .quickTable(title: title, columns: columns, rows: rows,
                                                     cells: cells, hasHeaderRow: $0) }
            ))
        }
        Section("Cells") {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { c in
                        let idx = r * columns + c
                        let placeholder = hasHeaderRow && r == 0 ? "Header \(c + 1)" : "Cell"
                        TextField(placeholder, text: Binding(
                            get: { idx < cells.count ? cells[idx].text : "" },
                            set: { newVal in
                                var updated = cells
                                if idx < updated.count {
                                    updated[idx].text = newVal
                                }
                                widget.payload = .quickTable(title: title, columns: columns, rows: rows,
                                                              cells: updated, hasHeaderRow: hasHeaderRow)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(hasHeaderRow && r == 0 ? .system(size: 13, weight: .semibold) : .system(size: 13))
                        .frame(minWidth: 0)
                    }
                }
            }
        }
    }

    // MARK: - Callout Box

    @ViewBuilder
    private func calloutSection(title: String, body: String, style: CalloutStyle) -> some View {
        Section("Style") {
            Picker("Style", selection: Binding(
                get: { style },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        widget.payload = .calloutBox(title: title, body: body, style: newValue)
                    }
                }
            )) {
                ForEach(CalloutStyle.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Content") {
            TextField("Title", text: Binding(
                get: { title },
                set: { widget.payload = .calloutBox(title: $0, body: body, style: style) }
            ))
            TextField("Body", text: Binding(
                get: { body },
                set: { widget.payload = .calloutBox(title: title, body: $0, style: style) }
            ), axis: .vertical)
            .lineLimit(4...)
        }
    }

    // MARK: - Reference Card

    @ViewBuilder
    private func referenceSection(title: String, body: String) -> some View {
        Section("Content") {
            TextField("Title", text: Binding(
                get: { title },
                set: { widget.payload = .referenceCard(title: $0, body: body) }
            ))
            TextField("Body", text: Binding(
                get: { body },
                set: { widget.payload = .referenceCard(title: title, body: $0) }
            ), axis: .vertical)
            .lineLimit(4...)
        }
    }

    // MARK: - Sticky Note

    @ViewBuilder
    private func stickyNoteSection(body: String, color: StickyNoteColor) -> some View {
        Section("Color") {
            Picker("Color", selection: Binding(
                get: { color },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        widget.payload = .stickyNote(body: body, color: newValue)
                    }
                }
            )) {
                ForEach(StickyNoteColor.allCases, id: \.self) { c in
                    Text(c.displayName).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
        Section("Note") {
            TextField("Write your note...", text: Binding(
                get: { body },
                set: { widget.payload = .stickyNote(body: $0, color: color) }
            ), axis: .vertical)
            .lineLimit(6...)
        }
    }

    // MARK: - Flashcard

    @ViewBuilder
    private func flashcardSection(front: String, back: String,
                                   isFlipped: Bool, confidenceLevel: Int) -> some View {
        Section("Front") {
            TextField("Question or term", text: Binding(
                get: { front },
                set: { widget.payload = .flashcard(front: $0, back: back, isFlipped: isFlipped,
                                                    confidenceLevel: confidenceLevel) }
            ), axis: .vertical)
            .lineLimit(3...)
        }
        Section("Back") {
            TextField("Answer or definition", text: Binding(
                get: { back },
                set: { widget.payload = .flashcard(front: front, back: $0, isFlipped: isFlipped,
                                                    confidenceLevel: confidenceLevel) }
            ), axis: .vertical)
            .lineLimit(3...)
        }
        Section {
            HStack(spacing: 14) {
                ForEach(1...4, id: \.self) { i in
                    Button {
                        let newLevel = i == confidenceLevel ? 0 : i
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            widget.payload = .flashcard(front: front, back: back, isFlipped: isFlipped,
                                                        confidenceLevel: newLevel)
                        }
                        selectionFeedback.selectionChanged()
                    } label: {
                        Image(systemName: i <= confidenceLevel ? "star.fill" : "star")
                            .foregroundStyle(i <= confidenceLevel ? Color.yellow : Color.secondary)
                            .font(.title3)
                            .scaleEffect(i <= confidenceLevel ? 1.0 : 0.85)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: confidenceLevel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i) \(i == 1 ? "star" : "stars")")
                    .accessibilityAddTraits(i <= confidenceLevel ? .isSelected : [])
                }
                Spacer()
                Text(confidenceName(confidenceLevel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: confidenceLevel)
            }
        } header: {
            Text("Confidence")
        }
    }

    // MARK: - Progress Tracker

    @ViewBuilder
    private func progressSection(title: String, current: Int, total: Int) -> some View {
        Section("Goal") {
            TextField("Goal title", text: Binding(
                get: { title },
                set: { widget.payload = .progressTracker(title: $0, current: current, total: total) }
            ))
            Stepper("Goal: \(total)", value: Binding(
                get: { total },
                set: {
                    let newTotal = max($0, 1)
                    widget.payload = .progressTracker(title: title,
                                                       current: min(current, newTotal),
                                                       total: newTotal)
                }
            ), in: 1...9999)
        }
        Section("Progress") {
            Stepper("Current: \(current)", value: Binding(
                get: { current },
                set: {
                    widget.payload = .progressTracker(title: title,
                                                       current: max(0, min($0, total)),
                                                       total: total)
                }
            ), in: 0...total)

            HStack {
                Button("Reset") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        widget.payload = .progressTracker(title: title, current: 0, total: total)
                    }
                    selectionFeedback.selectionChanged()
                }
                .foregroundStyle(.orange)
                .accessibilityHint(NSLocalizedString("WidgetEditor.ResetHint", comment: "Resets progress to zero"))

                Spacer()

                Button("Mark Complete") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        widget.payload = .progressTracker(title: title, current: total, total: total)
                    }
                    successFeedback.notificationOccurred(.success)
                }
                .foregroundStyle(.green)
                .accessibilityHint(NSLocalizedString("WidgetEditor.CompleteHint", comment: "Sets progress to the goal"))
            }
        }
    }

    // MARK: - Helpers

    private func editorTitle(for kind: WidgetKind) -> String {
        switch kind {
        case .checklist:        return "Edit Checklist"
        case .quickTable:       return "Edit Table"
        case .calloutBox:       return "Edit Callout"
        case .referenceCard:    return "Edit Reference Card"
        case .stickyNote:       return "Edit Sticky Note"
        case .flashcard:        return "Edit Flashcard"
        case .progressTracker:  return "Edit Progress"
        }
    }

    private func confidenceName(_ level: Int) -> String {
        switch level {
        case 0:  return "Not rated"
        case 1:  return "Learning"
        case 2:  return "Familiar"
        case 3:  return "Confident"
        case 4:  return "Mastered"
        default: return ""
        }
    }
}
