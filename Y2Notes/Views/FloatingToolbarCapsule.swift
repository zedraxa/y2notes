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
    var canUndo: Bool = false
    var canRedo: Bool = false
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onOpenInspector: (() -> Void)? = nil

    // MARK: - State

    @State private var expandedTool: DrawingTool?
    @State private var showInkPicker = false

    /// The tool that was active before switching to eraser/shape,
    /// so tapping the "previous ink" button returns to it.
    @State private var previousInkTool: DrawingTool = .pen

    // MARK: - Tier 1 Tools

    /// The 5 tools shown in Tier 1. The first slot shows the "active ink" tool
    /// (the last inking tool used), which doubles as a way to return from eraser.
    private var activeInkTool: DrawingTool {
        toolStore.activeTool.isInking ? toolStore.activeTool : previousInkTool
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Tier 2 — contextual expansion above the capsule
            tier2Expansion

            // Tier 1 — always-present capsule
            tier1Capsule
        }
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

            // Inspector / Ink effects
            if onOpenInspector != nil || inkStore != nil {
                tier1Separator
                inspectorGroup
            }
        }
        .padding(.horizontal, 10)
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

    // MARK: - Helpers

    private func handleToolTap(_ tool: DrawingTool) {
        if toolStore.activeTool == tool {
            // Already active — toggle Tier 2 expansion
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if expandedTool == tool {
                    expandedTool = nil
                } else {
                    expandedTool = tool
                }
            }
        } else {
            // Switch tool
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
