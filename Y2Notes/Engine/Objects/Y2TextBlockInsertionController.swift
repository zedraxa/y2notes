import UIKit

// MARK: - Y2TextBlockInsertionDelegate

/// Delegate protocol for receiving a newly created text block wrapper.
protocol Y2TextBlockInsertionDelegate: AnyObject {
    /// Called when the user confirms the text-block creation.
    ///
    /// - Parameter wrapper: A fully configured `CanvasObjectWrapper` with
    ///   a `.textBlock` payload ready to be inserted into the object layer.
    func textBlockInsertionController(
        _ controller: Y2TextBlockInsertionController,
        didPrepare wrapper: CanvasObjectWrapper
    )
}

// MARK: - Y2TextBlockInsertionController

/// Presents a compact alert that lets the user type text and choose basic
/// formatting options, then delivers a ready-to-insert `CanvasObjectWrapper`
/// via its delegate.
///
/// ## Usage
/// ```swift
/// let ctrl = Y2TextBlockInsertionController()
/// ctrl.delegate = self
/// ctrl.present(from: self, insertionPoint: tapLocation)
/// ```
///
/// ## Design
/// Uses a `UIAlertController` with a text field for simplicity.
/// A future iteration may replace this with a richer inline editing sheet.
final class Y2TextBlockInsertionController {

    // MARK: - Properties

    weak var delegate: Y2TextBlockInsertionDelegate?

    /// Default font size for newly created text blocks.
    var defaultFontSize: CGFloat = 18

    /// Default text colour hex for newly created text blocks.
    var defaultTextColorHex: String = "#1A1A1A"

    // MARK: - Presentation

    /// Show the text-block creation dialog.
    ///
    /// - Parameters:
    ///   - presenter: The view controller that will present the alert.
    ///   - insertionPoint: The centre point in page content coordinates where
    ///     the text block should be placed.
    func present(from presenter: UIViewController, insertionPoint: CGPoint) {
        let alert = UIAlertController(
            title: "Add Text",
            message: nil,
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "Type your text…"
            textField.autocapitalizationType = .sentences
            textField.returnKeyType = .done
        }

        let insertAction = UIAlertAction(title: "Insert", style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let textBlock = self.makeTextBlockObject(text: text)
            let wrapper = CanvasObjectWrapper.makeTextBlock(textBlock, centeredAt: insertionPoint)
            self.delegate?.textBlockInsertionController(self, didPrepare: wrapper)
        }

        alert.addAction(insertAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.preferredAction = insertAction

        presenter.present(alert, animated: true)
    }

    // MARK: - Factory

    private func makeTextBlockObject(text: String) -> TextBlockObject {
        TextBlockObject(
            text: text,
            fontData: nil,
            fontSize: defaultFontSize,
            textColorHex: defaultTextColorHex,
            backgroundColorHex: nil,
            isBold: false,
            isItalic: false,
            alignment: NSTextAlignment.natural.rawValue
        )
    }
}
