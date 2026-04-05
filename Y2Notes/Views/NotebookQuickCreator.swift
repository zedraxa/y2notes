import SwiftUI
import PhotosUI

// MARK: - Quick Creator

/// Single-screen notebook creation sheet that replaces the 3-step wizard.
/// Presented at `.medium` detent (expandable to `.large` for advanced options).
/// Minimum tap-count: 2 (tap "+", tap "Create") with smart defaults.
struct NotebookQuickCreator: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var cover: NotebookCover = .ocean
    @State private var useCustomCover: Bool = false
    @State private var customCoverData: Data?
    @State private var pageType: PageType = .blank
    @State private var pageSize: PageSize = .a4
    @State private var orientation: PageOrientation = .portrait
    @State private var paperMaterial: PaperMaterial = .standard
    @State private var defaultTheme: AppTheme?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isCreating = false

    @FocusState private var isNameFocused: Bool

    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                coverPreview
                    .padding(.top, 20)

                nameField

                descriptionField

                coverStrip

                quickSettings

                createButton

                advancedSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            if let raw = try? await item.loadTransferable(type: Data.self),
               let uiImg = UIImage(data: raw),
               let jpeg = uiImg.jpegData(compressionQuality: 0.75) {
                customCoverData = jpeg
                useCustomCover = true
            }
        }
    }

    // MARK: - Zone 1: Live Cover Preview

    private var coverPreview: some View {
        ZStack(alignment: .bottomLeading) {
            // Paper peek (angled first page behind cover)
            paperPeek
                .offset(x: 8, y: -4)

            // Main cover surface
            Group {
                if useCustomCover, let data = customCoverData,
                   let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 196)
                        .clipped()
                } else {
                    cover.gradient
                }
            }
            .frame(width: 140, height: 196)
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
                .frame(width: 140, height: 196)

            // Book icon
            Image(systemName: "book.closed.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 140, height: 196)

            // Live title
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 156, height: 200)
        .shadow(color: .black.opacity(0.28), radius: 18, x: -3, y: 8)
        .scaleEffect(isCreating ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: cover)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isCreating)
    }

    /// Small paper preview peeking from behind the cover to show paper type.
    private var paperPeek: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemBackground))
            .frame(width: 120, height: 170)
            .overlay(
                PageTypeMiniCanvas(type: pageType)
                    .frame(width: 120, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
            )
            .rotationEffect(.degrees(3))
    }

    // MARK: - Zone 2: Name Field

    private var nameField: some View {
        TextField("Untitled", text: $name)
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .focused($isNameFocused)
            .submitLabel(.done)
            .onSubmit { isNameFocused = false }
            .accessibilityLabel("Notebook name")
    }

    // MARK: - Zone 2b: Description Field

    private var descriptionField: some View {
        TextField("Add a description…", text: $description, axis: .vertical)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2...4)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .accessibilityLabel("Notebook description")
    }

    // MARK: - Zone 3: Cover Strip

    private var coverStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cover")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NotebookCover.allCases, id: \.self) { c in
                        quickCoverSwatch(c)
                    }

                    // Custom photo button
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        customPhotoSwatch
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func quickCoverSwatch(_ c: NotebookCover) -> some View {
        let selected = !useCustomCover && cover == c
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(c.gradient)
                .frame(width: 44, height: 44)

            if selected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.25 : 0.08), radius: selected ? 4 : 2, y: 1)
        .scaleEffect(selected ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
        .onTapGesture {
            cover = c
            useCustomCover = false
        }
        .accessibilityLabel(c.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customPhotoSwatch: some View {
        ZStack {
            if useCustomCover, let data = customCoverData,
               let uiImg = UIImage(data: data) {
                Image(uiImage: uiImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white, lineWidth: 2.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .scaleEffect(useCustomCover ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: useCustomCover)
        .accessibilityLabel("Custom photo cover")
    }

    // MARK: - Zone 4: Quick Settings

    private var quickSettings: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(PageType.allCases) { type in
                    Button {
                        pageType = type
                    } label: {
                        Label(type.displayName, systemImage: type.systemImage)
                    }
                }
            } label: {
                quickSettingLabel(
                    icon: pageType.systemImage,
                    text: pageType.displayName
                )
            }

            Menu {
                ForEach(PageSize.allCases) { size in
                    Button {
                        pageSize = size
                    } label: {
                        Text(size.displayName)
                    }
                }
            } label: {
                quickSettingLabel(
                    icon: "ruler",
                    text: pageSize.displayName
                )
            }
        }
    }

    private func quickSettingLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Zone 5: Create Button

    private var createButton: some View {
        Button(action: performCreate) {
            HStack(spacing: 8) {
                if isCreating {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "book.fill")
                    Text("Create Notebook")
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isCreating)
        .accessibilityHint("Creates a new notebook and opens it")
    }

    // MARK: - Zone 6: Advanced (visible at .large)

    @ViewBuilder
    private var advancedSection: some View {
        if selectedDetent == .large {
            VStack(spacing: 16) {
                Divider()
                    .padding(.top, 4)

                orientationPicker

                materialStrip

                themePicker
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Text("More options")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var orientationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orientation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(PageOrientation.allCases) { o in
                    let selected = orientation == o
                    Button {
                        orientation = o
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: o.systemImage)
                                .font(.caption)
                            Text(o.displayName)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selected
                                      ? Color.accentColor.opacity(0.12)
                                      : Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                                )
                        )
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: selected)
                }
            }
        }
    }

    private var materialStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paper Material")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaperMaterial.allCases) { m in
                        materialChip(m)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func materialChip(_ m: PaperMaterial) -> some View {
        let selected = paperMaterial == m
        return Button {
            paperMaterial = m
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(m.pageTint)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                    )
                Text(m.displayName)
                    .font(.caption.weight(selected ? .semibold : .regular))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(selected
                          ? Color.accentColor.opacity(0.12)
                          : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule()
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
            )
            .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: selected)
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Theme")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Default Theme", selection: $defaultTheme) {
                Text("Follow App Theme").tag(nil as AppTheme?)
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.displayName, systemImage: theme.systemImage)
                        .tag(theme as AppTheme?)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Actions

    private func performCreate() {
        guard !isCreating else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            isCreating = true
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nb = noteStore.addNotebook(
            name: trimmed.isEmpty ? "Untitled" : trimmed,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            cover: cover,
            pageType: pageType,
            pageSize: pageSize,
            orientation: orientation,
            defaultTheme: defaultTheme,
            paperMaterial: paperMaterial,
            customCoverData: useCustomCover ? customCoverData : nil
        )

        // Auto-create the first page so the notebook opens ready to write
        noteStore.addNote(
            inNotebook: nb.id,
            pageType: pageType,
            paperMaterial: paperMaterial
        )

        // Brief delay to show checkmark then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }
}

// MARK: - Page Type Mini Canvas (reused from wizard)

/// Renders a small canvas preview showing the page type pattern.
private struct PageTypeMiniCanvas: View {
    let type: PageType

    var body: some View {
        Canvas { context, size in
            let lineColor = GraphicsContext.Shading.color(
                Color(uiColor: .secondaryLabel).opacity(0.38)
            )
            let dotColor = GraphicsContext.Shading.color(
                Color(uiColor: .secondaryLabel).opacity(0.50)
            )

            switch type {
            case .blank:
                break

            case .ruled:
                let count = 5
                let spacing = size.height / CGFloat(count + 1)
                for i in 1...count {
                    let y = spacing * CGFloat(i)
                    var p = Path()
                    p.move(to: .init(x: 8, y: y))
                    p.addLine(to: .init(x: size.width - 8, y: y))
                    context.stroke(p, with: lineColor, lineWidth: 0.8)
                }

            case .dot:
                let cols = 5, rows = 4
                let xSpacing = size.width / CGFloat(cols + 1)
                let ySpacing = size.height / CGFloat(rows + 1)
                for row in 1...rows {
                    for col in 1...cols {
                        let cx = xSpacing * CGFloat(col)
                        let cy = ySpacing * CGFloat(row)
                        let r: CGFloat = 1.5
                        context.fill(
                            Path(ellipseIn: .init(
                                x: cx - r, y: cy - r,
                                width: r * 2, height: r * 2
                            )),
                            with: dotColor
                        )
                    }
                }

            case .grid:
                let cols = 5, rows = 4
                let xSpacing = size.width / CGFloat(cols + 1)
                let ySpacing = size.height / CGFloat(rows + 1)
                for col in 1...cols {
                    let x = xSpacing * CGFloat(col)
                    var p = Path()
                    p.move(to: .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: size.height))
                    context.stroke(p, with: lineColor, lineWidth: 0.6)
                }
                for row in 1...rows {
                    let y = ySpacing * CGFloat(row)
                    var p = Path()
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: size.width, y: y))
                    context.stroke(p, with: lineColor, lineWidth: 0.6)
                }

            case .cornell:
                let marginX: CGFloat = size.width * 0.28
                let headerY: CGFloat = size.height * 0.18
                let summaryY: CGFloat = size.height * 0.82
                var p = Path()
                p.move(to: .init(x: marginX, y: 0)); p.addLine(to: .init(x: marginX, y: size.height))
                context.stroke(p, with: lineColor, lineWidth: 0.75)
                p = Path()
                p.move(to: .init(x: 0, y: headerY)); p.addLine(to: .init(x: size.width, y: headerY))
                context.stroke(p, with: lineColor, lineWidth: 0.75)
                p = Path()
                p.move(to: .init(x: 0, y: summaryY)); p.addLine(to: .init(x: size.width, y: summaryY))
                context.stroke(p, with: lineColor, lineWidth: 0.75)
                let ruledSpacing = (summaryY - headerY) / 4
                for i in 1..<4 {
                    let y = headerY + CGFloat(i) * ruledSpacing
                    p = Path()
                    p.move(to: .init(x: marginX, y: y)); p.addLine(to: .init(x: size.width - 4, y: y))
                    context.stroke(p, with: lineColor, lineWidth: 0.5)
                }

            case .hexagonal:
                let r: CGFloat = min(size.width, size.height) / 6
                let colStep = r * sqrt(3.0)
                let rowStep = r * 1.5
                let cols = Int(ceil(size.width  / colStep)) + 2
                let rows = Int(ceil(size.height / rowStep)) + 2
                for row in -1 ..< rows {
                    for col in -1 ..< cols {
                        let ox: CGFloat = (row & 1) != 0 ? colStep * 0.5 : 0
                        let cx = CGFloat(col) * colStep + ox
                        let cy = CGFloat(row) * rowStep
                        var hex = Path()
                        let startA: CGFloat = .pi / 2
                        let stepA:  CGFloat = .pi / 3
                        hex.move(to: .init(x: cx + r * cos(startA), y: cy - r * sin(startA)))
                        for i in 1 ..< 6 {
                            let a = startA + CGFloat(i) * stepA
                            hex.addLine(to: .init(x: cx + r * cos(a), y: cy - r * sin(a)))
                        }
                        hex.closeSubpath()
                        context.stroke(hex, with: lineColor, lineWidth: 0.5)
                    }
                }

            case .music:
                let lineGap:  CGFloat = size.height / 14
                let staffGap: CGFloat = lineGap * 3
                let staffH:   CGFloat = lineGap * 4
                let pitch:    CGFloat = staffH + staffGap
                var topY: CGFloat = staffGap * 0.5
                while topY <= size.height + pitch {
                    for lineIdx in 0 ..< 5 {
                        let y = topY + CGFloat(lineIdx) * lineGap
                        guard y <= size.height else { break }
                        var p = Path()
                        p.move(to: .init(x: 4, y: y)); p.addLine(to: .init(x: size.width - 4, y: y))
                        context.stroke(p, with: lineColor, lineWidth: 0.5)
                    }
                    topY += pitch
                }
            }
        }
    }
}
