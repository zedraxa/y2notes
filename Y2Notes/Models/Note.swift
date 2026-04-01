import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    /// Serialised PKDrawing data (empty Data = blank canvas).
    var drawingData: Data
    /// Whether the user has starred this note.
    var isFavorited: Bool
    /// The notebook this note belongs to (nil = unfiled).
    var notebookID: UUID?
    /// The section within the notebook this page belongs to (nil = no section / notebook-level).
    var sectionID: UUID?
    /// 0-based position within the section (or notebook root if `sectionID` is nil).
    /// Lower numbers appear first in ordered page lists.
    var sortOrder: Int
    /// Stable ID of the page template applied when this page was created.
    /// See ``TemplateRegistry`` and ``PageTemplate``.
    var templateID: String
    /// Per-note theme override. When non-nil the editor canvas uses this theme instead
    /// of the global app theme. App chrome (sidebar, navigation) always follows the global theme.
    var themeOverride: AppTheme?

    init(
        id: UUID = UUID(),
        title: String = "New Note",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        drawingData: Data = Data(),
        isFavorited: Bool = false,
        notebookID: UUID? = nil,
        sectionID: UUID? = nil,
        sortOrder: Int = 0,
        templateID: String = "builtin.blank",
        themeOverride: AppTheme? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.drawingData = drawingData
        self.isFavorited = isFavorited
        self.notebookID = notebookID
        self.sectionID = sectionID
        self.sortOrder = sortOrder
        self.templateID = templateID
        self.themeOverride = themeOverride
    }

    // MARK: Codable — custom decoder for backward compatibility with old saves
    // that pre-date the isFavorited / notebookID / themeOverride / sectionID / sortOrder / templateID fields.
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, drawingData
        case isFavorited, notebookID, sectionID, sortOrder, templateID, themeOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        title         = try c.decode(String.self, forKey: .title)
        createdAt     = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt    = try c.decode(Date.self,   forKey: .modifiedAt)
        drawingData   = try c.decode(Data.self,   forKey: .drawingData)
        isFavorited   = try c.decodeIfPresent(Bool.self,     forKey: .isFavorited)  ?? false
        notebookID    = try c.decodeIfPresent(UUID.self,     forKey: .notebookID)
        sectionID     = try c.decodeIfPresent(UUID.self,     forKey: .sectionID)
        sortOrder     = try c.decodeIfPresent(Int.self,      forKey: .sortOrder)    ?? 0
        templateID    = try c.decodeIfPresent(String.self,   forKey: .templateID)   ?? "builtin.blank"
        themeOverride = try c.decodeIfPresent(AppTheme.self, forKey: .themeOverride)
    }

    // MARK: Hashable — identity only, so list selection stays stable while content changes.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}
