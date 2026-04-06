import UIKit

// MARK: - Y2TextBlockViewDelegate

/// Callbacks from the text-block view to its owner (the overlay controller).
protocol Y2TextBlockViewDelegate: AnyObject {
    /// The user committed new text.  The owner should update the
    /// `TextBlockObject` in the corresponding `CanvasObjectWrapper`.
    func textBlockView(_ view: Y2TextBlockView, didCommitText text: String)
}

// MARK: - Y2TextBlockView

/// A `UIView` that displays an editable text block on the canvas.
///
/// In **display mode** (default) the view shows a non-editable `UILabel`.
/// Double-tapping switches to **edit mode** where an embedded `UITextView`
/// becomes first responder so the user can type.  Tapping outside or pressing
/// Return on an external keyboard commits the edit.
final class Y2TextBlockView: UIView {

    // MARK: - Subviews

    private let label = UILabel()
    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isHidden = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        tv.isScrollEnabled = false
        tv.delegate = self
        tv.returnKeyType = .default
        return tv
    }()

    // MARK: - State

    private(set) var textBlockObject: TextBlockObject
    private(set) var isEditing = false

    /// Delegate receives committed text updates.
    weak var textBlockDelegate: Y2TextBlockViewDelegate?

    // MARK: - Init

    init(textBlock: TextBlockObject) {
        self.textBlockObject = textBlock
        super.init(frame: .zero)
        setupView()
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupView() {
        clipsToBounds = true
        layer.cornerRadius = 4

        // Label (display mode)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Text view (edit mode) — laid out identically
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        for v in [label, textView] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            ])
        }

        // Double-tap enters edit mode.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        isAccessibilityElement = true
        accessibilityTraits = [.staticText]
    }

    // MARK: - Style application

    private func applyStyle() {
        let tb = textBlockObject
        let baseFont: UIFont
        if let data = tb.fontData,
           let descriptor = try? NSKeyedUnarchiver.unarchivedObject(
               ofClass: UIFontDescriptor.self, from: data) {
            baseFont = UIFont(descriptor: descriptor, size: tb.fontSize)
        } else {
            baseFont = UIFont.systemFont(ofSize: tb.fontSize)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if tb.isBold   { traits.insert(.traitBold) }
        if tb.isItalic  { traits.insert(.traitItalic) }

        let font: UIFont
        if let styledDescriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: styledDescriptor, size: tb.fontSize)
        } else {
            font = baseFont
        }

        let textColor = UIColor(hexString: tb.textColorHex) ?? .label
        let bgColor = tb.backgroundColorHex.flatMap { UIColor(hexString: $0) } ?? .clear
        let alignment = NSTextAlignment(rawValue: tb.alignment) ?? .natural

        // Label
        label.text = tb.text
        label.font = font
        label.textColor = textColor
        label.textAlignment = alignment

        // Text view
        textView.text = tb.text
        textView.font = font
        textView.textColor = textColor
        textView.textAlignment = alignment

        backgroundColor = bgColor

        accessibilityLabel = tb.text.isEmpty ? "Empty text block" : tb.text
    }

    // MARK: - Update

    /// Replace the backing `TextBlockObject` and refresh visuals.
    func update(textBlock: TextBlockObject) {
        self.textBlockObject = textBlock
        applyStyle()
    }

    // MARK: - Edit mode

    @objc private func handleDoubleTap() {
        beginEditing()
    }

    /// Transition to edit mode — shows the text view and hides the label.
    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        label.isHidden = true
        textView.isHidden = false
        textView.text = textBlockObject.text
        textView.becomeFirstResponder()
    }

    /// Commit and exit edit mode.
    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        let newText = textView.text ?? ""
        textView.resignFirstResponder()
        textView.isHidden = true
        label.isHidden = false

        if newText != textBlockObject.text {
            textBlockObject.text = newText
            label.text = newText
            accessibilityLabel = newText.isEmpty ? "Empty text block" : newText
            textBlockDelegate?.textBlockView(self, didCommitText: newText)
        }
    }
}

// MARK: - UITextViewDelegate

extension Y2TextBlockView: UITextViewDelegate {

    func textViewDidEndEditing(_ textView: UITextView) {
        endEditing()
    }
}

// MARK: - UIColor hex helper (private)

private extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
