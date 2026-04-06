// InsightsAnalytics.swift
// Y2Core
//
// Custom statistical analysis engine for writing insights.

import Foundation

// MARK: - Linear Regression

public struct LinearRegression {
    public let slope: Double
    public let intercept: Double
    public let rSquared: Double
    public let sampleCount: Int

    public init(slope: Double, intercept: Double, rSquared: Double, sampleCount: Int) {
        self.slope = slope
        self.intercept = intercept
        self.rSquared = rSquared
        self.sampleCount = sampleCount
    }

    public static func fit(x: [Double], y: [Double]) -> LinearRegression? {
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

    public func predict(_ x: Double) -> Double {
        return slope * x + intercept
    }
}

// MARK: - Descriptive Statistics

public struct DescriptiveStats {
    public let count: Int
    public let mean: Double
    public let variance: Double
    public let standardDeviation: Double
    public let min: Double
    public let max: Double
    public let median: Double

    public init(count: Int, mean: Double, variance: Double, standardDeviation: Double, min: Double, max: Double, median: Double) {
        self.count = count
        self.mean = mean
        self.variance = variance
        self.standardDeviation = standardDeviation
        self.min = min
        self.max = max
        self.median = median
    }

    public static func compute(_ values: [Double]) -> DescriptiveStats? {
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

public struct WritingSession: Identifiable {
    public let id = UUID()
    public let startDate: Date
    public let endDate: Date
    public let eventCount: Int

    public var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    public init(startDate: Date, endDate: Date, eventCount: Int) {
        self.startDate = startDate
        self.endDate = endDate
        self.eventCount = eventCount
    }
}

public enum SessionDetector {
    public static func detectSessions(
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

        sessions.append(WritingSession(
            startDate: sessionStart,
            endDate: sessionEnd,
            eventCount: eventCount
        ))

        return sessions
    }

    public static func sessionStats(from sessions: [WritingSession]) -> DescriptiveStats? {
        let durations = sessions.map { $0.duration }
        return DescriptiveStats.compute(durations)
    }
}

// MARK: - Writing Pace Fingerprint

public struct PaceFingerprint: Codable, Equatable {
    public let histogram: [Double]
    public let eventsPerMinute: Double
    public let burstRatio: Double

    public static let binEdges: [TimeInterval] = [0, 0.5, 1.0, 2.0, 5.0, 15.0, .infinity]

    public init(histogram: [Double], eventsPerMinute: Double, burstRatio: Double) {
        self.histogram = histogram
        self.eventsPerMinute = eventsPerMinute
        self.burstRatio = burstRatio
    }

    public static func build(from timestamps: [Date]) -> PaceFingerprint? {
        let sorted = timestamps.sorted()
        guard sorted.count >= 2 else { return nil }

        var intervals: [TimeInterval] = []
        for i in 1..<sorted.count {
            let gap = sorted[i].timeIntervalSince(sorted[i - 1])
            if gap <= 300 {
                intervals.append(gap)
            }
        }
        guard !intervals.isEmpty else { return nil }

        var counts = Array(repeating: 0.0, count: binEdges.count - 1)
        for interval in intervals {
            for bin in 0..<counts.count {
                if interval >= binEdges[bin] && interval < binEdges[bin + 1] {
                    counts[bin] += 1
                    break
                }
            }
        }

        let total = counts.reduce(0, +)
        let histogram = total > 0 ? counts.map { $0 / total } : counts

        let totalDuration = sorted.last!.timeIntervalSince(sorted.first!)
        let epm = totalDuration > 0 ? Double(sorted.count) / (totalDuration / 60.0) : 0

        let burstRatio = histogram.first ?? 0

        return PaceFingerprint(
            histogram: histogram,
            eventsPerMinute: epm,
            burstRatio: burstRatio
        )
    }

    public func similarity(to other: PaceFingerprint) -> Double {
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

public enum AnomalyDetector {
    public struct Anomaly {
        public let index: Int
        public let value: Double
        public let zScore: Double
        public let isHigh: Bool

        public init(index: Int, value: Double, zScore: Double, isHigh: Bool) {
            self.index = index
            self.value = value
            self.zScore = zScore
            self.isHigh = isHigh
        }
    }

    public static func detect(values: [Double], threshold: Double = 2.0) -> [Anomaly] {
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

    public static func exponentialMovingAverage(_ values: [Double], alpha: Double = 0.3) -> [Double] {
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

public enum TrendAnalyser {

    public enum TrendDirection: String {
        case increasing = "increasing"
        case decreasing = "decreasing"
        case stable = "stable"
        case insufficient = "insufficient_data"
    }

    public struct TrendResult {
        public let direction: TrendDirection
        public let dailyChangeRate: Double
        public let confidence: Double
        public let nextDayPrediction: Double

        public init(direction: TrendDirection, dailyChangeRate: Double, confidence: Double, nextDayPrediction: Double) {
            self.direction = direction
            self.dailyChangeRate = dailyChangeRate
            self.confidence = confidence
            self.nextDayPrediction = nextDayPrediction
        }
    }

    public static func analyse(dailyValues: [Double]) -> TrendResult {
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

public enum MovingWindowStats {

    public struct WindowResult {
        public let windowMean: Double
        public let windowStdDev: Double
        public let momentum: Double

        public init(windowMean: Double, windowStdDev: Double, momentum: Double) {
            self.windowMean = windowMean
            self.windowStdDev = windowStdDev
            self.momentum = momentum
        }
    }

    public static func compute(values: [Double], windowSize: Int) -> [WindowResult] {
        guard windowSize >= 2, values.count >= windowSize else { return [] }

        var results: [WindowResult] = []
        var sum = 0.0
        var sumSq = 0.0

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

            let outgoing = values[windowEnd - windowSize]
            let incoming = values[windowEnd]
            sum += incoming - outgoing
            sumSq += incoming * incoming - outgoing * outgoing
        }

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
