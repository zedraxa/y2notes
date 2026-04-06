import Foundation

// MARK: - MediaFileManager

/// Manages external media files for embedded canvas objects.
///
/// Binary blobs (images, audio) are stored in the app's Documents directory
/// rather than inline in the note JSON.  Only lightweight metadata (file paths,
/// frames, settings) travels with the JSON payload.
///
/// ## Directory layout
/// ```
/// Documents/
/// ├── NoteMedia/
/// │   └── {noteID}/
/// │       └── {objectID}.jpg   ← image files
/// └── AudioClips/
///     └── {objectID}.m4a       ← audio recordings
/// ```
final class MediaFileManager {

    // MARK: Shared instance

    static let shared = MediaFileManager()
    private init() { ensureDirectoriesExist() }

    // MARK: - Directories

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var noteMediaRootURL: URL {
        documentsURL.appendingPathComponent("NoteMedia", isDirectory: true)
    }

    var audioClipsRootURL: URL {
        documentsURL.appendingPathComponent("AudioClips", isDirectory: true)
    }

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        [noteMediaRootURL, audioClipsRootURL].forEach { url in
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Image I/O

    /// Persists JPEG image data for a canvas object.
    ///
    /// - Parameters:
    ///   - noteID: Owning note UUID.
    ///   - objectID: Canvas object UUID (used as filename).
    ///   - imageData: JPEG-compressed data.
    /// - Returns: The relative path stored in ``ImageObject.relativePath``.
    @discardableResult
    func saveImage(noteID: UUID, objectID: UUID, imageData: Data) throws -> String {
        let dir = noteMediaRootURL.appendingPathComponent(noteID.uuidString, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let filename = "\(objectID.uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        try imageData.write(to: fileURL, options: .atomic)
        return "NoteMedia/\(noteID.uuidString)/\(filename)"
    }

    /// Loads image data for a canvas object.
    ///
    /// - Parameters:
    ///   - relativePath: The ``ImageObject.relativePath`` value.
    /// - Returns: JPEG data, or `nil` if the file does not exist.
    func loadImage(relativePath: String) -> Data? {
        let fileURL = documentsURL.appendingPathComponent(relativePath)
        return try? Data(contentsOf: fileURL)
    }

    /// Returns the full URL for an image given its relative path.
    func imageURL(relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }

    // MARK: - Audio I/O

    /// Returns the file URL for a new audio recording.
    ///
    /// - Parameter objectID: Canvas object UUID that will own this recording.
    /// - Returns: URL to write the `.m4a` file to.
    func audioURL(objectID: UUID) -> URL {
        audioClipsRootURL.appendingPathComponent("\(objectID.uuidString).m4a")
    }

    /// Saves audio data from an in-memory buffer.
    ///
    /// When recording directly with `AVAudioRecorder` the file is written by
    /// the recorder itself to ``audioURL(objectID:)``.  Call this variant only
    /// when you have an in-memory buffer (e.g. from a URL import).
    @discardableResult
    func saveAudio(objectID: UUID, audioData: Data) throws -> URL {
        let url = audioURL(objectID: objectID)
        try audioData.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Cascade Delete

    /// Deletes all media files belonging to a note.
    ///
    /// Called from `NoteStore.deleteNotes(ids:)` after the note record is removed.
    func deleteMediaForNote(noteID: UUID) {
        let dir = noteMediaRootURL.appendingPathComponent(noteID.uuidString)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Storage Accounting

    /// Total disk usage of managed media files in bytes.
    func diskUsage() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        let roots = [noteMediaRootURL, audioClipsRootURL]
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in enumerator {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Orphan Cleanup

    /// Removes media files that are not referenced by any live note.
    ///
    /// - Parameter referencedPaths: All `relativePath` values gathered from active notes.
    func cleanup(referencedPaths: Set<String>) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: noteMediaRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: documentsURL.path + "/", with: "")
            if !referencedPaths.contains(relative) {
                try? fm.removeItem(at: url)
            }
        }
    }
}
