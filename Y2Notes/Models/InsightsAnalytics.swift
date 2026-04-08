// InsightsAnalytics.swift
// Y2Notes
//
// Custom statistical analysis engine for writing insights.
// Implements linear regression, session detection, pace fingerprinting,
// and anomaly detection without external math libraries.
//

import Foundation

// MARK: - Linear Regression

/// Ordinary least squares linear regression: y = slope·x + intercept.
/// Uses the closed-form normal equation, O(n) time.
struct LinearRegression {
    let slope: Double
    let intercept: Double
    /// R² coefficient of determination in [0, 1].
    let rSquared: Double
    /// Number of data points used.
    let sampleCount: Int

    /// Fit a line to (x, y) pairs.
    /// Returns nil if fewer than 2 points or zero variance in x.
    static func fit(x: [Double], y: [Double]) -> LinearRegression? {
        let n = min(x.count, y.count)
        guard n >= 2 else { return nil }

        let sumX  = x.prefix(n).reduce(0, +)
        let sumY  = y.prefix(n).reduce(0, +)
        let sumXY = zip(x, y).prefix(n).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sumX2 = x.prefix(n).reduce(0.0) { $0 + $1 * $1 }

        let nd = Double(n)
        let denominator = nd * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-15 else { return nil }

        let slope = (nd * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / nd

        // Compute R²
        let meanY = sumY / nd
        let ssTotal = y.prefix(n).reduce(0.0) { $0 + ($1 - meanY) * ($1 - meanY) }
        let ssResidual = zip(x, y).prefix(n).reduce(0.0) { acc, pair in
            let predicted = slope * pair.0 + intercept
            let residual = pair.1 - predicted
            return acc + residual * residual
        }
        let r2 = ssTotal > 1e-15 ? 1.0 - ssResidual / ssTotal : 0.0

        return LinearRegression(
            slope: slope,
            intercept: intercept,
            rSquared: max(0, min(1, r2)),
            sampleCount: n
        )
    }

    /// Predict y for a given x.
    func predict(_ x: Double) -> Double {
        return slope * x + intercept
    }
}

// MARK: - Descriptive Statistics

/// Basic descriptive statistics computed in a single O(n) pass (Welford's online algorithm for variance).
struct DescriptiveStats {
    let count: Int
    let mean: Double
    let variance: Double
    let standardDeviation: Double
    let min: Double
    let max: Double
    let median: Double

    /// Compute stats for an array of Doubles.
    /// Returns nil for empty input.
    static func compute(_ values: [Double]) -> DescriptiveStats? {
        guard !values.isEmpty else { return nil }

        var n = 0
        var mean = 0.0
        var m2 = 0.0
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude

        for value in values {
            n += 1
            let delta = value - mean
            mean += delta / Double(n)
            let delta2 = value - mean
            m2 += delta * delta2
            minVal = Swift.min(minVal, value)
            maxVal = Swift.max(maxVal, value)
        }

        let variance = n > 1 ? m2 / Double(n - 1) : 0
        let sorted = values.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        return DescriptiveStats(
            count: n,
            mean: mean,
            variance: variance,
            standardDeviation: variance.squareRoot(),
            min: minVal,
            max: maxVal,
            median: median
        )
    }
}

// MARK: - Writing Session Detection

/// Detects writing sessions from a series of timestamps using gap-based segmentation.
/// A new session starts when the gap between consecutive events exceeds `sessionGapThreshold`.
struct WritingSession: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let eventCount: Int

    /// Duration in seconds.
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    /// Formatted duration string (e.g. "12m 30s").
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

enum SessionDetector {
    /// Segment timestamps into sessions with a gap threshold (default 5 minutes).
    static func detectSessions(
        from timestamps: [Date],
        gapThreshold: TimeInterval = 300
    ) -> [WritingSession] {
        let sorted = timestamps.sorted()
        guard let first = sorted.first else { return [] }

        var sessions: [WritingSession] = []
        var sessionStart = first
        var sessionEnd = first
        var eventCount = 1

        for i in 1..<sorted.count {
            let gap = sorted[i].timeIntervalSince(sorted[i - 1])
            if gap > gapThreshold {
                // Close current session, start new one.
                sessions.append(WritingSession(
                    startDate: sessionStart,
                    endDate: sessionEnd,
                    eventCount: eventCount
                ))
                sessionStart = sorted[i]
                eventCount = 0
            }
            sessionEnd = sorted[i]
            eventCount += 1
        }

        // Close final session.
        sessions.append(WritingSession(
            startDate: sessionStart,
            endDate: sessionEnd,
            eventCount: eventCount
        ))

        return sessions
    }

    /// Compute session statistics.
    static func sessionStats(from sessions: [WritingSession]) -> DescriptiveStats? {
        let durations = sessions.map { $0.duration }
        return DescriptiveStats.compute(durations)
    }
}

// MARK: - Writing Pace Fingerprint

/// A fingerprint of a user's writing pace, characterised by the distribution
/// of inter-stroke intervals. Uses histogram binning to create a compact
/// representation comparable across time periods.
struct PaceFingerprint: Codable, Equatable {
    /// Histogram bins: [0–0.5s, 0.5–1s, 1–2s, 2–5s, 5–15s, 15s+]
    let histogram: [Double]
    /// Events per minute (raw throughput).
    let eventsPerMinute: Double
    /// Burst ratio: fraction of intervals < 0.5s (continuous writing vs. pauses).
    let burstRatio: Double

    static let binEdges: [TimeInterval] = [0, 0.5, 1.0, 2.0, 5.0, 15.0, .infinity]

    /// Build a fingerprint from a sequence of event timestamps.
    static func build(from timestamps: [Date]) -> PaceFingerprint? {
        let sorted = timestamps.sorted()
        guard sorted.count >= 2 else { return nil }

        // Compute inter-event intervals.
        var intervals: [TimeInterval] = []
        for i in 1..<sorted.count {
            let gap = sorted[i].timeIntervalSince(sorted[i - 1])
            // Ignore gaps > 5 minutes (session breaks).
            if gap <= 300 {
                intervals.append(gap)
            }
        }
        guard !intervals.isEmpty else { return nil }

        // Bin intervals into histogram.
        var counts = Array(repeating: 0.0, count: binEdges.count - 1)
        for interval in intervals {
            for bin in 0..<counts.count {
                if interval >= binEdges[bin] && interval < binEdges[bin + 1] {
                    counts[bin] += 1
                    break
                }
            }
        }

        // Normalise to probability distribution.
        let total = counts.reduce(0, +)
        let histogram = total > 0 ? counts.map { $0 / total } : counts

        // Events per minute.
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let totalDuration = last.timeIntervalSince(first)
        let epm = totalDuration > 0 ? Double(sorted.count) / (totalDuration / 60.0) : 0

        // Burst ratio = fraction in first bin (< 0.5s).
        let burstRatio = histogram.first ?? 0

        return PaceFingerprint(
            histogram: histogram,
            eventsPerMinute: epm,
            burstRatio: burstRatio
        )
    }

    /// Cosine similarity between two fingerprints in [0, 1].
    /// Custom implementation of the dot-product similarity.
    func similarity(to other: PaceFingerprint) -> Double {
        guard histogram.count == other.histogram.count else { return 0 }

        var dot = 0.0
        var normA = 0.0
        var normB = 0.0

        for i in 0..<histogram.count {
            dot   += histogram[i] * other.histogram[i]
            normA += histogram[i] * histogram[i]
            normB += other.histogram[i] * other.histogram[i]
        }

        let denominator = (normA.squareRoot() * normB.squareRoot())
        return denominator > 1e-15 ? dot / denominator : 0
    }
}

// MARK: - Anomaly Detection

/// Z-score based anomaly detection for writing metrics.
/// Flags values that deviate more than `threshold` standard deviations from the mean.
enum AnomalyDetector {
    struct Anomaly {
        let index: Int
        let value: Double
        let zScore: Double
        let isHigh: Bool   // true = above mean, false = below
    }

    /// Detect anomalies in a time series using z-score thresholding.
    /// Default threshold = 2.0 standard deviations.
    static func detect(values: [Double], threshold: Double = 2.0) -> [Anomaly] {
        guard let stats = DescriptiveStats.compute(values),
              stats.standardDeviation > 1e-15 else { return [] }

        var anomalies: [Anomaly] = []
        for (i, value) in values.enumerated() {
            let z = (value - stats.mean) / stats.standardDeviation
            if abs(z) > threshold {
                anomalies.append(Anomaly(
                    index: i,
                    value: value,
                    zScore: z,
                    isHigh: z > 0
                ))
            }
        }
        return anomalies
    }

    /// Exponential moving average for smoothing before anomaly detection.
    /// Custom implementation with configurable smoothing factor α ∈ (0, 1].
    static func exponentialMovingAverage(_ values: [Double], alpha: Double = 0.3) -> [Double] {
        guard let first = values.first else { return [] }
        var ema = [first]
        for i in 1..<values.count {
            let smoothed = alpha * values[i] + (1.0 - alpha) * ema[i - 1]
            ema.append(smoothed)
        }
        return ema
    }
}

// MARK: - Trend Analysis

/// Analyses trends in daily writing activity to provide human-readable insights.
enum TrendAnalyser {

    enum TrendDirection: String {
        case increasing = "increasing"
        case decreasing = "decreasing"
        case stable = "stable"
        case insufficient = "insufficient_data"
    }

    struct TrendResult {
        let direction: TrendDirection
        /// Slope in units per day.
        let dailyChangeRate: Double
        /// Confidence (R²) in [0, 1].
        let confidence: Double
        /// Predicted value for tomorrow.
        let nextDayPrediction: Double
    }

    /// Analyse the trend in a series of daily values.
    /// Values are assumed to be ordered chronologically (index 0 = earliest).
    static func analyse(dailyValues: [Double]) -> TrendResult {
        guard dailyValues.count >= 3 else {
            return TrendResult(
                direction: .insufficient,
                dailyChangeRate: 0,
                confidence: 0,
                nextDayPrediction: dailyValues.last ?? 0
            )
        }

        let x = dailyValues.indices.map { Double($0) }
        guard let regression = LinearRegression.fit(x: x, y: dailyValues) else {
            return TrendResult(
                direction: .stable,
                dailyChangeRate: 0,
                confidence: 0,
                nextDayPrediction: dailyValues.last ?? 0
            )
        }

        let direction: TrendDirection
        // Consider stable if slope is very small relative to mean.
        let mean = dailyValues.reduce(0, +) / Double(dailyValues.count)
        let relativeSlope = mean > 1e-15 ? abs(regression.slope) / mean : abs(regression.slope)

        if relativeSlope < 0.02 || regression.rSquared < 0.1 {
            direction = .stable
        } else if regression.slope > 0 {
            direction = .increasing
        } else {
            direction = .decreasing
        }

        let nextDay = regression.predict(Double(dailyValues.count))

        return TrendResult(
            direction: direction,
            dailyChangeRate: regression.slope,
            confidence: regression.rSquared,
            nextDayPrediction: max(0, nextDay)
        )
    }
}

// MARK: - Moving Window Statistics

/// Computes rolling statistics over a sliding window for smoothed trend detection.
enum MovingWindowStats {

    struct WindowResult {
        let windowMean: Double
        let windowStdDev: Double
        let momentum: Double  // Change from previous window
    }

    /// Compute rolling statistics with the given window size.
    /// Uses an efficient incremental algorithm (no re-summing).
    static func compute(values: [Double], windowSize: Int) -> [WindowResult] {
        guard windowSize >= 2, values.count >= windowSize else { return [] }

        var results: [WindowResult] = []
        var sum = 0.0
        var sumSq = 0.0

        // Initialise first window.
        for i in 0..<windowSize {
            sum += values[i]
            sumSq += values[i] * values[i]
        }

        let w = Double(windowSize)
        var prevMean = sum / w

        for windowEnd in windowSize..<values.count {
            let mean = sum / w
            let variance = max(0, (sumSq / w) - mean * mean)
            let stdDev = variance.squareRoot()
            let momentum = mean - prevMean

            results.append(WindowResult(
                windowMean: mean,
                windowStdDev: stdDev,
                momentum: momentum
            ))

            prevMean = mean

            // Slide window forward: remove outgoing element, add incoming.
            let outgoing = values[windowEnd - windowSize]
            let incoming = values[windowEnd]
            sum += incoming - outgoing
            sumSq += incoming * incoming - outgoing * outgoing
        }

        // Append stats for the final window position.
        if values.count >= windowSize {
            let mean = sum / w
            let variance = max(0, (sumSq / w) - mean * mean)
            let stdDev = variance.squareRoot()
            let momentum = mean - prevMean
            results.append(WindowResult(
                windowMean: mean,
                windowStdDev: stdDev,
                momentum: momentum
            ))
        }

        return results
    }
}
