import SwiftUI

/// SwiftUI view that renders a context menu / action bar for the selected sticker.
/// Displayed above the floating toolbar when a sticker is selected.
///
/// Actions: Bring to Front, Send to Back, Duplicate, Lock/Unlock, Opacity, Delete, Favorite.
struct StickerActionBar: View {
    let sticker: StickerInstance
    let isFavorite: Bool
    var onBringToFront: () -> Void = {}
    var onSendToBack: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onToggleLock: () -> Void = {}
    var onDelete: () -> Void = {}
    var onToggleFavorite: () -> Void = {}
    var onOpacityChanged: (CGFloat) -> Void = { _ in }

    @State private var showOpacitySlider = false

    var body: some View {
        VStack(spacing: 6) {
            if showOpacitySlider {
                opacityControl
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 4) {
                actionButton(icon: "arrow.up.to.line", label: "Front") { onBringToFront() }
                actionButton(icon: "arrow.down.to.line", label: "Back") { onSendToBack() }

                actionSeparator

                actionButton(icon: "plus.square.on.square", label: "Copy") { onDuplicate() }
                actionButton(
                    icon: sticker.isLocked ? "lock.fill" : "lock.open",
                    label: sticker.isLocked ? "Unlock" : "Lock"
                ) { onToggleLock() }

                actionSeparator

                actionButton(
                    icon: showOpacitySlider ? "circle.lefthalf.filled" : "circle.lefthalf.filled",
                    label: "Opacity",
                    isActive: showOpacitySlider
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showOpacitySlider.toggle()
                    }
                }

                actionButton(
                    icon: isFavorite ? "star.fill" : "star",
                    label: "Fav",
                    tint: isFavorite ? .yellow : nil
                ) { onToggleFavorite() }

                actionSeparator

                actionButton(icon: "trash", label: "Delete", tint: .red) { onDelete() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
    }

    // MARK: - Opacity Control

    private var opacityControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(sticker.opacity) },
                    set: { onOpacityChanged(CGFloat($0)) }
                ),
                in: 0.1...1.0,
                step: 0.05
            )
            .frame(width: 140)
            .tint(.accentColor)

            Text("\(Int(sticker.opacity * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(
        icon: String,
        label: String,
        tint: Color? = nil,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .frame(width: 32, height: 32)
                .foregroundStyle(tint ?? (isActive ? Color.accentColor : Color(uiColor: .secondaryLabel)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var actionSeparator: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color(uiColor: .separator).opacity(0.3))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 1)
    }
}
