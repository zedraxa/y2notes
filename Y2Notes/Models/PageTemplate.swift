import Foundation

// MARK: - Built-in template catalogue

/// The page rule/grid templates shipped with Y2Notes.
/// Each case maps 1-to-1 to a ``PageTemplate`` with ID `"builtin.<rawValue>"`.
enum BuiltInTemplate: String, CaseIterable, Codable {
    case blank
    case lined
    case grid
    case dotted
    case cornell    // Cornell notes: vertical rule + horizontal footer band
    case staved     // Music: five-line staff groups

    var displayName: String {
        switch self {
        case .blank:   return "Blank"
        case .lined:   return "Lined"
        case .grid:    return "Grid"
        case .dotted:  return "Dotted"
        case .cornell: return "Cornell"
        case .staved:  return "Music Staff"
        }
    }

    var systemImage: String {
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
    var category: String { "Built-in" }
}

// MARK: - PageTemplate

/// A fully described page template.  Used when creating or configuring a page (``Note``).
///
/// ## ID convention
/// - Built-in: `"builtin.<BuiltInTemplate.rawValue>"`, e.g. `"builtin.blank"`
/// - Pack-supplied: `"pack.<packID>.<slug>"`, e.g. `"pack.com.y2notes.packs.classico.ruled"`
struct PageTemplate: Identifiable, Codable, Hashable {
    /// Stable string key — **never changes after creation**.
    let id: String
    var displayName: String
    /// Human-readable source label ("Built-in", pack display name, …).
    var category: String
    /// SF Symbol name used in picker UIs.
    var systemImage: String
    /// Non-nil only for the ``BuiltInTemplate`` cases.
    var builtIn: BuiltInTemplate?

    // MARK: Factory helpers

    static func builtIn(_ t: BuiltInTemplate) -> PageTemplate {
        PageTemplate(
            id: "builtin.\(t.rawValue)",
            displayName: t.displayName,
            category: t.category,
            systemImage: t.systemImage,
            builtIn: t
        )
    }

    /// All built-in templates in catalogue order (blank first).
    static var allBuiltIn: [PageTemplate] {
        BuiltInTemplate.allCases.map { .builtIn($0) }
    }

    // MARK: Hashable — identity only so that list selections stay stable while content changes.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PageTemplate, rhs: PageTemplate) -> Bool { lhs.id == rhs.id }
}

// MARK: - Template pack protocol

/// Conform to this protocol to supply a third-party template pack and register it
/// via ``TemplateRegistry/register(_:)`` at app launch.
///
/// ```swift
/// struct ClassicoPack: TemplatePackProviding {
///     let packID      = "com.y2notes.packs.classico"
///     let displayName = "Classico"
///     let templates   = [
///         PageTemplate(id: "pack.com.y2notes.packs.classico.ruled",
///                      displayName: "Ruled", category: "Classico",
///                      systemImage: "text.alignleft", builtIn: nil)
///     ]
/// }
/// TemplateRegistry.shared.register(ClassicoPack())
/// ```
protocol TemplatePackProviding {
    /// Stable reverse-DNS identifier, e.g. `"com.y2notes.packs.classico"`.
    var packID: String { get }
    var displayName: String { get }
    var templates: [PageTemplate] { get }
}

// MARK: - TemplateRegistry

/// Central registry that merges built-in templates with any registered packs.
///
/// - Thread safety: reads are safe from any thread; ``register(_:)`` must be called on
///   the main thread at app launch before any reads occur from other threads.
final class TemplateRegistry {
    static let shared = TemplateRegistry()
    private init() {}

    private var registeredPacks: [String: any TemplatePackProviding] = [:]

    /// All available templates: built-ins first, then packs sorted by `packID`.
    var allTemplates: [PageTemplate] {
        var result = PageTemplate.allBuiltIn
        for pack in registeredPacks.values.sorted(by: { $0.packID < $1.packID }) {
            result.append(contentsOf: pack.templates)
        }
        return result
    }

    /// The default template for new pages (always the built-in blank template).
    var defaultTemplate: PageTemplate { .builtIn(.blank) }

    /// Stable ID of the default template (`"builtin.blank"`).
    var defaultTemplateID: String { defaultTemplate.id }

    /// Looks up a template by its stable ID; returns the blank built-in if not found.
    func template(withID id: String) -> PageTemplate {
        allTemplates.first { $0.id == id } ?? defaultTemplate
    }

    /// All templates belonging to a specific pack.
    func templates(inPack packID: String) -> [PageTemplate] {
        registeredPacks[packID]?.templates ?? []
    }

    /// Registers a third-party template pack.  No-op if the `packID` is already registered.
    func register(_ pack: any TemplatePackProviding) {
        guard registeredPacks[pack.packID] == nil else { return }
        registeredPacks[pack.packID] = pack
    }
}
