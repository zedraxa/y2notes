import UIKit
import PencilKit

// MARK: - ContextualPencilPaletteView

/// A compact floating tool palette that appears near the Apple Pencil tip when the
/// user's preferred double-tap / squeeze action is "Show Color Palette."
///
/// The palette offers one-tap access to the five core PencilKit inking tools and a
/// row of quick-pick colors drawn from the active PKToolPicker.  It anchors itself
/// to the last known Pencil position in the window, staying fully on-screen.
///
/// Dismiss by selecting any item, tapping outside the palette, or calling `dismiss()`.
final class ContextualPencilPaletteView: UIView {

    // MARK: - Constants

    private enum Layout {
        static let paletteWidth:   CGFloat = 288
        static let paletteHeight:  CGFloat = 108
        static let cornerRadius:   CGFloat = 16
        static let buttonSize:     CGFloat = 44
        static let colorSwatchSize: CGFloat = 28
        static let anchorArrowHeight: CGFloat = 8
        static let edgePadding:    CGFloat = 12
    }

    // MARK: - Public factory

    /// Present (or reposition) the contextual palette anchored near `anchorPoint`
    /// inside `window`.
    ///
    /// - Parameters:
    ///   - anchorPoint: Pencil tip position in window coordinates.
    ///   - window:      The window to host the palette in.
    ///   - canvas:      The active `PKCanvasView` that will receive tool changes.
    ///   - colors:      Quick-pick colors to display (at most 6 are shown).
    static func show(
        at anchorPoint: CGPoint,
        in window: UIWindow,
        canvas: PKCanvasView,
        colors: [UIColor] = ContextualPencilPaletteView.defaultColors
    ) {
        // Dismiss any existing palette.
        existing(in: window)?.dismiss()

        let palette = ContextualPencilPaletteView(
            anchorPoint: anchorPoint,
            window: window,
            canvas: canvas,
            colors: colors
        )
        window.addSubview(palette)
        palette.animateIn()
    }

    /// Dismiss and remove the currently visible palette in `window`, if any.
    static func dismissExisting(in window: UIWindow) {
        existing(in: window)?.dismiss()
    }

    // MARK: - Init

    private weak var canvas: PKCanvasView?
    private var dismissTapGesture: UITapGestureRecognizer?
    private var backgroundTapView: UIView?   // full-screen invisible tap-to-dismiss

    private init(
        anchorPoint: CGPoint,
        window: UIWindow,
        canvas: PKCanvasView,
        colors: [UIColor]
    ) {
        self.canvas = canvas
        super.init(frame: .zero)

        setupBackground(in: window)
        setupAppearance()
        buildContent(colors: colors)
        layoutPalette(anchorPoint: anchorPoint, in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Setup

    private func setupBackground(in window: UIWindow?) {
        guard let window = window else { return }
        let tapDismiss = UIView(frame: window.bounds)
        tapDismiss.backgroundColor = .clear
        tapDismiss.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        tapDismiss.addGestureRecognizer(tap)
        window.insertSubview(tapDismiss, belowSubview: self)
        self.backgroundTapView = tapDismiss
    }

    private func setupAppearance() {
        backgroundColor       = .clear
        layer.shadowColor     = UIColor.black.cgColor
        layer.shadowOpacity   = 0.18
        layer.shadowRadius    = 12
        layer.shadowOffset    = CGSize(width: 0, height: 4)
    }

    private func buildContent(colors: [UIColor]) {
        // Pill-shaped card
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        card.layer.cornerRadius = Layout.cornerRadius
        card.layer.masksToBounds = true
        card.frame = CGRect(x: 0, y: Layout.anchorArrowHeight,
                            width: Layout.paletteWidth, height: Layout.paletteHeight)
        addSubview(card)

        let stack = UIStackView()
        stack.axis      = .vertical
        stack.spacing   = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
        ])

        stack.addArrangedSubview(buildToolRow())
        stack.addArrangedSubview(buildColorRow(colors: colors))
    }

    // MARK: - Tool row

    private func buildToolRow() -> UIStackView {
        let row = UIStackView()
        row.axis       = .horizontal
        row.spacing    = 4
        row.distribution = .equalSpacing
        row.alignment  = .center

        let tools: [(PKInkingTool.InkType, String, Bool)] = [
            (.pen,     "pencil.tip",       false),
            (.pencil,  "pencil",           false),
            (.marker,  "highlighter",      false),
        ]

        // Additional tools available in iOS 17.5 (PencilKit Pro / Pencil Pro).
        var allTools: [(PKInkingTool.InkType, String, Bool)] = tools
        if #available(iOS 17.5, *) {
            allTools.append(contentsOf: [
                (.fountainPen, "paintbrush.pointed", false),
                (.monoline,    "minus",              false),
            ])
        }

        for (inkType, icon, _) in allTools {
            let button = makeToolButton(systemImage: icon) { [weak self] in
                self?.selectInkTool(inkType)
            }
            row.addArrangedSubview(button)
        }

        // Eraser
        let eraserBtn = makeToolButton(systemImage: "eraser") { [weak self] in
            self?.selectEraser()
        }
        row.addArrangedSubview(eraserBtn)

        return row
    }

    private func makeToolButton(systemImage: String, action: @escaping () -> Void) -> UIButton {
        let config = UIButton.Configuration.plain()
        var c = config
        c.image          = UIImage(systemName: systemImage)
        c.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18)
        let button = UIButton(configuration: c, primaryAction: UIAction { _ in action() })
        button.widthAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: Layout.buttonSize).isActive = true
        button.tintColor = .label
        return button
    }

    // MARK: - Color row

    private func buildColorRow(colors: [UIColor]) -> UIStackView {
        let row = UIStackView()
        row.axis       = .horizontal
        row.spacing    = 8
        row.distribution = .equalSpacing
        row.alignment  = .center

        let sliceCount = min(colors.count, 6)
        for color in colors.prefix(sliceCount) {
            let swatch = makeColorSwatch(color: color)
            row.addArrangedSubview(swatch)
        }
        return row
    }

    private func makeColorSwatch(color: UIColor) -> UIView {
        let container = UIView()
        container.widthAnchor.constraint(equalToConstant: Layout.colorSwatchSize).isActive = true
        container.heightAnchor.constraint(equalToConstant: Layout.colorSwatchSize).isActive = true

        let circle = UIView(frame: CGRect(x: 0, y: 0, width: Layout.colorSwatchSize, height: Layout.colorSwatchSize))
        circle.backgroundColor    = color
        circle.layer.cornerRadius = Layout.colorSwatchSize / 2
        circle.layer.borderWidth  = 1
        circle.layer.borderColor  = UIColor.separator.cgColor
        circle.autoresizingMask   = [.flexibleWidth, .flexibleHeight]
        container.addSubview(circle)

        container.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(handleColorTap(_:))
            )
        )
        container.tag = colorTag(for: color)
        container.isUserInteractionEnabled = true
        return container
    }

    // MARK: - Positioning

    private func layoutPalette(anchorPoint: CGPoint, in window: UIWindow?) {
        guard let window = window else { return }
        let totalHeight = Layout.paletteHeight + Layout.anchorArrowHeight
        let paletteWidth = Layout.paletteWidth

        // Default: palette appears above the Pencil tip.
        var originX = anchorPoint.x - paletteWidth / 2
        var originY = anchorPoint.y - totalHeight - 8

        // Clamp horizontally within the window.
        originX = max(Layout.edgePadding, min(originX, window.bounds.width - paletteWidth - Layout.edgePadding))

        // If the palette would be clipped at the top, flip below.
        if originY < Layout.edgePadding {
            originY = anchorPoint.y + 8
        }

        frame = CGRect(x: originX, y: originY, width: paletteWidth, height: totalHeight)
    }

    // MARK: - Animations

    private func animateIn() {
        alpha     = 0
        transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.72,
                       initialSpringVelocity: 0.4) {
            self.alpha     = 1
            self.transform = .identity
        }
    }

    @objc func dismiss() {
        backgroundTapView?.removeFromSuperview()
        UIView.animate(withDuration: 0.16) {
            self.alpha     = 0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    // MARK: - Tool Actions

    private func selectInkTool(_ inkType: PKInkingTool.InkType) {
        guard let canvas = canvas else { dismiss(); return }
        let currentColor: UIColor
        if let existing = canvas.tool as? PKInkingTool {
            currentColor = existing.color
        } else {
            currentColor = .label
        }
        canvas.tool = PKInkingTool(inkType, color: currentColor, width: 2)
        dismiss()
    }

    private func selectEraser() {
        guard let canvas = canvas else { dismiss(); return }
        canvas.tool = PKEraserTool(.vector)
        dismiss()
    }

    @objc private func handleColorTap(_ gesture: UITapGestureRecognizer) {
        guard let canvas = canvas,
              let inkTool = canvas.tool as? PKInkingTool else {
            dismiss()
            return
        }
        let tag   = gesture.view?.tag ?? 0
        let color = resolvedColor(forTag: tag)
        canvas.tool = PKInkingTool(inkTool.inkType, color: color, width: inkTool.width)
        dismiss()
    }

    // MARK: - Color Lookup

    /// Simple tag-based lookup: store ARGB as Int.
    private func colorTag(for color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255) & 0xFF
        let gi = Int(g * 255) & 0xFF
        let bi = Int(b * 255) & 0xFF
        return (ri << 16) | (gi << 8) | bi
    }

    private func resolvedColor(forTag tag: Int) -> UIColor {
        let r = CGFloat((tag >> 16) & 0xFF) / 255
        let g = CGFloat((tag >> 8)  & 0xFF) / 255
        let b = CGFloat( tag        & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - Helpers

    private static func existing(in window: UIWindow) -> ContextualPencilPaletteView? {
        window.subviews.compactMap { $0 as? ContextualPencilPaletteView }.last
    }

    // MARK: - Default colors

    static let defaultColors: [UIColor] = [
        .black,
        .white,
        .systemBlue,
        .systemRed,
        .systemGreen,
        UIColor(red: 1.0, green: 0.84, blue: 0, alpha: 1),  // yellow
    ]
}

// MARK: - UIApplication key-window helper

private extension UIApplication {
    /// Retrieve the active key window without relying on the deprecated `.keyWindow` property.
    static var keyWindowIfAvailable: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
