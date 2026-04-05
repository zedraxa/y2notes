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

    // MARK: - Body

    var body: some View {
        selectionCapsule
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: - Selection Capsule

    @ViewBuilder
    private var selectionCapsule: some View {
        HStack(spacing: 6) {
            actionButton("scissors", label: "Cut", hint: "Cut selected strokes to clipboard") { onAction(.cut) }
            actionButton("doc.on.doc", label: "Copy", hint: "Copy selected strokes to clipboard") { onAction(.copy) }
            actionButton("plus.square.on.square", label: "Duplicate", hint: "Duplicate selected strokes in place") { onAction(.duplicate) }
            actionButton("trash", label: "Delete", hint: "Delete selected strokes") { onAction(.delete) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(Color(uiColor: .label))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
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
