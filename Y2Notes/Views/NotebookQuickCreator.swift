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
    @State private var coverTexture: CoverTexture = .smooth
    @State private var pageType: PageType = .blank
    @State private var pageSize: PageSize = .a4
    @State private var orientation: PageOrientation = .portrait
    @State private var paperMaterial: PaperMaterial = .standard
    @State private var defaultTheme: AppTheme?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isCreating = false
    @State private var creatorAppeared = false
    @State private var selectedTemplate: NotebookTemplate?

    @FocusState private var isNameFocused: Bool

    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                templateStrip

                coverPreview
                    .padding(.top, 4)

                nameField

                descriptionField

                coverStrip

                textureStrip

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

    // MARK: - Template Strip

    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Creation.Templates", comment: ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NotebookTemplate.allCases) { tmpl in
                        templateChip(tmpl)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 16)
    }

    private func templateChip(_ tmpl: NotebookTemplate) -> some View {
        let selected = selectedTemplate == tmpl
        return Button {
            applyTemplate(tmpl)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tmpl.systemImage)
                    .font(.system(size: 18))
                    .frame(width: 44, height: 32)
                Text(tmpl.displayName)
                    .font(.caption2.weight(selected ? .semibold : .regular))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
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
        .accessibilityLabel(tmpl.displayName)
        .accessibilityHint(tmpl.subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func applyTemplate(_ tmpl: NotebookTemplate) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedTemplate = tmpl
            pageType = tmpl.pageType
            paperMaterial = tmpl.paperMaterial
            cover = tmpl.suggestedCover
            coverTexture = tmpl.suggestedTexture
            useCustomCover = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

            // Texture overlay
            CoverTextureOverlay(
                texture: coverTexture,
                size: CGSize(width: 140, height: 196)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Spine highlight with stitching
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .black.opacity(0.04), .clear],
                            startPoint: .leading,
                            endPoint: .init(x: 0.14, y: 0)
                        )
                    )
                    .frame(width: 140, height: 196)

                CoverSpineStitching(height: 196, dotCount: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
                    .frame(width: 140, height: 196)
            }

            // Book icon
            Image(systemName: "book.closed.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 140, height: 196)

            // Embossed title (top center)
            if !name.isEmpty {
                VStack {
                    CoverEmbossedTitle(text: name, maxWidth: 116)
                        .padding(.top, 24)
                    Spacer()
                }
                .frame(width: 140, height: 196)
            }

            // Live title (bottom)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: coverTexture)
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
                    ForEach(Array(NotebookCover.allCases.enumerated()), id: \.element) { index, c in
                        quickCoverSwatch(c)
                            .opacity(creatorAppeared ? 1 : 0)
                            .scaleEffect(creatorAppeared ? 1.0 : 0.7)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.75)
                                    .delay(Double(index) * 0.04),
                                value: creatorAppeared
                            )
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

    // MARK: - Zone 3b: Texture Strip

    private var textureStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Texture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
