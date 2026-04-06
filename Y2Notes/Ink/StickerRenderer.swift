import UIKit

// MARK: - StickerRenderer

/// Generates built-in sticker images programmatically via Core Graphics so
/// the sticker library has real visuals without requiring PNG asset files in
/// the bundle.  All stickers are rendered at 2× scale on a transparent canvas.
///
/// `StickerStore` calls `render(id:size:)` as a fallback when
/// `UIImage(named:)` returns nil for a built-in asset.
enum StickerRenderer {

    static let defaultSize = CGSize(width: 64, height: 64)

    // MARK: - Public Entry Point

    /// Returns a `UIImage` for the given sticker ID, or `nil` if unknown.
    static func render(id: String, size: CGSize = defaultSize) -> UIImage? {
        switch id {

        // MARK: Essentials
        case "star-gold":         return drawStar(size: size)
        case "checkmark-green":   return drawCheckmark(size: size)
        case "arrow-right":       return drawArrowRight(size: size)
        case "badge-important":   return drawBadgeImportant(size: size)
        case "heart-red":         return drawHeart(size: size)
        case "thumbsup":          return drawThumbsUp(size: size)
        case "lightning-bolt":    return drawLightningBolt(size: size)
        case "trophy-gold":       return drawTrophy(size: size)
        case "exclamation-red":   return drawExclamation(size: size)
        case "pin-push":          return drawPushPin(size: size)

        // MARK: Academic
        case "grade-a":           return drawGradeA(size: size)
        case "book-open":         return drawBookOpen(size: size)
        case "formula-e":         return drawFormulaE(size: size)
        case "microscope":        return drawMicroscope(size: size)
        case "pencil-sharp":      return drawPencil(size: size)
        case "lightbulb-idea":    return drawLightbulb(size: size)
        case "globe-world":       return drawGlobe(size: size)
        case "chemistry-flask":   return drawFlask(size: size)

        // MARK: Planner
        case "flag-priority":     return drawFlagPriority(size: size)
        case "clock-time":        return drawClock(size: size)
        case "calendar-day":      return drawCalendar(size: size)
        case "pin-location":      return drawLocationPin(size: size)
        case "target-goal":       return drawTarget(size: size)
        case "hourglass-time":    return drawHourglass(size: size)
        case "rocket-launch":     return drawRocket(size: size)
        case "notepad-memo":      return drawNotepad(size: size)

        // MARK: Decorative
        case "washi-stripe":      return drawWashiStripe(size: size)
        case "corner-flourish":   return drawCornerFlourish(size: size)
        case "divider-dots":      return drawDividerDots(size: size)
        case "frame-simple":      return drawSimpleFrame(size: size)
        case "rainbow-arc":       return drawRainbow(size: size)
        case "leaf-green":        return drawLeaf(size: size)
        case "cloud-fluffy":      return drawCloud(size: size)
        case "diamond-gem":       return drawDiamond(size: size)

        // MARK: Emoji
        case "smile-happy":       return drawHappyFace(size: size)
        case "face-think":        return drawThinkingFace(size: size)
        case "fire-hot":          return drawFire(size: size)
        case "sparkles":          return drawSparkles(size: size)
        case "clover-lucky":      return drawClover(size: size)
        case "snowflake-ice":     return drawSnowflake(size: size)
        case "gem-crystal":       return drawCrystalGem(size: size)
        case "music-note":        return drawMusicNote(size: size)

        default:                  return nil
        }
    }

    // MARK: - Renderer Factory

    /// Device screen scale, captured once on first use to avoid threading issues.
    private static let deviceScale: CGFloat = {
        var scale: CGFloat = 2
        if Thread.isMainThread {
            scale = UIScreen.main.scale
        }
        return scale
    }()

    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = deviceScale
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt)
    }

    // MARK: - Geometry Helpers

    /// Builds a 5-pointed star path centred in `rect`.
    private static func starPath(in rect: CGRect) -> UIBezierPath {
        let cx = rect.midX, cy = rect.midY
        let outerR = min(rect.width, rect.height) * 0.44
        let innerR = outerR * 0.42
        let path = UIBezierPath()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        return path
    }

    // MARK: ──────────────────────────────────────────
    // MARK: Essentials
    // MARK: ──────────────────────────────────────────

    private static func drawStar(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let gold     = UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1)
            let darkGold = UIColor(red: 0.82, green: 0.58, blue: 0.00, alpha: 1)
            let path = starPath(in: CGRect(origin: .zero, size: size))
            gold.setFill(); path.fill()
            darkGold.setStroke(); path.lineWidth = 2; path.stroke()
        }
    }

    private static func drawCheckmark(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let green = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
            let bg = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            green.setFill(); bg.fill()

            let path = UIBezierPath()
            let s = size.width
            path.move(to: CGPoint(x: s * 0.22, y: s * 0.52))
            path.addLine(to: CGPoint(x: s * 0.42, y: s * 0.70))
            path.addLine(to: CGPoint(x: s * 0.78, y: s * 0.32))
            UIColor.white.setStroke()
            path.lineWidth = s * 0.12
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private static func drawArrowRight(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let blue = UIColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            path.move(to: CGPoint(x: s * 0.18, y: s * 0.50))
            path.addLine(to: CGPoint(x: s * 0.72, y: s * 0.50))
            path.move(to: CGPoint(x: s * 0.52, y: s * 0.30))
            path.addLine(to: CGPoint(x: s * 0.78, y: s * 0.50))
            path.addLine(to: CGPoint(x: s * 0.52, y: s * 0.70))
            blue.setStroke(); path.lineWidth = s * 0.11; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        }
    }

    private static func drawBadgeImportant(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red    = UIColor(red: 0.95, green: 0.22, blue: 0.22, alpha: 1)
            let white  = UIColor.white
            let s = size.width
            // Octagonal badge
            let r = s * 0.44
            let cx = s / 2, cy = s / 2
            let path = UIBezierPath()
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4 - .pi / 8
                let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.close()
            red.setFill(); path.fill()
            // Exclamation
            let ePath = UIBezierPath()
            ePath.move(to: CGPoint(x: cx, y: cy - s * 0.22))
            ePath.addLine(to: CGPoint(x: cx, y: cy + s * 0.06))
            ePath.lineCapStyle = .round; ePath.lineWidth = s * 0.11
            white.setStroke(); ePath.stroke()
            let dot = UIBezierPath(ovalIn: CGRect(x: cx - s * 0.055, y: cy + s * 0.13, width: s * 0.11, height: s * 0.11))
            white.setFill(); dot.fill()
        }
    }

    private static func drawHeart(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red   = UIColor(red: 0.95, green: 0.22, blue: 0.28, alpha: 1)
            let darkR = UIColor(red: 0.75, green: 0.10, blue: 0.15, alpha: 1)
            let s = size.width
            let cx = s / 2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cx, y: s * 0.72))
            path.addCurve(to: CGPoint(x: s * 0.08, y: s * 0.38),
                          controlPoint1: CGPoint(x: s * 0.22, y: s * 0.72),
                          controlPoint2: CGPoint(x: s * 0.08, y: s * 0.58))
            path.addArc(withCenter: CGPoint(x: s * 0.28, y: s * 0.32),
                        radius: s * 0.20, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addArc(withCenter: CGPoint(x: s * 0.72, y: s * 0.32),
                        radius: s * 0.20, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addCurve(to: CGPoint(x: cx, y: s * 0.72),
                          controlPoint1: CGPoint(x: s * 0.92, y: s * 0.58),
                          controlPoint2: CGPoint(x: s * 0.78, y: s * 0.72))
            path.close()
            red.setFill(); path.fill()
            darkR.setStroke(); path.lineWidth = 1.5; path.stroke()
        }
    }

    private static func drawThumbsUp(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let s = size.width
            // Skin-tone thumb
            let skin  = UIColor(red: 0.96, green: 0.76, blue: 0.52, alpha: 1)
            let dark  = UIColor(red: 0.78, green: 0.55, blue: 0.32, alpha: 1)
            // Hand base (rectangle)
            let base = UIBezierPath(roundedRect: CGRect(x: s*0.28, y: s*0.40, width: s*0.42, height: s*0.42), cornerRadius: s*0.07)
            skin.setFill(); base.fill(); dark.setStroke(); base.lineWidth = 1.5; base.stroke()
            // Thumb
            let thumb = UIBezierPath(roundedRect: CGRect(x: s*0.14, y: s*0.18, width: s*0.22, height: s*0.34), cornerRadius: s*0.10)
            skin.setFill(); thumb.fill(); dark.setStroke(); thumb.lineWidth = 1.5; thumb.stroke()
        }
    }

    private static func drawLightningBolt(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let yellow = UIColor(red: 1.00, green: 0.85, blue: 0.00, alpha: 1)
            let amber  = UIColor(red: 0.90, green: 0.55, blue: 0.00, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            path.move(to:    CGPoint(x: s*0.60, y: s*0.08))
            path.addLine(to: CGPoint(x: s*0.30, y: s*0.52))
            path.addLine(to: CGPoint(x: s*0.52, y: s*0.52))
            path.addLine(to: CGPoint(x: s*0.38, y: s*0.92))
            path.addLine(to: CGPoint(x: s*0.72, y: s*0.44))
            path.addLine(to: CGPoint(x: s*0.50, y: s*0.44))
            path.close()
            yellow.setFill(); path.fill()
            amber.setStroke(); path.lineWidth = 1.5; path.stroke()
        }
    }

    private static func drawTrophy(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let gold   = UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1)
            let amber  = UIColor(red: 0.82, green: 0.56, blue: 0.00, alpha: 1)
            let s = size.width
            // Cup body
            let cup = UIBezierPath(roundedRect: CGRect(x: s*0.22, y: s*0.10, width: s*0.56, height: s*0.42), cornerRadius: s*0.10)
            gold.setFill(); cup.fill(); amber.setStroke(); cup.lineWidth = 1.5; cup.stroke()
            // Stem
            let stem = UIBezierPath(rect: CGRect(x: s*0.44, y: s*0.52, width: s*0.12, height: s*0.22))
            gold.setFill(); stem.fill()
            // Base
            let base = UIBezierPath(roundedRect: CGRect(x: s*0.26, y: s*0.74, width: s*0.48, height: s*0.13), cornerRadius: s*0.05)
            gold.setFill(); base.fill(); amber.setStroke(); base.lineWidth = 1.5; base.stroke()
            // Handles
            let lHandle = UIBezierPath()
            lHandle.move(to: CGPoint(x: s*0.22, y: s*0.22))
            lHandle.addCurve(to: CGPoint(x: s*0.22, y: s*0.42),
                             controlPoint1: CGPoint(x: s*0.06, y: s*0.22),
                             controlPoint2: CGPoint(x: s*0.06, y: s*0.42))
            amber.setStroke(); lHandle.lineWidth = s*0.06; lHandle.lineCapStyle = .round; lHandle.stroke()
            let rHandle = UIBezierPath()
            rHandle.move(to: CGPoint(x: s*0.78, y: s*0.22))
            rHandle.addCurve(to: CGPoint(x: s*0.78, y: s*0.42),
                             controlPoint1: CGPoint(x: s*0.94, y: s*0.22),
                             controlPoint2: CGPoint(x: s*0.94, y: s*0.42))
            rHandle.lineWidth = s*0.06; rHandle.lineCapStyle = .round; rHandle.stroke()
        }
    }

    private static func drawExclamation(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red   = UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1)
            let white = UIColor.white
            let s = size.width
            let bg = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            red.setFill(); bg.fill()
            let bar = UIBezierPath(roundedRect: CGRect(x: s*0.44, y: s*0.16, width: s*0.12, height: s*0.42), cornerRadius: s*0.06)
            white.setFill(); bar.fill()
            let dot = UIBezierPath(ovalIn: CGRect(x: s*0.44, y: s*0.64, width: s*0.12, height: s*0.12))
            white.setFill(); dot.fill()
        }
    }

    private static func drawPushPin(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let pinRed  = UIColor(red: 0.92, green: 0.25, blue: 0.25, alpha: 1)
            let darkRed = UIColor(red: 0.72, green: 0.10, blue: 0.10, alpha: 1)
            let silver  = UIColor(red: 0.70, green: 0.72, blue: 0.76, alpha: 1)
            let s = size.width
            // Needle
            let needle = UIBezierPath()
            needle.move(to: CGPoint(x: s*0.50, y: s*0.52))
            needle.addLine(to: CGPoint(x: s*0.50, y: s*0.88))
            silver.setStroke(); needle.lineWidth = s*0.06; needle.lineCapStyle = .round; needle.stroke()
            // Pin head (circle)
            let head = UIBezierPath(ovalIn: CGRect(x: s*0.22, y: s*0.10, width: s*0.56, height: s*0.46))
            pinRed.setFill(); head.fill(); darkRed.setStroke(); head.lineWidth = 1.5; head.stroke()
            // Shine
            let shine = UIBezierPath(ovalIn: CGRect(x: s*0.30, y: s*0.16, width: s*0.20, height: s*0.14))
            UIColor.white.withAlphaComponent(0.45).setFill(); shine.fill()
        }
    }

    // MARK: ──────────────────────────────────────────
    // MARK: Academic
    // MARK: ──────────────────────────────────────────

    private static func drawGradeA(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let purple = UIColor(red: 0.55, green: 0.25, blue: 0.90, alpha: 1)
            let white  = UIColor.white
            let s = size.width
            let bg = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4), cornerRadius: s*0.16)
            purple.setFill(); bg.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: s * 0.52),
                .foregroundColor: white
            ]
            let str = NSAttributedString(string: "A", attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(x: (s - strSize.width)/2, y: (s - strSize.height)/2))
        }
    }

    private static func drawBookOpen(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let blue  = UIColor(red: 0.25, green: 0.50, blue: 0.95, alpha: 1)
            let white = UIColor.white
            let s = size.width
            // Left page
            let left = UIBezierPath(roundedRect: CGRect(x: s*0.06, y: s*0.18, width: s*0.42, height: s*0.58), cornerRadius: s*0.06)
            blue.setFill(); left.fill()
            // Right page
            let right = UIBezierPath(roundedRect: CGRect(x: s*0.52, y: s*0.18, width: s*0.42, height: s*0.58), cornerRadius: s*0.06)
            blue.setFill(); right.fill()
            // Spine line
            let spine = UIBezierPath()
            spine.move(to: CGPoint(x: s*0.50, y: s*0.14))
            spine.addLine(to: CGPoint(x: s*0.50, y: s*0.80))
            white.setStroke(); spine.lineWidth = s*0.06; spine.lineCapStyle = .round; spine.stroke()
            // Lines on pages
            for frac in [0.38, 0.52, 0.66] as [CGFloat] {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: s*0.14, y: s*frac))
                line.addLine(to: CGPoint(x: s*0.42, y: s*frac))
                white.withAlphaComponent(0.5).setStroke(); line.lineWidth = s*0.04; line.stroke()
                let line2 = UIBezierPath()
                line2.move(to: CGPoint(x: s*0.58, y: s*frac))
                line2.addLine(to: CGPoint(x: s*0.86, y: s*frac))
                white.withAlphaComponent(0.5).setStroke(); line2.lineWidth = s*0.04; line2.stroke()
            }
        }
    }

    private static func drawFormulaE(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let teal  = UIColor(red: 0.05, green: 0.70, blue: 0.65, alpha: 1)
            let white = UIColor.white
            let s = size.width
            let bg = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4), cornerRadius: s*0.16)
            teal.setFill(); bg.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: s * 0.44),
                .foregroundColor: white
            ]
            let str = NSAttributedString(string: "e=mc²", attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(x: (s - strSize.width)/2, y: (s - strSize.height)/2))
        }
    }

    private static func drawMicroscope(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let darkGray = UIColor(red: 0.25, green: 0.28, blue: 0.32, alpha: 1)
            let teal     = UIColor(red: 0.10, green: 0.72, blue: 0.68, alpha: 1)
            let s = size.width
            // Lens tube
            let tube = UIBezierPath(roundedRect: CGRect(x: s*0.38, y: s*0.08, width: s*0.20, height: s*0.40), cornerRadius: s*0.05)
            darkGray.setFill(); tube.fill()
            // Eyepiece
            let eye = UIBezierPath(roundedRect: CGRect(x: s*0.34, y: s*0.08, width: s*0.28, height: s*0.10), cornerRadius: s*0.04)
            teal.setFill(); eye.fill()
            // Arm
            let arm = UIBezierPath()
            arm.move(to: CGPoint(x: s*0.50, y: s*0.46))
            arm.addLine(to: CGPoint(x: s*0.30, y: s*0.72))
            darkGray.setStroke(); arm.lineWidth = s*0.10; arm.lineCapStyle = .round; arm.stroke()
            // Base
            let base = UIBezierPath(roundedRect: CGRect(x: s*0.16, y: s*0.74, width: s*0.55, height: s*0.13), cornerRadius: s*0.05)
            darkGray.setFill(); base.fill()
            // Stage
            let stage = UIBezierPath(rect: CGRect(x: s*0.36, y: s*0.60, width: s*0.24, height: s*0.08))
            teal.setFill(); stage.fill()
        }
    }

    private static func drawPencil(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let yellow = UIColor(red: 1.00, green: 0.85, blue: 0.15, alpha: 1)
            let pink   = UIColor(red: 0.98, green: 0.72, blue: 0.72, alpha: 1)
            let dark   = UIColor(red: 0.30, green: 0.28, blue: 0.26, alpha: 1)
            let s = size.width
            // Pencil body (rotated 45°)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                #if DEBUG
                print("StickerRenderer: drawPencil — graphics context unavailable")
                #endif
                return
            }
            ctx.saveGState()
            ctx.translateBy(x: s/2, y: s/2)
            ctx.rotate(by: -.pi / 4)
            ctx.translateBy(x: -s/2, y: -s/2)
            // Body
            let body = UIBezierPath(roundedRect: CGRect(x: s*0.22, y: s*0.22, width: s*0.56, height: s*0.18), cornerRadius: s*0.04)
            yellow.setFill(); body.fill(); dark.setStroke(); body.lineWidth = 1.2; body.stroke()
            // Eraser
            let eraser = UIBezierPath(rect: CGRect(x: s*0.72, y: s*0.22, width: s*0.08, height: s*0.18))
            pink.setFill(); eraser.fill()
            // Tip
            let tip = UIBezierPath()
            tip.move(to: CGPoint(x: s*0.14, y: s*0.22))
            tip.addLine(to: CGPoint(x: s*0.22, y: s*0.31))
            tip.addLine(to: CGPoint(x: s*0.14, y: s*0.40))
            tip.close()
            UIColor(red: 0.96, green: 0.78, blue: 0.45, alpha: 1).setFill(); tip.fill()
            ctx.restoreGState()
        }
    }

    private static func drawLightbulb(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let yellow  = UIColor(red: 1.00, green: 0.88, blue: 0.20, alpha: 1)
            let amber   = UIColor(red: 0.90, green: 0.62, blue: 0.00, alpha: 1)
            let silver  = UIColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1)
            let s = size.width
            // Bulb
            let bulb = UIBezierPath(ovalIn: CGRect(x: s*0.18, y: s*0.10, width: s*0.64, height: s*0.56))
            yellow.setFill(); bulb.fill(); amber.setStroke(); bulb.lineWidth = 1.5; bulb.stroke()
            // Base rings
            for i in 0...2 {
                let dy = CGFloat(i) * s * 0.07
                let ring = UIBezierPath(roundedRect: CGRect(x: s*0.30, y: s*0.62 + dy, width: s*0.40, height: s*0.07), cornerRadius: s*0.02)
                silver.setFill(); ring.fill()
            }
            // Shine
            let shine = UIBezierPath(ovalIn: CGRect(x: s*0.28, y: s*0.18, width: s*0.20, height: s*0.18))
            UIColor.white.withAlphaComponent(0.50).setFill(); shine.fill()
        }
    }

    private static func drawGlobe(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let ocean = UIColor(red: 0.20, green: 0.55, blue: 0.92, alpha: 1)
            let land  = UIColor(red: 0.30, green: 0.78, blue: 0.38, alpha: 1)
            let white = UIColor.white
            let s = size.width
            let r = s * 0.42
            let cx = s / 2, cy = s / 2
            let globe = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2))
            ocean.setFill(); globe.fill()
            // Meridian lines
            white.withAlphaComponent(0.30).setStroke()
            for frac in [-0.25, 0.0, 0.25] as [CGFloat] {
                let meridian = UIBezierPath(ovalIn: CGRect(x: cx + frac * r * 2 - r * 0.08, y: cy - r, width: r * 0.16, height: r * 2))
                meridian.lineWidth = 0.8; meridian.stroke()
            }
            // Equator
            let equator = UIBezierPath()
            equator.move(to: CGPoint(x: cx - r, y: cy))
            equator.addLine(to: CGPoint(x: cx + r, y: cy))
            equator.lineWidth = 0.8; equator.stroke()
            // Simple continent blob
            let cont = UIBezierPath()
            cont.move(to: CGPoint(x: cx - s*0.08, y: cy - s*0.18))
            cont.addCurve(to: CGPoint(x: cx + s*0.16, y: cy + s*0.08),
                          controlPoint1: CGPoint(x: cx + s*0.20, y: cy - s*0.22),
                          controlPoint2: CGPoint(x: cx + s*0.26, y: cy - s*0.04))
            cont.addCurve(to: CGPoint(x: cx - s*0.08, y: cy - s*0.18),
                          controlPoint1: CGPoint(x: cx + s*0.02, y: cy + s*0.18),
                          controlPoint2: CGPoint(x: cx - s*0.24, y: cy + s*0.04))
            cont.close()
            land.setFill(); cont.fill()
            // Border
            ocean.withAlphaComponent(0.6).setStroke()
            globe.lineWidth = 1.5; globe.stroke()
        }
    }

    private static func drawFlask(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let teal  = UIColor(red: 0.10, green: 0.75, blue: 0.70, alpha: 1)
            let fill  = UIColor(red: 0.10, green: 0.75, blue: 0.70, alpha: 0.50)
            let dark  = UIColor(red: 0.02, green: 0.48, blue: 0.45, alpha: 1)
            let s = size.width
            // Flask outline
            let flask = UIBezierPath()
            flask.move(to: CGPoint(x: s*0.36, y: s*0.10))
            flask.addLine(to: CGPoint(x: s*0.36, y: s*0.40))
            flask.addLine(to: CGPoint(x: s*0.14, y: s*0.72))
            flask.addCurve(to: CGPoint(x: s*0.86, y: s*0.72),
                           controlPoint1: CGPoint(x: s*0.08, y: s*0.88),
                           controlPoint2: CGPoint(x: s*0.92, y: s*0.88))
            flask.addLine(to: CGPoint(x: s*0.64, y: s*0.40))
            flask.addLine(to: CGPoint(x: s*0.64, y: s*0.10))
            flask.close()
            fill.setFill(); flask.fill()
            teal.setStroke(); flask.lineWidth = 2; flask.stroke()
            // Neck band
            let neck = UIBezierPath(rect: CGRect(x: s*0.32, y: s*0.10, width: s*0.36, height: s*0.08))
            dark.setFill(); neck.fill()
            // Bubbles
            for (bx, by, br) in [(0.38, 0.68, 0.06), (0.55, 0.62, 0.04), (0.46, 0.58, 0.03)] as [(CGFloat,CGFloat,CGFloat)] {
                let bubble = UIBezierPath(ovalIn: CGRect(x: s*bx, y: s*by, width: s*br*2, height: s*br*2))
                UIColor.white.withAlphaComponent(0.60).setFill(); bubble.fill()
            }
        }
    }

    // MARK: ──────────────────────────────────────────
    // MARK: Planner
    // MARK: ──────────────────────────────────────────

    private static func drawFlagPriority(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red  = UIColor(red: 0.95, green: 0.22, blue: 0.22, alpha: 1)
            let dark = UIColor(red: 0.72, green: 0.10, blue: 0.10, alpha: 1)
            let s = size.width
            // Pole
            let pole = UIBezierPath()
            pole.move(to: CGPoint(x: s*0.28, y: s*0.12))
            pole.addLine(to: CGPoint(x: s*0.28, y: s*0.88))
            dark.setStroke(); pole.lineWidth = s*0.07; pole.lineCapStyle = .round; pole.stroke()
            // Flag
            let flag = UIBezierPath()
            flag.move(to: CGPoint(x: s*0.28, y: s*0.14))
            flag.addLine(to: CGPoint(x: s*0.78, y: s*0.26))
            flag.addLine(to: CGPoint(x: s*0.28, y: s*0.48))
            flag.close()
            red.setFill(); flag.fill()
        }
    }

    private static func drawClock(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let white = UIColor.white
            let blue  = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1)
            let dark  = UIColor(red: 0.10, green: 0.28, blue: 0.70, alpha: 1)
            let s = size.width
            let r = s * 0.42
            let cx = s/2, cy = s/2
            let face = UIBezierPath(ovalIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            white.setFill(); face.fill()
            blue.setStroke(); face.lineWidth = s*0.08; face.stroke()
            // Hour hand
            let hour = UIBezierPath()
            hour.move(to: CGPoint(x: cx, y: cy))
            hour.addLine(to: CGPoint(x: cx - s*0.12, y: cy - s*0.22))
            dark.setStroke(); hour.lineWidth = s*0.07; hour.lineCapStyle = .round; hour.stroke()
            // Minute hand
            let minute = UIBezierPath()
            minute.move(to: CGPoint(x: cx, y: cy))
            minute.addLine(to: CGPoint(x: cx + s*0.22, y: cy - s*0.10))
            dark.setStroke(); minute.lineWidth = s*0.05; minute.lineCapStyle = .round; minute.stroke()
            // Centre dot
            let dot = UIBezierPath(ovalIn: CGRect(x: cx - s*0.04, y: cy - s*0.04, width: s*0.08, height: s*0.08))
            dark.setFill(); dot.fill()
        }
    }

    private static func drawCalendar(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let white = UIColor.white
            let red   = UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)
            let blue  = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1)
            let s = size.width
            let body = UIBezierPath(roundedRect: CGRect(x: s*0.08, y: s*0.18, width: s*0.84, height: s*0.72), cornerRadius: s*0.10)
            white.setFill(); body.fill(); blue.withAlphaComponent(0.30).setStroke(); body.lineWidth = 1.5; body.stroke()
            // Header band
            let header = UIBezierPath(roundedRect: CGRect(x: s*0.08, y: s*0.18, width: s*0.84, height: s*0.20), cornerRadius: s*0.10)
            red.setFill(); header.fill()
            // Day number "1"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: s * 0.36),
                .foregroundColor: blue
            ]
            let str = NSAttributedString(string: "1", attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: (s - sz.width)/2, y: s*0.46 - sz.height/2))
        }
    }

    private static func drawLocationPin(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red  = UIColor(red: 0.92, green: 0.22, blue: 0.28, alpha: 1)
            let dark = UIColor(red: 0.70, green: 0.08, blue: 0.12, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            let cx = s/2
            let r  = s * 0.32
            path.addArc(withCenter: CGPoint(x: cx, y: s*0.34),
                        radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: cx + r, y: s*0.36))
            path.addCurve(to: CGPoint(x: cx, y: s*0.84),
                          controlPoint1: CGPoint(x: cx + r, y: s*0.60),
                          controlPoint2: CGPoint(x: cx + s*0.06, y: s*0.80))
            path.addCurve(to: CGPoint(x: cx - r, y: s*0.36),
                          controlPoint1: CGPoint(x: cx - s*0.06, y: s*0.80),
                          controlPoint2: CGPoint(x: cx - r, y: s*0.60))
            path.close()
            red.setFill(); path.fill(); dark.setStroke(); path.lineWidth = 1.5; path.stroke()
            let inner = UIBezierPath(ovalIn: CGRect(x: cx - s*0.12, y: s*0.22, width: s*0.24, height: s*0.24))
            UIColor.white.withAlphaComponent(0.70).setFill(); inner.fill()
        }
    }

    private static func drawTarget(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let red   = UIColor(red: 0.92, green: 0.20, blue: 0.20, alpha: 1)
            let white = UIColor.white
            let s = size.width
            let cx = s/2, cy = s/2
            for (r, clr) in [(s*0.44, red), (s*0.32, white), (s*0.20, red), (s*0.10, white)] as [(CGFloat, UIColor)] {
                let ring = UIBezierPath(ovalIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
                clr.setFill(); ring.fill()
            }
            // Dot
            let dot = UIBezierPath(ovalIn: CGRect(x: cx - s*0.04, y: cy - s*0.04, width: s*0.08, height: s*0.08))
            red.setFill(); dot.fill()
        }
    }

    private static func drawHourglass(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let amber  = UIColor(red: 0.98, green: 0.68, blue: 0.10, alpha: 1)
            let dark   = UIColor(red: 0.70, green: 0.42, blue: 0.00, alpha: 1)
            let sand   = UIColor(red: 1.00, green: 0.88, blue: 0.55, alpha: 1)
            let s = size.width
            // Frame top
            let top = UIBezierPath(roundedRect: CGRect(x: s*0.16, y: s*0.08, width: s*0.68, height: s*0.10), cornerRadius: s*0.04)
            amber.setFill(); top.fill()
            // Frame bottom
            let bot = UIBezierPath(roundedRect: CGRect(x: s*0.16, y: s*0.82, width: s*0.68, height: s*0.10), cornerRadius: s*0.04)
            amber.setFill(); bot.fill()
            // Glass outline
            let glass = UIBezierPath()
            glass.move(to: CGPoint(x: s*0.18, y: s*0.18))
            glass.addLine(to: CGPoint(x: s*0.48, y: s*0.48))
            glass.addLine(to: CGPoint(x: s*0.18, y: s*0.80))
            glass.move(to: CGPoint(x: s*0.82, y: s*0.18))
            glass.addLine(to: CGPoint(x: s*0.52, y: s*0.48))
            glass.addLine(to: CGPoint(x: s*0.82, y: s*0.80))
            dark.setStroke(); glass.lineWidth = 1.5; glass.stroke()
            // Sand top (upper half, partial)
            let sandTop = UIBezierPath()
            sandTop.move(to: CGPoint(x: s*0.24, y: s*0.18))
            sandTop.addLine(to: CGPoint(x: s*0.76, y: s*0.18))
            sandTop.addLine(to: CGPoint(x: s*0.56, y: s*0.40))
            sandTop.addLine(to: CGPoint(x: s*0.44, y: s*0.40))
            sandTop.close()
            sand.setFill(); sandTop.fill()
            // Sand bottom pile
            let sandBot = UIBezierPath()
            sandBot.move(to: CGPoint(x: s*0.30, y: s*0.80))
            sandBot.addLine(to: CGPoint(x: s*0.70, y: s*0.80))
            sandBot.addLine(to: CGPoint(x: s*0.56, y: s*0.60))
            sandBot.addLine(to: CGPoint(x: s*0.44, y: s*0.60))
            sandBot.close()
            sand.setFill(); sandBot.fill()
        }
    }

    private static func drawRocket(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let white  = UIColor.white
            let red    = UIColor(red: 0.92, green: 0.22, blue: 0.22, alpha: 1)
            let dark   = UIColor(red: 0.24, green: 0.26, blue: 0.32, alpha: 1)
            let flame  = UIColor(red: 1.00, green: 0.60, blue: 0.10, alpha: 1)
            let s = size.width
            // Flame
            let fl = UIBezierPath()
            fl.move(to: CGPoint(x: s*0.50, y: s*0.86))
            fl.addCurve(to: CGPoint(x: s*0.38, y: s*0.72),
                        controlPoint1: CGPoint(x: s*0.42, y: s*0.92),
                        controlPoint2: CGPoint(x: s*0.34, y: s*0.80))
            fl.addCurve(to: CGPoint(x: s*0.62, y: s*0.72),
                        controlPoint1: CGPoint(x: s*0.50, y: s*0.66),
                        controlPoint2: CGPoint(x: s*0.66, y: s*0.80))
            fl.close()
            flame.setFill(); fl.fill()
            // Body
            let body = UIBezierPath()
            body.move(to: CGPoint(x: s*0.50, y: s*0.08))
            body.addCurve(to: CGPoint(x: s*0.68, y: s*0.48),
                          controlPoint1: CGPoint(x: s*0.70, y: s*0.14),
                          controlPoint2: CGPoint(x: s*0.70, y: s*0.38))
            body.addLine(to: CGPoint(x: s*0.68, y: s*0.72))
            body.addLine(to: CGPoint(x: s*0.32, y: s*0.72))
            body.addLine(to: CGPoint(x: s*0.32, y: s*0.48))
            body.addCurve(to: CGPoint(x: s*0.50, y: s*0.08),
                          controlPoint1: CGPoint(x: s*0.30, y: s*0.38),
                          controlPoint2: CGPoint(x: s*0.30, y: s*0.14))
            body.close()
            white.setFill(); body.fill(); dark.setStroke(); body.lineWidth = 1.5; body.stroke()
            // Window
            let win = UIBezierPath(ovalIn: CGRect(x: s*0.39, y: s*0.34, width: s*0.22, height: s*0.22))
            UIColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1).setFill(); win.fill()
            dark.setStroke(); win.lineWidth = 1.2; win.stroke()
            // Fins
            let lFin = UIBezierPath()
            lFin.move(to: CGPoint(x: s*0.32, y: s*0.58))
            lFin.addLine(to: CGPoint(x: s*0.14, y: s*0.72))
            lFin.addLine(to: CGPoint(x: s*0.32, y: s*0.72))
            red.setFill(); lFin.fill()
            let rFin = UIBezierPath()
            rFin.move(to: CGPoint(x: s*0.68, y: s*0.58))
            rFin.addLine(to: CGPoint(x: s*0.86, y: s*0.72))
            rFin.addLine(to: CGPoint(x: s*0.68, y: s*0.72))
            red.setFill(); rFin.fill()
        }
    }

    private static func drawNotepad(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let cream  = UIColor(red: 1.00, green: 0.97, blue: 0.88, alpha: 1)
            let blue   = UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1)
            let ruled  = UIColor(red: 0.80, green: 0.88, blue: 1.00, alpha: 1)
            let s = size.width
            let pad = UIBezierPath(roundedRect: CGRect(x: s*0.10, y: s*0.12, width: s*0.80, height: s*0.78), cornerRadius: s*0.08)
            cream.setFill(); pad.fill(); blue.withAlphaComponent(0.40).setStroke(); pad.lineWidth = 1.5; pad.stroke()
            // Top spiral dots
            for i in 0...4 {
                let x = s*0.22 + CGFloat(i) * s*0.14
                let dot = UIBezierPath(ovalIn: CGRect(x: x, y: s*0.08, width: s*0.06, height: s*0.08))
                blue.setFill(); dot.fill()
            }
            // Ruled lines
            for row in 1...4 {
                let y = s*0.34 + CGFloat(row) * s*0.12
                let line = UIBezierPath()
                line.move(to: CGPoint(x: s*0.20, y: y))
                line.addLine(to: CGPoint(x: s*0.80, y: y))
                ruled.setStroke(); line.lineWidth = 1.2; line.stroke()
            }
        }
    }

    // MARK: ──────────────────────────────────────────
    // MARK: Decorative
    // MARK: ──────────────────────────────────────────

    private static func drawWashiStripe(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let s = size.width
            let colors: [UIColor] = [
                UIColor(red: 0.98, green: 0.72, blue: 0.82, alpha: 1),
                UIColor(red: 0.72, green: 0.90, blue: 0.98, alpha: 1),
                UIColor(red: 0.90, green: 0.98, blue: 0.72, alpha: 1),
            ]
            let h = s * 0.28
            let strip = UIBezierPath(roundedRect: CGRect(x: 0, y: (s-h)/2, width: s, height: h), cornerRadius: s*0.04)
            if let ctx = UIGraphicsGetCurrentContext() {
                ctx.saveGState()
                strip.addClip()
                for i in 0...8 {
                    let rect = CGRect(x: CGFloat(i) * s * 0.12, y: (s-h)/2, width: s * 0.12, height: h)
                    colors[i % colors.count].setFill()
                    UIBezierPath(rect: rect).fill()
                }
                ctx.restoreGState()
            }
            UIColor.black.withAlphaComponent(0.12).setStroke(); strip.lineWidth = 1; strip.stroke()
        }
    }

    private static func drawCornerFlourish(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let purple = UIColor(red: 0.62, green: 0.30, blue: 0.88, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            // Main scroll curve
            path.move(to: CGPoint(x: s*0.10, y: s*0.88))
            path.addCurve(to: CGPoint(x: s*0.88, y: s*0.10),
                          controlPoint1: CGPoint(x: s*0.10, y: s*0.42),
                          controlPoint2: CGPoint(x: s*0.42, y: s*0.10))
            // Inner curl
            path.addCurve(to: CGPoint(x: s*0.60, y: s*0.40),
                          controlPoint1: CGPoint(x: s*0.96, y: s*0.10),
                          controlPoint2: CGPoint(x: s*0.78, y: s*0.22))
            path.addCurve(to: CGPoint(x: s*0.40, y: s*0.60),
                          controlPoint1: CGPoint(x: s*0.46, y: s*0.56),
                          controlPoint2: CGPoint(x: s*0.40, y: s*0.58))
            purple.setStroke()
            path.lineWidth = s * 0.06
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    private static func drawDividerDots(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let s = size.width
            let colors: [UIColor] = [
                UIColor(red: 0.95, green: 0.40, blue: 0.50, alpha: 1),
                UIColor(red: 0.40, green: 0.72, blue: 0.95, alpha: 1),
                UIColor(red: 0.50, green: 0.88, blue: 0.50, alpha: 1),
                UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1),
                UIColor(red: 0.75, green: 0.42, blue: 0.90, alpha: 1),
            ]
            let r: CGFloat = s * 0.078
            let y = s / 2
            let step = s / CGFloat(colors.count + 1)
            for (i, color) in colors.enumerated() {
                let x = step * CGFloat(i + 1)
                let dot = UIBezierPath(ovalIn: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
                color.setFill(); dot.fill()
            }
        }
    }

    private static func drawSimpleFrame(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let coral = UIColor(red: 0.98, green: 0.52, blue: 0.44, alpha: 1)
            let s = size.width
            let outer = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerRadius: s*0.12)
            let inner = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10), cornerRadius: s*0.08)
            let path = UIBezierPath()
            path.append(outer); path.append(inner)
            path.usesEvenOddFillRule = true
            coral.setFill(); path.fill()
        }
    }

    private static func drawRainbow(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let s = size.width
            let cx = s / 2, cy = s * 0.78
            let bands: [(CGFloat, UIColor)] = [
                (s*0.44, UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)),
                (s*0.38, UIColor(red: 0.98, green: 0.62, blue: 0.10, alpha: 1)),
                (s*0.32, UIColor(red: 1.00, green: 0.88, blue: 0.10, alpha: 1)),
                (s*0.26, UIColor(red: 0.22, green: 0.82, blue: 0.32, alpha: 1)),
                (s*0.20, UIColor(red: 0.22, green: 0.52, blue: 0.95, alpha: 1)),
                (s*0.14, UIColor(red: 0.60, green: 0.22, blue: 0.90, alpha: 1)),
            ]
            for (r, color) in bands {
                let arc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy),
                                       radius: r,
                                       startAngle: .pi,
                                       endAngle: 0,
                                       clockwise: true)
                color.setStroke(); arc.lineWidth = s * 0.07; arc.stroke()
            }
        }
    }

    private static func drawLeaf(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let green  = UIColor(red: 0.22, green: 0.78, blue: 0.32, alpha: 1)
            let darkG  = UIColor(red: 0.10, green: 0.55, blue: 0.18, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            path.move(to: CGPoint(x: s*0.50, y: s*0.10))
            path.addCurve(to: CGPoint(x: s*0.88, y: s*0.50),
                          controlPoint1: CGPoint(x: s*0.90, y: s*0.16),
                          controlPoint2: CGPoint(x: s*0.88, y: s*0.32))
            path.addCurve(to: CGPoint(x: s*0.50, y: s*0.88),
                          controlPoint1: CGPoint(x: s*0.88, y: s*0.72),
                          controlPoint2: CGPoint(x: s*0.72, y: s*0.88))
            path.addCurve(to: CGPoint(x: s*0.12, y: s*0.50),
                          controlPoint1: CGPoint(x: s*0.28, y: s*0.88),
                          controlPoint2: CGPoint(x: s*0.12, y: s*0.72))
            path.addCurve(to: CGPoint(x: s*0.50, y: s*0.10),
                          controlPoint1: CGPoint(x: s*0.12, y: s*0.32),
                          controlPoint2: CGPoint(x: s*0.10, y: s*0.16))
            path.close()
            green.setFill(); path.fill(); darkG.setStroke(); path.lineWidth = 1.5; path.stroke()
            // Midrib
            let mid = UIBezierPath()
            mid.move(to: CGPoint(x: s*0.50, y: s*0.14))
            mid.addLine(to: CGPoint(x: s*0.50, y: s*0.84))
            darkG.withAlphaComponent(0.60).setStroke(); mid.lineWidth = 1.2; mid.stroke()
        }
    }

    private static func drawCloud(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let white  = UIColor(red: 0.96, green: 0.97, blue: 1.00, alpha: 1)
            let shadow = UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1)
            let s = size.width
            let path = UIBezierPath()
            path.addArc(withCenter: CGPoint(x: s*0.32, y: s*0.54), radius: s*0.20, startAngle: .pi/2, endAngle: -.pi/2 + .pi/4, clockwise: false)
            path.addArc(withCenter: CGPoint(x: s*0.42, y: s*0.38), radius: s*0.18, startAngle: -.pi * 0.78, endAngle: -.pi * 0.05, clockwise: true)
            path.addArc(withCenter: CGPoint(x: s*0.62, y: s*0.36), radius: s*0.20, startAngle: -.pi * 1.0, endAngle: -.pi * 0.08, clockwise: true)
            path.addArc(withCenter: CGPoint(x: s*0.76, y: s*0.52), radius: s*0.16, startAngle: -.pi/2, endAngle: .pi/2, clockwise: true)
            path.close()
            shadow.setFill(); UIBezierPath(
                roundedRect: path.bounds.offsetBy(dx: 0, dy: s*0.04),
                cornerRadius: s*0.10
            ).fill()
            white.setFill(); path.fill()
            UIColor(red: 0.70, green: 0.78, blue: 0.92, alpha: 0.50).setStroke()
            path.lineWidth = 1.2; path.stroke()
        }
    }

    private static func drawDiamond(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let blue   = UIColor(red: 0.42, green: 0.72, blue: 0.98, alpha: 1)
            let light  = UIColor(red: 0.70, green: 0.88, blue: 1.00, alpha: 1)
            let dark   = UIColor(red: 0.15, green: 0.48, blue: 0.82, alpha: 1)
            let s = size.width
            let cx = s/2
            let path = UIBezierPath()
            path.move(to:    CGPoint(x: cx,      y: s*0.08))
            path.addLine(to: CGPoint(x: s*0.86,  y: s*0.42))
            path.addLine(to: CGPoint(x: cx,      y: s*0.92))
            path.addLine(to: CGPoint(x: s*0.14,  y: s*0.42))
            path.close()
            blue.setFill(); path.fill(); dark.setStroke(); path.lineWidth = 1.5; path.stroke()
            // Facet lines
            let facet = UIBezierPath()
            facet.move(to: CGPoint(x: s*0.14, y: s*0.42))
            facet.addLine(to: CGPoint(x: cx, y: s*0.08))
            facet.addLine(to: CGPoint(x: s*0.86, y: s*0.42))
            light.setFill()
            let topFacet = UIBezierPath()
            topFacet.move(to: CGPoint(x: s*0.14, y: s*0.42))
            topFacet.addLine(to: CGPoint(x: cx, y: s*0.08))
            topFacet.addLine(to: CGPoint(x: s*0.86, y: s*0.42))
            topFacet.addLine(to: CGPoint(x: cx, y: s*0.44))
            topFacet.close()
            light.setFill(); topFacet.fill()
        }
    }

    // MARK: ──────────────────────────────────────────
    // MARK: Emoji
    // MARK: ──────────────────────────────────────────

    private static func drawHappyFace(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let yellow  = UIColor(red: 1.00, green: 0.86, blue: 0.20, alpha: 1)
            let darkY   = UIColor(red: 0.84, green: 0.62, blue: 0.00, alpha: 1)
            let s = size.width
            let face = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            yellow.setFill(); face.fill(); darkY.setStroke(); face.lineWidth = 1.5; face.stroke()
            // Eyes
            for ex in [s*0.34, s*0.66] {
                let eye = UIBezierPath(ovalIn: CGRect(x: ex - s*0.06, y: s*0.30, width: s*0.12, height: s*0.13))
                UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1).setFill(); eye.fill()
            }
            // Smile
            let smile = UIBezierPath()
            smile.move(to: CGPoint(x: s*0.28, y: s*0.60))
            smile.addCurve(to: CGPoint(x: s*0.72, y: s*0.60),
                           controlPoint1: CGPoint(x: s*0.36, y: s*0.80),
                           controlPoint2: CGPoint(x: s*0.64, y: s*0.80))
            darkY.setStroke(); smile.lineWidth = s*0.07; smile.lineCapStyle = .round; smile.stroke()
        }
    }

    private static func drawThinkingFace(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let yellow = UIColor(red: 1.00, green: 0.86, blue: 0.20, alpha: 1)
            let darkY  = UIColor(red: 0.84, green: 0.62, blue: 0.00, alpha: 1)
            let s = size.width
            let face = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            yellow.setFill(); face.fill(); darkY.setStroke(); face.lineWidth = 1.5; face.stroke()
            // Eyes
            for ex in [s*0.34, s*0.66] {
                let eye = UIBezierPath(ovalIn: CGRect(x: ex - s*0.06, y: s*0.30, width: s*0.12, height: s*0.13))
                UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1).setFill(); eye.fill()
            }
            // Smirk
            let smirk = UIBezierPath()
            smirk.move(to: CGPoint(x: s*0.28, y: s*0.64))
            smirk.addCurve(to: CGPoint(x: s*0.56, y: s*0.62),
                           controlPoint1: CGPoint(x: s*0.36, y: s*0.70),
                           controlPoint2: CGPoint(x: s*0.48, y: s*0.64))
            darkY.setStroke(); smirk.lineWidth = s*0.06; smirk.lineCapStyle = .round; smirk.stroke()
            // Hand on chin
            let hand = UIBezierPath()
            hand.move(to: CGPoint(x: s*0.60, y: s*0.62))
            hand.addCurve(to: CGPoint(x: s*0.76, y: s*0.50),
                          controlPoint1: CGPoint(x: s*0.70, y: s*0.66),
                          controlPoint2: CGPoint(x: s*0.76, y: s*0.58))
            darkY.setStroke(); hand.lineWidth = s*0.06; hand.lineCapStyle = .round; hand.stroke()
        }
    }

    private static func drawFire(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let orange = UIColor(red: 1.00, green: 0.50, blue: 0.05, alpha: 1)
            let yellow = UIColor(red: 1.00, green: 0.85, blue: 0.10, alpha: 1)
            let s = size.width
            // Outer flame
            let outer = UIBezierPath()
            outer.move(to: CGPoint(x: s*0.50, y: s*0.06))
            outer.addCurve(to: CGPoint(x: s*0.78, y: s*0.54),
                           controlPoint1: CGPoint(x: s*0.76, y: s*0.14),
                           controlPoint2: CGPoint(x: s*0.80, y: s*0.36))
            outer.addCurve(to: CGPoint(x: s*0.50, y: s*0.90),
                           controlPoint1: CGPoint(x: s*0.84, y: s*0.76),
                           controlPoint2: CGPoint(x: s*0.68, y: s*0.90))
            outer.addCurve(to: CGPoint(x: s*0.22, y: s*0.54),
                           controlPoint1: CGPoint(x: s*0.32, y: s*0.90),
                           controlPoint2: CGPoint(x: s*0.16, y: s*0.76))
            outer.addCurve(to: CGPoint(x: s*0.50, y: s*0.06),
                           controlPoint1: CGPoint(x: s*0.20, y: s*0.36),
                           controlPoint2: CGPoint(x: s*0.24, y: s*0.14))
            outer.close()
            orange.setFill(); outer.fill()
            // Inner flame
            let inner = UIBezierPath()
            inner.move(to: CGPoint(x: s*0.50, y: s*0.28))
            inner.addCurve(to: CGPoint(x: s*0.64, y: s*0.58),
                           controlPoint1: CGPoint(x: s*0.68, y: s*0.34),
                           controlPoint2: CGPoint(x: s*0.68, y: s*0.50))
            inner.addCurve(to: CGPoint(x: s*0.50, y: s*0.80),
                           controlPoint1: CGPoint(x: s*0.64, y: s*0.70),
                           controlPoint2: CGPoint(x: s*0.58, y: s*0.80))
            inner.addCurve(to: CGPoint(x: s*0.36, y: s*0.58),
                           controlPoint1: CGPoint(x: s*0.42, y: s*0.80),
                           controlPoint2: CGPoint(x: s*0.36, y: s*0.70))
            inner.addCurve(to: CGPoint(x: s*0.50, y: s*0.28),
                           controlPoint1: CGPoint(x: s*0.32, y: s*0.50),
                           controlPoint2: CGPoint(x: s*0.32, y: s*0.34))
            inner.close()
            yellow.setFill(); inner.fill()
        }
    }

    private static func drawSparkles(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let gold = UIColor(red: 1.00, green: 0.82, blue: 0.10, alpha: 1)
            let s = size.width
            func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat) {
                let path = UIBezierPath()
                for i in 0..<8 {
                    let angle = CGFloat(i) * .pi / 4
                    let outerR = i.isMultiple(of: 2) ? r : r * 0.35
                    let pt = CGPoint(x: cx + outerR * cos(angle), y: cy + outerR * sin(angle))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.close()
                gold.setFill(); path.fill()
            }
            sparkle(cx: s*0.50, cy: s*0.50, r: s*0.26)
            sparkle(cx: s*0.22, cy: s*0.24, r: s*0.14)
            sparkle(cx: s*0.78, cy: s*0.20, r: s*0.12)
            sparkle(cx: s*0.82, cy: s*0.72, r: s*0.10)
        }
    }

    private static func drawClover(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let green  = UIColor(red: 0.18, green: 0.76, blue: 0.32, alpha: 1)
            let darkG  = UIColor(red: 0.08, green: 0.52, blue: 0.18, alpha: 1)
            let s = size.width
            let cx = s / 2, cy = s / 2
            let lr = s * 0.24
            // Four leaf petals
            for angle in [CGFloat(0), .pi/2, .pi, .pi*1.5] {
                let lx = cx + cos(angle) * lr * 0.55
                let ly = cy + sin(angle) * lr * 0.55
                let leaf = UIBezierPath(ovalIn: CGRect(x: lx-lr, y: ly-lr, width: lr*2, height: lr*1.8))
                green.setFill(); leaf.fill()
            }
            // Stem
            let stem = UIBezierPath()
            stem.move(to: CGPoint(x: cx, y: cy + lr*0.6))
            stem.addLine(to: CGPoint(x: cx, y: s*0.92))
            darkG.setStroke(); stem.lineWidth = s*0.07; stem.lineCapStyle = .round; stem.stroke()
            // Center
            let center = UIBezierPath(ovalIn: CGRect(x: cx-lr*0.28, y: cy-lr*0.28, width: lr*0.56, height: lr*0.56))
            darkG.setFill(); center.fill()
        }
    }

    private static func drawSnowflake(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let ice   = UIColor(red: 0.55, green: 0.82, blue: 0.98, alpha: 1)
            let white = UIColor.white
            let s = size.width
            let cx = s/2, cy = s/2
            let arm = s * 0.42
            // 6 arms
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 6
                let spoke = UIBezierPath()
                spoke.move(to: CGPoint(x: cx, y: cy))
                spoke.addLine(to: CGPoint(x: cx + arm * cos(angle), y: cy + arm * sin(angle)))
                ice.setStroke(); spoke.lineWidth = s*0.07; spoke.lineCapStyle = .round; spoke.stroke()
                // Side branches
                for frac in [0.40, 0.65] as [CGFloat] {
                    let bx = cx + arm * frac * cos(angle)
                    let by = cy + arm * frac * sin(angle)
                    let bLen = arm * 0.22
                    for side in [-1, 1] as [CGFloat] {
                        let branch = UIBezierPath()
                        let ba = angle + side * .pi / 3
                        branch.move(to: CGPoint(x: bx, y: by))
                        branch.addLine(to: CGPoint(x: bx + bLen * cos(ba), y: by + bLen * sin(ba)))
                        ice.setStroke(); branch.lineWidth = s*0.05; branch.lineCapStyle = .round; branch.stroke()
                    }
                }
            }
            let dot = UIBezierPath(ovalIn: CGRect(x: cx - s*0.06, y: cy - s*0.06, width: s*0.12, height: s*0.12))
            white.setFill(); dot.fill(); ice.setStroke(); dot.lineWidth = 1.2; dot.stroke()
        }
    }

    private static func drawCrystalGem(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let purple = UIColor(red: 0.68, green: 0.30, blue: 0.98, alpha: 1)
            let light  = UIColor(red: 0.88, green: 0.68, blue: 1.00, alpha: 1)
            let dark   = UIColor(red: 0.42, green: 0.10, blue: 0.72, alpha: 1)
            let s = size.width
            let cx = s / 2
            // Crown (top part)
            let crown = UIBezierPath()
            crown.move(to: CGPoint(x: s*0.22, y: s*0.38))
            crown.addLine(to: CGPoint(x: s*0.36, y: s*0.14))
            crown.addLine(to: CGPoint(x: cx,     y: s*0.22))
            crown.addLine(to: CGPoint(x: s*0.64, y: s*0.14))
            crown.addLine(to: CGPoint(x: s*0.78, y: s*0.38))
            crown.close()
            light.setFill(); crown.fill(); dark.setStroke(); crown.lineWidth = 1.2; crown.stroke()
            // Pavilion (lower part)
            let pav = UIBezierPath()
            pav.move(to: CGPoint(x: s*0.22, y: s*0.38))
            pav.addLine(to: CGPoint(x: s*0.78, y: s*0.38))
            pav.addLine(to: CGPoint(x: cx,     y: s*0.86))
            pav.close()
            purple.setFill(); pav.fill(); dark.setStroke(); pav.lineWidth = 1.2; pav.stroke()
            // Facet line
            let facet = UIBezierPath()
            facet.move(to: CGPoint(x: s*0.22, y: s*0.38))
            facet.addLine(to: CGPoint(x: cx,   y: s*0.54))
            facet.addLine(to: CGPoint(x: s*0.78, y: s*0.38))
            light.withAlphaComponent(0.50).setStroke(); facet.lineWidth = 1.0; facet.stroke()
        }
    }

    private static func drawMusicNote(size: CGSize) -> UIImage {
        renderer(size: size).image { _ in
            let purple = UIColor(red: 0.55, green: 0.25, blue: 0.90, alpha: 1)
            let s = size.width
            // Notehead
            let head = UIBezierPath(ovalIn: CGRect(x: s*0.18, y: s*0.60, width: s*0.28, height: s*0.22))
            head.apply(CGAffineTransform(rotationAngle: -.pi/10)
                .concatenating(CGAffineTransform(translationX: s*0.06, y: s*0.04)))
            purple.setFill(); head.fill()
            // Stem
            let stem = UIBezierPath()
            stem.move(to: CGPoint(x: s*0.45, y: s*0.70))
            stem.addLine(to: CGPoint(x: s*0.45, y: s*0.16))
            purple.setStroke(); stem.lineWidth = s*0.075; stem.lineCapStyle = .round; stem.stroke()
            // Flag
            let flag = UIBezierPath()
            flag.move(to: CGPoint(x: s*0.45, y: s*0.18))
            flag.addCurve(to: CGPoint(x: s*0.76, y: s*0.38),
                          controlPoint1: CGPoint(x: s*0.68, y: s*0.18),
                          controlPoint2: CGPoint(x: s*0.78, y: s*0.28))
            flag.addCurve(to: CGPoint(x: s*0.45, y: s*0.46),
                          controlPoint1: CGPoint(x: s*0.78, y: s*0.50),
                          controlPoint2: CGPoint(x: s*0.60, y: s*0.46))
            purple.setStroke(); flag.lineWidth = s*0.06; flag.lineCapStyle = .round; flag.stroke()
        }
    }
}
