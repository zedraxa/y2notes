import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    /// Serialised PKDrawing data (empty Data = blank canvas).
    var drawingData: Data

    init(
        id: UUID = UUID(),
        title: String = "New Note",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        drawingData: Data = Data()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.drawingData = drawingData
    }

    // MARK: Hashable — identity only, so list selection stays stable while content changes.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}
