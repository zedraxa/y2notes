import Foundation
import SwiftUI

// MARK: - Section color tag

/// Named color options for section tabs. Stored as a raw String for forward compatibility.
enum SectionColorTag: String, CaseIterable, Codable {
    case none   = "none"
    case red    = "red"
    case orange = "orange"
    case teal   = "teal"
    case blue   = "blue"
    case purple = "purple"
}

// MARK: - SectionColorTag SwiftUI color

extension SectionColorTag {
    var color: Color {
        switch self {
        case .none:   return Color.accentColor
        case .red:    return Color(red: 0.86, green: 0.20, blue: 0.20)
        case .orange: return Color(red: 0.92, green: 0.50, blue: 0.10)
        case .teal:   return Color(red: 0.10, green: 0.65, blue: 0.60)
        case .blue:   return Color(red: 0.12, green: 0.45, blue: 0.90)
        case .purple: return Color(red: 0.55, green: 0.15, blue: 0.80)
        }
    }
}

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
    /// Optional color tag shown in section tabs. `.none` falls back to the app accent color.
    var colorTag: SectionColorTag
    /// Optional per-section page type override. `nil` = inherit the notebook's `pageType`.
    var defaultPageType: PageType?
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        notebookID: UUID,
        name: String,
        kind: SectionKind = .section,
        sortOrder: Int = 0,
        defaultTemplateID: String = "builtin.blank",
        colorTag: SectionColorTag = .none,
        defaultPageType: PageType? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.notebookID = notebookID
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.defaultTemplateID = defaultTemplateID
        self.colorTag = colorTag
        self.defaultPageType = defaultPageType
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: Codable — decodeIfPresent for new fields to enable smooth schema evolution.

    enum CodingKeys: String, CodingKey {
        case id, notebookID, name, kind, sortOrder, defaultTemplateID, colorTag, defaultPageType, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        notebookID        = try c.decode(UUID.self,   forKey: .notebookID)
        name              = try c.decode(String.self, forKey: .name)
        createdAt         = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt        = try c.decode(Date.self,   forKey: .modifiedAt)
        kind              = try c.decodeIfPresent(SectionKind.self,      forKey: .kind)              ?? .section
        sortOrder         = try c.decodeIfPresent(Int.self,              forKey: .sortOrder)         ?? 0
        defaultTemplateID = try c.decodeIfPresent(String.self,           forKey: .defaultTemplateID) ?? "builtin.blank"
        colorTag          = try c.decodeIfPresent(SectionColorTag.self,  forKey: .colorTag)          ?? .none
        defaultPageType   = try c.decodeIfPresent(PageType.self,         forKey: .defaultPageType)
    }

    // MARK: Hashable — identity only so that list selections stay stable while content changes.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: NotebookSection, rhs: NotebookSection) -> Bool { lhs.id == rhs.id }
}
