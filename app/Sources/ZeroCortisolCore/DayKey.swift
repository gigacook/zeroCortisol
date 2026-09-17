import Foundation

/// Calendar-day keys in `YYYY-MM-DD` form, plus day arithmetic that ignores time zones
/// and daylight-saving shifts (days are counted on a fixed UTC Gregorian calendar).
public enum DayKey {
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// The key for `date` as seen on the given (by default the user's) calendar.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public static func today(calendar: Calendar = .current) -> String {
        key(for: Date(), calendar: calendar)
    }

    /// Days since 1970-01-01 for a `YYYY-MM-DD` key, or nil when malformed.
    public static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let date = utc.date(from: comps) else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The key for a day number produced by `dayNumber(_:)`.
    public static func key(forDayNumber n: Int) -> String {
        key(for: Date(timeIntervalSince1970: TimeInterval(n) * 86_400), calendar: utc)
    }

    /// Noon (local time) on the given day; convenient for chart x-values.
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12
        return calendar.date(from: comps)
    }
}
