import Foundation

// MARK: - Section kind

/// Distinguishes a real named section from a purely visual section divider.
enum SectionKind: String, Codable {
    /// A named section that can own pages.
    case section
    /// A visual separator row with an optional label; does not own pages.
    case divider
}

// MARK: - NotebookSection model

/// A section — or visual divider — within a notebook.
///
/// Sections add an explicit ordering layer between a ``Notebook`` and its pages (``Note``s).
/// Each section belongs to exactly one notebook and carries a 0-based ``sortOrder`` that
/// determines its position within the notebook's section list.
///
/// Backward compatibility: all ``CodingKeys`` use ``decodeIfPresent`` where safe so that
/// older stores (without this model) still load cleanly.
struct NotebookSection: Identifiable, Codable, Hashable {
    let id: UUID
    /// The notebook this section belongs to.
    var notebookID: UUID
    /// Display name shown in section headers.  Empty string is fine for dividers.
    var name: String
    /// Whether this entry is a real section or a visual divider.
    var kind: SectionKind
    /// 0-based position within the notebook; lower numbers appear first.
    var sortOrder: Int
    /// Default template ID applied to new pages added to this section.
    /// Falls back to `"builtin.blank"` if empty.
    var defaultTemplateID: String
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        notebookID: UUID,
        name: String,
        kind: SectionKind = .section,
        sortOrder: Int = 0,
        defaultTemplateID: String = "builtin.blank",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.notebookID = notebookID
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.defaultTemplateID = defaultTemplateID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: Codable — decodeIfPresent for new fields to enable smooth schema evolution.

    enum CodingKeys: String, CodingKey {
        case id, notebookID, name, kind, sortOrder, defaultTemplateID, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        notebookID        = try c.decode(UUID.self,   forKey: .notebookID)
        name              = try c.decode(String.self, forKey: .name)
        createdAt         = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt        = try c.decode(Date.self,   forKey: .modifiedAt)
        kind              = try c.decodeIfPresent(SectionKind.self, forKey: .kind)              ?? .section
        sortOrder         = try c.decodeIfPresent(Int.self,         forKey: .sortOrder)         ?? 0
        defaultTemplateID = try c.decodeIfPresent(String.self,      forKey: .defaultTemplateID) ?? "builtin.blank"
    }

    // MARK: Hashable — identity only so that list selections stay stable while content changes.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: NotebookSection, rhs: NotebookSection) -> Bool { lhs.id == rhs.id }
}
