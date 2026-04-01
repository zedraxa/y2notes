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

    init(
        id: UUID = UUID(),
        title: String = "New Note",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        drawingData: Data = Data(),
        isFavorited: Bool = false,
        notebookID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.drawingData = drawingData
        self.isFavorited = isFavorited
        self.notebookID = notebookID
    }

    // MARK: Codable — custom decoder for backward compatibility with old saves
    // that pre-date the isFavorited / notebookID fields.
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, drawingData, isFavorited, notebookID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        title      = try c.decode(String.self, forKey: .title)
        createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt = try c.decode(Date.self,   forKey: .modifiedAt)
        drawingData = try c.decode(Data.self,  forKey: .drawingData)
        isFavorited = try c.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
        notebookID  = try c.decodeIfPresent(UUID.self, forKey: .notebookID)
    }

    // MARK: Hashable — identity only, so list selection stays stable while content changes.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}
