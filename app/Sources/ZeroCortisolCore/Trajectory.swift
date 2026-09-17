import Foundation

public struct TrajectoryPoint: Hashable, Sendable {
    public let day: Int       // DayKey.dayNumber
    public let dateKey: String
    public let value: Double

    public init(day: Int, value: Double) {
        self.day = day
        self.dateKey = DayKey.key(forDayNumber: day)
        self.value = value
    }
}

public struct TrajectoryResult: Sendable {
    /// Composite scores actually logged inside the window.
    public let actual: [TrajectoryPoint]
    /// Asymmetric EMA of `actual`.
    public let smoothed: [TrajectoryPoint]
    /// Anchor (last smoothed point) followed by `horizon` projected days.
    public let projection: [TrajectoryPoint]
    /// Least-squares slope (points per day) of the recent smoothed values, before damping.
    public let rawSlope: Double
    /// Slope actually used for the projection (negative slopes are damped).
    public let appliedSlope: Double

    public var isEmpty: Bool { actual.isEmpty }

    public static let empty = TrajectoryResult(actual: [], smoothed: [], projection: [], rawSlope: 0, appliedSlope: 0)
}

/// Lenient trajectory: responsive to improvement, resistant to decline.
public enum Trajectory {
    public static let windowDays = 30
    public static let alphaUp = 0.6
    public static let alphaDown = 0.1
    public static let negativeSlopeDamping = 0.25
    public static let horizonDays = 7
    public static let slopeLookback = 7
    public static let floor = Double(Scoring.compositeMin)
    public static let ceiling = Double(Scoring.compositeMax)

    /// Asymmetric exponential moving average. The first value seeds the average; after that
    /// alpha = 0.6 when the new value is above the running average, 0.1 otherwise.
    public static func smooth(_ values: [Double]) -> [Double] {
        guard let first = values.first else { return [] }
        var s = first
        var out = [s]
        for x in values.dropFirst() {
            let alpha = x > s ? alphaUp : alphaDown
            s += alpha * (x - s)
            out.append(s)
        }
        return out
    }

    public static func clamp(_ v: Double) -> Double { min(ceiling, max(floor, v)) }

    /// Logs restricted to the 30-day window that ends at the most recent log (at most 30 entries).
    public static func window(_ logs: [DailyLog]) -> [DailyLog] {
        let dated = logs.compactMap { log -> (Int, DailyLog)? in
            guard let d = DayKey.dayNumber(log.date) else { return nil }
            return (d, log)
        }.sorted { $0.0 < $1.0 }
        guard let last = dated.last?.0 else { return [] }
        let start = last - (windowDays - 1)
        return Array(dated.filter { $0.0 >= start }.suffix(windowDays).map { $0.1 })
    }

    public static func compute(_ logs: [DailyLog]) -> TrajectoryResult {
        let recent = window(logs)
        guard !recent.isEmpty else { return .empty }
        let days = recent.compactMap { DayKey.dayNumber($0.date) }
        let values = recent.map { Double($0.composite) }
        let smoothedValues = smooth(values)

        let actual = zip(days, values).map { TrajectoryPoint(day: $0, value: $1) }
        let smoothed = zip(days, smoothedValues).map { TrajectoryPoint(day: $0, value: $1) }

        let raw = slope(days: Array(days.suffix(slopeLookback)), values: Array(smoothedValues.suffix(slopeLookback)))
        let applied = raw < 0 ? raw * negativeSlopeDamping : raw

        let lastDay = days[days.count - 1]
        let lastValue = smoothedValues[smoothedValues.count - 1]
        var projection = [TrajectoryPoint(day: lastDay, value: clamp(lastValue))]
        for step in 1...horizonDays {
            projection.append(TrajectoryPoint(day: lastDay + step, value: clamp(lastValue + applied * Double(step))))
        }
        return TrajectoryResult(actual: actual, smoothed: smoothed, projection: projection, rawSlope: raw, appliedSlope: applied)
    }

    /// Ordinary least-squares slope of values against day numbers; 0 with fewer than 2 distinct days.
    static func slope(days: [Int], values: [Double]) -> Double {
        let n = Double(days.count)
        guard days.count >= 2 else { return 0 }
        let xs = days.map(Double.init)
        let mx = xs.reduce(0, +) / n
        let my = values.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for (x, y) in zip(xs, values) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den == 0 ? 0 : num / den
    }
}
