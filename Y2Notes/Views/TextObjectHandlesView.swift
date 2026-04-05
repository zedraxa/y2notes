import SwiftUI

// MARK: - Text Object Handles View

/// Floating action bar that appears when a text object is selected on the canvas.
/// Provides quick actions: style editor (font size, colour, alignment, background),
/// duplicate, lock/unlock, bring to front / send to back, and delete.
///
/// Rendered as a SwiftUI overlay in `NoteEditorView` and positioned near the
/// toolbar area, matching the aesthetic of `ShapeHandlesView`.
struct TextObjectHandlesView: View {
    let textObject: TextObject
    var onAction: (TextObjectAction) -> Void

    @State private var showStyleEditor = false

    var body: some View {
        HStack(spacing: 4) {
            // Style editor
            Button {
                showStyleEditor = true
            } label: {
                Label("Style", systemImage: "textformat")
                    .labelStyle(.iconOnly)
            }
            .popover(isPresented: $showStyleEditor) {
                TextStyleEditorView(
                    textObject: textObject,
                    onAction: onAction
                )
                .frame(width: 260)
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
                    textObject.isLocked ? "Unlock" : "Lock",
                    systemImage: textObject.isLocked ? "lock.fill" : "lock.open"
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

// MARK: - Text Style Editor

/// Inline popover for editing text object font size, text colour, background
/// colour, and alignment. Mirrors the `ShapeStyleEditorView` aesthetic.
struct TextStyleEditorView: View {
    let textObject: TextObject
    var onAction: (TextObjectAction) -> Void

    @State private var fontSize: CGFloat
    @State private var textColor: Color
    @State private var hasBackground: Bool
    @State private var backgroundColor: Color
    @State private var alignmentRaw: Int

    init(textObject: TextObject, onAction: @escaping (TextObjectAction) -> Void) {
        self.textObject = textObject
        self.onAction = onAction
        _fontSize = State(initialValue: textObject.fontSize)
        _textColor = State(initialValue: Color(uiColor: textObject.textColor))
        _hasBackground = State(initialValue: textObject.backgroundColor != nil)
        _backgroundColor = State(initialValue: Color(uiColor: textObject.backgroundColor ?? .systemYellow.withAlphaComponent(TextObjectConstants.defaultBackgroundAlpha)))
        _alignmentRaw = State(initialValue: textObject.alignmentRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Style")
                .font(.headline)

            // Font size
            HStack {
                Text("Size")
                    .font(.subheadline)
                Slider(
                    value: $fontSize,
                    in: TextObjectConstants.minFontSize...TextObjectConstants.maxFontSize,
                    step: 1
                )
                .onChange(of: fontSize) { _, newValue in
                    onAction(.updateFontSize(newValue))
                }
                Text("\(Int(fontSize))pt")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36)
            }

            // Text colour
            HStack {
                Text("Colour")
                    .font(.subheadline)
                Spacer()
                ColorPicker("", selection: $textColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: textColor) { _, _ in
                        onAction(.updateTextColor(UIColor(textColor)))
                    }
            }

            // Alignment
            HStack {
                Text("Align")
                    .font(.subheadline)
                Spacer()
                Picker("Alignment", selection: $alignmentRaw) {
                    Image(systemName: "text.alignleft").tag(0)
                    Image(systemName: "text.aligncenter").tag(1)
                    Image(systemName: "text.alignright").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: alignmentRaw) { _, newValue in
                    let alignment: NSTextAlignment
                    switch newValue {
                    case 1:  alignment = .center
                    case 2:  alignment = .right
                    default: alignment = .left
                    }
                    onAction(.updateAlignment(alignment))
                }
            }

            // Background toggle + colour
            Toggle(isOn: $hasBackground) {
                Text("Background")
                    .font(.subheadline)
            }
            .onChange(of: hasBackground) { _, newValue in
                onAction(.updateBackgroundColor(newValue ? UIColor(backgroundColor) : nil))
            }

            if hasBackground {
                HStack {
                    Text("Fill")
                        .font(.subheadline)
                    Spacer()
                    ColorPicker("", selection: $backgroundColor, supportsOpacity: true)
                        .labelsHidden()
                        .onChange(of: backgroundColor) { _, _ in
                            onAction(.updateBackgroundColor(UIColor(backgroundColor)))
                        }
                }
            }
        }
        .padding()
    }
}
