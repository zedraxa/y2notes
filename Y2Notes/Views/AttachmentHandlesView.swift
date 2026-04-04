import SwiftUI

// MARK: - Attachment Action

/// Actions dispatched from the attachment action bar.
enum AttachmentAction {
    case expand
    case duplicate
    case toggleLock
    case delete
}

// MARK: - Attachment Handles View

/// Floating action bar that appears above a selected attachment.
/// Follows the same pattern as `ShapeHandlesView` and `StickerActionBar`.
struct AttachmentHandlesView: View {
    let attachment: AttachmentObject
    var onAction: (AttachmentAction) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            actionButton(
                icon: "arrow.up.left.and.arrow.down.right",
                label: "Expand"
            ) { onAction(.expand) }

            actionSeparator

            actionButton(
                icon: "plus.square.on.square",
                label: "Copy"
            ) { onAction(.duplicate) }

            actionButton(
                icon: attachment.isLocked ? "lock.fill" : "lock.open",
                label: attachment.isLocked ? "Unlock" : "Lock"
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
