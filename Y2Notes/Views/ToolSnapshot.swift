import PencilKit

// MARK: - Tool Snapshot

/// Lightweight, equatable snapshot of a PKTool's identity.
/// Used to avoid redundant `canvas.tool` assignments in `updateUIView` that
/// would reset PencilKit's pressure/tilt pipeline.
struct ToolSnapshot: Equatable {
    let kind: String       // "inking", "eraser", "lasso"
    let inkType: String?   // e.g. "pen", "pencil", "marker", "fountainPen"
    let colorHash: Int?
    let width: CGFloat?

    init(_ tool: PKTool) {
        if let ink = tool as? PKInkingTool {
            kind = "inking"
            inkType = ink.inkType.rawValue
            colorHash = ink.color.hash
            width = ink.width
        } else if tool is PKEraserTool {
            kind = "eraser"
            inkType = nil
            colorHash = nil
            width = nil
        } else {
            kind = "lasso"
            inkType = nil
            colorHash = nil
            width = nil
        }
    }
}
