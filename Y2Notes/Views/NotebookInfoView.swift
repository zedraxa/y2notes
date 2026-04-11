import SwiftUI
import PhotosUI

// MARK: - Notebook Info View

/// Presents statistics, metadata, and quick actions for a notebook.
/// Shown as a sheet from the reader toolbar.
struct NotebookInfoView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook

    @State private var showCoverPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var customCoverData: Data?

    private var allNotes: [Note] {
        noteStore.notes(inNotebook: notebook.id)
    }

    private var allSections: [NotebookSection] {
        noteStore.sections(inNotebook: notebook.id).filter { $0.kind == .section }
    }

    private var totalPages: Int {
        allNotes.reduce(0) { $0 + $1.pageCount }
    }

    /// Live notebook (picks up mutations from NoteStore).
    private var liveNotebook: Notebook {
        noteStore.notebooks.first { $0.id == notebook.id } ?? notebook
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
            .sheet(isPresented: $showCoverPicker) {
                coverPickerSheet
            }
            .task(id: pickerItem) {
                guard let item = pickerItem else { return }
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let uiImg = UIImage(data: raw),
                   let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                    customCoverData = jpeg
                    noteStore.updateNotebookCustomCover(id: liveNotebook.id, customCoverData: jpeg)
                }
            }
        }
    }

    // MARK: - Cover

    private var coverSection: some View {
        Section {
            HStack(spacing: 16) {
                // Mini cover
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if let data = liveNotebook.customCoverData,
                           let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 80)
                                .clipped()
                        } else {
                            liveNotebook.cover.gradient
                                .frame(width: 56, height: 80)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Colour tag badge
                    Circle()
                        .fill(liveNotebook.colorTag.color)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                    // Pin badge
                    if liveNotebook.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.orange, in: Circle())
                            .offset(x: 4, y: liveNotebook.colorTag != .none ? -20 : -4)
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(liveNotebook.name)
                        .font(.headline)
                    if !liveNotebook.description.isEmpty {
                        Text(liveNotebook.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if liveNotebook.isLocked {
                        Label(
                            NSLocalizedString("NotebookInfo.Locked", comment: ""),
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if liveNotebook.isPinned {
                        Label(
                            NSLocalizedString("NotebookInfo.Pinned", comment: ""),
                            systemImage: "pin.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                value: liveNotebook.createdAt.formatted(date: .abbreviated, time: .omitted)
            )
            infoRow(
                icon: "pencil",
                label: NSLocalizedString("NotebookInfo.LastModified", comment: ""),
                value: liveNotebook.modifiedAt.formatted(date: .abbreviated, time: .shortened)
            )
            infoRow(
                icon: "eye",
                label: NSLocalizedString("NotebookInfo.LastOpened", comment: ""),
                value: liveNotebook.lastOpenedAt.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? NSLocalizedString("NotebookInfo.NeverOpened", comment: "")
            )
        }
    }

    // MARK: - Configuration

    private var configSection: some View {
        Section(NSLocalizedString("NotebookInfo.Configuration", comment: "")) {
            infoRow(
                icon: liveNotebook.pageType.systemImage,
                label: NSLocalizedString("NotebookInfo.PageType", comment: ""),
                value: liveNotebook.pageType.displayName
            )
            infoRow(
                icon: "ruler",
                label: NSLocalizedString("NotebookInfo.PageSize", comment: ""),
                value: liveNotebook.pageSize.displayName
            )
            infoRow(
                icon: liveNotebook.orientation.systemImage,
                label: NSLocalizedString("NotebookInfo.Orientation", comment: ""),
                value: liveNotebook.orientation.displayName
            )
            if let theme = liveNotebook.defaultTheme {
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
            // Change cover button
            Button {
                showCoverPicker = true
            } label: {
                Label("Change Cover", systemImage: "photo.on.rectangle")
            }

            // Colour tag picker
            HStack {
                Label(
                    NSLocalizedString("NotebookInfo.ColorTag", comment: ""),
                    systemImage: "circle.fill"
                )
                .foregroundStyle(
                    liveNotebook.colorTag == .none ? .secondary : liveNotebook.colorTag.color
                )
                Spacer()
                colorTagPicker
            }

            Button {
                noteStore.toggleNotebookPin(id: liveNotebook.id)
            } label: {
                Label(
                    liveNotebook.isPinned
                        ? NSLocalizedString("NotebookInfo.Unpin", comment: "")
                        : NSLocalizedString("NotebookInfo.Pin", comment: ""),
                    systemImage: liveNotebook.isPinned ? "pin.slash" : "pin"
                )
            }

            Button {
                noteStore.toggleNotebookLock(id: liveNotebook.id)
            } label: {
                Label(
                    liveNotebook.isLocked
                        ? NSLocalizedString("NotebookInfo.Unlock", comment: "")
                        : NSLocalizedString("NotebookInfo.Lock", comment: ""),
                    systemImage: liveNotebook.isLocked ? "lock.open" : "lock"
                )
            }

            Button {
                noteStore.duplicateNotebook(id: liveNotebook.id)
                dismiss()
            } label: {
                Label(
                    NSLocalizedString("NotebookInfo.Duplicate", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }

    // MARK: - Colour tag picker

    private var colorTagPicker: some View {
        HStack(spacing: 8) {
            ForEach(NotebookColorTag.allCases, id: \.self) { tag in
                Button {
                    noteStore.updateNotebookColorTag(
                        id: liveNotebook.id,
                        colorTag: liveNotebook.colorTag == tag ? .none : tag
                    )
                } label: {
                    ZStack {
                        if tag == .none {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 22, height: 22)
                        }
                        if liveNotebook.colorTag == tag {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.7), lineWidth: 2)
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.displayName)
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

    // MARK: - Cover Picker Sheet

    private var coverPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose a new cover for your notebook")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Built-in covers grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 12)], spacing: 12) {
                        ForEach(NotebookCover.allCases, id: \.self) { cover in
                            coverSwatch(cover)
                        }
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.vertical, 8)

                    // Custom photo cover picker
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 8) {
                            if let data = liveNotebook.customCoverData,
                               let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                                    .frame(width: 100, height: 140)
                                    .overlay(
                                        VStack(spacing: 6) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                            Text("Custom")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    )
                            }
                            Text("Choose from Photos")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Change Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showCoverPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func coverSwatch(_ cover: NotebookCover) -> some View {
        let isSelected = liveNotebook.customCoverData == nil && liveNotebook.cover == cover
        return Button {
            noteStore.updateNotebookCover(id: liveNotebook.id, cover: cover)
            noteStore.updateNotebookCustomCover(id: liveNotebook.id, customCoverData: nil)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    cover.gradient
                        .frame(width: 70, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 70, height: 100)
                    }
                }
                .shadow(color: .black.opacity(isSelected ? 0.25 : 0.1), radius: isSelected ? 6 : 3, y: 2)

                Text(cover.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
