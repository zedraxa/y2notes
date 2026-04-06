import Foundation

// MARK: - Toolbar Opacity Provider

/// Describes an object whose toolbar opacity can be updated by effect engines.
///
/// `FocusModeEngine` and `AmbientEnvironmentEngine` write to this property to
/// reduce the toolbar's visual weight when immersive effects are active.
/// Conformance is trivially satisfied by any `ObservableObject` that already
/// exposes a `toolbarOpacity: Double` property (e.g. `DrawingToolStore`).
public protocol ToolbarOpacityProvider: AnyObject {
    var toolbarOpacity: Double { get set }
}
