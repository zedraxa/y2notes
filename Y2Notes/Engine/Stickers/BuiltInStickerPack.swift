import UIKit

// MARK: - BuiltInStickerPack

/// Core Graphics–rendered sticker pack bundled with Y2Notes.
///
/// All stickers are vector-like and resolution-independent.  They are
/// rendered on demand into a `UIImage` at whatever size is requested.
///
/// ## Categories
/// - **Academic**: arrows, brackets, checkmarks, stars, bullets, dividers
/// - **Shapes**: geometric shapes, speech bubbles, banners, frames
/// - **Icons**: common SF Symbols rendered as decorative stickers
/// - **Decorative**: washi tape strips, corner decorations, page flags
final class BuiltInStickerPack: StickerPackProviding {

    static let shared = BuiltInStickerPack()
    private init() {}

    // MARK: - StickerPackProviding

    let packID = "builtin"
    let displayName = "Built-In Elements"

    func packPreviewImage(size: CGSize) -> UIImage? {
        render(stickerID: "academic.star.filled", size: size)
    }

    var stickers: [StickerDefinition] { allDefinitions }

    func render(stickerID: String, size: CGSize) -> UIImage? {
        guard let renderer = renderers[stickerID] else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            renderer(ctx.cgContext, size)
        }
    }

    // MARK: - Definitions

    private lazy var allDefinitions: [StickerDefinition] = [
        // Academic
        StickerDefinition(
            id: "academic.arrow.right",
            category: "Academic",
            displayName: "Arrow Right",
            symbolFallback: "arrow.right"
        ),
        StickerDefinition(
            id: "academic.arrow.up",
            category: "Academic",
            displayName: "Arrow Up",
            symbolFallback: "arrow.up"
        ),
        StickerDefinition(
            id: "academic.arrow.curved",
            category: "Academic",
            displayName: "Curved Arrow",
            symbolFallback: "arrow.turn.up.right"
        ),
        StickerDefinition(
            id: "academic.checkmark",
            category: "Academic",
            displayName: "Checkmark",
            symbolFallback: "checkmark"
        ),
        StickerDefinition(
            id: "academic.star.filled",
            category: "Academic",
            displayName: "Star",
            symbolFallback: "star.fill"
        ),
        StickerDefinition(
            id: "academic.bullet.round",
            category: "Academic",
            displayName: "Round Bullet",
            symbolFallback: "circle.fill"
        ),
        StickerDefinition(
            id: "academic.divider.wavy",
            category: "Academic",
            displayName: "Wavy Divider",
            symbolFallback: "minus"
        ),
        StickerDefinition(
            id: "academic.bracket.left",
            category: "Academic",
            displayName: "Left Bracket",
            symbolFallback: "lessthan"
        ),
        // Shapes
        StickerDefinition(
            id: "shape.speech.bubble",
            category: "Shapes",
            displayName: "Speech Bubble",
            symbolFallback: "bubble.left.fill"
        ),
        StickerDefinition(
            id: "shape.banner.ribbon",
            category: "Shapes",
            displayName: "Banner",
            symbolFallback: "flag.fill"
        ),
        StickerDefinition(
            id: "shape.frame.rounded",
            category: "Shapes",
            displayName: "Rounded Frame",
            symbolFallback: "rectangle"
        ),
        StickerDefinition(
            id: "shape.cloud",
            category: "Shapes",
            displayName: "Cloud",
            symbolFallback: "cloud.fill"
        ),
        // Icons
        StickerDefinition(
            id: "icon.lightbulb",
            category: "Icons",
            displayName: "Lightbulb",
            symbolFallback: "lightbulb.fill"
        ),
        StickerDefinition(
            id: "icon.bookmark",
            category: "Icons",
            displayName: "Bookmark",
            symbolFallback: "bookmark.fill"
        ),
        StickerDefinition(
            id: "icon.exclamation",
            category: "Icons",
            displayName: "Exclamation",
            symbolFallback: "exclamationmark.circle.fill"
        ),
        StickerDefinition(
            id: "icon.question",
            category: "Icons",
            displayName: "Question",
            symbolFallback: "questionmark.circle.fill"
        ),
        // Decorative
        StickerDefinition(
            id: "deco.washi.pink",
            category: "Decorative",
            displayName: "Pink Washi",
            symbolFallback: "rectangle.fill"
        ),
        StickerDefinition(
            id: "deco.corner.leaf",
            category: "Decorative",
            displayName: "Leaf Corner",
            symbolFallback: "leaf.fill"
        ),
        StickerDefinition(
            id: "deco.flag.tab",
            category: "Decorative",
            displayName: "Page Flag",
            symbolFallback: "flag.fill"
        ),
    ]

    // MARK: - Renderers

    private lazy var renderers: [String: (CGContext, CGSize) -> Void] = [
        "academic.arrow.right": drawArrowRight,
        "academic.arrow.up": drawArrowUp,
        "academic.arrow.curved": drawCurvedArrow,
        "academic.checkmark": drawCheckmark,
        "academic.star.filled": drawStar,
        "academic.bullet.round": drawRoundBullet,
        "academic.divider.wavy": drawWavyDivider,
        "academic.bracket.left": drawLeftBracket,
        "shape.speech.bubble": drawSpeechBubble,
        "shape.banner.ribbon": drawBanner,
        "shape.frame.rounded": drawRoundedFrame,
        "shape.cloud": drawCloud,
        "icon.lightbulb": drawLightbulb,
        "icon.bookmark": drawBookmark,
        "icon.exclamation": drawExclamation,
        "icon.question": drawQuestion,
        "deco.washi.pink": drawWashiPink,
        "deco.corner.leaf": drawLeafCorner,
        "deco.flag.tab": drawFlagTab,
    ]

    // MARK: - Academic drawers

    private func drawArrowRight(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(max(2, size.width * 0.07))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let mid = size.height / 2
        let left: CGFloat = size.width * 0.1
        let right: CGFloat = size.width * 0.9
        let arrowHead: CGFloat = size.width * 0.2
        ctx.move(to: CGPoint(x: left, y: mid))
        ctx.addLine(to: CGPoint(x: right, y: mid))
        ctx.move(to: CGPoint(x: right - arrowHead, y: mid - arrowHead * 0.6))
        ctx.addLine(to: CGPoint(x: right, y: mid))
        ctx.addLine(to: CGPoint(x: right - arrowHead, y: mid + arrowHead * 0.6))
        ctx.strokePath()
    }

    private func drawArrowUp(_ ctx: CGContext, _ size: CGSize) {
        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: -.pi / 2)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        drawArrowRight(ctx, size)
        ctx.restoreGState()
    }

    private func drawCurvedArrow(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemPurple.cgColor)
        ctx.setLineWidth(max(2, size.width * 0.07))
        ctx.setLineCap(.round)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.7))
        path.addCurve(
            to: CGPoint(x: size.width * 0.85, y: size.height * 0.3),
            controlPoint1: CGPoint(x: size.width * 0.15, y: size.height * 0.1),
            controlPoint2: CGPoint(x: size.width * 0.85, y: size.height * 0.1)
        )
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        // Arrowhead
        let tip = CGPoint(x: size.width * 0.85, y: size.height * 0.3)
        ctx.move(to: CGPoint(x: tip.x - size.width * 0.15, y: tip.y - size.height * 0.05))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x, y: tip.y + size.height * 0.18))
        ctx.strokePath()
    }

    private func drawCheckmark(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemGreen.cgColor)
        ctx.setLineWidth(max(3, size.width * 0.1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.55))
        ctx.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.8))
        ctx.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.2))
        ctx.strokePath()
    }

    private func drawStar(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemYellow.cgColor)
        let cx = size.width / 2, cy = size.height / 2
        let outerR = min(size.width, size.height) * 0.46
        let innerR = outerR * 0.4
        let path = CGMutablePath()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let radius = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawRoundBullet(_ ctx: CGContext, _ size: CGSize) {
        let radius = min(size.width, size.height) * 0.4
        let rect = CGRect(
            x: size.width / 2 - radius,
            y: size.height / 2 - radius,
            width: radius * 2,
            height: radius * 2
        )
        ctx.setFillColor(UIColor.systemOrange.cgColor)
        ctx.fillEllipse(in: rect)
    }

    private func drawWavyDivider(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemTeal.cgColor)
        ctx.setLineWidth(max(2, size.height * 0.1))
        let path = UIBezierPath()
        let wave: CGFloat = size.height * 0.3
        let step = size.width / 6
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        for i in 0..<6 {
            let x = CGFloat(i) * step
            let cp1 = CGPoint(x: x + step / 3, y: size.height / 2 - wave)
            let cp2 = CGPoint(x: x + 2 * step / 3, y: size.height / 2 + wave)
            path.addCurve(to: CGPoint(x: x + step, y: size.height / 2), controlPoint1: cp1, controlPoint2: cp2)
        }
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    private func drawLeftBracket(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemIndigo.cgColor)
        ctx.setLineWidth(max(2, size.width * 0.1))
        ctx.setLineCap(.round)
        let x = size.width * 0.6
        ctx.move(to: CGPoint(x: x - size.width * 0.2, y: size.height * 0.1))
        ctx.addLine(to: CGPoint(x: x, y: size.height * 0.1))
        ctx.addLine(to: CGPoint(x: x, y: size.height * 0.9))
        ctx.addLine(to: CGPoint(x: x - size.width * 0.2, y: size.height * 0.9))
        ctx.strokePath()
    }

    // MARK: - Shapes drawers

    private func drawSpeechBubble(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.15).cgColor)
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(max(2, size.width * 0.05))
        let cornerRadius: CGFloat = size.height * 0.2
        let bubble = CGRect(
            x: size.width * 0.05,
            y: size.height * 0.05,
            width: size.width * 0.9,
            height: size.height * 0.72
        )
        let path = UIBezierPath(roundedRect: bubble, cornerRadius: cornerRadius)
        // Tail
        path.move(to: CGPoint(x: size.width * 0.25, y: bubble.maxY))
        path.addLine(to: CGPoint(x: size.width * 0.2, y: size.height * 0.95))
        path.addLine(to: CGPoint(x: size.width * 0.4, y: bubble.maxY))
        ctx.addPath(path.cgPath)
        ctx.drawPath(using: .fillStroke)
    }

    private func drawBanner(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemPink.cgColor)
        let body = CGRect(x: 0, y: size.height * 0.2, width: size.width, height: size.height * 0.6)
        ctx.fill(body)
        // Left notch
        let notchW = size.width * 0.08
        let triPath = CGMutablePath()
        triPath.move(to: CGPoint(x: 0, y: body.minY))
        triPath.addLine(to: CGPoint(x: 0, y: body.maxY))
        triPath.addLine(to: CGPoint(x: notchW, y: body.midY))
        triPath.closeSubpath()
        ctx.setFillColor(UIColor.systemPink.darker().cgColor)
        ctx.addPath(triPath)
        ctx.fillPath()
    }

    private func drawRoundedFrame(_ ctx: CGContext, _ size: CGSize) {
        ctx.setStrokeColor(UIColor.systemGray.cgColor)
        ctx.setLineWidth(max(3, size.width * 0.06))
        ctx.setLineDash(phase: 0, lengths: [size.width * 0.06, size.width * 0.04])
        let rect = CGRect(
            x: size.width * 0.08,
            y: size.height * 0.08,
            width: size.width * 0.84,
            height: size.height * 0.84
        )
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.12)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    private func drawCloud(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemCyan.withAlphaComponent(0.6).cgColor)
        let circles: [(CGFloat, CGFloat, CGFloat)] = [
            (0.5, 0.5, 0.28), (0.28, 0.62, 0.2),
            (0.72, 0.62, 0.2), (0.18, 0.72, 0.15),
            (0.82, 0.72, 0.15),
        ]
        for (cx, cy, r) in circles {
            let rect = CGRect(
                x: size.width * cx - size.width * r,
                y: size.height * cy - size.height * r,
                width: size.width * r * 2,
                height: size.height * r * 2
            )
            ctx.fillEllipse(in: rect)
        }
    }

    // MARK: - Icon drawers (SF Symbol style)

    private func drawSFSymbol(_ name: String, color: UIColor, _ ctx: CGContext, _ size: CGSize) {
        let config = UIImage.SymbolConfiguration(pointSize: min(size.width, size.height) * 0.7, weight: .medium)
        guard let img = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let origin = CGPoint(x: (size.width - img.size.width) / 2, y: (size.height - img.size.height) / 2)
        UIGraphicsPushContext(ctx)
        img.draw(at: origin)
        UIGraphicsPopContext()
    }

    private func drawLightbulb(_ ctx: CGContext, _ size: CGSize) {
        drawSFSymbol("lightbulb.fill", color: .systemYellow, ctx, size)
    }

    private func drawBookmark(_ ctx: CGContext, _ size: CGSize) {
        drawSFSymbol("bookmark.fill", color: .systemRed, ctx, size)
    }

    private func drawExclamation(_ ctx: CGContext, _ size: CGSize) {
        drawSFSymbol("exclamationmark.circle.fill", color: .systemOrange, ctx, size)
    }

    private func drawQuestion(_ ctx: CGContext, _ size: CGSize) {
        drawSFSymbol("questionmark.circle.fill", color: .systemBlue, ctx, size)
    }

    // MARK: - Decorative drawers

    private func drawWashiPink(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemPink.withAlphaComponent(0.5).cgColor)
        ctx.setAlpha(0.85)
        ctx.fill(CGRect(x: 0, y: size.height * 0.3, width: size.width, height: size.height * 0.4))
        // Texture lines
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        let lineCount = 5
        for i in 0..<lineCount {
            let y = size.height * 0.3 + size.height * 0.4 / CGFloat(lineCount) * CGFloat(i)
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.strokePath()
    }

    private func drawLeafCorner(_ ctx: CGContext, _ size: CGSize) {
        drawSFSymbol("leaf.fill", color: .systemGreen, ctx, size)
    }

    private func drawFlagTab(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor.systemYellow.cgColor)
        let w = size.width * 0.6, h = size.height * 0.85
        let path = CGMutablePath()
        path.move(to: CGPoint(x: size.width * 0.2, y: 0))
        path.addLine(to: CGPoint(x: size.width * 0.2 + w, y: 0))
        path.addLine(to: CGPoint(x: size.width * 0.2 + w, y: h * 0.75))
        path.addLine(to: CGPoint(x: size.width * 0.2 + w / 2, y: h))
        path.addLine(to: CGPoint(x: size.width * 0.2, y: h * 0.75))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
}

// MARK: - UIColor darker helper (private)

private extension UIColor {
    func darker() -> UIColor {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        if getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha) {
            return UIColor(hue: hue, saturation: sat, brightness: bri * 0.75, alpha: alpha)
        }
        return self
    }
}
