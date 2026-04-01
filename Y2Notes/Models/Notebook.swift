import Foundation

// MARK: - Cover theme

/// Named color themes for notebook covers.
enum NotebookCover: String, CaseIterable, Codable {
    case ocean
    case forest
    case sunset
    case lavender
    case slate
    case sand

    var displayName: String {
        switch self {
        case .ocean:    return "Ocean"
        case .forest:   return "Forest"
        case .sunset:   return "Sunset"
        case .lavender: return "Lavender"
        case .slate:    return "Slate"
        case .sand:     return "Sand"
        }
    }
}

// MARK: - Notebook model

struct Notebook: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var cover: NotebookCover

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        cover: NotebookCover = .ocean
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.cover = cover
    }

    // MARK: Hashable — identity only.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Notebook, rhs: Notebook) -> Bool { lhs.id == rhs.id }
}
