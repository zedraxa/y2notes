import SwiftUI

// MARK: - Cover Texture Overlay

/// Procedurally-drawn surface texture rendered over a notebook cover gradient
/// or custom photo. Uses SwiftUI `Canvas` for pixel-level detail without any
/// bitmap assets.
struct CoverTextureOverlay: View {
    let texture: CoverTexture
    let size: CGSize

    /// Master opacity for the entire texture layer (0…1).
    var intensity: Double = 1.0

    @ViewBuilder
    var body: some View {
        if texture == .smooth {
            Color.clear.frame(width: size.width, height: size.height)
        } else {
            Canvas { context, canvasSize in
                switch texture {
                case .smooth:
                    break
                case .leather:
                    drawLeather(context: context, size: canvasSize)
                case .linen:
                    drawLinen(context: context, size: canvasSize)
                case .canvas:
                    drawCanvas(context: context, size: canvasSize)
                case .cloth:
                    drawCloth(context: context, size: canvasSize)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(intensity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Leather

    /// Subtle pebbled grain — scattered micro-ellipses with slight variation.
    private func drawLeather(context: GraphicsContext, size: CGSize) {
        let cols = Int(size.width / 4)
        let rows = Int(size.height / 4)
        let dark = GraphicsContext.Shading.color(.black.opacity(0.06))
        let light = GraphicsContext.Shading.color(.white.opacity(0.04))

        for row in 0..<rows {
            for col in 0..<cols {
                let seed = (row &* 7 + col &* 13) & 0xFF
                guard seed % 3 != 0 else { continue }
                let x = CGFloat(col) * 4 + CGFloat(seed % 3)
                let y = CGFloat(row) * 4 + CGFloat((seed >> 2) % 3)
                let w: CGFloat = 2.0 + CGFloat(seed % 2)
                let h: CGFloat = 1.5 + CGFloat((seed >> 1) % 2)
                let shading = seed % 2 == 0 ? dark : light
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: shading)
            }
        }
    }

    // MARK: - Linen

    /// Horizontal + vertical micro-lines at a fine pitch, creating a woven look.
    private func drawLinen(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 3
        let h = GraphicsContext.Shading.color(.white.opacity(0.05))
        let v = GraphicsContext.Shading.color(.black.opacity(0.04))

        // Horizontal threads
        var y: CGFloat = 0
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: h, lineWidth: 0.5)
            y += spacing
        }

        // Vertical threads
        var x: CGFloat = 0
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: v, lineWidth: 0.5)
            x += spacing
        }
    }

    // MARK: - Canvas (woven crosshatch)

    /// Denser crosshatch pattern with alternating opacity, mimicking a woven canvas.
    private func drawCanvas(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 5
        let a = GraphicsContext.Shading.color(.black.opacity(0.05))
        let b = GraphicsContext.Shading.color(.white.opacity(0.04))

        var idx = 0
        var y: CGFloat = 0
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: idx % 2 == 0 ? a : b, lineWidth: 0.7)
            y += spacing
            idx += 1
        }
        idx = 0
        var x: CGFloat = 0
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: idx % 2 == 0 ? b : a, lineWidth: 0.7)
            x += spacing
            idx += 1
        }

        // Diagonal accent every other cell
        var ry: CGFloat = 0
        while ry < size.height {
            var rx: CGFloat = (Int(ry / spacing) % 2 == 0) ? 0 : spacing
            while rx < size.width {
                var diag = Path()
                diag.move(to: CGPoint(x: rx, y: ry))
                diag.addLine(to: CGPoint(x: rx + spacing, y: ry + spacing))
                context.stroke(diag, with: .color(.black.opacity(0.02)), lineWidth: 0.4)
                rx += spacing * 2
            }
            ry += spacing
        }
    }

    // MARK: - Cloth (soft ribbed)

    /// Soft ribbed texture with horizontal emphasis, like book cloth.
    private func drawCloth(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 2.5
        let rib = GraphicsContext.Shading.color(.black.opacity(0.04))
        let highlight = GraphicsContext.Shading.color(.white.opacity(0.035))

        var y: CGFloat = 0
        var idx = 0
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: idx % 2 == 0 ? rib : highlight, lineWidth: 0.6)
            y += spacing
            idx += 1
        }
    }
}

// MARK: - Embossed Title Overlay

/// Renders a notebook title with a debossed/embossed foil look using multiple
/// offset layers and blend modes.
struct CoverEmbossedTitle: View {
    let text: String
    let maxWidth: CGFloat

    @ViewBuilder
    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            ZStack {
                // Shadow layer (pushed inward)
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(.black.opacity(0.30))
                    .offset(x: 0.5, y: 0.5)

                // Highlight layer (raised edge)
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.22))
                    .offset(x: -0.4, y: -0.4)

                // Main text
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: maxWidth)
        }
    }
}

// MARK: - Page Edge Effect

/// Draws thin stacked lines on the right side of a cover to simulate visible
/// page edges, like looking at a closed hardcover notebook from the side.
struct CoverPageEdge: View {
    let height: CGFloat
    let lineCount: Int

    init(height: CGFloat, lineCount: Int = 6) {
        self.height = height
        self.lineCount = lineCount
    }

    var body: some View {
        Canvas { context, size in
            let edgeWidth = size.width
            let spacing = edgeWidth / CGFloat(lineCount + 1)
            for i in 1...lineCount {
                let x = spacing * CGFloat(i)
                let topInset: CGFloat = 4 + CGFloat(i) * 0.5
                let bottomInset: CGFloat = 4 + CGFloat(i) * 0.5
                var path = Path()
                path.move(to: CGPoint(x: x, y: topInset))
                path.addLine(to: CGPoint(x: x, y: size.height - bottomInset))
                let alpha = 0.08 + Double(lineCount - i) * 0.015
                context.stroke(path, with: .color(.primary.opacity(alpha)), lineWidth: 0.5)
            }
        }
        .frame(width: 8, height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Spine Stitching

/// Draws tiny evenly-spaced dots along the spine to simulate thread stitching.
struct CoverSpineStitching: View {
    let height: CGFloat
    let dotCount: Int

    init(height: CGFloat, dotCount: Int = 12) {
        self.height = height
        self.dotCount = dotCount
    }

    var body: some View {
        Canvas { context, size in
            let spacing = size.height / CGFloat(dotCount + 1)
            let centerX = size.width / 2
            for i in 1...dotCount {
                let y = spacing * CGFloat(i)
                let radius: CGFloat = 0.7
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centerX - radius, y: y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(.white.opacity(0.30))
                )
            }
        }
        .frame(width: 6, height: height)
        .allowsHitTesting(false)
    }
}
