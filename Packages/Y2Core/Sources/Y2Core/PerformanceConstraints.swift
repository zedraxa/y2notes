import Foundation

/// Performance budgets and concurrency rules for the audio recording pipeline.
public enum PerformanceConstraints {

    // MARK: - Frame Budget

    public static let frameBudgetMs: Double = 8.0

    // MARK: 1. Recording Path

    public static let recordStartLatencyMs: Double = 16.0
    public static let strokeEventBudgetMs: Double = 2.0
    public static let pageEventBudgetMs: Double = 1.0
    public static let autosaveFlushBudgetMs: Double = 5.0

    // MARK: 2. UI Thread

    public static let resolveEventBudgetMs: Double = 0.5
    public static let pageHighlightHandlerBudgetMs: Double = 4.0
    public static let sessionListLoadBudgetMs: Double = 50.0
    public static let searchQueryBudgetMs: Double = 16.0

    // MARK: 3. CPU Budget

    public static let recordingCPUPercentCap: Double = 5.0
    public static let searchIndexRebuildBudgetMs: Double = 200.0
    public static let compressionQoS: DispatchQoS = .utility
    public static let diskCheckIntervalSeconds: TimeInterval = 30.0
    public static let orphanCleanupBudgetMs: Double = 100.0

    // MARK: 4. Memory Constraints

    public static let maxTimelineMemoryBytes: Int = 10 * 1024 * 1024
    public static let maxSearchIndexMemoryBytes: Int = 20 * 1024 * 1024

    // MARK: 5. Disk I/O Constraints

    public static let autosaveMaxFlushBytes: Int = 50 * 1024
    public static let standardAudioBytesPerSecond: Int = 11 * 1024
    public static let highAudioBytesPerSecond: Int = 22 * 1024

    // MARK: 6. Concurrency Rules

    public static let storageQueue = DispatchQueue(
        label: "com.y2notes.audioStorage",
        qos: .utility
    )

    // MARK: 7. Writing Effects & Micro-Interactions

    public static let writingEffectTotalBudgetMs: Double = 1.9
    public static let coreEffectBudgetMs: Double = 0.7
    public static let advancedEffectOverlayBudgetMs: Double = 0.8
    public static let microInteractionBudgetMs: Double = 0.5
    public static let maxSimultaneousMicroAnimations: Int = 2
    public static let pageTransitionBudgetMs: Double = 0.4
    public static let focusModeBudgetMs: Double = 0.3
    public static let ambientEnvironmentBudgetMs: Double = 0.5
    public static let adaptiveEffectsEvaluationBudgetMs: Double = 0.1
    public static let magicModeBudgetMs: Double = 0.4
    public static let studyModeBudgetMs: Double = 0.3

    // MARK: 9. Deepened Physics & Animation Budgets

    public static let velocityPageTransitionBudgetMs: Double = 0.5
    public static let interactiveDragBudgetMs: Double = 0.3
    public static let springProfileResolutionBudgetMs: Double = 0.05
    public static let chainAnimationSetupBudgetMs: Double = 0.4
    public static let momentumShadowBudgetMs: Double = 0.2
    public static let inkFlowPhysicsBudgetMs: Double = 0.1
    public static let pressureCurveBudgetMs: Double = 0.05
    public static let thermalStateEvaluationBudgetMs: Double = 0.01

    // MARK: 8. Future — Transcript Search

    public static let transcriptionQoS: DispatchQoS = .background
    public static let transcriptIndexBudgetMs: Double = 500.0
}
