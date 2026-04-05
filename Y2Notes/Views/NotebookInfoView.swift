import SwiftUI

// MARK: - Notebook Info View

/// Presents statistics, metadata, and quick actions for a notebook.
/// Shown as a sheet from the reader toolbar.
struct NotebookInfoView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook

    private var allNotes: [Note] {
        noteStore.notes(inNotebook: notebook.id)
    }

    private var allSections: [NotebookSection] {
        noteStore.sections(inNotebook: notebook.id).filter { $0.kind == .section }
    }

    private var totalPages: Int {
        allNotes.reduce(0) { $0 + $1.pageCount }
    }

    var body: some View {
        NavigationStack {
            List {
                coverSection
                statsSection
                configSection
                if !allSections.isEmpty {
                    sectionsSection
                }
                actionsSection
            }
            .navigationTitle(NSLocalizedString("NotebookInfo.Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Common.Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Cover

    private var coverSection: some View {
        Section {
            HStack(spacing: 16) {
                // Mini cover
                ZStack {
                    if let data = notebook.customCoverData,
                       let uiImg = UIImage(data: data) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 80)
                            .clipped()
                    } else {
                        notebook.cover.gradient
                            .frame(width: 56, height: 80)
                    }

                    CoverTextureOverlay(
                        texture: notebook.coverTexture,
                        size: CGSize(width: 56, height: 80),
                        intensity: 0.6
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notebook.name)
                        .font(.headline)
                    if !notebook.description.isEmpty {
                        Text(notebook.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if notebook.isLocked {
                        Label(
                            NSLocalizedString("NotebookInfo.Locked", comment: ""),
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Statistics

    private var statsSection: some View {
        Section(NSLocalizedString("NotebookInfo.Statistics", comment: "")) {
            infoRow(
                icon: "doc.plaintext",
                label: NSLocalizedString("NotebookInfo.TotalPages", comment: ""),
                value: "\(totalPages)"
            )
            infoRow(
                icon: "note.text",
                label: NSLocalizedString("NotebookInfo.Notes", comment: ""),
                value: "\(allNotes.count)"
            )
            infoRow(
                icon: "list.bullet.indent",
                label: NSLocalizedString("NotebookInfo.Sections", comment: ""),
                value: "\(allSections.count)"
            )
            infoRow(
                icon: "calendar",
                label: NSLocalizedString("NotebookInfo.Created", comment: ""),
                value: notebook.createdAt.formatted(date: .abbreviated, time: .omitted)
            )
            infoRow(
                icon: "pencil",
                label: NSLocalizedString("NotebookInfo.LastModified", comment: ""),
                value: notebook.modifiedAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }

    // MARK: - Configuration

    private var configSection: some View {
        Section(NSLocalizedString("NotebookInfo.Configuration", comment: "")) {
            infoRow(
                icon: notebook.pageType.systemImage,
                label: NSLocalizedString("NotebookInfo.PageType", comment: ""),
                value: notebook.pageType.displayName
            )
            infoRow(
                icon: "ruler",
                label: NSLocalizedString("NotebookInfo.PageSize", comment: ""),
                value: notebook.pageSize.displayName
            )
            infoRow(
                icon: notebook.orientation.systemImage,
                label: NSLocalizedString("NotebookInfo.Orientation", comment: ""),
                value: notebook.orientation.displayName
            )
            infoRow(
                icon: notebook.paperMaterial.systemImage,
                label: NSLocalizedString("NotebookInfo.Material", comment: ""),
                value: notebook.paperMaterial.displayName
            )
            infoRow(
                icon: notebook.coverTexture.systemImage,
                label: NSLocalizedString("NotebookInfo.Texture", comment: ""),
                value: notebook.coverTexture.displayName
            )
            if let theme = notebook.defaultTheme {
                infoRow(
                    icon: theme.systemImage,
                    label: NSLocalizedString("NotebookInfo.Theme", comment: ""),
                    value: theme.displayName
                )
            }
        }
    }

    // MARK: - Sections breakdown

    private var sectionsSection: some View {
        Section(NSLocalizedString("NotebookInfo.SectionsBreakdown", comment: "")) {
            ForEach(allSections) { section in
                let count = noteStore.pages(inSection: section.id).count
                HStack {
                    Circle()
                        .fill(section.colorTag.color)
                        .frame(width: 8, height: 8)
                    Text(section.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let spt = section.defaultPageType {
                        Image(systemName: spt.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                noteStore.toggleNotebookLock(id: notebook.id)
            } label: {
                Label(
                    notebook.isLocked
                        ? NSLocalizedString("NotebookInfo.Unlock", comment: "")
                        : NSLocalizedString("NotebookInfo.Lock", comment: ""),
                    systemImage: notebook.isLocked ? "lock.open" : "lock"
                )
            }

            Button {
                noteStore.duplicateNotebook(id: notebook.id)
                dismiss()
            } label: {
                Label(
                    NSLocalizedString("NotebookInfo.Duplicate", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
