import SwiftUI

// MARK: - Note creation sheet

/// GoodNotes-style note creation sheet that lets the user pick a paper type
/// and material before creating a new note. Presented as a compact sheet from
/// the "+" New menu in the library grid.
struct NoteCreationSheet: View {
    @EnvironmentObject var noteStore: NoteStore

    /// When non-nil the new note will be filed into this notebook.
    let notebookID: UUID?

    /// Called after a note is created, passing the new note's ID.
    let onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPageType: PageType = .ruled
    @State private var selectedMaterial: PaperMaterial = .standard

    private let selectionFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let confirmFeedback   = UINotificationFeedbackGenerator()

    // Two-column grid for the paper type cards.
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Paper type ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paper Type")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(PageType.allCases) { pt in
                                PaperTypeCard(
                                    pageType: pt,
                                    isSelected: selectedPageType == pt
                                )
                                .onTapGesture {
                                    if selectedPageType != pt {
                                        selectionFeedback.impactOccurred()
                                        selectedPageType = pt
                                    }
                                }
                            }
                        }
                    }

                    // ── Paper material ─────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paper Material")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(PaperMaterial.allCases) { pm in
                                    MaterialChip(
                                        material: pm,
                                        isSelected: selectedMaterial == pm
                                    )
                                    .onTapGesture {
                                        if selectedMaterial != pm {
                                            selectionFeedback.impactOccurred(intensity: 0.6)
                                            selectedMaterial = pm
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }

                    // ── Live preview ──────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        PaperPreview(pageType: selectedPageType, material: selectedMaterial)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(uiColor: .secondaryLabel).opacity(0.2), lineWidth: 1)
                            )
                            .transition(.opacity)
                            .id("\(selectedPageType.rawValue)-\(selectedMaterial.rawValue)")
                            .animation(.easeInOut(duration: 0.2), value: selectedPageType)
                            .animation(.easeInOut(duration: 0.2), value: selectedMaterial)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createNote() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func createNote() {
        confirmFeedback.notificationOccurred(.success)
        let note = noteStore.addNote(
            inNotebook: notebookID,
            pageType: selectedPageType,
            paperMaterial: selectedMaterial
        )
        onCreated(note.id)
        dismiss()
    }
}

// MARK: - Paper type card

/// Visual card representing a single page type (blank, ruled, dot, grid).
/// Tapping selects it. Mimics GoodNotes' template thumbnail grid.
private struct PaperTypeCard: View {
    let pageType: PageType
    let isSelected: Bool

    @GestureState private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            // Mini paper preview
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .frame(height: 90)

                paperRuling
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 4, y: 2)

            VStack(spacing: 2) {
                Text(pageType.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .label))
                Text(pageType.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(pageType.displayName) paper")
    }

    @ViewBuilder
    private var paperRuling: some View {
        Canvas { ctx, size in
            let lineColor = Color(uiColor: .secondaryLabel).opacity(0.18)
            switch pageType {
            case .blank:
                break
            case .ruled:
                let spacing: CGFloat = 12
                var y: CGFloat = spacing + 4
                while y < size.height {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: 8, y: y)); p.addLine(to: .init(x: size.width - 8, y: y)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    y += spacing
                }
            case .dot:
                let spacing: CGFloat = 10
                var y: CGFloat = spacing
                while y < size.height {
                    var x: CGFloat = spacing
                    while x < size.width {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                            with: .color(lineColor)
                        )
                        x += spacing
                    }
                    y += spacing
                }
            case .cornell:
                // Vertical margin line + header + summary + light body ruling
                let marginX: CGFloat = size.width * 0.28
                let headerY: CGFloat = 16
                let summaryY: CGFloat = size.height - 12
                // Structure lines
                ctx.stroke(
                    Path { p in p.move(to: .init(x: marginX, y: 0)); p.addLine(to: .init(x: marginX, y: size.height)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: headerY)); p.addLine(to: .init(x: size.width, y: headerY)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: summaryY)); p.addLine(to: .init(x: size.width, y: summaryY)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                // Body ruling
                let spacing: CGFloat = 12
                var y: CGFloat = headerY + spacing
                while y < summaryY - 1 {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: marginX, y: y)); p.addLine(to: .init(x: size.width - 4, y: y)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    y += spacing
                }
            case .hexagonal:
                let r: CGFloat = 8.0
                let colStep = r * sqrt(3.0)
                let rowStep = r * 1.5
                let cols = Int(ceil(size.width  / colStep)) + 2
                let rows = Int(ceil(size.height / rowStep)) + 2
                for row in -1 ..< rows {
                    for col in -1 ..< cols {
                        let ox: CGFloat = (row & 1) != 0 ? colStep * 0.5 : 0
                        let cx = CGFloat(col) * colStep + ox
                        let cy = CGFloat(row) * rowStep
                        var hex = Path()
                        let start: CGFloat = .pi / 2
                        let step2: CGFloat = .pi / 3
                        hex.move(to: .init(x: cx + r * cos(start), y: cy - r * sin(start)))
                        for i in 1 ..< 6 {
                            let a = start + CGFloat(i) * step2
                            hex.addLine(to: .init(x: cx + r * cos(a), y: cy - r * sin(a)))
                        }
                        hex.closeSubpath()
                        ctx.stroke(hex, with: .color(lineColor), lineWidth: 0.5)
                    }
                }
            case .music:
                let lineGap:   CGFloat = 4
                let staffGap:  CGFloat = 18
                let staffH:    CGFloat = lineGap * 4
                let pitch:     CGFloat = staffH + staffGap
                var topY: CGFloat = staffGap * 0.5
                while topY <= size.height + pitch {
                    for lineIdx in 0 ..< 5 {
                        let y = topY + CGFloat(lineIdx) * lineGap
                        guard y <= size.height else { break }
                        ctx.stroke(
                            Path { p in p.move(to: .init(x: 4, y: y)); p.addLine(to: .init(x: size.width - 4, y: y)) },
                            with: .color(lineColor), lineWidth: 0.5
                        )
                    }
                    topY += pitch
                }
            case .grid:
                let gridSpacing: CGFloat = 10
                var pos: CGFloat = gridSpacing
                while pos < size.width {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: pos, y: 0)); p.addLine(to: .init(x: pos, y: size.height)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    pos += gridSpacing
                }
                pos = gridSpacing
                while pos < size.height {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: 0, y: pos)); p.addLine(to: .init(x: size.width, y: pos)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    pos += gridSpacing
                }
            }
        }
    }
}

// MARK: - Material chip

/// Horizontally scrollable chip for paper material selection.
private struct MaterialChip: View {
    let material: PaperMaterial
    let isSelected: Bool

    @GestureState private var isPressed = false

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(material.pageTint)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel).opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
                )
                .overlay(
                    Image(systemName: material.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 3, y: 1)

            Text(material.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .scaleEffect(isPressed ? 0.88 : (isSelected ? 1.06 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(material.displayName) paper")
    }
}

// MARK: - Paper preview

/// Renders a larger preview of the selected paper type + material combination.
private struct PaperPreview: View {
    let pageType: PageType
    let material: PaperMaterial

    var body: some View {
        Canvas { ctx, size in
            // Background fill with material tint
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(material.pageTint))

            let lineColor = Color(uiColor: .secondaryLabel).opacity(0.15)

            switch pageType {
            case .blank:
                break
            case .ruled:
                let spacing: CGFloat = 20
                var y: CGFloat = spacing + 8
                while y < size.height {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: 16, y: y)); p.addLine(to: .init(x: size.width - 16, y: y)) },
                        with: .color(lineColor), lineWidth: 0.8
                    )
                    y += spacing
                }
            case .dot:
                let spacing: CGFloat = 16
                var y: CGFloat = spacing
                while y < size.height {
                    var x: CGFloat = spacing
                    while x < size.width {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)),
                            with: .color(lineColor)
                        )
                        x += spacing
                    }
                    y += spacing
                }
            case .grid:
                let spacing: CGFloat = 16
                var pos: CGFloat = spacing
                while pos < size.width {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: pos, y: 0)); p.addLine(to: .init(x: pos, y: size.height)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    pos += spacing
                }
                pos = spacing
                while pos < size.height {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: 0, y: pos)); p.addLine(to: .init(x: size.width, y: pos)) },
                        with: .color(lineColor), lineWidth: 0.5
                    )
                    pos += spacing
                }
            case .cornell:
                let marginX: CGFloat = size.width * 0.28
                let headerY: CGFloat = 24
                let summaryY: CGFloat = size.height - 20
                ctx.stroke(
                    Path { p in p.move(to: .init(x: marginX, y: 0)); p.addLine(to: .init(x: marginX, y: size.height)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: headerY)); p.addLine(to: .init(x: size.width, y: headerY)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: summaryY)); p.addLine(to: .init(x: size.width, y: summaryY)) },
                    with: .color(lineColor), lineWidth: 0.75
                )
                let bodySpacing: CGFloat = 20
                var y: CGFloat = headerY + bodySpacing
                while y < summaryY - 1 {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x: marginX, y: y)); p.addLine(to: .init(x: size.width - 16, y: y)) },
                        with: .color(lineColor), lineWidth: 0.8
                    )
                    y += bodySpacing
                }
            case .hexagonal:
                let r: CGFloat = 12.0
                let colStep = r * sqrt(3.0)
                let rowStep = r * 1.5
                let cols = Int(ceil(size.width  / colStep)) + 2
                let rows = Int(ceil(size.height / rowStep)) + 2
                for row in -1 ..< rows {
                    for col in -1 ..< cols {
                        let ox: CGFloat = (row & 1) != 0 ? colStep * 0.5 : 0
                        let cx = CGFloat(col) * colStep + ox
                        let cy = CGFloat(row) * rowStep
                        var hex = Path()
                        let startA: CGFloat = .pi / 2
                        let stepA:  CGFloat = .pi / 3
                        hex.move(to: .init(x: cx + r * cos(startA), y: cy - r * sin(startA)))
                        for i in 1 ..< 6 {
                            let a = startA + CGFloat(i) * stepA
                            hex.addLine(to: .init(x: cx + r * cos(a), y: cy - r * sin(a)))
                        }
                        hex.closeSubpath()
                        ctx.stroke(hex, with: .color(lineColor), lineWidth: 0.5)
                    }
                }
            case .music:
                let lineGap:  CGFloat = 5
                let staffGap: CGFloat = 28
                let staffH:   CGFloat = lineGap * 4
                let pitch:    CGFloat = staffH + staffGap
                var topY: CGFloat = staffGap * 0.5
                while topY <= size.height + pitch {
                    for lineIdx in 0 ..< 5 {
                        let y = topY + CGFloat(lineIdx) * lineGap
                        guard y <= size.height else { break }
                        ctx.stroke(
                            Path { p in p.move(to: .init(x: 16, y: y)); p.addLine(to: .init(x: size.width - 16, y: y)) },
                            with: .color(lineColor), lineWidth: 0.6
                        )
                    }
                    topY += pitch
                }
            }
        }
    }
}
