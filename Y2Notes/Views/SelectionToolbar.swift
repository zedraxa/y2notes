import SwiftUI

/// Selection-mode toolbar variant that replaces Tier 1 when the user has
/// an active lasso selection on the canvas.
///
/// Shows contextual actions: Cut, Copy, Duplicate, Delete.
/// All buttons fire immediately and deselect, returning the toolbar
/// to its standard state.
struct SelectionToolbar: View {
    @ObservedObject var toolStore: DrawingToolStore
    var onAction: (SelectionAction) -> Void

    private let actionImpact = UIImpactFeedbackGenerator(style: .medium)
    private let destructiveImpact = UINotificationFeedbackGenerator()

    // MARK: - Body

    var body: some View {
        selectionCapsule
    }

    // MARK: - Selection Capsule

    @ViewBuilder
    private var selectionCapsule: some View {
        HStack(spacing: 6) {
            actionButton("scissors", label: "Cut") { fireAction(.cut) }
            actionButton("doc.on.doc", label: "Copy") { fireAction(.copy) }
            actionButton("plus.square.on.square", label: "Duplicate") { fireAction(.duplicate) }
            actionButton("trash", label: "Delete") { fireAction(.delete) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func fireAction(_ action: SelectionAction) {
        if action == .delete {
            destructiveImpact.notificationOccurred(.warning)
        } else {
            actionImpact.impactOccurred()
        }
        onAction(action)
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color(uiColor: .label))
        }
        .buttonStyle(SelectionActionButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Selection Action Button Style

/// Press-scale style for selection toolbar buttons.
private struct SelectionActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Selection Action

/// Actions available when strokes are selected on the canvas.
enum SelectionAction {
    case cut
    case copy
    case duplicate
    case delete
}
