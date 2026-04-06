import Foundation
import SwiftUI

// MARK: - Section color tag

/// Named color options for section tabs.
public enum SectionColorTag: String, CaseIterable, Codable {
    case none   = "none"
    case red    = "red"
    case orange = "orange"
    case teal   = "teal"
    case blue   = "blue"
    case purple = "purple"
}

// MARK: - SectionColorTag SwiftUI color

extension SectionColorTag {
    public var color: Color {
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
public enum SectionKind: String, Codable {
    case section
    case divider
}

// MARK: - NotebookSection model

public struct NotebookSection: Identifiable, Codable, Hashable {
    public let id: UUID
    public var notebookID: UUID
    public var name: String
    public var kind: SectionKind
    public var sortOrder: Int
    public var defaultTemplateID: String
    public var colorTag: SectionColorTag
    public var defaultPageType: PageType?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
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

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, notebookID, name, kind, sortOrder, defaultTemplateID, colorTag, defaultPageType, createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
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

    // MARK: Hashable
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: NotebookSection, rhs: NotebookSection) -> Bool { lhs.id == rhs.id }
}
