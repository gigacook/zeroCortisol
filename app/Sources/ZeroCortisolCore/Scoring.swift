import Foundation

public enum Metric: String, CaseIterable, Codable, Sendable {
    case mood, sleep, strength, stillness

    public var weight: Int {
        switch self {
        case .mood, .sleep: return 1
        case .strength, .stillness: return 2
        }
    }

    public var title: String { rawValue.capitalized }

    /// Short label used in the condensed tracker row.
    public var short: String {
        switch self {
        case .mood: return "M"
        case .sleep: return "Sl"
        case .strength: return "St"
        case .stillness: return "Sti"
        }
    }

    /// Legend label with the weight, e.g. `Strength (2x)`.
    public var legendLabel: String { "\(title) (\(weight)x)" }

    public func value(in log: DailyLog) -> Int {
        switch self {
        case .mood: return log.mood
        case .sleep: return log.sleep
        case .strength: return log.strength
        case .stillness: return log.stillness
        }
    }
}

public enum Scoring {
    public static let valueRange = 1...9
    public static let compositeMin = 6
    public static let compositeMax = 54

    /// Composite = mood*1 + sleep*1 + strength*2 + stillness*2 (range 6...54).
    public static func composite(mood: Int, sleep: Int, strength: Int, stillness: Int) -> Int {
        mood * Metric.mood.weight
            + sleep * Metric.sleep.weight
            + strength * Metric.strength.weight
            + stillness * Metric.stillness.weight
    }

    public static func composite(_ log: DailyLog) -> Int {
        composite(mood: log.mood, sleep: log.sleep, strength: log.strength, stillness: log.stillness)
    }
}

public enum Streaks {
    /// Consecutive logged days ending today, or ending yesterday when today is not logged yet.
    public static func streak(logDates: [String], today: String) -> Int {
        let days = Set(logDates.compactMap(DayKey.dayNumber))
        guard let t = DayKey.dayNumber(today) else { return 0 }
        var cursor: Int
        if days.contains(t) {
            cursor = t
        } else if days.contains(t - 1) {
            cursor = t - 1
        } else {
            return 0
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor -= 1
        }
        return count
    }

    /// Total number of distinct logged days.
    public static func total(logDates: [String]) -> Int {
        Set(logDates.compactMap(DayKey.dayNumber)).count
    }
}

public enum TruthOfDay {
    /// Deterministic quote index for a day. Walks the whole corpus in a scrambled but
    /// complete cycle: index = (day * stride + offset) mod count, with stride coprime to count.
    public static func index(for dayKey: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let day = DayKey.dayNumber(dayKey) ?? 0
        let stride = self.stride(for: count)
        let raw = (day % count) * stride + 17
        return ((raw % count) + count) % count
    }

    static func stride(for count: Int) -> Int {
        guard count > 2 else { return 1 }
        var s = max(1, Int(Double(count) * 0.618))
        while gcd(s, count) != 1 { s += 1 }
        return s
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (a, b)
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    /// Quotes must be in a stable order (by id).
    public static func quote(for dayKey: String, in quotes: [Quote]) -> Quote? {
        guard !quotes.isEmpty else { return nil }
        return quotes[index(for: dayKey, count: quotes.count)]
    }
}
