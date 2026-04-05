import SwiftUI

// MARK: - File Browser View

/// A full-screen browser that lets the user navigate their Google Drive folders,
/// search for files, and import compatible documents (PDFs, images) into Y2Notes.
struct GoogleDriveFileBrowserView: View {
    @EnvironmentObject var syncEngine: GoogleDriveSyncEngine

    @StateObject private var viewModel = DriveFileBrowserViewModel()

    @State private var searchText = ""
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isAuthenticated {
                    breadcrumbBar
                    Divider()
                    fileListContent
                } else {
                    notConnectedView
                }
            }
            .navigationTitle("My Drive")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Drive files")
            .onSubmit(of: .search) {
                Task { await viewModel.search(query: searchText) }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty && isSearching {
                    isSearching = false
                    viewModel.clearSearch()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .task {
                viewModel.authManager = syncEngine.authManager
                await viewModel.loadRootIfNeeded()
            }
        }
    }

    // MARK: - Breadcrumbs

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        Task { await viewModel.navigateToBreadcrumb(at: index) }
                    } label: {
                        Text(crumb.name)
                            .font(.caption)
                            .fontWeight(index == viewModel.breadcrumbs.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == viewModel.breadcrumbs.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - File list

    @ViewBuilder
    private var fileListContent: some View {
        if viewModel.files.isEmpty && !viewModel.isLoading {
            ContentUnavailableView {
                Label("No Files", systemImage: "folder")
            } description: {
                Text(searchText.isEmpty ? "This folder is empty." : "No results for \"\(searchText)\".")
            }
        } else {
            List {
                // Storage quota section (shown only at root level)
                if viewModel.breadcrumbs.count <= 1 && searchText.isEmpty,
                   let quota = viewModel.storageQuota {
                    Section {
                        storageQuotaRow(quota)
                    }
                }

                // Files
                Section {
                    ForEach(viewModel.files) { file in
                        driveFileRow(file)
                    }

                    // Load more
                    if viewModel.hasMorePages {
                        Button {
                            Task { await viewModel.loadNextPage() }
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Load More")
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - File row

    private func driveFileRow(_ file: DriveFileMetadata) -> some View {
        Button {
            if file.mimeType == "application/vnd.google-apps.folder" {
                Task { await viewModel.openFolder(file) }
            } else {
                Task { await viewModel.importFile(file) }
            }
        } label: {
            HStack(spacing: 12) {
                driveFileIcon(file)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if let size = file.size {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                        Text(file.modifiedTime, style: .date)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if file.mimeType == "application/vnd.google-apps.folder" {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if viewModel.importingFileID == file.id {
                    ProgressView()
                        .controlSize(.small)
                } else if isImportable(file) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - File icons

    @ViewBuilder
    private func driveFileIcon(_ file: DriveFileMetadata) -> some View {
        let mime = file.mimeType
        Group {
            if mime == "application/vnd.google-apps.folder" {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
            } else if mime == "application/pdf" {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.red)
            } else if mime.hasPrefix("image/") {
                Image(systemName: "photo.fill")
                    .foregroundStyle(.green)
            } else if mime.hasPrefix("video/") {
                Image(systemName: "film.fill")
                    .foregroundStyle(.purple)
            } else if mime.hasPrefix("audio/") {
                Image(systemName: "waveform")
                    .foregroundStyle(.orange)
            } else if mime.contains("spreadsheet") || mime.contains("excel") {
                Image(systemName: "tablecells.fill")
                    .foregroundStyle(.green)
            } else if mime.contains("presentation") || mime.contains("powerpoint") {
                Image(systemName: "rectangle.fill.on.rectangle.fill")
                    .foregroundStyle(.orange)
            } else if mime.contains("document") || mime.contains("word") || mime.hasPrefix("text/") {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title3)
    }

    // MARK: - Storage quota

    private func storageQuotaRow(_ quota: DriveStorageQuota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.blue)
                Text("Storage")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: quota.usageBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: quota.limitBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(quotaColor(quota.usedFraction))
                        .frame(width: max(2, geo.size.width * quota.usedFraction))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    private func quotaColor(_ fraction: Double) -> Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.75 { return .orange }
        return .blue
    }

    // MARK: - Not connected

    private var notConnectedView: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Connect your Google account in Drive Settings to browse your files.")
        }
    }

    // MARK: - Helpers

    private func isImportable(_ file: DriveFileMetadata) -> Bool {
        DriveFileBrowserViewModel.importableMIMETypes.contains(where: { file.mimeType.hasPrefix($0) })
    }
}

// MARK: - View Model

@MainActor
final class DriveFileBrowserViewModel: ObservableObject {

    // MARK: - Published state

    @Published var files: [DriveFileMetadata] = []
    @Published var breadcrumbs: [DriveBreadcrumb] = []
    @Published var storageQuota: DriveStorageQuota?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMorePages = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var importingFileID: String?

    // MARK: - Dependencies

    var authManager: GoogleDriveAuthManager?

    var isAuthenticated: Bool {
        authManager?.isAuthenticated ?? false
    }

    /// MIME type prefixes that the app can import.
    static let importableMIMETypes: [String] = [
        "application/pdf",
        "image/",
    ]

    // MARK: - Internal

    private var nextPageToken: String?
    private var isSearchMode = false
    private var lastSearchQuery = ""

    // MARK: - Load root

    func loadRootIfNeeded() async {
        guard isAuthenticated, files.isEmpty else { return }
        breadcrumbs = [DriveBreadcrumb(id: "root", name: "My Drive")]
        await loadFolder(id: "root")
        await loadStorageQuota()
    }

    // MARK: - Navigation

    func openFolder(_ file: DriveFileMetadata) async {
        breadcrumbs.append(DriveBreadcrumb(id: file.id, name: file.name))
        await loadFolder(id: file.id)
    }

    func navigateToBreadcrumb(at index: Int) async {
        guard index < breadcrumbs.count else { return }
        let target = breadcrumbs[index]
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        await loadFolder(id: target.id)
    }

    // MARK: - Search

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let token = await validToken() else { return }

        isSearchMode = true
        lastSearchQuery = query
        isLoading = true
        files = []
        nextPageToken = nil

        do {
            let result = try await GoogleDriveClient.searchUserFiles(
                query: query,
                accessToken: token
            )
            files = result.files
            nextPageToken = result.nextPageToken
            hasMorePages = result.nextPageToken != nil
        } catch {
            handleError(error)
        }
        isLoading = false
    }

    func clearSearch() {
        guard isSearchMode else { return }
        isSearchMode = false
        if let lastFolder = breadcrumbs.last {
            Task { await loadFolder(id: lastFolder.id) }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        if let current = breadcrumbs.last {
            await loadFolder(id: current.id)
        }
        await loadStorageQuota()
    }

    // MARK: - Pagination

    func loadNextPage() async {
        guard let pageToken = nextPageToken, !isLoadingMore else { return }
        guard let token = await validToken() else { return }

        isLoadingMore = true
        do {
            let result: DrivePagedFileList
            if isSearchMode {
                result = try await GoogleDriveClient.searchUserFiles(
                    query: lastSearchQuery,
                    pageToken: pageToken,
                    accessToken: token
                )
            } else {
                result = try await GoogleDriveClient.listUserFiles(
                    inFolder: breadcrumbs.last?.id ?? "root",
                    pageToken: pageToken,
                    accessToken: token
                )
            }
            files.append(contentsOf: result.files)
            nextPageToken = result.nextPageToken
            hasMorePages = result.nextPageToken != nil
        } catch {
            handleError(error)
        }
        isLoadingMore = false
    }

    // MARK: - Import

    func importFile(_ file: DriveFileMetadata) async {
        guard isImportable(file) else { return }
        guard let token = await validToken() else { return }

        importingFileID = file.id

        do {
            let data = try await GoogleDriveClient.downloadFile(
                fileID: file.id,
                accessToken: token
            )
            saveImportedFile(name: file.name, mimeType: file.mimeType, data: data)
        } catch {
            handleError(error)
        }

        importingFileID = nil
    }

    // MARK: - Private

    private func loadFolder(id: String) async {
        guard let token = await validToken() else { return }

        isLoading = true
        isSearchMode = false
        files = []
        nextPageToken = nil

        do {
            let result = try await GoogleDriveClient.listUserFiles(
                inFolder: id,
                accessToken: token
            )
            files = result.files
            nextPageToken = result.nextPageToken
            hasMorePages = result.nextPageToken != nil
        } catch {
            handleError(error)
        }
        isLoading = false
    }

    private func loadStorageQuota() async {
        guard let token = await validToken() else { return }
        do {
            storageQuota = try await GoogleDriveClient.getStorageQuota(accessToken: token)
        } catch {
            // Non-critical — quota display is cosmetic.
            print("Y2Notes: Failed to load Drive storage quota — \(error.localizedDescription)")
        }
    }

    private func validToken() async -> String? {
        await authManager?.validAccessToken()
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func isImportable(_ file: DriveFileMetadata) -> Bool {
        Self.importableMIMETypes.contains(where: { file.mimeType.hasPrefix($0) })
    }

    /// Saves a downloaded file to the app's Documents directory and notifies
    /// the appropriate store.
    private func saveImportedFile(name: String, mimeType: String, data: Data) {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importDir = docsDir.appendingPathComponent("DriveImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

        // Sanitise the filename to avoid path-traversal issues.
        let safeName = sanitiseFileName(name)
        var target = importDir.appendingPathComponent(safeName)

        // Deduplicate: append a counter if the file already exists.
        var counter = 1
        let baseName = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: target.path) {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            target = importDir.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try data.write(to: target, options: .atomic)
            print("Y2Notes: Imported Drive file → \(target.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save file: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Strips directory separators and trims whitespace to produce a safe file name.
    private func sanitiseFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
