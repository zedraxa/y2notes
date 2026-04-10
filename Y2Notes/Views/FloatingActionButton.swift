import SwiftUI

// MARK: - FloatingActionButton

/// Persistent FAB (bottom-right corner) for quick creation actions.
///
/// Visible in sidebar, home, and grid views. Auto-hides when the
/// note editor is active (the floating drawing toolbar takes over).
///
/// Tap → expands to show Quick Note, New Note…, New Notebook…, Import.
struct FloatingActionButton: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var pdfStore: PDFStore
    @Environment(TabWorkspaceStore.self) private var tabSession

    /// Called when a new note is created via quick-note.
    let onSelectNote: (UUID) -> Void

    @State private var isExpanded = false
    @State private var showNoteCreationSheet = false
    @State private var showNotebookWizard = false
    @State private var showPDFImporter = false

    private let buttonSize: CGFloat = 56
    private let miniButtonSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isExpanded {
                // Mini action buttons — stacked above the main FAB
                FABMiniButton(
                    title: NSLocalizedString("FAB.ImportPDF", comment: ""),
                    systemImage: "doc.fill",
                    tint: .orange
                ) {
                    isExpanded = false
                    showPDFImporter = true
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.4).combined(with: .opacity).combined(with: .offset(y: 20)),
                    removal: .scale(scale: 0.6).combined(with: .opacity)
                ))

                FABMiniButton(
                    title: NSLocalizedString("FAB.NewNotebook", comment: ""),
                    systemImage: "book.closed.fill",
                    tint: .purple
                ) {
                    isExpanded = false
                    showNotebookWizard = true
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.4).combined(with: .opacity).combined(with: .offset(y: 14)),
                    removal: .scale(scale: 0.6).combined(with: .opacity)
                ))

                FABMiniButton(
                    title: NSLocalizedString("FAB.NewNote", comment: ""),
                    systemImage: "doc.badge.plus",
                    tint: .green
                ) {
                    isExpanded = false
                    showNoteCreationSheet = true
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.4).combined(with: .opacity).combined(with: .offset(y: 8)),
                    removal: .scale(scale: 0.6).combined(with: .opacity)
                ))

                FABMiniButton(
                    title: NSLocalizedString("FAB.QuickNote", comment: ""),
                    systemImage: "square.and.pencil",
                    tint: .blue
                ) {
                    isExpanded = false
                    let note = noteStore.addNote()
                    onSelectNote(note.id)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.4).combined(with: .opacity).combined(with: .offset(y: 4)),
                    removal: .scale(scale: 0.6).combined(with: .opacity)
                ))
            }

            // Main FAB button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 4)
                    )
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded
                ? NSLocalizedString("FAB.Close", comment: "")
                : NSLocalizedString("FAB.Create", comment: ""))
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .sheet(isPresented: $showNoteCreationSheet) {
            NoteCreationSheet(onCreated: { id in onSelectNote(id) })
        }
        .sheet(isPresented: $showNotebookWizard) {
            NotebookQuickCreator()
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let record = pdfStore.importPDF(from: url) {
                    tabSession.openTab(
                        .pdf(id: record.id),
                        displayName: record.title,
                        accentColor: [0.8, 0.3, 0.3]
                    )
                }
            }
        }
    }
}

// MARK: - FAB Mini Button

private struct FABMiniButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint))
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
