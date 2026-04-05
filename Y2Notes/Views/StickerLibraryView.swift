import SwiftUI
import PhotosUI

/// Bottom-sheet sticker browser presented from the floating toolbar.
///
/// Layout: search bar → category pills → Favorites / Recents sections → grid.
/// Tap a sticker to select it for placement; long-press to toggle favorite.
struct StickerLibraryView: View {
    @ObservedObject var stickerStore: StickerStore
    /// Called when the user selects a sticker to place on the canvas.
    var onSelect: (StickerAsset) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: StickerCategory? = nil
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Category pills
                categoryStrip

                Divider()

                // Sticker grid
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Special sections
                        if searchText.isEmpty && selectedCategory == nil {
                            if !stickerStore.recents.isEmpty {
                                stickerSection(title: "Recent", icon: "clock.arrow.circlepath", assets: stickerStore.recents)
                            }
                            if !stickerStore.favorites.isEmpty {
                                stickerSection(title: "Favorites", icon: "star.fill", assets: stickerStore.favorites)
                            }
                        }

                        // Category or search results
                        let displayed = displayedAssets
                        if !displayed.isEmpty {
                            stickerGrid(assets: displayed)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        preferredItemEncoding: .compatible
                    ) {
                        Label("Import", systemImage: "plus.circle")
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                handlePhotoImport(newItem)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search stickers…", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Category Strip

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(title: "All", category: nil)
                ForEach(StickerCategory.allCases) { category in
                    categoryPill(title: category.displayName, category: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func categoryPill(title: String, category: StickerCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedCategory = category
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticker Grid

    private var displayedAssets: [StickerAsset] {
        if !searchText.isEmpty {
            return stickerStore.search(query: searchText)
        }
        if let cat = selectedCategory {
            return stickerStore.assets(for: cat)
        }
        return stickerStore.allAssets
    }

    private func stickerSection(title: String, icon: String, assets: [StickerAsset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            stickerGrid(assets: assets)
        }
    }

    private func stickerGrid(assets: [StickerAsset]) -> some View {
        let columns = Array(repeating: GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 12), count: 1)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(assets) { asset in
                stickerCell(asset)
            }
        }
    }

    private func stickerCell(_ asset: StickerAsset) -> some View {
        Button {
            stickerStore.recordRecent(asset.id)
            onSelect(asset)
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 56, height: 56)

                if let image = stickerStore.image(for: asset) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                } else {
                    // Placeholder for built-in stickers without actual assets
                    Image(systemName: asset.category.systemImage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                // Favorite indicator
                if stickerStore.isFavorite(asset.id) {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                                .padding(3)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                stickerStore.toggleFavorite(asset.id)
            } label: {
                Label(
                    stickerStore.isFavorite(asset.id) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: stickerStore.isFavorite(asset.id) ? "star.slash" : "star"
                )
            }

            if asset.isCustom {
                Button(role: .destructive) {
                    stickerStore.deleteCustomSticker(id: asset.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(asset.name)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "face.dashed")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No stickers found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if selectedCategory == .custom {
                Text("Import images to create custom stickers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Photo Import

    private func handlePhotoImport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                guard let data, let uiImage = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if let asset = stickerStore.importCustomSticker(image: uiImage) {
                        stickerStore.recordRecent(asset.id)
                    }
                    selectedPhoto = nil
                }
            case .failure:
                DispatchQueue.main.async { selectedPhoto = nil }
            }
        }
    }
}
