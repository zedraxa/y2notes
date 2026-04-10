import SwiftUI

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
