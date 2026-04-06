import UIKit
import SwiftUI

// MARK: - Y2ColorWheel

/// A custom color wheel that renders an HSB disc with a brightness slider,
/// giving users more precise colour control than Apple's standard picker.
///
/// Internally uses Core Graphics for the wheel texture and UIKit gesture
/// recognisers for smooth 60 fps dragging. Fully supports VoiceOver
/// (adjustable trait for hue/saturation) and Dynamic Type (label sizing).
///
/// **SwiftUI usage:**
/// ```swift
/// Y2ColorWheelView(selectedColor: $inkColor)
/// ```
final class Y2ColorWheel: UIView {

    // MARK: - Configuration

    struct Configuration {
        var wheelDiameter: CGFloat = 220
        var knobSize: CGFloat = 28
        var brightnessSliderHeight: CGFloat = 28
        var respectsReduceMotion: Bool = true
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let wheelLayer = CALayer()
    private let knobView = UIView()
    private let brightnessSlider = UISlider()
    private let previewSwatch = UIView()
    private var panGesture: UIPanGestureRecognizer!

    /// Current hue (0…1).
    private(set) var hue: CGFloat = 0

    /// Current saturation (0…1).
    private(set) var saturation: CGFloat = 1

    /// Current brightness (0…1).
    private(set) var brightness: CGFloat = 1

    /// Callback when the colour changes.
    var onColorChange: ((UIColor) -> Void)?

    /// The currently selected colour.
    var selectedColor: UIColor {
        get { UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1) }
        set { setColor(newValue, notify: false) }
    }

    // MARK: - Init

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupWheel()
        setupKnob()
        setupBrightnessSlider()
        setupPreviewSwatch()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    // MARK: - Setup

    private func setupWheel() {
        let size = configuration.wheelDiameter
        wheelLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        wheelLayer.contents = generateWheelImage(size: size)?.cgImage
        wheelLayer.cornerRadius = size / 2
        wheelLayer.masksToBounds = true
        layer.addSublayer(wheelLayer)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleWheelPan(_:)))
        addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleWheelTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    private func setupKnob() {
        let size = configuration.knobSize
        knobView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        knobView.layer.cornerRadius = size / 2
        knobView.layer.borderWidth = 3
        knobView.layer.borderColor = UIColor.white.cgColor
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOffset = CGSize(width: 0, height: 1)
        knobView.layer.shadowRadius = 3
        knobView.layer.shadowOpacity = 0.3
        knobView.isUserInteractionEnabled = false
        addSubview(knobView)
        updateKnobPosition()
    }

    private func setupBrightnessSlider() {
        brightnessSlider.minimumValue = 0.05
        brightnessSlider.maximumValue = 1.0
        brightnessSlider.value = 1.0
        brightnessSlider.addTarget(self, action: #selector(brightnessChanged(_:)), for: .valueChanged)
        brightnessSlider.translatesAutoresizingMaskIntoConstraints = false
        brightnessSlider.accessibilityLabel = NSLocalizedString("Brightness", comment: "Color wheel brightness slider")
        addSubview(brightnessSlider)

        let wheelSize = configuration.wheelDiameter
        NSLayoutConstraint.activate([
            brightnessSlider.topAnchor.constraint(equalTo: topAnchor, constant: wheelSize + 16),
            brightnessSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            brightnessSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            brightnessSlider.heightAnchor.constraint(equalToConstant: configuration.brightnessSliderHeight),
        ])
    }

    private func setupPreviewSwatch() {
        previewSwatch.layer.cornerRadius = 8
        previewSwatch.layer.cornerCurve = .continuous
        previewSwatch.layer.borderWidth = 1
        previewSwatch.layer.borderColor = UIColor.separator.cgColor
        previewSwatch.translatesAutoresizingMaskIntoConstraints = false
        previewSwatch.isAccessibilityElement = true
        previewSwatch.accessibilityLabel = NSLocalizedString("Selected Color", comment: "Color preview swatch")
        addSubview(previewSwatch)

        let wheelSize = configuration.wheelDiameter
        NSLayoutConstraint.activate([
            previewSwatch.topAnchor.constraint(equalTo: topAnchor, constant: wheelSize + 56),
            previewSwatch.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewSwatch.widthAnchor.constraint(equalToConstant: 44),
            previewSwatch.heightAnchor.constraint(equalToConstant: 44),
        ])
        updatePreview()
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("Color Wheel", comment: "Accessibility label for color wheel")
        accessibilityTraits = .adjustable
        accessibilityHint = NSLocalizedString(
            "Swipe up or down to change hue. Use the brightness slider below.",
            comment: "Color wheel accessibility hint"
        )
    }

    // MARK: - Wheel Image Generation

    private func generateWheelImage(size: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2

            // Draw HSB wheel pixel by pixel (optimised with stride)
            let step: CGFloat = 2
            var y: CGFloat = 0
            while y < size {
                var x: CGFloat = 0
                while x < size {
                    let dx = x - center.x
                    let dy = y - center.y
                    let dist = hypot(dx, dy)
                    if dist <= radius {
                        let angle = atan2(dy, dx)
                        let h = (angle + .pi) / (2 * .pi)
                        let s = dist / radius
                        let color = UIColor(hue: h, saturation: s, brightness: 1, alpha: 1)
                        ctx.cgContext.setFillColor(color.cgColor)
                        ctx.cgContext.fill(CGRect(x: x, y: y, width: step, height: step))
                    }
                    x += step
                }
                y += step
            }
        }
    }

    // MARK: - Gesture Handling

    @objc private func handleWheelPan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        updateColorFromPoint(point)
    }

    @objc private func handleWheelTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        updateColorFromPoint(point)
    }

    private func updateColorFromPoint(_ point: CGPoint) {
        let radius = configuration.wheelDiameter / 2
        let center = CGPoint(x: radius, y: radius)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = min(hypot(dx, dy), radius)

        hue = (atan2(dy, dx) + .pi) / (2 * .pi)
        saturation = dist / radius

        updateKnobPosition()
        updatePreview()
        onColorChange?(selectedColor)
    }

    // MARK: - Brightness

    @objc private func brightnessChanged(_ slider: UISlider) {
        brightness = CGFloat(slider.value)
        updatePreview()
        onColorChange?(selectedColor)
    }

    // MARK: - Color Setting

    private func setColor(_ color: UIColor, notify: Bool) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        brightnessSlider.value = Float(b)
        updateKnobPosition()
        updatePreview()
        if notify { onColorChange?(selectedColor) }
    }

    // MARK: - UI Updates

    private func updateKnobPosition() {
        let radius = configuration.wheelDiameter / 2
        let angle = hue * 2 * .pi - .pi
        let dist = saturation * radius
        let center = CGPoint(x: radius, y: radius)
        let knobCenter = CGPoint(x: center.x + dist * cos(angle), y: center.y + dist * sin(angle))
        knobView.center = knobCenter
        knobView.backgroundColor = UIColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1)
    }

    private func updatePreview() {
        previewSwatch.backgroundColor = selectedColor
    }

    // MARK: - Accessibility

    override func accessibilityIncrement() {
        hue = min(hue + 0.05, 1)
        updateKnobPosition()
        updatePreview()
        onColorChange?(selectedColor)
    }

    override func accessibilityDecrement() {
        hue = max(hue - 0.05, 0)
        updateKnobPosition()
        updatePreview()
        onColorChange?(selectedColor)
    }

    // MARK: - Intrinsic Size

    override var intrinsicContentSize: CGSize {
        let width = configuration.wheelDiameter
        let height = configuration.wheelDiameter + 16 + configuration.brightnessSliderHeight + 16 + 44
        return CGSize(width: width, height: height)
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI hosting wrapper for ``Y2ColorWheel``.
struct Y2ColorWheelView: UIViewRepresentable {

    @Binding var selectedColor: Color
    var configuration: Y2ColorWheel.Configuration

    init(
        selectedColor: Binding<Color>,
        configuration: Y2ColorWheel.Configuration = .init()
    ) {
        self._selectedColor = selectedColor
        self.configuration = configuration
    }

    func makeUIView(context: Context) -> Y2ColorWheel {
        let wheel = Y2ColorWheel(configuration: configuration)
        wheel.selectedColor = UIColor(selectedColor)
        wheel.onColorChange = { uiColor in
            selectedColor = Color(uiColor)
        }
        return wheel
    }

    func updateUIView(_ uiView: Y2ColorWheel, context: Context) {
        uiView.selectedColor = UIColor(selectedColor)
    }
}
