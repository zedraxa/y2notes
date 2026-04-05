import SwiftUI

// MARK: - Text Object Handles View

/// Floating action bar that appears when a text object is selected on the canvas.
/// Provides quick actions: style editor (font family, size, weight, colour,
/// alignment, background, border), duplicate, lock/unlock, bring to front /
/// send to back, and delete.
///
/// Rendered as a SwiftUI overlay in `NoteEditorView` and positioned near the
/// toolbar area, matching the aesthetic of `ShapeHandlesView`.
struct TextObjectHandlesView: View {
    let textObject: TextObject
    var onAction: (TextObjectAction) -> Void

    @State private var showStyleEditor = false

    private let selectionFeedback = UISelectionFeedbackGenerator()

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
                .frame(width: 280)
            }

            divider

            // Bold toggle
            Button {
                selectionFeedback.selectionChanged()
                onAction(.toggleBold)
            } label: {
                Label("Bold", systemImage: "bold")
                    .labelStyle(.iconOnly)
                    .fontWeight(textObject.isBold ? .bold : .regular)
            }
            .tint(textObject.isBold ? .accentColor : .secondary)

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

/// Inline popover for editing text object font family, size, weight, text
/// colour, alignment, background colour, and border style.
/// Mirrors the `ShapeStyleEditorView` aesthetic.
struct TextStyleEditorView: View {
    let textObject: TextObject
    var onAction: (TextObjectAction) -> Void

    @State private var fontSize: CGFloat
    @State private var fontFamily: TextFontFamily
    @State private var isBold: Bool
    @State private var textColor: Color
    @State private var hasBackground: Bool
    @State private var backgroundColor: Color
    @State private var alignmentRaw: Int
    @State private var borderRadius: CGFloat
    @State private var hasBorder: Bool
    @State private var borderColor: Color
    @State private var borderWidth: CGFloat

    private let selectionFeedback = UISelectionFeedbackGenerator()

    init(textObject: TextObject, onAction: @escaping (TextObjectAction) -> Void) {
        self.textObject = textObject
        self.onAction = onAction
        _fontSize = State(initialValue: textObject.fontSize)
        _fontFamily = State(initialValue: textObject.fontFamily)
        _isBold = State(initialValue: textObject.isBold)
        _textColor = State(initialValue: Color(uiColor: textObject.textColor))
        _hasBackground = State(initialValue: textObject.backgroundColor != nil)
        _backgroundColor = State(initialValue: Color(uiColor: textObject.backgroundColor ?? .systemYellow.withAlphaComponent(TextObjectConstants.defaultBackgroundAlpha)))
        _alignmentRaw = State(initialValue: textObject.alignmentRaw)
        _borderRadius = State(initialValue: textObject.borderRadius)
        _hasBorder = State(initialValue: textObject.borderWidth > 0)
        _borderColor = State(initialValue: Color(uiColor: textObject.borderColor ?? .separator))
        _borderWidth = State(initialValue: textObject.borderWidth)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("TextStyle.Title", comment: ""))
                    .font(.headline)

                // Font family picker
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("TextStyle.Font", comment: ""))
                        .font(.subheadline)
                    HStack(spacing: 4) {
                        ForEach(TextFontFamily.allCases) { family in
                            let isSelected = fontFamily == family
                            Button {
                                fontFamily = family
                                selectionFeedback.selectionChanged()
                                onAction(.updateFontFamily(family))
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: family.systemImage)
                                        .font(.system(size: 14))
                                    Text(family.displayName)
                                        .font(.system(size: 9))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    isSelected
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(.systemGray5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Bold toggle
                Toggle(isOn: $isBold) {
                    Text(NSLocalizedString("TextStyle.Bold", comment: ""))
                        .font(.subheadline)
                }
                .onChange(of: isBold) { _, _ in
                    onAction(.toggleBold)
                }

                // Font size
                HStack {
                    Text(NSLocalizedString("TextStyle.Size", comment: ""))
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
                    Text(NSLocalizedString("TextStyle.Colour", comment: ""))
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
                    Text(NSLocalizedString("TextStyle.Align", comment: ""))
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

                Divider()

                // Background toggle + colour
                Toggle(isOn: $hasBackground) {
                    Text(NSLocalizedString("TextStyle.Background", comment: ""))
                        .font(.subheadline)
                }
                .onChange(of: hasBackground) { _, newValue in
                    onAction(.updateBackgroundColor(newValue ? UIColor(backgroundColor) : nil))
                }

                if hasBackground {
                    HStack {
                        Text(NSLocalizedString("TextStyle.Fill", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        ColorPicker("", selection: $backgroundColor, supportsOpacity: true)
                            .labelsHidden()
                            .onChange(of: backgroundColor) { _, _ in
                                onAction(.updateBackgroundColor(UIColor(backgroundColor)))
                            }
                    }
                }

                Divider()

                // Border toggle + controls
                Toggle(isOn: $hasBorder) {
                    Text(NSLocalizedString("TextStyle.Border", comment: ""))
                        .font(.subheadline)
                }
                .onChange(of: hasBorder) { _, newValue in
                    if newValue {
                        borderWidth = max(borderWidth, 1)
                        onAction(.updateBorderWidth(borderWidth))
                        onAction(.updateBorderColor(UIColor(borderColor)))
                    } else {
                        onAction(.updateBorderWidth(0))
                        onAction(.updateBorderColor(nil))
                    }
                }

                if hasBorder {
                    HStack {
                        Text(NSLocalizedString("TextStyle.BorderColour", comment: ""))
                            .font(.subheadline)
                        Spacer()
                        ColorPicker("", selection: $borderColor, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: borderColor) { _, _ in
                                onAction(.updateBorderColor(UIColor(borderColor)))
                            }
                    }

                    HStack {
                        Text(NSLocalizedString("TextStyle.Thickness", comment: ""))
                            .font(.subheadline)
                        Slider(
                            value: $borderWidth,
                            in: TextObjectConstants.minBorderWidth...TextObjectConstants.maxBorderWidth,
                            step: 0.5
                        )
                        .onChange(of: borderWidth) { _, newValue in
                            onAction(.updateBorderWidth(newValue))
                        }
                        Text(String(format: "%.1f", borderWidth))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }

                // Corner radius (always available)
                HStack {
                    Text(NSLocalizedString("TextStyle.Corners", comment: ""))
                        .font(.subheadline)
                    Slider(
                        value: $borderRadius,
                        in: TextObjectConstants.minBorderRadius...TextObjectConstants.maxBorderRadius,
                        step: 1
                    )
                    .onChange(of: borderRadius) { _, newValue in
                        onAction(.updateBorderRadius(newValue))
                    }
                    Text("\(Int(borderRadius))")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 20)
                }
            }
            .padding()
        }
    }
}
