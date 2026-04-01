import SwiftUI
import PhotosUI

// MARK: - Draft model

private struct NotebookDraft {
    var name: String = ""
    var cover: NotebookCover = .ocean
    var useCustomCover: Bool = false
    var customCoverData: Data? = nil
    var pageType: PageType = .ruled
    var pageSize: PageSize = .letter
    var orientation: PageOrientation = .portrait
    var defaultTheme: AppTheme? = nil
    var paperMaterial: PaperMaterial = .standard
}

// MARK: - Wizard step

private enum WizardStep: Int, CaseIterable {
    case cover   = 0
    case paper   = 1
    case details = 2

    var title: String {
        switch self {
        case .cover:   return "Choose a Cover"
        case .paper:   return "Paper Style"
        case .details: return "Notebook Details"
        }
    }
}

// MARK: - Root wizard

/// Full-screen three-step notebook creation wizard.
///   Step 1 — Cover: built-in gradient swatches or custom photo upload.
///   Step 2 — Paper: page type, size, orientation, and material.
///   Step 3 — Details: name, default theme, summary, and create.
struct NotebookCreationWizard: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NotebookDraft()
    @State private var step: WizardStep = .cover
    @State private var goingForward = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WizardStepIndicator(current: step.rawValue, total: WizardStep.allCases.count)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .cover:
            CoverStepView(draft: $draft) {
                advance(to: .paper)
            }
        case .paper:
            PaperStepView(draft: $draft) {
                retreat(to: .cover)
            } onNext: {
                advance(to: .details)
            }
        case .details:
            DetailsStepView(draft: $draft) {
                retreat(to: .paper)
            } onCreate: {
                createNotebook()
            }
        }
    }

    private func advance(to newStep: WizardStep) {
        goingForward = true
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            step = newStep
        }
    }

    private func retreat(to newStep: WizardStep) {
        goingForward = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            step = newStep
        }
    }

    private func createNotebook() {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        noteStore.addNotebook(
            name: trimmed.isEmpty ? "Untitled" : trimmed,
            cover: draft.cover,
            pageType: draft.pageType,
            pageSize: draft.pageSize,
            orientation: draft.orientation,
            defaultTheme: draft.defaultTheme,
            paperMaterial: draft.paperMaterial,
            customCoverData: draft.useCustomCover ? draft.customCoverData : nil
        )
        dismiss()
    }
}

// MARK: - Step indicator

private struct WizardStepIndicator: View {
    let current: Int  // 0-based
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == current ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
            }
        }
    }
}

// MARK: - Cover preview

/// Renders a premium notebook cover thumbnail from the current draft state.
private struct NotebookCoverPreview: View {
    let draft: NotebookDraft

    private let width: CGFloat  = 140
    private let height: CGFloat = 196

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover surface
            Group {
                if draft.useCustomCover, let data = draft.customCoverData,
                   let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    draft.cover.gradient
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Spine highlight
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear],
                        startPoint: .leading,
                        endPoint: .init(x: 0.14, y: 0)
                    )
                )
                .frame(width: width, height: height)

            // Book icon (centred)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: width, height: height)

            // Title label at bottom
            if !draft.name.isEmpty {
                Text(draft.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.28), radius: 18, x: -3, y: 8)
    }
}

// MARK: - Step 1: Cover

private struct CoverStepView: View {
    @Binding var draft: NotebookDraft
    let onNext: () -> Void

    private enum CoverMode { case builtIn, custom }

    @State private var coverMode: CoverMode
    @State private var pickerItem: PhotosPickerItem?

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 100), spacing: 14)]

    init(draft: Binding<NotebookDraft>, onNext: @escaping () -> Void) {
        self._draft = draft
        self._coverMode = State(initialValue: draft.wrappedValue.useCustomCover ? .custom : .builtIn)
        self.onNext = onNext
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                NotebookCoverPreview(draft: draft)
                    .padding(.top, 12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: draft.cover)

                Picker("Cover Source", selection: $coverMode) {
                    Text("Built-in").tag(CoverMode.builtIn)
                    Text("Custom Photo").tag(CoverMode.custom)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                if coverMode == .builtIn {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(NotebookCover.allCases, id: \.self) { cover in
                            WizardCoverSwatch(
                                cover: cover,
                                isSelected: !draft.useCustomCover && draft.cover == cover
                            )
                            .onTapGesture {
                                draft.cover = cover
                                draft.useCustomCover = false
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 14) {
                        PhotosPicker(
                            selection: $pickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(height: 104)

                                if draft.useCustomCover, let data = draft.customCoverData,
                                   let uiImg = UIImage(data: data) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 104)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white, .green)
                                                .padding(10)
                                        }
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.tint)
                                        Text("Choose from Photo Library")
                                            .font(.subheadline)
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        if draft.useCustomCover {
                            Button(role: .destructive) {
                                draft.useCustomCover = false
                                draft.customCoverData = nil
                                pickerItem = nil
                            } label: {
                                Label("Remove Photo", systemImage: "trash")
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            wizardNextButton(label: "Next: Paper Style", action: onNext)
        }
        // onChange(of:perform:) is the correct form for iOS 16 compatibility;
        // the two-parameter variant was introduced in iOS 17.
        .onChange(of: coverMode) { mode in
            if mode == .builtIn { draft.useCustomCover = false }
        }
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            if let raw = try? await item.loadTransferable(type: Data.self),
               let uiImg = UIImage(data: raw),
               let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                draft.customCoverData = jpeg
                draft.useCustomCover = true
            }
        }
    }
}

// MARK: - Cover swatch

private struct WizardCoverSwatch: View {
    let cover: NotebookCover
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(cover.gradient)
                .aspectRatio(0.72, contentMode: .fit)

            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white, lineWidth: 3)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.12),
                radius: isSelected ? 6 : 3, y: 2)
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .overlay(alignment: .bottom) {
            Text(cover.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 7)
        }
    }
}

// MARK: - Step 2: Paper

private struct PaperStepView: View {
    @Binding var draft: NotebookDraft
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // Page type
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Page Type")

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(PageType.allCases) { type in
                            PageTypeCard(type: type, isSelected: draft.pageType == type)
                                .onTapGesture { draft.pageType = type }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Page size
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Page Size")

                    Picker("Page Size", selection: $draft.pageSize) {
                        ForEach(PageSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    Text(draft.pageSize.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }

                // Orientation
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Orientation")

                    HStack(spacing: 12) {
                        ForEach(PageOrientation.allCases) { o in
                            OrientationButton(orientation: o, isSelected: draft.orientation == o)
                                .onTapGesture { draft.orientation = o }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Paper material
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Paper Material")

                    VStack(spacing: 8) {
                        ForEach(PaperMaterial.allCases) { material in
                            PaperMaterialRow(
                                material: material,
                                isSelected: draft.paperMaterial == material
                            )
                            .onTapGesture { draft.paperMaterial = material }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
        .safeAreaInset(edge: .bottom) {
            wizardNavButtons(backLabel: "Cover", nextLabel: "Next: Details",
                             onBack: onBack, onNext: onNext)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
    }
}

// MARK: - Page type card

private struct PageTypeCard: View {
    let type: PageType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .frame(height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.separator,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )
                PageTypeMiniCanvas(type: type)
                    .frame(height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(type.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)

            Text(type.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.08)
                      : Color(.secondarySystemGroupedBackground))
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Page type canvas preview

private struct PageTypeMiniCanvas: View {
    let type: PageType

    var body: some View {
        Canvas { context, size in
            let lineColor = GraphicsContext.Shading.color(Color.secondary.opacity(0.38))
            let dotColor  = GraphicsContext.Shading.color(Color.secondary.opacity(0.50))

            switch type {
            case .blank:
                break

            case .ruled:
                let count = 5
                let spacing = size.height / CGFloat(count + 1)
                for i in 1...count {
                    let y = spacing * CGFloat(i)
                    var p = Path()
                    p.move(to:    .init(x: 8, y: y))
                    p.addLine(to: .init(x: size.width - 8, y: y))
                    context.stroke(p, with: lineColor, lineWidth: 0.8)
                }

            case .dot:
                let cols = 5, rows = 4
                let xSpacing = size.width  / CGFloat(cols + 1)
                let ySpacing = size.height / CGFloat(rows + 1)
                for row in 1...rows {
                    for col in 1...cols {
                        let cx = xSpacing * CGFloat(col)
                        let cy = ySpacing * CGFloat(row)
                        let r: CGFloat = 1.5
                        context.fill(
                            Path(ellipseIn: .init(x: cx - r, y: cy - r,
                                                  width: r * 2, height: r * 2)),
                            with: dotColor
                        )
                    }
                }

            case .grid:
                let cols = 5, rows = 4
                let xSpacing = size.width  / CGFloat(cols + 1)
                let ySpacing = size.height / CGFloat(rows + 1)
                for col in 1...cols {
                    let x = xSpacing * CGFloat(col)
                    var p = Path()
                    p.move(to:    .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: size.height))
                    context.stroke(p, with: lineColor, lineWidth: 0.6)
                }
                for row in 1...rows {
                    let y = ySpacing * CGFloat(row)
                    var p = Path()
                    p.move(to:    .init(x: 0, y: y))
                    p.addLine(to: .init(x: size.width, y: y))
                    context.stroke(p, with: lineColor, lineWidth: 0.6)
                }
            }
        }
    }
}

// MARK: - Orientation button

private struct OrientationButton: View {
    let orientation: PageOrientation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: orientation.systemImage)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(orientation.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.accentColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.09)
                      : Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Paper material row

private struct PaperMaterialRow: View {
    let material: PaperMaterial
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(material.pageTint)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle().strokeBorder(Color.separator.opacity(0.4), lineWidth: 0.5)
                    )
                Image(systemName: material.systemImage)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(material.displayName)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(material.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.accentColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.07)
                      : Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Step 3: Details

private struct DetailsStepView: View {
    @Binding var draft: NotebookDraft
    let onBack: () -> Void
    let onCreate: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Live cover preview with current name
                NotebookCoverPreview(draft: draft)
                    .padding(.top, 12)

                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notebook Name")
                        .font(.headline)

                    TextField("e.g. Work Notes, Journal…", text: $draft.name)
                        .font(.body)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }

                    if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Leave blank to use "Untitled"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                // Default theme
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default Theme")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    Picker("Default Theme", selection: $draft.defaultTheme) {
                        Text("Follow App Theme").tag(nil as AppTheme?)
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.displayName, systemImage: theme.systemImage)
                                .tag(theme as AppTheme?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                }

                // Summary card
                summaryCard
                    .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
        .safeAreaInset(edge: .bottom) {
            wizardNavButtons(backLabel: "Paper", nextLabel: "Create Notebook",
                             nextSystemImage: "book.fill",
                             onBack: onBack, onNext: onCreate)
        }
        .task {
            // Brief delay lets the presentation animation finish before the keyboard appears.
            try? await Task.sleep(nanoseconds: 350_000_000)
            nameFieldFocused = true
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            summaryRow(
                icon: "rectangle.portrait",
                label: "Page",
                value: "\(draft.pageSize.displayName) · \(draft.orientation.displayName)"
            )
            Divider().padding(.vertical, 6)
            summaryRow(
                icon: draft.pageType.systemImage,
                label: "Style",
                value: draft.pageType.displayName
            )
            Divider().padding(.vertical, 6)
            summaryRow(
                icon: draft.paperMaterial.systemImage,
                label: "Material",
                value: draft.paperMaterial.displayName
            )
            Divider().padding(.vertical, 6)
            summaryRow(
                icon: (draft.defaultTheme ?? .system).systemImage,
                label: "Theme",
                value: draft.defaultTheme.map { $0.displayName } ?? "App Default"
            )
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }
}

// MARK: - Shared button helpers

/// Primary "Next" button used on the first step.
private func wizardNextButton(label: String, systemImage: String? = nil,
                               action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            Text(label)
            if let img = systemImage {
                Image(systemName: img)
            } else {
                Image(systemName: "chevron.right")
            }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .background(Material.bar)
}

/// Back + Next/Create button pair used on steps 2 and 3.
private func wizardNavButtons(backLabel: String, nextLabel: String,
                               nextSystemImage: String? = nil,
                               onBack: @escaping () -> Void,
                               onNext: @escaping () -> Void) -> some View {
    HStack(spacing: 12) {
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Text(backLabel)
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        Button(action: onNext) {
            HStack(spacing: 6) {
                if let img = nextSystemImage {
                    Image(systemName: img)
                }
                Text(nextLabel)
                if nextSystemImage == nil {
                    Image(systemName: "chevron.right")
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .background(Material.bar)
}
