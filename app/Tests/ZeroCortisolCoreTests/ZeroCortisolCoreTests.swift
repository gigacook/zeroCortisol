import Foundation
import Testing
@testable import ZeroCortisolCore

// MARK: - Helpers

private let repo = ResourcePaths.repository(ResourcePaths.repositoryRoot)

private func tempDBPath() -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("zc-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("zc.sqlite").path
}

private func seededStore() throws -> Store {
    try Store(path: tempDBPath(), resources: repo)
}

private func log(_ date: String, _ m: Int, _ sl: Int, _ st: Int, _ sti: Int) -> DailyLog {
    DailyLog(date: date, mood: m, sleep: sl, strength: st, stillness: sti)
}

/// Logs on consecutive days starting at `start`, all four metrics set so the composite equals `composite`.
private func logs(start: String, composites: [Int]) -> [DailyLog] {
    let d0 = DayKey.dayNumber(start)!
    return composites.enumerated().map { i, c in
        // composite = 6v when all metrics equal v; use equal metrics for multiples of 6.
        precondition(c % 6 == 0, "use multiples of 6")
        let v = c / 6
        return log(DayKey.key(forDayNumber: d0 + i), v, v, v, v)
    }
}

// MARK: - Composite

@Suite struct CompositeTests {
    @Test func weights() {
        #expect(Scoring.composite(mood: 1, sleep: 1, strength: 1, stillness: 1) == 6)
        #expect(Scoring.composite(mood: 9, sleep: 9, strength: 9, stillness: 9) == 54)
        #expect(Scoring.composite(mood: 2, sleep: 3, strength: 4, stillness: 5) == 2 + 3 + 8 + 10)
        #expect(log("2026-01-01", 7, 6, 8, 5).composite == 7 + 6 + 16 + 10)
        #expect(Metric.strength.legendLabel == "Strength (2x)")
        #expect(Metric.mood.legendLabel == "Mood (1x)")
    }

    @Test func condensedRow() {
        #expect(log("2026-01-01", 7, 6, 8, 5).condensed == "M:7 Sl:6 St:8 Sti:5")
    }
}

// MARK: - Trajectory

@Suite struct TrajectoryTests {
    @Test func asymmetricSmoothingFavoursRises() {
        let rise = Trajectory.smooth([30, 40])
        let drop = Trajectory.smooth([40, 30])
        let riseMove = abs(rise[1] - rise[0])
        let dropMove = abs(drop[1] - drop[0])
        #expect(abs(rise[1] - 36) < 1e-9)   // alpha_up = 0.6
        #expect(abs(drop[1] - 39) < 1e-9)   // alpha_down = 0.1
        #expect(riseMove >= 5 * dropMove)
    }

    @Test func negativeSlopeIsDamped() {
        let series = logs(start: "2026-03-01", composites: [54, 48, 42, 36, 30, 24, 18, 12])
        let r = Trajectory.compute(series)
        #expect(r.rawSlope < 0)
        #expect(abs(r.appliedSlope - r.rawSlope * 0.25) < 1e-9)
        let last = r.smoothed.last!.value
        #expect(r.projection.count == 8)
        #expect(r.projection.first!.value == last)
        #expect(abs(r.projection.last!.value - Trajectory.clamp(last + r.rawSlope * 0.25 * 7)) < 1e-9)
        #expect(r.projection.last!.day == r.smoothed.last!.day + 7)
    }

    @Test func positiveSlopeIsNotDamped() {
        let r = Trajectory.compute(logs(start: "2026-03-01", composites: [12, 18, 24, 30, 36]))
        #expect(r.rawSlope > 0)
        #expect(r.appliedSlope == r.rawSlope)
    }

    @Test func projectionIsClampedTo6And54() {
        let up = Trajectory.compute(logs(start: "2026-03-01", composites: [6, 54, 54, 54, 54, 54, 54]))
        #expect(up.projection.allSatisfy { $0.value <= 54 && $0.value >= 6 })
        let down = Trajectory.compute(logs(start: "2026-03-01", composites: [54, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]))
        #expect(down.projection.allSatisfy { $0.value <= 54 && $0.value >= 6 })
        // Extreme synthetic values are clamped too.
        #expect(Trajectory.clamp(80) == 54)
        #expect(Trajectory.clamp(-3) == 6)
    }

    @Test func usesAtMostThirtyDays() {
        let series = logs(start: "2026-01-01", composites: Array(repeating: 30, count: 45))
        let r = Trajectory.compute(series)
        #expect(r.actual.count == 30)
        let span = r.actual.last!.day - r.actual.first!.day
        #expect(span <= 29)
        #expect(r.actual.last!.dateKey == series.last!.date)

        // Sparse logs: only entries within 30 calendar days of the latest log count.
        let sparse = [log("2026-01-01", 1, 1, 1, 1), log("2026-02-15", 5, 5, 5, 5), log("2026-02-20", 6, 6, 6, 6)]
        #expect(Trajectory.compute(sparse).actual.count == 2)
    }

    @Test func emptyAndSingle() {
        #expect(Trajectory.compute([]).isEmpty)
        let one = Trajectory.compute([log("2026-05-05", 5, 5, 5, 5)])
        #expect(one.smoothed.count == 1)
        #expect(one.rawSlope == 0)
        #expect(one.projection.allSatisfy { $0.value == 30 })
    }
}

// MARK: - Streaks

@Suite struct StreakTests {
    @Test func streakEndsTodayOrYesterday() {
        let dates = ["2026-09-10", "2026-09-14", "2026-09-15", "2026-09-16"]
        #expect(Streaks.streak(logDates: dates, today: "2026-09-16") == 3)
        #expect(Streaks.streak(logDates: dates, today: "2026-09-17") == 3)   // today not logged yet
        #expect(Streaks.streak(logDates: dates, today: "2026-09-18") == 0)   // gap of a full day
        #expect(Streaks.streak(logDates: [], today: "2026-09-18") == 0)
        #expect(Streaks.streak(logDates: ["2026-02-28", "2026-03-01"], today: "2026-03-01") == 2)
        #expect(Streaks.total(logDates: dates) == 4)
    }

    @Test func storeStreakAndTotal() throws {
        let store = try seededStore()
        for d in ["2026-09-01", "2026-09-15", "2026-09-16", "2026-09-17"] {
            try store.saveLog(log(d, 5, 5, 5, 5))
        }
        try store.saveLog(log("2026-09-17", 9, 9, 9, 9))  // upsert, not a new day
        #expect(try store.totalLogged() == 4)
        #expect(try store.streak(today: "2026-09-17") == 3)
        #expect(try store.log(for: "2026-09-17")?.mood == 9)
    }
}

// MARK: - Store and seeding

@Suite struct StoreTests {
    @Test func seedingIsIdempotent() throws {
        let path = tempDBPath()
        let first = try Store(path: path, resources: repo)
        let counts = (try first.authorCount(), try first.workCount(), try first.quoteCount())
        #expect(counts.2 == 407)
        try first.pin(quoteID: "q0001")
        try first.seed(quotesJSON: repo.quotes, corpusMeta: repo.corpusMeta)
        #expect(try first.quoteCount() == counts.2)

        let reopened = try Store(path: path, resources: repo)
        #expect(try reopened.authorCount() == counts.0)
        #expect(try reopened.workCount() == counts.1)
        #expect(try reopened.quoteCount() == counts.2)
        #expect(try reopened.pinCount() == 1)
    }

    @Test func pinsAndTags() throws {
        let store = try seededStore()
        let p1 = try store.pin(quoteID: "q0001")
        let p2 = try store.pin(quoteID: "q0100")
        #expect(try store.pin(quoteID: "q0001") == p1)  // pinning twice is a no-op
        #expect(try store.pinCount() == 2)

        let tag = try #require(try store.createTag("  morning "))
        #expect(tag.name == "morning")
        #expect(try store.createTag("MORNING")?.id == tag.id)
        try store.addTag(tagID: tag.id, toPin: p1)
        #expect(try store.pins(.tag(tag.id)).map(\.id) == [p1])
        #expect(try store.pins(.untagged).map(\.id) == [p2])
        #expect(try store.pins(.all).count == 2)
        #expect(try store.pins(.all).first { $0.id == p1 }?.tags.map(\.name) == ["morning"])

        try store.removeTag(tagID: tag.id, fromPin: p1)
        #expect(try store.pins(.untagged).count == 2)

        try store.addTag(tagID: tag.id, toPin: p2)
        try store.unpin(quoteID: "q0100")
        #expect(try store.pinCount() == 1)
        try store.deleteTag(id: tag.id)
        #expect(try store.tags().isEmpty)
    }
}

// MARK: - Recommendations

@Suite struct RecommendationTests {
    private struct Rec: Decodable { let id: String; let quote: String; let author: String; let work: String }

    @Test func excludesPinnedWorksAndOrdersByAuthorPins() throws {
        let store = try seededStore()
        let quotes = try JSONDecoder().decode([Rec].self, from: Data(contentsOf: repo.quotes))
        func ids(_ author: String, _ work: String) -> [String] {
            quotes.filter { $0.author == author && $0.work == work }.map(\.id).sorted()
        }
        // Nietzsche: 2 pins in one work. Epictetus: 1 pin.
        let z = ids("Friedrich Nietzsche", "Thus Spake Zarathustra")
        try store.pin(quoteID: z[0])
        try store.pin(quoteID: z[1])
        try store.pin(quoteID: ids("Epictetus", "Discourses")[0])

        let posters = try store.recommendations()
        #expect(!posters.isEmpty)
        // Only pinned authors, highest pin count first.
        #expect(Set(posters.map(\.author)) == ["Friedrich Nietzsche", "Epictetus"])
        let firstEpictetus = posters.firstIndex { $0.author == "Epictetus" }!
        #expect(posters[..<firstEpictetus].allSatisfy { $0.author == "Friedrich Nietzsche" })
        #expect(posters.first?.authorPinCount == 2)
        // Pinned works are excluded.
        #expect(!posters.contains { $0.work == "Thus Spake Zarathustra" })
        #expect(!posters.contains { $0.work == "Discourses" })
        #expect(posters.contains { $0.work == "Beyond Good and Evil" })
        #expect(posters.contains { $0.work == "Enchiridion" })
        // Teaser is the lowest-id quote of the work.
        for poster in posters {
            let expected = quotes.filter { $0.author == poster.author && $0.work == poster.work }
                .min { $0.id < $1.id }?.quote
            #expect(poster.teaserQuote == expected)
        }
    }

    @Test func noPinsNoPosters() throws {
        #expect(try seededStore().recommendations().isEmpty)
    }
}

// MARK: - Truth of the day

@Suite struct TruthOfDayTests {
    @Test func deterministicPerDate() throws {
        let store = try seededStore()
        let a = try store.truthOfDay("2026-09-17")
        let b = try store.truthOfDay("2026-09-17")
        #expect(a != nil)
        #expect(a == b)
        #expect(TruthOfDay.index(for: "2026-09-17", count: 407) == TruthOfDay.index(for: "2026-09-17", count: 407))
    }

    @Test func coversWholeCorpusOverACycle() {
        let n = 407
        let start = DayKey.dayNumber("2026-01-01")!
        let indices = (0..<n).map { TruthOfDay.index(for: DayKey.key(forDayNumber: start + $0), count: n) }
        #expect(Set(indices).count == n)
        #expect(indices.allSatisfy { (0..<n).contains($0) })
        // Consecutive days do not step to the neighbouring quote.
        #expect(zip(indices, indices.dropFirst()).allSatisfy { abs($0 - $1) != 1 })
    }
}

// MARK: - Web export

@Suite struct WebExportTests {
    @Test func writesDataAndIndex() throws {
        let store = try seededStore()
        let epictetus = try #require(try store.allQuotes().first { $0.author == "Epictetus" })
        let pin = try store.pin(quoteID: epictetus.id)
        let tag = try #require(try store.createTag("focus"))
        try store.addTag(tagID: tag.id, toPin: pin)

        let out = URL(fileURLWithPath: tempDBPath()).deletingLastPathComponent().appendingPathComponent("web")
        let index = try WebExport.export(store: store, indexHTML: repo.webIndex, to: out)
        #expect(FileManager.default.fileExists(atPath: index.path))
        let js = try String(contentsOf: out.appendingPathComponent("data.js"), encoding: .utf8)
        #expect(js.contains("window.ZC_DATA = {"))
        #expect(js.contains("\"focus\""))

        let payload = try WebExport.payload(from: store)
        #expect(payload.pins.count == 1)
        #expect(payload.truth != nil)
        #expect(payload.truth?.id == (try store.truthOfDay(payload.today))?.id)
        #expect(payload.showTruthIntro == false)
        #expect(try WebExport.payload(from: store, showTruthIntro: true).showTruthIntro)
        #expect(payload.authors.contains { $0.pinCount == 1 })
        #expect(!payload.recommendations.isEmpty)
    }
}
