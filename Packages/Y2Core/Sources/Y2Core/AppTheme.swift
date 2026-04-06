import Foundation

public enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system    = "system"
    case light     = "light"
    case dark      = "dark"
    case sepia     = "sepia"
    case midnight  = "midnight"
    case ocean     = "ocean"
    case rose      = "rose"
    case forest    = "forest"
    case lavender  = "lavender"
    case slate     = "slate"
    case ember     = "ember"
    case paper     = "paper"

    public var id: String { rawValue }
}
