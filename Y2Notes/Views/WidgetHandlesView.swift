import SwiftUI

// MARK: - Widget Action

/// Actions dispatched from the widget action bar.
enum WidgetAction {
    case duplicate
    case toggleLock
    case delete
}

// MARK: - Widget Handles View

/// Floating action bar that appears above a selected widget.
/// Follows the same pattern as `AttachmentHandlesView` and `ShapeHandlesView`.
struct WidgetHandlesView: View {
    let widget: NoteWidget
    var onAction: (WidgetAction) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            actionButton(
                icon: "plus.square.on.square",
                label: "Copy"
            ) { onAction(.duplicate) }

            actionButton(
                icon: widget.isLocked ? "lock.fill" : "lock.open",
                label: widget.isLocked ? "Unlock" : "Lock"
            ) { onAction(.toggleLock) }

            actionSeparator

            actionButton(
                icon: "trash",
                label: "Delete",
                tint: .red
            ) { onAction(.delete) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(
        icon: String,
        label: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(tint ?? .primary)
            .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
    }

    private var actionSeparator: some View {
        Divider()
            .frame(height: 24)
            .padding(.horizontal, 2)
    }
}
