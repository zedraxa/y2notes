import Combine
import SwiftUI

// MARK: - ObservableToolStore

/// Thin SwiftUI adapter that bridges `ToolStateProvider` → `ObservableObject`.
///
/// The drawing tool store has many properties; this adapter exposes the full
/// `ToolStateProvider` and triggers `objectWillChange` when any reactive
/// property changes. SwiftUI views access tool state through this adapter.
@MainActor
final class ObservableToolStore: ObservableObject {

    @Published var activeTool: DrawingTool = .pen
    @Published var activeColor: UIColor = .black
    @Published var activeWidth: Double = 3.0
    @Published var activeOpacity: Double = 1.0

    let provider: ToolStateProvider
    private var cancellables = Set<AnyCancellable>()

    init(provider: ToolStateProvider) {
        self.provider = provider

        provider.activeToolPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeTool)

        provider.activeColorPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeColor)

        provider.activeWidthPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeWidth)

        provider.activeOpacityPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeOpacity)
    }
}
