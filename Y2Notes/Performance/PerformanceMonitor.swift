import Foundation
import UIKit
import os.log

// MARK: - Performance Monitor

/// Central performance metrics collector for Phase 5 quality targets.
///
/// Tracks launch time, page switches, save operations, memory usage,
/// and crash-free rate to validate app meets launch readiness criteria.
@MainActor
final class PerformanceMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = PerformanceMonitor()

    // MARK: - Quality Metrics (Phase 5 Targets)

    /// Target: < 500ms from app launch to first render
    @Published private(set) var launchTimeMs: Double = 0

    /// Target: < 100ms for page switch animations
    @Published private(set) var averagePageSwitchMs: Double = 0

    /// Target: < 50ms for save operations
    @Published private(set) var averageSaveLatencyMs: Double = 0

    /// Target: < 50MB for typical use (reduced from 100MB)
    @Published private(set) var currentMemoryMB: Double = 0

    /// Target: > 99.5% crash-free sessions
    @Published private(set) var crashFreeRate: Double = 100.0

    // MARK: - Internal Tracking

    private var appLaunchTime: Date?
    private var pageSwitchSamples: [Double] = []
    private var saveLatencySamples: [Double] = []
    private var sessionCount: Int = 0
    private var crashCount: Int = 0

    private let logger = Logger(subsystem: "com.y2notes", category: "Performance")

    // MARK: - Initialization

    private init() {
        appLaunchTime = Date()
        loadPersistentMetrics()
        startMemoryMonitoring()
    }

    // MARK: - Launch Time Tracking

    /// Call this when the app finishes initial render
    func recordAppLaunched() {
        guard let startTime = appLaunchTime else { return }
        launchTimeMs = Date().timeIntervalSince(startTime) * 1000
        logger.info("App launch time: \(self.launchTimeMs, format: .fixed(precision: 1))ms [Target: < 500ms]")

        if launchTimeMs > 500 {
            logger.warning("⚠️ Launch time exceeds 500ms target")
        }
    }

    // MARK: - Page Switch Tracking

    /// Record a page switch duration
    func recordPageSwitch(durationMs: Double) {
        pageSwitchSamples.append(durationMs)

        // Keep rolling window of last 100 samples
        if pageSwitchSamples.count > 100 {
            pageSwitchSamples.removeFirst()
        }

        averagePageSwitchMs = pageSwitchSamples.reduce(0, +) / Double(pageSwitchSamples.count)

        if durationMs > 100 {
            logger.warning("⚠️ Page switch \(durationMs, format: .fixed(precision: 1))ms exceeds 100ms target")
        }
    }

    // MARK: - Save Latency Tracking

    /// Record a save operation duration
    func recordSaveOperation(durationMs: Double) {
        saveLatencySamples.append(durationMs)

        // Keep rolling window of last 100 samples
        if saveLatencySamples.count > 100 {
            saveLatencySamples.removeFirst()
        }

        averageSaveLatencyMs = saveLatencySamples.reduce(0, +) / Double(saveLatencySamples.count)

        if durationMs > 50 {
            logger.warning("⚠️ Save latency \(durationMs, format: .fixed(precision: 1))ms exceeds 50ms target")
        }
    }

    // MARK: - Memory Monitoring

    private func startMemoryMonitoring() {
        // Update memory usage every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedBytes = Double(info.resident_size)
            currentMemoryMB = usedBytes / 1024.0 / 1024.0

            if currentMemoryMB > 50 {
                logger.warning("⚠️ Memory usage \(self.currentMemoryMB, format: .fixed(precision: 1))MB exceeds 50MB target")
            }
        }
    }

    // MARK: - Crash Tracking

    /// Record that a session started successfully
    func recordSessionStart() {
        sessionCount += 1
        savePersistentMetrics()
    }

    /// Record that a crash occurred (called during recovery)
    func recordCrash() {
        crashCount += 1
        updateCrashFreeRate()
        savePersistentMetrics()
        logger.error("Crash recorded. Crash-free rate: \(self.crashFreeRate, format: .fixed(precision: 2))%")
    }

    private func updateCrashFreeRate() {
        guard sessionCount > 0 else {
            crashFreeRate = 100.0
            return
        }
        let crashFreeSessions = max(0, sessionCount - crashCount)
        crashFreeRate = (Double(crashFreeSessions) / Double(sessionCount)) * 100.0
    }

    // MARK: - Persistence

    private func loadPersistentMetrics() {
        let defaults = UserDefaults.standard
        sessionCount = defaults.integer(forKey: "PerformanceMonitor.sessionCount")
        crashCount = defaults.integer(forKey: "PerformanceMonitor.crashCount")
        updateCrashFreeRate()
    }

    private func savePersistentMetrics() {
        let defaults = UserDefaults.standard
        defaults.set(sessionCount, forKey: "PerformanceMonitor.sessionCount")
        defaults.set(crashCount, forKey: "PerformanceMonitor.crashCount")
    }

    // MARK: - Reporting

    /// Generate a performance report for diagnostics
    func generateReport() -> String {
        var lines: [String] = []
        lines.append("Performance Metrics Report")
        lines.append("=========================")
        lines.append("")
        lines.append("Phase 5 Quality Targets:")
        lines.append("")

        // Launch Time
        let launchStatus = launchTimeMs < 500 ? "✅ PASS" : "❌ FAIL"
        lines.append("Launch Time: \(String(format: "%.1f", launchTimeMs))ms [Target: < 500ms] \(launchStatus)")

        // Page Switch
        let pageSwitchStatus = averagePageSwitchMs < 100 ? "✅ PASS" : "❌ FAIL"
        lines.append("Page Switch (avg): \(String(format: "%.1f", averagePageSwitchMs))ms [Target: < 100ms] \(pageSwitchStatus)")

        // Save Latency
        let saveStatus = averageSaveLatencyMs < 50 ? "✅ PASS" : "❌ FAIL"
        lines.append("Save Latency (avg): \(String(format: "%.1f", averageSaveLatencyMs))ms [Target: < 50ms] \(saveStatus)")

        // Memory Usage
        let memoryStatus = currentMemoryMB < 50 ? "✅ PASS" : "❌ FAIL"
        lines.append("Memory Usage: \(String(format: "%.1f", currentMemoryMB))MB [Target: < 50MB] \(memoryStatus)")

        // Crash-Free Rate
        let crashStatus = crashFreeRate >= 99.5 ? "✅ PASS" : "❌ FAIL"
        lines.append("Crash-Free Rate: \(String(format: "%.2f", crashFreeRate))% [Target: > 99.5%] \(crashStatus)")

        lines.append("")
        lines.append("Sessions: \(sessionCount)")
        lines.append("Crashes: \(crashCount)")
        lines.append("Page Switch Samples: \(pageSwitchSamples.count)")
        lines.append("Save Latency Samples: \(saveLatencySamples.count)")

        return lines.joined(separator: "\n")
    }

    /// Check if all Phase 5 targets are met
    var meetsAllTargets: Bool {
        return launchTimeMs < 500 &&
               averagePageSwitchMs < 100 &&
               averageSaveLatencyMs < 50 &&
               currentMemoryMB < 50 &&
               crashFreeRate >= 99.5
    }
}
