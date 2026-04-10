import SwiftUI
import PencilKit

// MARK: - HomeView

/// Dashboard landing page shown when "Home" is selected in the sidebar.
///
/// Provides at-a-glance access to recent work, pinned notebooks,
/// quick creation actions, and study-due counts.
struct HomeView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore: PDFStore
    @Environment(TabWorkspaceStore.self) private var tabSession

    /// Called when the user taps a note card.
    let onSelectNote: (UUID) -> Void
    /// Called when the user taps a notebook cover.
    let onOpenNotebook: (UUID) -> Void

    @State private var showNoteCreationSheet = false
    @State private var showNotebookWizard = false
    @State private var showPDFImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                quickActionsSection
                continueSection
                pinnedNotebooksSection
                studyDueSection
                recentActivitySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Home")
        .sheet(isPresented: $showNoteCreationSheet) {
            NoteCreationSheet(onCreated: { id in onSelectNote(id) })
        }
        .sheet(isPresented: $showNotebookWizard) {
            NotebookQuickCreator()
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let record = pdfStore.importPDF(from: url) {
                    tabSession.openTab(
                        .pdf(id: record.id),
                        displayName: record.title,
                        accentColor: [0.8, 0.3, 0.3]
                    )
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                HomeQuickActionButton(
                    title: NSLocalizedString("Home.QuickNote", comment: ""),
                    systemImage: "square.and.pencil",
                    tint: .blue
                ) {
                    let note = noteStore.addNote()
                    onSelectNote(note.id)
                }

                HomeQuickActionButton(
                    title: NSLocalizedString("Home.NewNote", comment: ""),
                    systemImage: "doc.badge.plus",
                    tint: .green
                ) {
                    showNoteCreationSheet = true
                }

                HomeQuickActionButton(
                    title: NSLocalizedString("Home.NewNotebook", comment: ""),
                    systemImage: "book.closed.fill",
                    tint: .purple
                ) {
                    showNotebookWizard = true
                }

                HomeQuickActionButton(
                    title: NSLocalizedString("Home.ImportPDF", comment: ""),
                    systemImage: "doc.fill",
                    tint: .orange
                ) {
                    showPDFImporter = true
                }
            }
        }
    }

    // MARK: - Continue Where You Left Off

    @ViewBuilder
    private var continueSection: some View {
        let recent = Array(noteStore.recentNotes.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Home.Continue", comment: ""))
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recent) { note in
                            HomeContinueCard(note: note)
                                .onTapGesture {
                                    onSelectNote(note.id)
                                    tabSession.openTab(
                                        .note(id: note.id),
                                        displayName: note.title.isEmpty
                                            ? "Untitled Note" : note.title,
                                        accentColor: [0.45, 0.45, 0.5]
                                    )
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pinned Notebooks

    @ViewBuilder
    private var pinnedNotebooksSection: some View {
        let pinned = noteStore.notebooks.filter { $0.isPinned }
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Home.PinnedNotebooks", comment: ""))
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(pinned) { nb in
                            HomePinnedNotebookCard(notebook: nb)
                                .onTapGesture {
                                    noteStore.updateNotebookLastOpened(id: nb.id)
                                    onOpenNotebook(nb.id)
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Study Due

    @ViewBuilder
    private var studyDueSection: some View {
        let totalDue = noteStore.studySets.reduce(0) { acc, set in
            acc + noteStore.dueCards(inSet: set.id).count
        }
        if totalDue > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Home.StudyDue", comment: ""))
                    .font(.headline)

                HStack(spacing: 16) {
                    Image(systemName: "graduationcap.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(
                            format: NSLocalizedString("Home.CardsDue", comment: ""),
                            totalDue
                        ))
                        .font(.subheadline.weight(.semibold))

                        Text(NSLocalizedString("Home.CardsDueSubtitle", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    NavigationLink(destination: StudySetListView()) {
                        Text(NSLocalizedString("Home.StartReview", comment: ""))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        let recent = Array(noteStore.notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Home.RecentActivity", comment: ""))
                    .font(.headline)

                ForEach(recent) { note in
                    Button {
                        onSelectNote(note.id)
                        tabSession.openTab(
                            .note(id: note.id),
                            displayName: note.title.isEmpty
                                ? "Untitled Note" : note.title,
                            accentColor: [0.45, 0.45, 0.5]
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: .label))
                                    .lineLimit(1)
                                Text(note.modifiedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Quick Action Button

private struct HomeQuickActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Continue Card

private struct HomeContinueCard: View {
    let note: Note
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(uiColor: .systemBackground)

                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 180, height: 120)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(Color(uiColor: .label))
                Text(note.modifiedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 180, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(uiColor: .label).opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .task(id: note.drawingData) {
            thumbnail = await makeThumbnail(from: note.drawingData)
        }
    }

    private func makeThumbnail(from data: Data) async -> UIImage? {
        guard !data.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data),
                  !drawing.bounds.isEmpty else { return nil }
            let renderRect = drawing.bounds.insetBy(dx: -20, dy: -20)
            let scale = max(180 / renderRect.width, 120 / renderRect.height) * 0.5
            return drawing.image(from: renderRect, scale: scale)
        }.value
    }
}

// MARK: - Pinned Notebook Card

private struct HomePinnedNotebookCard: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let data = notebook.customCoverData,
                   let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 100)
                        .clipped()
                } else {
                    notebook.cover.gradient
                        .frame(width: 140, height: 100)
                }

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.85))

                // Pin badge
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Color.orange.opacity(0.85)))
                            .padding(6)
                    }
                    Spacer()
                }
            }
            .frame(width: 140, height: 100)

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color(uiColor: .label))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 140, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
