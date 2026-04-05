import SwiftUI

/// Floating context-aware toolbar capsule that replaces the fixed toolbar strip.
///
/// **Tier 1 (always present)**: 5 buttons — active inking tool, eraser, lasso,
/// undo, redo — rendered as a thin floating capsule with `.ultraThinMaterial`
/// background. Tap a tool to activate; tap the *already-active* inking tool
/// to reveal Tier 2.
///
/// **Tier 2 (revealed on tap)**: contextual expansion that slides up from the
/// capsule — colour strip + width/opacity for inking tools, mode toggle for
/// eraser, shape picker for shape tool.
///
/// **Tier 3 (intentional access)**: the existing `AdvancedToolsPanel` inspector,
/// opened via the inspector button or long-press on the toolbar.
///
/// The capsule auto-fades during active Pencil input (controlled by
/// `toolStore.toolbarOpacity`) and supports keyboard shortcuts.
struct FloatingToolbarCapsule: View {
    @ObservedObject var toolStore: DrawingToolStore
    var inkStore: InkEffectStore? = nil
    var stickerStore: StickerStore? = nil
    var recordingStore: AudioRecordingStore? = nil
    var canUndo: Bool = false
    var canRedo: Bool = false
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onOpenInspector: (() -> Void)? = nil
    /// Called when the user taps the mic button to start recording.
    /// The parent view handles the actual recording start (needs notebook context).
    var onStartRecording: (() -> Void)? = nil
    /// Called when the user taps the stop button to end recording.
    var onStopRecording: (() -> Void)? = nil
    /// Callback for selection actions (cut / copy / delete / recolor).
    /// Only relevant when `toolStore.hasActiveSelection` is true.
    var onSelectionAction: ((SelectionAction) -> Void)? = nil

    // MARK: - State

    @State private var expandedTool: DrawingTool?
    @State private var showInkPicker = false
    @State private var showRecordingExpansion = false

    /// The tool that was active before switching to eraser/shape,
    /// so tapping the "previous ink" button returns to it.
    @State private var previousInkTool: DrawingTool = .pen

    // MARK: - Haptics

    private let toolSwitchFeedback = UIImpactFeedbackGenerator(style: .light)
    private let modeToggleFeedback = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Tier 1 Tools

    /// The 5 tools shown in Tier 1. The first slot shows the "active ink" tool
    /// (the last inking tool used), which doubles as a way to return from eraser.
    private var activeInkTool: DrawingTool {
        toolStore.activeTool.isInking ? toolStore.activeTool : previousInkTool
    }

    // MARK: - Body

    var body: some View {
        tier1Content
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: toolStore.hasActiveSelection)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toolStore.isToolbarMinimized)
            .onChange(of: toolStore.activeTool) { oldTool, newTool in
                if oldTool.isInking {
                    previousInkTool = oldTool
                }
                // Dismiss expansion when tool changes externally
                if expandedTool != nil && newTool != expandedTool {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        expandedTool = nil
                    }
                }
            }
            .sheet(isPresented: $showInkPicker) {
                if let inkStore {
                    InkEffectPickerView(inkStore: inkStore)
                }
            }
    }

    // MARK: - Tier 1 Content (Standard vs Selection)

    /// Switches between the standard drawing toolbar and the selection-action
    /// toolbar depending on whether the user has an active lasso selection.
    @ViewBuilder
    private var tier1Content: some View {
        if toolStore.hasActiveSelection, let onSelectionAction {
            SelectionToolbar(toolStore: toolStore, onAction: onSelectionAction)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
        } else {
            standardToolbar
                .transition(.opacity)
        }
    }

    /// Switches between the compact minimized stub and the full drawing toolbar.
    @ViewBuilder
    private var standardToolbar: some View {
        if toolStore.isToolbarMinimized {
            minimizedCapsule
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 4) {
                // Tier 2 — contextual expansion above the capsule
                tier2Expansion

                // Recording expansion — quality picker + recordings link
                recordingExpansion

                // Tier 1 — always-present capsule
                tier1Capsule
            }
            .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Recording Expansion (Tier 2)

    @ViewBuilder
    private var recordingExpansion: some View {
        if showRecordingExpansion, let recordingStore {
            VStack(spacing: 8) {
                // Quality picker
                HStack(spacing: 8) {
                    ForEach(AudioRecordingStore.RecordingQuality.allCases) { quality in
                        let isSelected = recordingStore.quality == quality
                        Button {
                            recordingStore.quality = quality
                        } label: {
                            Text(quality.displayName)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected
                                        ? Color.accentColor.opacity(0.12)
                                        : Color(uiColor: .systemGray5),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Recordings link
                Button {
                    showRecordingExpansion = false
                    toolStore.isRecordingSessionListPresented = true
                } label: {
                    Label("Recordings", systemImage: "list.bullet")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Tier 1 Capsule

    @ViewBuilder
    private var tier1Capsule: some View {
        HStack(spacing: 6) {
            // Active inking tool (first slot)
            tier1ToolButton(activeInkTool, forceIcon: activeInkTool.systemImage)

            // Eraser
            tier1ToolButton(.eraser)

            // Lasso / Select
            tier1ToolButton(.lasso)

            // Sticker
            if stickerStore != nil {
                stickerButton
            }

            // Widget
            widgetButton

            // Focus mode
            focusModeButton

            // Ambient environment scene
            ambientSceneButton

            // Magic mode
            magicModeButton

            // Study mode
            studyModeButton

            tier1Separator

            // Undo
            Button {
                onUndo?()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(canUndo ? Color(uiColor: .label) : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo")

            // Redo
            Button {
                onRedo?()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(canRedo ? Color(uiColor: .label) : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityLabel("Redo")

            // Recording mic / stop
            if recordingStore != nil {
                micButton
            }

            // Inspector / Ink effects
            if onOpenInspector != nil || inkStore != nil {
                tier1Separator
                inspectorGroup
                tier1Separator
            } else {
                tier1Separator
            }

            // Minimize — collapse toolbar to a compact pill
            minimizeButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Minimize Button

    /// Collapses the toolbar to a compact stub. Long-press or the expand button restores it.
    @ViewBuilder
    private var minimizeButton: some View {
        Button {
            toolSwitchFeedback.impactOccurred(intensity: 0.3)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                toolStore.isToolbarMinimized = true
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 28)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minimize toolbar")
    }

    // MARK: - Minimized Capsule

    /// Compact stub rendered when `toolStore.isToolbarMinimized` is true.
    /// Shows the active tool colour, undo/redo, and an expand button.
    @ViewBuilder
    private var minimizedCapsule: some View {
        HStack(spacing: 4) {
            // Active-tool icon tinted with the current ink colour
            Image(systemName: activeInkTool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Color(uiColor: toolStore.activeColor))

            tier1Separator

            // Undo
            Button {
                onUndo?()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(canUndo
                                     ? Color(uiColor: .label)
                                     : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)

            // Redo
            Button {
                onRedo?()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(canRedo
                                     ? Color(uiColor: .label)
                                     : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            tier1Separator

            // Expand
            Button {
                toolSwitchFeedback.impactOccurred(intensity: 0.5)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toolStore.isToolbarMinimized = false
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 28)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand toolbar")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: - Tier 1 Tool Button

    @ViewBuilder
    private func tier1ToolButton(_ tool: DrawingTool, forceIcon: String? = nil) -> some View {
        let isActive = toolStore.activeTool == tool
        let iconName = forceIcon ?? tool.systemImage

        Button {
            handleToolTap(tool)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(isActive ? Color.accentColor : Color(uiColor: .secondaryLabel))

                // Active indicator dot
                Circle()
                    .fill(isActive ? colorDot(for: tool) : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    modeToggleFeedback.impactOccurred()
                    onOpenInspector?()
                }
        )
    }

    // MARK: - Inspector Group

    @ViewBuilder
    private var inspectorGroup: some View {
        if let inkStore {
            let isActive = inkStore.activePreset != nil
            Button {
                showInkPicker = true
            } label: {
                Image(systemName: isActive ? "wand.and.stars.inverse" : "wand.and.stars")
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isActive ? Color.accentColor : Color(uiColor: .secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ink effects")
        }

        if let onOpenInspector {
            Button {
                onOpenInspector()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Inspector")
        }
    }

    // MARK: - Tier 2 Expansion

    @ViewBuilder
    private var tier2Expansion: some View {
        if let tool = expandedTool {
            ToolExpansionView(
                toolStore: toolStore,
                expandedTool: tool,
                onDismiss: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        expandedTool = nil
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Sticker Button

    @ViewBuilder
    private var stickerButton: some View {
        let isActive = toolStore.activeTool == .sticker
        Button {
            if isActive {
                // Already in sticker mode — open library
                toolStore.isStickerLibraryPresented = true
            } else {
                toolStore.activeTool = .sticker
                toolStore.isStickerLibraryPresented = true
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(isActive ? Color.accentColor : Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sticker")
    }

    // MARK: - Widget Button

    @ViewBuilder
    private var widgetButton: some View {
        Button {
            toolStore.isWidgetPickerPresented = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Widget")
    }

    // MARK: - Focus Mode Button

    @ViewBuilder
    private var focusModeButton: some View {
        Button {
            modeToggleFeedback.impactOccurred()
            toolStore.isFocusModeActive.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: toolStore.isFocusModeActive
                      ? "moon.fill" : "moon")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(toolStore.isFocusModeActive
                                     ? Color.accentColor
                                     : Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(toolStore.isFocusModeActive
                          ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Mode")
        .accessibilityAddTraits(toolStore.isFocusModeActive
                                ? .isSelected : [])
    }

    // MARK: - Ambient Scene Button

    @State private var showAmbientPicker = false

    @ViewBuilder
    private var ambientSceneButton: some View {
        Button {
            if toolStore.activeAmbientScene != nil {
                // If active, tap deactivates.
                modeToggleFeedback.impactOccurred()
                toolStore.activeAmbientScene = nil
            } else {
                showAmbientPicker = true
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: toolStore.activeAmbientScene?.iconName
                      ?? "cloud.rain")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(toolStore.activeAmbientScene != nil
                                     ? Color.accentColor
                                     : Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(toolStore.activeAmbientScene != nil
                          ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ambient Scene")
        .accessibilityAddTraits(toolStore.activeAmbientScene != nil
                                ? .isSelected : [])
        .popover(isPresented: $showAmbientPicker, arrowEdge: .bottom) {
            ambientScenePicker
        }
    }

    @ViewBuilder
    private var ambientScenePicker: some View {
        VStack(spacing: 0) {
            ForEach(AmbientScene.allCases) { scene in
                Button {
                    modeToggleFeedback.impactOccurred()
                    toolStore.activeAmbientScene = scene
                    showAmbientPicker = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: scene.iconName)
                            .font(.system(size: 16))
                            .frame(width: 24)
                        Text(scene.label)
                            .font(.subheadline)
                        Spacer()
                        if toolStore.activeAmbientScene == scene {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(uiColor: .label))

                if scene != AmbientScene.allCases.last {
                    Divider().padding(.leading, 48)
                }
            }

            Divider()

            // Sound toggle row.
            Button {
                toolStore.isAmbientSoundEnabled.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: toolStore.isAmbientSoundEnabled
                          ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 16))
                        .frame(width: 24)
                        .foregroundStyle(toolStore.isAmbientSoundEnabled
                                         ? Color.accentColor
                                         : Color(uiColor: .secondaryLabel))
                    Text("Sound")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: .label))
        }
        .frame(width: 180)
        .padding(.vertical, 4)
    }

    // MARK: - Magic Mode Button

    @ViewBuilder
    private var magicModeButton: some View {
        Button {
            modeToggleFeedback.impactOccurred()
            toolStore.isMagicModeActive.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: toolStore.isMagicModeActive
                      ? "wand.and.stars.inverse" : "wand.and.stars")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(toolStore.isMagicModeActive
                                     ? Color.accentColor
                                     : Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(toolStore.isMagicModeActive
                          ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Magic Mode")
        .accessibilityAddTraits(toolStore.isMagicModeActive
                                ? .isSelected : [])
    }

    // MARK: - Study Mode Button

    @ViewBuilder
    private var studyModeButton: some View {
        Button {
            modeToggleFeedback.impactOccurred()
            toolStore.isStudyModeActive.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: toolStore.isStudyModeActive
                      ? "graduationcap.fill" : "graduationcap")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(toolStore.isStudyModeActive
                                     ? Color.accentColor
                                     : Color(uiColor: .secondaryLabel))

                Circle()
                    .fill(toolStore.isStudyModeActive
                          ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Study Mode")
        .accessibilityAddTraits(toolStore.isStudyModeActive
                                ? .isSelected : [])
    }

    // MARK: - Recording Mic Button

    @State private var micPulsing = false

    @ViewBuilder
    private var micButton: some View {
        tier1Separator

        if toolStore.isRecording {
            // Stop button — pulsing red dot
            Button {
                onStopRecording?()
            } label: {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(micPulsing ? 1.0 : 0.6)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    micPulsing = true
                }
            }
            .onDisappear { micPulsing = false }
        } else {
            // Mic button — idle state
            Button {
                onStartRecording?()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start recording")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showRecordingExpansion.toggle()
                        }
                    }
            )
        }
    }

    // MARK: - Helpers

    private func handleToolTap(_ tool: DrawingTool) {
        if toolStore.activeTool == tool {
            // Already active — toggle Tier 2 expansion
            toolSwitchFeedback.impactOccurred(intensity: 0.5)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if expandedTool == tool {
                    expandedTool = nil
                } else {
                    expandedTool = tool
                }
            }
        } else {
            // Switch tool
            toolSwitchFeedback.impactOccurred()
            toolStore.activeTool = tool
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                expandedTool = nil
            }
        }
    }

    private func colorDot(for tool: DrawingTool) -> Color {
        if tool.isInking {
            return Color(uiColor: toolStore.activeColor)
        }
        return Color.accentColor
    }

    private var tier1Separator: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color(uiColor: .separator).opacity(0.3))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }
}
