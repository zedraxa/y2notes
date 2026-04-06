import Foundation

// MARK: - Built-in template catalogue

/// The page rule/grid templates shipped with Y2Notes.
/// Each case maps 1-to-1 to a ``PageTemplate`` with ID `"builtin.<rawValue>"`.
public enum BuiltInTemplate: String, CaseIterable, Codable {
    case blank
    case lined
    case grid
    case dotted
    case cornell    // Cornell notes: vertical rule + horizontal footer band
    case staved     // Music: five-line staff groups

    public var displayName: String {
        switch self {
        case .blank:   return "Blank"
        case .lined:   return "Lined"
        case .grid:    return "Grid"
        case .dotted:  return "Dotted"
        case .cornell: return "Cornell"
        case .staved:  return "Music Staff"
        }
    }

    public var systemImage: String {
        switch self {
        case .blank:   return "doc"
        case .lined:   return "text.alignleft"
        case .grid:    return "grid"
        case .dotted:  return "circle.grid.3x3"
        case .cornell: return "rectangle.split.2x1"
        case .staved:  return "music.note.list"
        }
    }

    /// Human-readable category for grouping in the picker UI.
    public var category: String { "Built-in" }
}

// MARK: - PageTemplate

/// A fully described page template.  Used when creating or configuring a page (``Note``).
public struct PageTemplate: Identifiable, Codable, Hashable {
    /// Stable string key — **never changes after creation**.
    public let id: String
    public var displayName: String
    /// Human-readable source label ("Built-in", pack display name, …).
    public var category: String
    /// SF Symbol name used in picker UIs.
    public var systemImage: String
    /// Non-nil only for the ``BuiltInTemplate`` cases.
    public var builtIn: BuiltInTemplate?

    public init(
        id: String,
        displayName: String,
        category: String,
        systemImage: String,
        builtIn: BuiltInTemplate? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.systemImage = systemImage
        self.builtIn = builtIn
    }

    // MARK: Factory helpers

    public static func builtIn(_ t: BuiltInTemplate) -> PageTemplate {
        PageTemplate(
            id: "builtin.\(t.rawValue)",
            displayName: t.displayName,
            category: t.category,
            systemImage: t.systemImage,
            builtIn: t
        )
    }

    /// All built-in templates in catalogue order (blank first).
    public static var allBuiltIn: [PageTemplate] {
        BuiltInTemplate.allCases.map { .builtIn($0) }
    }

    // MARK: Hashable — identity only so that list selections stay stable while content changes.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: PageTemplate, rhs: PageTemplate) -> Bool { lhs.id == rhs.id }
}

// MARK: - Template pack protocol

/// Conform to this protocol to supply a third-party template pack and register it
/// via ``TemplateRegistry/register(_:)`` at app launch.
public protocol TemplatePackProviding {
    /// Stable reverse-DNS identifier, e.g. `"com.y2notes.packs.classico"`.
    var packID: String { get }
    var displayName: String { get }
    var templates: [PageTemplate] { get }
}

// MARK: - TemplateRegistry

/// Central registry that merges built-in templates with any registered packs.
public final class TemplateRegistry {
    public static let shared = TemplateRegistry()
    private init() {}

    private var registeredPacks: [String: any TemplatePackProviding] = [:]

    /// All available templates: built-ins first, then packs sorted by `packID`.
    public var allTemplates: [PageTemplate] {
        var result = PageTemplate.allBuiltIn
        for pack in registeredPacks.values.sorted(by: { $0.packID < $1.packID }) {
            result.append(contentsOf: pack.templates)
        }
        return result
    }

    /// The default template for new pages (always the built-in blank template).
    public var defaultTemplate: PageTemplate { .builtIn(.blank) }

    /// Stable ID of the default template (`"builtin.blank"`).
    public var defaultTemplateID: String { defaultTemplate.id }

    /// Looks up a template by its stable ID; returns the blank built-in if not found.
    public func template(withID id: String) -> PageTemplate {
        allTemplates.first { $0.id == id } ?? defaultTemplate
    }

    /// All templates belonging to a specific pack.
    public func templates(inPack packID: String) -> [PageTemplate] {
        registeredPacks[packID]?.templates ?? []
    }

    /// Registers a third-party template pack.  No-op if the `packID` is already registered.
    public func register(_ pack: any TemplatePackProviding) {
        guard registeredPacks[pack.packID] == nil else { return }
        registeredPacks[pack.packID] = pack
    }
}
