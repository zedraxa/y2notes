import Foundation

/// Low-level HTTP client for the Google Drive REST API v3.
///
/// All methods require a valid access token obtained from `GoogleDriveAuthManager`.
/// This client is intentionally stateless — callers supply auth tokens on each call.
/// Errors are propagated as `GoogleDriveClientError`.
enum GoogleDriveClientError: Error, LocalizedError {
    case unauthorized
    case notFound
    case quotaExceeded
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:                    return "Google Drive authorization expired."
        case .notFound:                        return "File not found on Google Drive."
        case .quotaExceeded:                   return "Google Drive quota exceeded."
        case .serverError(let code, let msg):  return "Drive error \(code): \(msg)"
        case .networkError(let err):           return "Network error: \(err.localizedDescription)"
        case .decodingError(let err):          return "Decoding error: \(err.localizedDescription)"
        }
    }
}

struct GoogleDriveClient {

    // MARK: - Configuration

    private static let apiBase   = "https://www.googleapis.com/drive/v3"
    private static let uploadBase = "https://www.googleapis.com/upload/drive/v3"

    // MARK: - Folder operations

    /// Ensures a folder named `name` exists under the user's Drive root.
    /// Returns the folder's Drive file ID, creating the folder if necessary.
    static func ensureFolder(
        named name: String,
        accessToken: String
    ) async throws -> String {
        // Search for existing folder.
        let query = "name='\(name)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        let listURL = URL(string: "\(apiBase)/files?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&fields=files(id,name)")!
        let existing: DriveListResponse = try await get(listURL, accessToken: accessToken)
        if let first = existing.files.first {
            return first.id
        }
        // Create folder.
        let metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
        ]
        let created: DriveFileResponse = try await postJSON(
            URL(string: "\(apiBase)/files?fields=id,name")!,
            json: metadata,
            accessToken: accessToken
        )
        return created.id
    }

    // MARK: - Upload

    /// Uploads `data` as a file inside the specified Drive folder.
    /// Uses simple upload for files ≤ 5 MB; multipart for larger payloads.
    ///
    /// - Returns: The Drive file ID of the uploaded file.
    @discardableResult
    static func uploadFile(
        name: String,
        data: Data,
        mimeType: String = "application/json",
        parentFolderID: String,
        existingFileID: String? = nil,
        accessToken: String
    ) async throws -> String {
        if let fileID = existingFileID {
            return try await updateFile(fileID: fileID, data: data, mimeType: mimeType, accessToken: accessToken)
        }
        return try await createFile(name: name, data: data, mimeType: mimeType, parentFolderID: parentFolderID, accessToken: accessToken)
    }

    /// Creates a new file on Drive via multipart upload.
    private static func createFile(
        name: String,
        data: Data,
        mimeType: String,
        parentFolderID: String,
        accessToken: String
    ) async throws -> String {
        let boundary = "Y2NotesBoundary\(UUID().uuidString)"
        let url = URL(string: "\(uploadBase)/files?uploadType=multipart&fields=id,name,modifiedTime,md5Checksum")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentFolderID],
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let response: DriveFileResponse = try await execute(request)
        return response.id
    }

    /// Updates an existing file's content on Drive.
    private static func updateFile(
        fileID: String,
        data: Data,
        mimeType: String,
        accessToken: String
    ) async throws -> String {
        let url = URL(string: "\(uploadBase)/files/\(fileID)?uploadType=media&fields=id")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let response: DriveFileResponse = try await execute(request)
        return response.id
    }

    // MARK: - Download

    /// Downloads the content of a file by its Drive file ID.
    static func downloadFile(
        fileID: String,
        accessToken: String
    ) async throws -> Data {
        let url = URL(string: "\(apiBase)/files/\(fileID)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response)
            return data
        } catch let error as GoogleDriveClientError {
            throw error
        } catch {
            throw GoogleDriveClientError.networkError(error)
        }
    }

    // MARK: - List files

    /// Lists files in a folder matching an optional query filter.
    static func listFiles(
        inFolder folderID: String,
        query: String? = nil,
        accessToken: String
    ) async throws -> [DriveFileMetadata] {
        var q = "'\(folderID)' in parents and trashed=false"
        if let extra = query {
            q += " and \(extra)"
        }
        let encodedQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let fields = "files(id,name,mimeType,modifiedTime,size,md5Checksum)"
        let urlString = "\(apiBase)/files?q=\(encodedQ)&fields=\(fields)&orderBy=modifiedTime desc&pageSize=100"
        let url = URL(string: urlString)!
        let response: DriveListResponse = try await get(url, accessToken: accessToken)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return response.files.map { file in
            DriveFileMetadata(
                id: file.id,
                name: file.name,
                mimeType: file.mimeType ?? "application/octet-stream",
                modifiedTime: formatter.date(from: file.modifiedTime ?? "") ?? Date.distantPast,
                size: file.size,
                md5Checksum: file.md5Checksum
            )
        }
    }

    // MARK: - Delete

    /// Permanently deletes a file from Google Drive.
    static func deleteFile(
        fileID: String,
        accessToken: String
    ) async throws {
        let url = URL(string: "\(apiBase)/files/\(fileID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 204 && http.statusCode != 200 {
                try validateHTTPResponse(response)
            }
        } catch let error as GoogleDriveClientError {
            throw error
        } catch {
            throw GoogleDriveClientError.networkError(error)
        }
    }

    // MARK: - File metadata

    /// Fetches metadata for a single file.
    static func fileMetadata(
        fileID: String,
        accessToken: String
    ) async throws -> DriveFileMetadata {
        let url = URL(string: "\(apiBase)/files/\(fileID)?fields=id,name,mimeType,modifiedTime,size,md5Checksum")!
        let file: DriveFileResponse = try await get(url, accessToken: accessToken)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return DriveFileMetadata(
            id: file.id,
            name: file.name,
            mimeType: file.mimeType ?? "application/octet-stream",
            modifiedTime: formatter.date(from: file.modifiedTime ?? "") ?? Date.distantPast,
            size: file.size,
            md5Checksum: file.md5Checksum
        )
    }

    // MARK: - Browse user files

    /// Lists files in any folder on the user's Drive (not limited to app-created files).
    /// Supports pagination via `pageToken`. Returns folders first, then files.
    static func listUserFiles(
        inFolder folderID: String = "root",
        pageToken: String? = nil,
        accessToken: String
    ) async throws -> DrivePagedFileList {
        let q = "'\(folderID)' in parents and trashed=false"
        let encodedQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let fields = "nextPageToken,files(id,name,mimeType,modifiedTime,size,md5Checksum,iconLink,thumbnailLink)"
        var urlString = "\(apiBase)/files?q=\(encodedQ)&fields=\(fields)&orderBy=folder,name&pageSize=50"
        if let token = pageToken {
            urlString += "&pageToken=\(token)"
        }
        let url = URL(string: urlString)!
        let response: PagedDriveListResponse = try await get(url, accessToken: accessToken)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metadata = response.files.map { file in
            DriveFileMetadata(
                id: file.id,
                name: file.name,
                mimeType: file.mimeType ?? "application/octet-stream",
                modifiedTime: formatter.date(from: file.modifiedTime ?? "") ?? Date.distantPast,
                size: file.size,
                md5Checksum: file.md5Checksum
            )
        }
        return DrivePagedFileList(files: metadata, nextPageToken: response.nextPageToken)
    }

    /// Searches the user's entire Drive for files matching a free-text query.
    static func searchUserFiles(
        query: String,
        pageToken: String? = nil,
        accessToken: String
    ) async throws -> DrivePagedFileList {
        let escaped = query.replacingOccurrences(of: "'", with: "\\'")
        let q = "fullText contains '\(escaped)' and trashed=false"
        let encodedQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let fields = "nextPageToken,files(id,name,mimeType,modifiedTime,size,md5Checksum)"
        var urlString = "\(apiBase)/files?q=\(encodedQ)&fields=\(fields)&orderBy=modifiedTime desc&pageSize=50"
        if let token = pageToken {
            urlString += "&pageToken=\(token)"
        }
        let url = URL(string: urlString)!
        let response: PagedDriveListResponse = try await get(url, accessToken: accessToken)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metadata = response.files.map { file in
            DriveFileMetadata(
                id: file.id,
                name: file.name,
                mimeType: file.mimeType ?? "application/octet-stream",
                modifiedTime: formatter.date(from: file.modifiedTime ?? "") ?? Date.distantPast,
                size: file.size,
                md5Checksum: file.md5Checksum
            )
        }
        return DrivePagedFileList(files: metadata, nextPageToken: response.nextPageToken)
    }

    // MARK: - Storage quota

    /// Returns the authenticated user's Drive storage quota.
    static func getStorageQuota(accessToken: String) async throws -> DriveStorageQuota {
        let url = URL(string: "\(apiBase)/about?fields=storageQuota")!
        let response: AboutResponse = try await get(url, accessToken: accessToken)
        let sq = response.storageQuota
        return DriveStorageQuota(
            limitBytes: Int64(sq.limit ?? "0") ?? -1,
            usageBytes: Int64(sq.usage ?? "0") ?? 0,
            usageInDriveBytes: Int64(sq.usageInDrive ?? "0") ?? 0,
            usageInDriveTrashBytes: Int64(sq.usageInDriveTrash ?? "0") ?? 0
        )
    }

    // MARK: - Internal networking

    private static func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await execute(request)
    }

    private static func postJSON<T: Decodable>(
        _ url: URL,
        json: [String: Any],
        accessToken: String
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await execute(request)
    }

    private static func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response)
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw GoogleDriveClientError.decodingError(error)
            }
        } catch let error as GoogleDriveClientError {
            throw error
        } catch {
            throw GoogleDriveClientError.networkError(error)
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw GoogleDriveClientError.unauthorized
        case 404:       throw GoogleDriveClientError.notFound
        case 429:       throw GoogleDriveClientError.quotaExceeded
        default:
            throw GoogleDriveClientError.serverError(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
    }

    // MARK: - Response models (internal)

    private struct DriveListResponse: Decodable {
        let files: [DriveFileResponse]
    }

    private struct PagedDriveListResponse: Decodable {
        let files: [DriveFileResponse]
        let nextPageToken: String?
    }

    struct DriveFileResponse: Decodable {
        let id: String
        let name: String
        var mimeType: String?
        var modifiedTime: String?
        var size: Int64?
        var md5Checksum: String?
    }

    private struct AboutResponse: Decodable {
        let storageQuota: StorageQuotaResponse
    }

    private struct StorageQuotaResponse: Decodable {
        var limit: String?
        var usage: String?
        var usageInDrive: String?
        var usageInDriveTrash: String?
    }
}
