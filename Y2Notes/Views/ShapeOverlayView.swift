import UIKit
import PencilKit

// MARK: - Shape Overlay View

/// Transparent UIView overlay that captures pan gestures when the shape tool is
/// active. Displays a dashed CAShapeLayer preview while the user drags, then
/// converts the finished gesture path into a PKStroke and calls onShapeDrawn.
final class ShapeOverlayView: UIView {
    var shapeType: ShapeType
    var strokeColor: UIColor { didSet { previewLayer.strokeColor = strokeColor.cgColor } }
    var strokeWidth: CGFloat  { didSet { previewLayer.lineWidth  = strokeWidth } }
    private let onShapeDrawn: (PKStroke) -> Void

    private let previewLayer = CAShapeLayer()
    private var startPoint: CGPoint = .zero

    init(
        shapeType: ShapeType,
        strokeColor: UIColor,
        strokeWidth: CGFloat,
        onShapeDrawn: @escaping (PKStroke) -> Void
    ) {
        self.shapeType   = shapeType
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.onShapeDrawn = onShapeDrawn
        super.init(frame: .zero)

        backgroundColor = .clear
        isOpaque = false

        previewLayer.fillColor      = UIColor.clear.cgColor
        previewLayer.strokeColor    = strokeColor.cgColor
        previewLayer.lineWidth      = strokeWidth
        previewLayer.lineDashPattern = [6, 4]
        previewLayer.isHidden       = true
        layer.addSublayer(previewLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            startPoint = point
            previewLayer.isHidden = false
        case .changed:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.path = makeBezierPath(from: startPoint, to: point).cgPath
            CATransaction.commit()
        case .ended:
            previewLayer.isHidden = true
            previewLayer.path     = nil
            onShapeDrawn(makeStroke(from: startPoint, to: point))
        default:
            previewLayer.isHidden = true
            previewLayer.path     = nil
        }
    }

    // MARK: Path Construction

    private func makeBezierPath(from: CGPoint, to: CGPoint) -> UIBezierPath {
        switch shapeType {
        case .line:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            return p
        case .rectangle:
            return UIBezierPath(rect: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .circle:
            return UIBezierPath(ovalIn: CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ))
        case .arrow:
            let p = UIBezierPath(); p.move(to: from); p.addLine(to: to)
            let angle   = atan2(to.y - from.y, to.x - from.x)
            let headLen = min(24, hypot(to.x - from.x, to.y - from.y) * 0.25)
            let left  = CGPoint(x: to.x - headLen * cos(angle - .pi / 6),
                                y: to.y - headLen * sin(angle - .pi / 6))
            let right = CGPoint(x: to.x - headLen * cos(angle + .pi / 6),
                                y: to.y - headLen * sin(angle + .pi / 6))
            p.move(to: to); p.addLine(to: left)
            p.move(to: to); p.addLine(to: right)
            return p
        }
    }

    // MARK: Stroke Construction

    private func makeStroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let ink    = PKInk(.pen, color: strokeColor)
        let points = samplePath(makeBezierPath(from: from, to: to), spacing: 3)

        // Ensure at least two points so PencilKit renders a visible stroke.
        let resolved = points.count >= 2 ? points : [from, to]

        let pkPoints = resolved.enumerated().map { i, pt in
            PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(i) * 0.005,
                size: CGSize(width: strokeWidth, height: strokeWidth),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let pkPath = PKStrokePath(controlPoints: pkPoints, creationDate: Date())
        return PKStroke(ink: ink, path: pkPath, transform: .identity, mask: nil)
    }

    /// Densely samples a UIBezierPath into evenly-spaced CGPoints.
    private func samplePath(_ bezier: UIBezierPath, spacing: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        var prev: CGPoint = .zero

        bezier.cgPath.applyWithBlock { (ptr: UnsafePointer<CGPathElement>) in
            let el = ptr.pointee
            switch el.type {
            case .moveToPoint:
                prev = el.points[0]; result.append(prev)

            case .addLineToPoint:
                let end = el.points[0]
                linearSample(from: prev, to: end, spacing: spacing, into: &result)
                prev = end

            case .addQuadCurveToPoint:
                let ctrl = el.points[0]; let end = el.points[1]
                let steps = max(4, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t: CGFloat = CGFloat(i) / CGFloat(steps)
                    let mt: CGFloat = 1 - t
                    let px: CGFloat = mt*mt*prev.x + 2*mt*t*ctrl.x + t*t*end.x
                    let py: CGFloat = mt*mt*prev.y + 2*mt*t*ctrl.y + t*t*end.y
                    result.append(CGPoint(x: px, y: py))
                }; prev = end

            case .addCurveToPoint:
                let c1 = el.points[0]; let c2 = el.points[1]; let end = el.points[2]
                let steps = max(8, Int(hypot(end.x - prev.x, end.y - prev.y) / spacing))
                for i in 1...steps {
                    let t: CGFloat = CGFloat(i) / CGFloat(steps); let mt: CGFloat = 1 - t
                    let px: CGFloat = mt*mt*mt*prev.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x
                    let py: CGFloat = mt*mt*mt*prev.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
                    result.append(CGPoint(x: px, y: py))
                }; prev = end

            case .closeSubpath:
                if let first = result.first {
                    linearSample(from: prev, to: first, spacing: spacing, into: &result)
                    prev = first
                }

            @unknown default: break
            }
        }
        return result
    }

    private func linearSample(from: CGPoint, to: CGPoint, spacing: CGFloat, into result: inout [CGPoint]) {
        let dist  = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(dist / spacing))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            result.append(CGPoint(
                x: from.x + t * (to.x - from.x),
                y: from.y + t * (to.y - from.y)
            ))
        }
    }
}
