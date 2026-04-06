import SwiftUI

// MARK: - NoteEditorView+Toolbars

extension NoteEditorView {

    // MARK: - Floating Toolbar Overlay

    /// Floating toolbar capsule — bottom-center, above page navigation bar.
    @ViewBuilder
    var floatingToolbarOverlay: some View {
        if !isTextMode {
            VStack {
                Spacer()
                FloatingToolbarCapsule(
                    toolStore: toolStore,
                    inkStore: inkStore,
                    stickerStore: stickerStore,
                    canUndo: canUndo,
                    canRedo: canRedo,
                    onUndo: { undoManager?.undo() },
                    onRedo: { undoManager?.redo() },
                    onOpenInspector: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showAdvancedPanel.toggle()
                        }
                    },
                    onSelectionAction: { action in
                        handleSelectionAction(action)
                    }
                )
                .opacity(toolStore.toolbarOpacity)
                .animation(.easeInOut(duration: 0.3), value: toolStore.toolbarOpacity)
                .allowsHitTesting(toolStore.toolbarOpacity > 0.5)
                .padding(.bottom, 8)
            }
            .zIndex(0.5)
        }
    }

    // MARK: - Selection Action Bars

    /// Shape / attachment / widget action bars — appear when an object is selected.
    @ViewBuilder
    var selectionActionBars: some View {
        // Shape action bar
        if toolStore.hasActiveShapeSelection,
           let selectedID = toolStore.activeShapeSelection,
           let selectedShape = note.shapes(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                ShapeHandlesView(
                    toolStore: toolStore,
                    selectedShape: selectedShape,
                    onAction: { action in
                        handleShapeAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.6)
        }

        // Attachment action bar
        if toolStore.hasActiveAttachmentSelection,
           let selectedID = toolStore.activeAttachmentSelection,
           let selectedAttachment = note.attachments(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                AttachmentHandlesView(
                    attachment: selectedAttachment,
                    onAction: { action in
                        handleAttachmentAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.7)
        }

        // Widget action bar
        if toolStore.hasActiveWidgetSelection,
           let selectedID = toolStore.activeWidgetSelection,
           let selectedWidget = note.widgets(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                WidgetHandlesView(
                    widget: selectedWidget,
                    onAction: { action in
                        handleWidgetAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.75)
        }

        // Text object action bar
        if toolStore.hasActiveTextObjectSelection,
           let selectedID = toolStore.activeTextObjectSelection,
           let selectedTextObject = note.textObjects(forPage: currentPageIndex).first(where: { $0.id == selectedID }) {
            VStack {
                TextObjectHandlesView(
                    textObject: selectedTextObject,
                    onAction: { action in
                        handleTextObjectAction(action, for: selectedID)
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                Spacer()
            }
            .padding(.top, 60)
            .zIndex(0.8)
        }
    }

    // MARK: - Advanced Panel Overlay

    /// Advanced tools inspector — slides in from the right.
    @ViewBuilder
    var advancedPanelOverlay: some View {
        if showAdvancedPanel {
            AdvancedToolsPanel(toolStore: toolStore, isPresented: $showAdvancedPanel)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(1)
        }
    }

    // MARK: - Effect Overlays

    /// Focus-mode and ambient scene overlays.
    @ViewBuilder
    var effectOverlays: some View {
        // Focus-mode ambient overlays — vignette + dim.
        if toolStore.isFocusModeActive {
            focusModeOverlay
                .zIndex(0.4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }

        // Ambient environment scene indicator.
        if toolStore.activeAmbientScene != nil {
            ambientSceneOverlay
                .zIndex(0.35)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Trailing Toolbar Content

    /// Trailing navigation bar toolbar items.
    @ViewBuilder
    var trailingToolbarContent: some View {
        noteThemeMenu

        // Page setup menu — GoodNotes-style per-page paper type & material picker.
        pageSetupMenu

        // Create flashcard from this note.
        Button {
            showCreateFlashcard = true
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
        }
        .accessibilityLabel("Create Flashcard")

        // Export menu — PDF (single page), PDF (all pages), PNG image.
        exportMenu

        // Version history browser.
        Button {
            showVersionHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("Version History")

        // Import document into the library.
        Button {
            showDocumentImporter = true
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .accessibilityLabel("Import document")

        // Open the PDF or document that this note was created for, if any.
        if note.linkedPDFID != nil || note.linkedDocumentID != nil {
            Button {
                openLinkedImport()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .accessibilityLabel("Open linked document")
        }

        // Draw ↔ Type mode toggle.
        // "keyboard" switches to text mode; "pencil" returns to drawing mode.
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flushTextNow()
            isTextMode.toggle()
        } label: {
            Image(systemName: isTextMode ? "pencil" : "keyboard")
        }
        .accessibilityLabel(isTextMode ? "Switch to drawing mode" : "Switch to text mode")

        // In-document find bar toggle.
        Button {
            showFindBar.toggle()
            if !showFindBar {
                findQuery = ""
                findMatches = []
            }
        } label: {
            Image(systemName: showFindBar ? "magnifyingglass.circle.fill" : "magnifyingglass")
        }
        .accessibilityLabel(showFindBar ? "Hide find bar" : "Find in note")

        if !isTextMode {
            // Finger / Pencil drawing policy toggle.
            Button {
                pencilOnlyDrawing.toggle()
            } label: {
                Image(systemName: pencilOnlyDrawing ? "pencil.tip" : "hand.and.pencil")
            }
            .accessibilityLabel(
                pencilOnlyDrawing ? "Enable finger drawing" : "Enable Pencil-only drawing"
            )

            // Zoom reset — animates the canvas back to 1× scale.
            Button {
                zoomResetTrigger.toggle()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Fit page to screen")

            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .accessibilityLabel("Redo")
        }
    }

    // MARK: - Note Theme Menu

    var noteThemeMenu: some View {
        Menu {
            Button {
                noteStore.updateThemeOverride(for: note.id, theme: nil)
            } label: {
                if note.themeOverride == nil {
                    Label("App Theme", systemImage: "checkmark")
                } else {
                    Text("App Theme")
                }
            }
            Divider()
            ForEach(AppTheme.allCases) { theme in
                Button {
                    noteStore.updateThemeOverride(for: note.id, theme: theme)
                } label: {
                    if note.themeOverride == theme {
                        Label(theme.displayName, systemImage: "checkmark")
                    } else {
                        Label(theme.displayName, systemImage: theme.systemImage)
                    }
                }
                .disabled(theme.isPremium)
            }
        } label: {
            Image(systemName: note.themeOverride == nil ? "paintbrush" : "paintbrush.fill")
                .accessibilityLabel("Note theme")
        }
    }

    // MARK: - Page Setup Menu

    /// GoodNotes-style page setup menu — lets users change the page ruling and paper material
    /// for the current note without leaving the editor.
    var pageSetupMenu: some View {
        let currentPagePT = effectivePageType(forPage: safePageIndex)
        return Menu {
            // Per-page ruling section — only changes the current page
            Section("This Page") {
                ForEach(PageType.allCases) { pt in
                    Button {
                        noteStore.updatePageType(for: note.id, pageIndex: safePageIndex, pageType: pt)
                    } label: {
                        if currentPagePT == pt {
                            Label(pt.displayName, systemImage: "checkmark")
                        } else {
                            Label(pt.displayName, systemImage: pt.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Note-level ruling — applies to all pages that have no per-page override
            Section("All Pages") {
                ForEach(PageType.allCases) { pt in
                    Button {
                        noteStore.updatePageType(for: note.id, pageType: pt)
                    } label: {
                        if effectivePageType == pt {
                            Label(pt.displayName, systemImage: "checkmark")
                        } else {
                            Label(pt.displayName, systemImage: pt.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Paper material section
            Section("Paper Material") {
                ForEach(PaperMaterial.allCases) { pm in
                    Button {
                        noteStore.updatePaperMaterial(for: note.id, paperMaterial: pm)
                    } label: {
                        if effectivePaperMaterial == pm {
                            Label(pm.displayName, systemImage: "checkmark")
                        } else {
                            Label(pm.displayName, systemImage: pm.systemImage)
                        }
                    }
                }
            }

            Divider()

            // Page colour — quick presets for the current page
            Section("Page Colour") {
                Button {
                    noteStore.updatePageColor(for: note.id, pageIndex: safePageIndex, color: nil)
                } label: {
                    Label("Theme Default", systemImage: note.pageColor(forPage: safePageIndex) == nil
                          ? "checkmark" : "paintbrush")
                }
                ForEach(pageColorPresets, id: \.name) { preset in
                    Button {
                        noteStore.updatePageColor(
                            for: note.id, pageIndex: safePageIndex, color: preset.color)
                    } label: {
                        Label(preset.name, systemImage: "circle.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "doc.richtext")
                .accessibilityLabel("Page setup")
        }
    }

    /// Quick-access page background colour presets.
    var pageColorPresets: [(name: String, color: UIColor)] {
        [
            ("White",       .white),
            ("Cream",       UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1)),
            ("Pale Yellow",  UIColor(red: 1.00, green: 0.99, blue: 0.88, alpha: 1)),
            ("Pale Blue",    UIColor(red: 0.93, green: 0.96, blue: 1.00, alpha: 1)),
            ("Pale Green",   UIColor(red: 0.93, green: 0.99, blue: 0.93, alpha: 1)),
            ("Pale Pink",    UIColor(red: 1.00, green: 0.93, blue: 0.95, alpha: 1)),
            ("Light Grey",   UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)),
            ("Dark Grey",    UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)),
            ("Black",        UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)),
        ]
    }

    // MARK: - Export Menu

    /// Toolbar menu that offers PDF and image export options for the current note.
    var exportMenu: some View {
        Menu {
            Section("Export") {
                Button {
                    exportCurrentPageAsPDF(pageIndex: safePageIndex)
                } label: {
                    Label("Export Page as PDF", systemImage: "doc.fill")
                }

                Button {
                    exportAllPagesAsPDF()
                } label: {
                    Label("Export All Pages as PDF", systemImage: "doc.on.doc.fill")
                }

                Button {
                    exportCurrentPageAsImage(pageIndex: safePageIndex)
                } label: {
                    Label("Export Page as Image", systemImage: "photo")
                }
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .accessibilityLabel("Export")
    }
}
