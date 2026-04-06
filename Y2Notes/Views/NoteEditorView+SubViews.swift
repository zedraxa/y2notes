import SwiftUI

// MARK: - NoteEditorView+SubViews

extension NoteEditorView {

    // MARK: - Contrast Banner

    var contrastBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.fill")
                .font(.caption2)
            Text("Dark canvas — use a light ink colour for best contrast")
                .font(.caption2)
        }
        .foregroundStyle(Color(uiColor: effectiveDefinition.secondaryText))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: effectiveDefinition.canvasBackground).opacity(0.8))
    }

    // MARK: - Focus Mode Overlay

    /// Full-screen SwiftUI overlay combining background dimming and a radial
    /// vignette.  Layered behind toolbar capsules (zIndex 0.4) but above the
    /// canvas, so it dims chrome without intercepting touch input.
    @ViewBuilder
    var focusModeOverlay: some View {
        ZStack {
            // Background dim — very subtle darkening of the entire view.
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            // Radial vignette — darkens edges, clear centre.
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.15)
                ]),
                center: .center,
                startRadius: 80,
                endRadius: UIScreen.main.bounds.height * 0.55
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Ambient Scene Overlay

    /// Lightweight SwiftUI tint overlay for the active ambient scene.
    /// The heavy lifting (rain streaks, grain, warm wash) is handled via
    /// CALayers in `AmbientEnvironmentEngine` — this overlay just adds
    /// a subtle colour tint that auto-sizes on rotation.
    @ViewBuilder
    var ambientSceneOverlay: some View {
        switch toolStore.activeAmbientScene {
        case .rainStudy:
            // Cool blue-grey tint.
            Color(red: 0.6, green: 0.72, blue: 0.88).opacity(0.05)
                .ignoresSafeArea()
        case .lofiLight:
            // Warm amber tint.
            Color(red: 1.0, green: 0.92, blue: 0.76).opacity(0.04)
                .ignoresSafeArea()
        case .nightGrain:
            // Cool dark blue tint.
            Color(red: 0.15, green: 0.18, blue: 0.28).opacity(0.06)
                .ignoresSafeArea()
        case .none:
            EmptyView()
        }
    }

    // MARK: - Save State Indicator

    /// Compact toolbar indicator that reflects the current disk-write state.
    /// - Spinning icon while saving (transitions quickly; mostly visible on slow storage).
    /// - Checkmark shown for 2 s after a successful save.
    /// - Warning triangle shown (persistently) when a save error has occurred.
    @ViewBuilder
    var saveStateIndicator: some View {
        switch noteStore.saveState {
        case .saving:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)
                .accessibilityLabel("Saving")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("Save error")
        case .saved where showSavedBadge:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .accessibilityLabel("Saved")
        default:
            EmptyView()
        }
    }

    // MARK: - Linked Import Banner

    /// Tappable banner shown below the title when this note is linked to an imported document.
    /// Shows the source file name and type; tapping opens the linked file in its viewer tab.
    var linkedImportBanner: some View {
        HStack(spacing: 8) {
            Button(action: openLinkedImport) {
                HStack(spacing: 8) {
                    Image(systemName: linkedImportIcon)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(
                            format: NSLocalizedString("Import.LinkedTo", comment: ""),
                            linkedImportTitle
                        ))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(linkedImportSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                format: NSLocalizedString("Import.LinkedTo", comment: ""),
                linkedImportTitle
            ))

            Button {
                showUnlinkConfirm = true
            } label: {
                Image(systemName: "link.badge.minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
                    .padding(.trailing, 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Import.Unlink", comment: ""))
        }
        .background(Color.accentColor.opacity(0.08))
        .alert(
            NSLocalizedString("Import.UnlinkTitle", comment: ""),
            isPresented: $showUnlinkConfirm
        ) {
            Button(NSLocalizedString("Import.Unlink", comment: ""), role: .destructive) {
                noteStore.unlinkCompanionNote(id: note.id)
            }
            Button(NSLocalizedString("Common.Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Import.UnlinkMessage", comment: ""))
        }
    }

    var linkedImportIcon: String {
        if note.linkedPDFID != nil { return "doc.richtext" }
        return "doc"
    }

    var linkedImportTitle: String {
        if let pdfID = note.linkedPDFID,
           let record = pdfStore.records.first(where: { $0.id == pdfID }) {
            return record.title
        }
        if let docID = note.linkedDocumentID,
           let doc = documentStore.documents.first(where: { $0.id == docID }) {
            return doc.displayName
        }
        return NSLocalizedString("Import.SourceDeleted", comment: "")
    }

    var linkedImportSubtitle: String {
        if note.linkedPDFID != nil {
            if pdfStore.records.first(where: { $0.id == note.linkedPDFID }) != nil {
                return "PDF Document — " + NSLocalizedString("Import.TapToOpen", comment: "")
            }
            return NSLocalizedString("Import.SourceDeleted", comment: "")
        }
        if let docID = note.linkedDocumentID,
           let doc = documentStore.documents.first(where: { $0.id == docID }) {
            return "\(doc.documentType.displayName) — " + NSLocalizedString("Import.TapToOpen", comment: "")
        }
        return NSLocalizedString("Import.SourceDeleted", comment: "")
    }

    // MARK: - Title Field

    var titleField: some View {
        TextField("Note title", text: $titleText)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: titleText) { _, newValue in
                noteStore.updateTitle(for: note.id, title: newValue)
            }
    }

    // MARK: - In-document find bar

    /// Compact find bar shown between the toolbar and the canvas.
    /// Searches the note's `typedText`; shows a count and previous/next navigation.
    /// For drawing-only notes (empty typedText) it shows a context message.
    var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField("Find in note…", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onChange(of: findQuery) { _, _ in updateFindMatches() }
                .submitLabel(.search)
                .onSubmit { advanceFindMatch(forward: true) }

            if !findMatches.isEmpty {
                Text("\(findMatchIndex + 1)/\(findMatches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else if !findQuery.isEmpty {
                Text(note.typedText.isEmpty && note.ocrText.isEmpty ? "Drawing only" : "0 results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            if !findMatches.isEmpty {
                Button {
                    advanceFindMatch(forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(findMatches.count <= 1)
                .accessibilityLabel("Previous match")

                Button {
                    advanceFindMatch(forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(findMatches.count <= 1)
                .accessibilityLabel("Next match")
            }

            Button {
                showFindBar = false
                findQuery = ""
                findMatches = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Typed text layer

    /// Full-height scrollable text editor shown when the user is in keyboard (text) mode.
    /// Uses the note's effective theme for background and text colours.
    var textLayer: some View {
        TextEditor(text: $typedTextContent)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: effectiveDefinition.canvasBackground))
            .foregroundStyle(Color(uiColor: effectiveDefinition.primaryText))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: typedTextContent) { _, _ in scheduleTextSave() }
    }

    // MARK: - Page navigation (book-like experience)

    /// Horizontal bar with prev/next buttons, page indicator, overview, and add-page action.
    var pageNavigationBar: some View {
        HStack(spacing: 16) {
            // Previous page
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPageIndex = max(0, currentPageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex <= 0)
            .accessibilityLabel("Previous page")

            Spacer()

            // Page overview button — opens the grid view
            Button {
                showPageOverview = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                    Text("Page \(currentPageIndex + 1) of \(note.pageCount)")
                        .font(.subheadline.monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Page \(currentPageIndex + 1) of \(note.pageCount). Tap to open page overview.")

            Spacer()

            // Add page
            Button {
                if let newIndex = noteStore.addPage(to: note.id) {
                    isNewPageJustAdded = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPageIndex = newIndex
                    }
                    // Reset the flag after the CA reveal animation completes.
                    // The delay (0.55 s) intentionally exceeds the SwiftUI navigation
                    // animation (0.25 s) to ensure the new CanvasView is fully
                    // displayed before the flag resets, preventing a double-reveal
                    // if SwiftUI re-renders during the transition.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        isNewPageJustAdded = false
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Add page")

            // Next page
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentPageIndex = min(note.pageCount - 1, currentPageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentPageIndex >= note.pageCount - 1)
            .accessibilityLabel("Next page")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85))
    }
}
