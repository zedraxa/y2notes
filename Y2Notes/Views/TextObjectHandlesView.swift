import SwiftUI
import UIKit

// MARK: - TextObjectHandlesView

/// SwiftUI action bar that appears above the selected text object.
/// Provides quick-access formatting buttons and a toggle for the full
/// `TextStyleEditorView` panel. Mirrors the `ShapeHandlesView` / `WidgetHandlesView`
/// pattern used for other canvas objects.
struct TextObjectHandlesView: View {

    @ObservedObject var toolStore: DrawingToolStore
    let textObject: TextObject
    var onAction: (TextObjectAction) -> Void

    @State private var showStyleEditor = false

    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 0) {
            handleBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if showStyleEditor {
                TextStyleEditorView(textObject: textObject) { updated in
                    onAction(.updateObject(updated))
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal:   .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
    }

    // MARK: - Handle Bar

    private var handleBar: some View {
        HStack(spacing: 4) {
            // Edit text content
            handleButton(icon: "pencil", label: NSLocalizedString("TextStyle.Edit", comment: "")) {
                onAction(.editText)
            }

            // Toggle style editor
            handleButton(
                icon: "textformat",
                label: NSLocalizedString("TextStyle.Title", comment: ""),
                isActive: showStyleEditor
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStyleEditor.toggle()
                }
            }

            Divider().frame(height: 18).padding(.horizontal, 2)

            // Bold
            handleButton(icon: "bold", label: NSLocalizedString("TextStyle.Bold", comment: ""),
                         isActive: textObject.isBold) {
                var u = textObject; u.isBold.toggle(); onAction(.updateObject(u))
            }
            // Italic
            handleButton(icon: "italic", label: NSLocalizedString("TextStyle.Italic", comment: ""),
                         isActive: textObject.isItalic) {
                var u = textObject; u.isItalic.toggle(); onAction(.updateObject(u))
            }
            // Underline
            handleButton(icon: "underline", label: NSLocalizedString("TextStyle.Underline", comment: ""),
                         isActive: textObject.isUnderline) {
                var u = textObject; u.isUnderline.toggle(); onAction(.updateObject(u))
            }

            Divider().frame(height: 18).padding(.horizontal, 2)

            // Bring forward
            handleButton(icon: "square.3.layers.3d.top.filled",
                         label: NSLocalizedString("TextStyle.BringForward", comment: "")) {
                onAction(.bringForward)
            }
            // Send backward
            handleButton(icon: "square.3.layers.3d.bottom.filled",
                         label: NSLocalizedString("TextStyle.SendBackward", comment: "")) {
                onAction(.sendBackward)
            }

            Divider().frame(height: 18).padding(.horizontal, 2)

            // Duplicate
            handleButton(icon: "doc.on.doc", label: NSLocalizedString("Common.Duplicate", comment: "")) {
                onAction(.duplicate)
            }

            // Lock / unlock
            handleButton(
                icon: textObject.isLocked ? "lock.fill" : "lock.open",
                label: textObject.isLocked
                    ? NSLocalizedString("TextStyle.Unlock", comment: "")
                    : NSLocalizedString("TextStyle.Lock", comment: ""),
                tint: textObject.isLocked ? .orange : nil
            ) {
                onAction(.toggleLock)
            }

            // Delete
            handleButton(icon: "trash", label: NSLocalizedString("TextStyle.Delete", comment: ""),
                         tint: .red) {
                onAction(.delete)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    // MARK: - Button Helper

    private func handleButton(
        icon: String,
        label: String,
        isActive: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            selectionFeedback.selectionChanged()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? (isActive ? Color.accentColor : Color.primary))
                .frame(width: 30, height: 30)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - TextStyleEditorView

/// Full typography and appearance editor shown below the handle bar.
struct TextStyleEditorView: View {

    let textObject: TextObject
    var onUpdate: (TextObject) -> Void

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Font ────────────────────────────────────────────────────────
            sectionLabel(NSLocalizedString("TextStyle.Font", comment: ""))
            fontFamilyRow
            fontSizeRow

            Divider()

            // ── Formatting ──────────────────────────────────────────────────
            sectionLabel(NSLocalizedString("TextStyle.Formatting", comment: ""))
            formattingRow

            Divider()

            // ── Alignment ───────────────────────────────────────────────────
            alignmentRow

            Divider()

            // ── Colour ──────────────────────────────────────────────────────
            sectionLabel(NSLocalizedString("TextStyle.Colour", comment: ""))
            textColorRow
            backgroundColorRow
            borderRow

            Divider()

            // ── Shadow & Opacity ────────────────────────────────────────────
            shadowRow
            opacityRow
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .frame(maxWidth: 320)
    }

    // MARK: Font Family

    private var fontFamilyRow: some View {
        HStack(spacing: 6) {
            ForEach(TextFontFamily.allCases) { family in
                let selected = textObject.fontFamily == family
                Button {
                    lightImpact.impactOccurred(intensity: 0.5)
                    var u = textObject; u.fontFamily = family; onUpdate(u)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: family.systemImage)
                            .font(.system(size: 14))
                        Text(family.displayName)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selected ? Color.accentColor.opacity(0.15) : Color(.systemGray6),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Font Size

    private var fontSizeRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("TextStyle.Size", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(textObject.fontSize) },
                    set: { val in
                        var u = textObject; u.fontSize = CGFloat(val); onUpdate(u)
                    }
                ),
                in: 8...72,
                step: 1
            )
            Text("\(Int(textObject.fontSize))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24)
        }
    }

    // MARK: Formatting toggles (Bold / Italic / Underline / Strikethrough)

    private var formattingRow: some View {
        HStack(spacing: 6) {
            formatToggle(icon: "bold",
                         label: NSLocalizedString("TextStyle.Bold", comment: ""),
                         isOn: textObject.isBold) {
                var u = textObject; u.isBold.toggle(); onUpdate(u)
            }
            formatToggle(icon: "italic",
                         label: NSLocalizedString("TextStyle.Italic", comment: ""),
                         isOn: textObject.isItalic) {
                var u = textObject; u.isItalic.toggle(); onUpdate(u)
            }
            formatToggle(icon: "underline",
                         label: NSLocalizedString("TextStyle.Underline", comment: ""),
                         isOn: textObject.isUnderline) {
                var u = textObject; u.isUnderline.toggle(); onUpdate(u)
            }
            formatToggle(icon: "strikethrough",
                         label: NSLocalizedString("TextStyle.Strikethrough", comment: ""),
                         isOn: textObject.isStrikethrough) {
                var u = textObject; u.isStrikethrough.toggle(); onUpdate(u)
            }
        }
    }

    private func formatToggle(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    isOn ? Color.accentColor.opacity(0.15) : Color(.systemGray6),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Alignment

    private var alignmentRow: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("TextStyle.Align", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(TextAlignmentType.allCases) { align in
                let selected = textObject.alignment == align
                Button {
                    var u = textObject; u.alignment = align; onUpdate(u)
                } label: {
                    Image(systemName: align.systemImage)
                        .font(.system(size: 14))
                        .frame(width: 36, height: 30)
                        .background(
                            selected ? Color.accentColor.opacity(0.15) : Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(align.accessibilityLabel)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Text Colour

    private var textColorRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("TextStyle.Colour", comment: ""))
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            TextColorPickerSwatch(
                components: textObject.textColorComponents,
                label: NSLocalizedString("TextStyle.Colour", comment: "")
            ) { newComponents in
                var u = textObject; u.textColorComponents = newComponents; onUpdate(u)
            }
        }
    }

    // MARK: Background Colour

    private var backgroundColorRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("TextStyle.Background", comment: ""))
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if let bg = textObject.backgroundColorComponents {
                TextColorPickerSwatch(components: bg,
                                      label: NSLocalizedString("TextStyle.Background", comment: "")) { c in
                    var u = textObject; u.backgroundColorComponents = c; onUpdate(u)
                }
                Button {
                    var u = textObject; u.backgroundColorComponents = nil; onUpdate(u)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    var u = textObject
                    u.backgroundColorComponents = [1, 1, 1, 0.85]
                    onUpdate(u)
                } label: {
                    Label(NSLocalizedString("TextStyle.Fill", comment: ""), systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: Border

    private var borderRow: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("TextStyle.Border", comment: ""))
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(textObject.borderWidth) },
                    set: { val in
                        var u = textObject
                        u.borderWidth = CGFloat(val)
                        if val > 0 && u.borderColorComponents == nil {
                            u.borderColorComponents = [0.3, 0.3, 0.3, 1]
                        }
                        onUpdate(u)
                    }
                ),
                in: 0...6,
                step: 0.5
            )
            .frame(maxWidth: 80)
            Text(String(format: "%.1f", textObject.borderWidth))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            if let bc = textObject.borderColorComponents {
                TextColorPickerSwatch(components: bc,
                                      label: NSLocalizedString("TextStyle.BorderColour", comment: "")) { c in
                    var u = textObject; u.borderColorComponents = c; onUpdate(u)
                }
            }
        }
    }

    // MARK: Shadow

    private var shadowRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("TextStyle.Shadow", comment: ""))
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(textObject.shadowOpacity) },
                    set: { val in var u = textObject; u.shadowOpacity = Float(val); onUpdate(u) }
                ),
                in: 0...1
            )
            Text(String(format: "%.0f%%", Double(textObject.shadowOpacity) * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32)
        }
    }

    // MARK: Opacity

    private var opacityRow: some View {
        HStack(spacing: 10) {
            Text(NSLocalizedString("TextStyle.Opacity", comment: ""))
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(textObject.opacity) },
                    set: { val in var u = textObject; u.opacity = CGFloat(val); onUpdate(u) }
                ),
                in: 0.05...1
            )
            Text(String(format: "%.0f%%", Double(textObject.opacity) * 100))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32)
        }
    }

    // MARK: Section label helper

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - TextColorPickerSwatch (file-private helper)

private struct TextColorPickerSwatch: View {
    let components: [Double]
    let label: String
    var onChange: ([Double]) -> Void

    private var color: Color {
        guard components.count >= 4 else { return .black }
        return Color(red: components[0], green: components[1],
                     blue: components[2], opacity: components[3])
    }

    var body: some View {
        ColorPicker(
            selection: Binding(
                get: { color },
                set: { newColor in
                    let ui = UIColor(newColor)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                    onChange([Double(r), Double(g), Double(b), Double(a)])
                }
            ),
            supportsOpacity: true
        ) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        }
        .labelsHidden()
        .accessibilityLabel(label)
    }
}
