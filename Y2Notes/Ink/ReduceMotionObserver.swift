import UIKit

// MARK: - Reduce Motion Observer

/// Shared singleton that tracks `UIAccessibility.isReduceMotionEnabled` and
/// updates dynamically when the user changes the setting at runtime.
///
/// All effect engines read ``isEnabled`` instead of caching the value at
/// `init()`, so a toggle in **Settings → Accessibility → Motion → Reduce
/// Motion** takes effect immediately without an app restart.
///
/// **Usage:**
/// ```swift
/// private var shouldSuppressAnimations: Bool {
///     ReduceMotionObserver.shared.isEnabled || !effectIntensity.allowsMagicMode
/// }
/// ```
final class ReduceMotionObserver {

    // MARK: - Shared Instance

    static let shared = ReduceMotionObserver()

    // MARK: - Published State

    /// `true` when the system *Reduce Motion* accessibility setting is on.
    private(set) var isEnabled: Bool = UIAccessibility.isReduceMotionEnabled

    // MARK: - Private

    private var observer: NSObjectProtocol?

    // MARK: - Init

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isEnabled = UIAccessibility.isReduceMotionEnabled
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
