import SwiftUI

/// Selection-mode toolbar variant that replaces Tier 1 when the user has
/// an active lasso selection on the canvas.
///
/// Shows contextual actions: Cut, Copy, Duplicate, Delete, Recolor.
/// Tapping "Recolor" expands an inline colour strip (same Tier 2 pattern).
/// All other buttons fire immediately and deselect, returning the toolbar
/// to its standard state.
struct SelectionToolbar: View {
    @ObservedObject var toolStore: DrawingToolStore
    var onAction: (SelectionAction) -> Void

    @State private var showRecolorStrip = false

    // MARK: - Color Binding

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: toolStore.activeColor) },
            set: { newColor in
                let uiColor = UIColor(newColor)
                toolStore.activeColor = uiColor
                toolStore.addRecentColor(uiColor)
                onAction(.recolor(uiColor))
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Recolor strip (Tier 2 expansion above selection capsule)
            if showRecolorStrip {
                recolorExpansion
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Selection action capsule
            selectionCapsule
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showRecolorStrip)
    }

    // MARK: - Selection Capsule

    @ViewBuilder
    private var selectionCapsule: some View {
        HStack(spacing: 6) {
            actionButton("scissors", label: "Cut") { onAction(.cut) }
            actionButton("doc.on.doc", label: "Copy") { onAction(.copy) }
            actionButton("plus.square.on.square", label: "Duplicate") { onAction(.duplicate) }
            actionButton("trash", label: "Delete") { onAction(.delete) }

            selectionSeparator

            // Recolor — toggles the inline colour strip
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showRecolorStrip.toggle()
                }
            } label: {
                Image(systemName: "paintbrush")
                    .font(.system(size: 14, weight: showRecolorStrip ? .semibold : .regular))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(showRecolorStrip ? Color.accentColor : Color(uiColor: .secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recolor selection")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Recolor Expansion

    @ViewBuilder
    private var recolorExpansion: some View {
        HStack(spacing: 6) {
            ForEach(Array(toolStore.recentColors.prefix(6).enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(Color(uiColor: color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: isSameColor(color, toolStore.activeColor) ? 2 : 0)
                    )
                    .onTapGesture {
                        onAction(.recolor(color))
                    }
            }

            Spacer(minLength: 4)

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 280)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color(uiColor: .label))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var selectionSeparator: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color(uiColor: .separator).opacity(0.3))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }

    private func isSameColor(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        b.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return abs(ar - br) < 0.02 && abs(ag - bg) < 0.02 && abs(ab - bb) < 0.02
    }
}

// MARK: - Selection Action

/// Actions available when strokes are selected on the canvas.
enum SelectionAction {
    case cut
    case copy
    case duplicate
    case delete
    case recolor(UIColor)
}
