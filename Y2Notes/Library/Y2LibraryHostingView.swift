import SwiftUI

// MARK: - Y2LibraryHostingView

/// Thin `UIViewControllerRepresentable` that embeds `Y2LibraryViewController`
/// in a SwiftUI view hierarchy.
///
/// This wrapper is intentionally minimal — all library logic lives in the
/// UIKit controller.  The hosting view bridges SwiftUI environment into the
/// controller and forwards delegate callbacks.
struct Y2LibraryHostingView: UIViewControllerRepresentable {

    /// Display models for the notebook grid.
    let notebooks: [NotebookDisplayItem]

    /// Theme colors from the current theme.
    let textColor: UIColor
    let accentColor: UIColor

    /// Callbacks forwarded to the parent SwiftUI view.
    var onSelectNotebook: ((UUID) -> Void)?
    var onNewNotebook: (() -> Void)?
    var onToggleFavorite: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSidebarChange: ((Y2SidebarItem.Kind) -> Void)?

    func makeUIViewController(context: Context) -> Y2LibraryViewController {
        let vc = Y2LibraryViewController()
        vc.libraryDelegate = context.coordinator
        vc.setNotebooks(notebooks)
        vc.applyTheme(textColor: textColor, accentColor: accentColor)
        return vc
    }

    func updateUIViewController(_ vc: Y2LibraryViewController, context: Context) {
        vc.setNotebooks(notebooks)
        vc.applyTheme(textColor: textColor, accentColor: accentColor)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, Y2LibraryDelegate {
        let parent: Y2LibraryHostingView
        init(parent: Y2LibraryHostingView) { self.parent = parent }

        func libraryDidSelectNotebook(id: UUID) { parent.onSelectNotebook?(id) }
        func libraryDidRequestNewNotebook() { parent.onNewNotebook?() }
        func libraryDidToggleFavorite(notebookID: UUID) { parent.onToggleFavorite?(notebookID) }
        func libraryDidRequestDelete(notebookID: UUID) { parent.onDelete?(notebookID) }
        func libraryDidChangeSidebarSection(_ section: Y2SidebarItem.Kind) { parent.onSidebarChange?(section) }
    }
}
