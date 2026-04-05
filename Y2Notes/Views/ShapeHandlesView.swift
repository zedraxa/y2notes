import SwiftUI

// MARK: - Shape Handles View

/// Floating action bar that appears when a shape is selected on the canvas.
/// Provides quick actions: duplicate, lock/unlock, bring to front / send to back,
/// delete, and a style editor popover for stroke/fill/opacity.
///
/// Rendered as a SwiftUI overlay in `NoteEditorView` and positioned near the
/// selected shape (or at a fixed toolbar location when space is tight).
struct ShapeHandlesView: View {
    @ObservedObject var toolStore: DrawingToolStore
    let selectedShape: ShapeInstance
    var onAction: (ShapeAction) -> Void

    @State private var showStyleEditor = false

    var body: some View {
        HStack(spacing: 4) {
            // Style editor
            Button {
                showStyleEditor = true
            } label: {
                Label("Style", systemImage: "paintbrush")
                    .labelStyle(.iconOnly)
            }
            .popover(isPresented: $showStyleEditor) {
                ShapeStyleEditorView(
                    style: selectedShape.style,
                    onStyleChange: { newStyle in
                        onAction(.updateStyle(newStyle))
                    }
                )
                .frame(width: 250)
            }

            divider

            // Duplicate
            Button {
                onAction(.duplicate)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .labelStyle(.iconOnly)
            }

            // Lock / Unlock
            Button {
                onAction(.toggleLock)
            } label: {
                Label(
                    selectedShape.isLocked ? "Unlock" : "Lock",
                    systemImage: selectedShape.isLocked ? "lock.fill" : "lock.open"
                )
                .labelStyle(.iconOnly)
            }

            divider

            // Bring to front
            Button {
                onAction(.bringToFront)
            } label: {
                Label("Front", systemImage: "square.3.layers.3d.top.filled")
                    .labelStyle(.iconOnly)
            }

            // Send to back
            Button {
                onAction(.sendToBack)
            } label: {
                Label("Back", systemImage: "square.3.layers.3d.bottom.filled")
                    .labelStyle(.iconOnly)
            }

            divider

            // Delete
            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }

    private var divider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color(uiColor: .separator).opacity(0.3))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }
}

// MARK: - Shape Action

/// Actions available for a selected shape object.
enum ShapeAction {
    case duplicate
    case delete
    case toggleLock
    case bringToFront
    case sendToBack
    case updateStyle(ShapeStyle)
}

// MARK: - Shape Style Editor

/// Inline popover for editing shape stroke colour, fill colour, stroke width,
/// and opacity. Mirrors the ToolExpansionView aesthetic.
struct ShapeStyleEditorView: View {
    var style: ShapeStyle
    var onStyleChange: (ShapeStyle) -> Void

    @State private var strokeColor: Color
    @State private var hasFill: Bool
    @State private var fillColor: Color
    @State private var strokeWidth: CGFloat
    @State private var opacity: CGFloat

    init(style: ShapeStyle, onStyleChange: @escaping (ShapeStyle) -> Void) {
        self.style = style
        self.onStyleChange = onStyleChange
        _strokeColor = State(initialValue: Color(uiColor: style.strokeColor))
        _hasFill = State(initialValue: style.fillColor != nil)
        _fillColor = State(initialValue: Color(uiColor: style.fillColor ?? .systemBlue))
        _strokeWidth = State(initialValue: style.strokeWidth)
        _opacity = State(initialValue: style.opacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shape Style")
                .font(.headline)

            // Stroke colour
            HStack {
                Text("Stroke")
                    .font(.subheadline)
                Spacer()
                ColorPicker("", selection: $strokeColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: strokeColor) { _, _ in emitChange() }
            }

            // Stroke width
            HStack {
                Text("Width")
                    .font(.subheadline)
                Slider(value: $strokeWidth, in: 0.5...10, step: 0.5)
                    .onChange(of: strokeWidth) { _, _ in emitChange() }
                Text("\(strokeWidth, specifier: "%.1f")")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 30)
            }

            // Fill toggle + colour
            Toggle(isOn: $hasFill) {
                Text("Fill")
                    .font(.subheadline)
            }
            .onChange(of: hasFill) { _, _ in emitChange() }

            if hasFill {
                HStack {
                    Text("Fill Color")
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: $fillColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: fillColor) { _, _ in emitChange() }
                }
            }

            // Opacity
            HStack {
                Text("Opacity")
                    .font(.subheadline)
                Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
                    .onChange(of: opacity) { _, _ in emitChange() }
                Text("\(Int(opacity * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36)
            }
        }
        .padding()
    }

    private func emitChange() {
        let newStyle = ShapeStyle(
            strokeColor: UIColor(strokeColor),
            strokeWidth: strokeWidth,
            fillColor: hasFill ? UIColor(fillColor) : nil,
            opacity: opacity
        )
        onStyleChange(newStyle)
    }
}
