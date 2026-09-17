import Foundation
import SQLite3

public enum StoreError: Error, CustomStringConvertible {
    case open(String)
    case sqlite(String)
    case resource(String)

    public var description: String {
        switch self {
        case .open(let m): return "open: \(m)"
        case .sqlite(let m): return "sqlite: \(m)"
        case .resource(let m): return "resource: \(m)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed store for the corpus, pins, tags and daily logs.
public final class Store {
    public let path: String
    private var db: OpaquePointer?

    /// Opens (creating if needed) the database at `path` and applies the schema.
    public init(path: String, schemaSQL: String) throws {
        self.path = path
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw StoreError.open(msg)
        }
        db = handle
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try exec(schemaSQL)
    }

    /// Opens the store using the schema and seed files in `resources`, seeding on first use.
    public convenience init(path: String, resources: ResourcePaths) throws {
        let schema: String
        do {
            schema = try String(contentsOf: resources.schema, encoding: .utf8)
        } catch {
            throw StoreError.resource("schema.sql not readable at \(resources.schema.path)")
        }
        try self.init(path: path, schemaSQL: schema)
        try seed(quotesJSON: resources.quotes, corpusMeta: resources.corpusMeta)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Low-level helpers

    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw StoreError.sqlite(msg)
        }
    }

    enum Bind {
        case text(String)
        case int(Int64)
        case null
    }

    private func prepare(_ sql: String, _ binds: [Bind]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlite("\(errorMessage) in: \(sql)")
        }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch b {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    @discardableResult
    func run(_ sql: String, _ binds: [Bind] = []) throws -> Int {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw StoreError.sqlite("\(errorMessage) in: \(sql)")
        }
        return Int(sqlite3_changes(db))
    }

    struct Row {
        let stmt: OpaquePointer?
        func text(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        func string(_ i: Int32) -> String { text(i) ?? "" }
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    }

    func query<T>(_ sql: String, _ binds: [Bind] = [], _ map: (Row) throws -> T) throws -> [T] {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(try map(Row(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw StoreError.sqlite("\(errorMessage) in: \(sql)")
            }
        }
        return out
    }

    func scalarInt(_ sql: String, _ binds: [Bind] = []) throws -> Int {
        try query(sql, binds) { Int($0.int(0)) }.first ?? 0
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Seeding

    /// Loads authors and works from corpus_meta.json, then quotes from quotes.json.
    /// Idempotent: existing rows are left untouched (INSERT OR IGNORE on natural keys).
    public func seed(quotesJSON: URL, corpusMeta: URL) throws {
        let decoder = JSONDecoder()
        let meta: CorpusMeta
        let records: [QuoteRecord]
        do {
            meta = try decoder.decode(CorpusMeta.self, from: Data(contentsOf: corpusMeta))
            records = try decoder.decode([QuoteRecord].self, from: Data(contentsOf: quotesJSON))
        } catch {
            throw StoreError.resource("cannot decode seed data: \(error)")
        }

        try transaction {
            for author in meta.authors {
                try run("INSERT OR IGNORE INTO authors(name) VALUES (?)", [.text(author.name)])
                for work in author.works {
                    try run("""
                        INSERT OR IGNORE INTO works(author_id, title)
                        SELECT id, ? FROM authors WHERE name = ?
                        """, [.text(work.title), .text(author.name)])
                }
            }
            for r in records {
                // Works that are missing from the meta file are created on the fly.
                try run("INSERT OR IGNORE INTO authors(name) VALUES (?)", [.text(r.author)])
                try run("""
                    INSERT OR IGNORE INTO works(author_id, title)
                    SELECT id, ? FROM authors WHERE name = ?
                    """, [.text(r.work), .text(r.author)])
                let themes = String(data: try JSONEncoder().encode(r.themes), encoding: .utf8) ?? "[]"
                try run("""
                    INSERT OR IGNORE INTO quotes(id, work_id, text, relevance, themes)
                    SELECT ?, w.id, ?, ?, ? FROM works w JOIN authors a ON a.id = w.author_id
                    WHERE a.name = ? AND w.title = ?
                    """, [.text(r.id), .text(r.quote), .text(r.relevance), .text(themes), .text(r.author), .text(r.work)])
            }
        }
    }

    // MARK: - Corpus

    private static let quoteSelect = """
        SELECT q.id, q.text, a.name, w.title, q.relevance, q.themes
        FROM quotes q JOIN works w ON w.id = q.work_id JOIN authors a ON a.id = w.author_id
        """

    private static func quote(from row: Row, offset: Int32 = 0) -> Quote {
        let themesText = row.string(offset + 5)
        let themes = (try? JSONDecoder().decode([String].self, from: Data(themesText.utf8))) ?? []
        return Quote(id: row.string(offset), text: row.string(offset + 1), author: row.string(offset + 2),
                     work: row.string(offset + 3), relevance: row.string(offset + 4), themes: themes)
    }

    public func quoteCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM quotes") }
    public func authorCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM authors") }
    public func workCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM works") }

    /// All quotes ordered by id.
    public func allQuotes() throws -> [Quote] {
        try query(Self.quoteSelect + " ORDER BY q.id") { Self.quote(from: $0) }
    }

    public func quote(id: String) throws -> Quote? {
        try query(Self.quoteSelect + " WHERE q.id = ?", [.text(id)]) { Self.quote(from: $0) }.first
    }

    public func truthOfDay(_ dayKey: String) throws -> Quote? {
        TruthOfDay.quote(for: dayKey, in: try allQuotes())
    }

    // MARK: - Pins

    public func pinCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM user_pins") }

    public func isPinned(quoteID: String) throws -> Bool {
        try scalarInt("SELECT COUNT(*) FROM user_pins WHERE quote_id = ?", [.text(quoteID)]) > 0
    }

    @discardableResult
    public func pin(quoteID: String, note: String? = nil) throws -> Int64 {
        try run("INSERT OR IGNORE INTO user_pins(quote_id, note) VALUES (?, ?)",
                [.text(quoteID), note.map { .text($0) } ?? .null])
        return Int64(try scalarInt("SELECT id FROM user_pins WHERE quote_id = ?", [.text(quoteID)]))
    }

    public func unpin(quoteID: String) throws {
        try run("DELETE FROM user_pins WHERE quote_id = ?", [.text(quoteID)])
    }

    public func unpin(pinID: Int64) throws {
        try run("DELETE FROM user_pins WHERE id = ?", [.int(pinID)])
    }

    /// Pinned quotes, newest first, filtered by tag / untagged / all.
    public func pins(_ filter: ArchiveFilter = .all) throws -> [Pin] {
        var sql = """
            SELECT p.id, p.pinned_at, q.id, q.text, a.name, w.title, q.relevance, q.themes
            FROM user_pins p
            JOIN quotes q ON q.id = p.quote_id
            JOIN works w ON w.id = q.work_id
            JOIN authors a ON a.id = w.author_id
            """
        var binds: [Bind] = []
        switch filter {
        case .all:
            break
        case .untagged:
            sql += " WHERE NOT EXISTS (SELECT 1 FROM pin_tags pt WHERE pt.pin_id = p.id)"
        case .tag(let tagID):
            sql += " WHERE EXISTS (SELECT 1 FROM pin_tags pt WHERE pt.pin_id = p.id AND pt.tag_id = ?)"
            binds.append(.int(tagID))
        }
        sql += " ORDER BY p.pinned_at DESC, p.id DESC"
        let rows = try query(sql, binds) { row in
            (row.int(0), row.string(1), Self.quote(from: row, offset: 2))
        }
        let tagMap = try tagsByPin()
        return rows.map { Pin(id: $0.0, quote: $0.2, pinnedAt: $0.1, tags: tagMap[$0.0] ?? []) }
    }

    private func tagsByPin() throws -> [Int64: [Tag]] {
        let rows = try query("""
            SELECT pt.pin_id, t.id, t.name FROM pin_tags pt JOIN tags t ON t.id = pt.tag_id
            ORDER BY t.name COLLATE NOCASE
            """) { ($0.int(0), Tag(id: $0.int(1), name: $0.string(2))) }
        return Dictionary(grouping: rows, by: { $0.0 }).mapValues { $0.map(\.1) }
    }

    // MARK: - Tags

    public func tags() throws -> [Tag] {
        try query("SELECT id, name FROM tags ORDER BY name COLLATE NOCASE") { Tag(id: $0.int(0), name: $0.string(1)) }
    }

    /// Creates a tag (or returns the existing one with the same case-insensitive name).
    @discardableResult
    public func createTag(_ rawName: String) throws -> Tag? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        try run("INSERT OR IGNORE INTO tags(name) VALUES (?)", [.text(name)])
        return try query("SELECT id, name FROM tags WHERE name = ?", [.text(name)]) { Tag(id: $0.int(0), name: $0.string(1)) }.first
    }

    public func deleteTag(id: Int64) throws {
        try run("DELETE FROM tags WHERE id = ?", [.int(id)])
    }

    public func addTag(tagID: Int64, toPin pinID: Int64) throws {
        try run("INSERT OR IGNORE INTO pin_tags(pin_id, tag_id) VALUES (?, ?)", [.int(pinID), .int(tagID)])
    }

    public func removeTag(tagID: Int64, fromPin pinID: Int64) throws {
        try run("DELETE FROM pin_tags WHERE pin_id = ? AND tag_id = ?", [.int(pinID), .int(tagID)])
    }

    // MARK: - Daily logs

    /// Inserts or replaces the row for `log.date`.
    public func saveLog(_ log: DailyLog) throws {
        try run("""
            INSERT INTO daily_logs(date, mood, sleep, strength, stillness) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET mood = excluded.mood, sleep = excluded.sleep,
                strength = excluded.strength, stillness = excluded.stillness
            """, [.text(log.date), .int(Int64(log.mood)), .int(Int64(log.sleep)),
                  .int(Int64(log.strength)), .int(Int64(log.stillness))])
    }

    public func log(for date: String) throws -> DailyLog? {
        try query("SELECT date, mood, sleep, strength, stillness FROM daily_logs WHERE date = ?", [.text(date)]) {
            DailyLog(date: $0.string(0), mood: Int($0.int(1)), sleep: Int($0.int(2)), strength: Int($0.int(3)), stillness: Int($0.int(4)))
        }.first
    }

    public func deleteLog(for date: String) throws {
        try run("DELETE FROM daily_logs WHERE date = ?", [.text(date)])
    }

    /// All logs, oldest first.
    public func logs() throws -> [DailyLog] {
        try query("SELECT date, mood, sleep, strength, stillness FROM daily_logs ORDER BY date") {
            DailyLog(date: $0.string(0), mood: Int($0.int(1)), sleep: Int($0.int(2)), strength: Int($0.int(3)), stillness: Int($0.int(4)))
        }
    }

    public func streak(today: String) throws -> Int {
        Streaks.streak(logDates: try logs().map(\.date), today: today)
    }

    public func totalLogged() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM daily_logs")
    }

    // MARK: - Aggregates and recommendations

    public func authorPinCounts() throws -> [AuthorPinCount] {
        try query("SELECT author, pin_count FROM v_author_pin_counts ORDER BY pin_count DESC, author") {
            AuthorPinCount(author: $0.string(0), pinCount: Int($0.int(1)))
        }
    }

    public func workPinCounts() throws -> [WorkPinCount] {
        try query("""
            SELECT wp.author, wp.work, wp.pin_count,
                   (SELECT COUNT(*) FROM quotes q WHERE q.work_id = wp.work_id)
            FROM v_work_pin_counts wp ORDER BY wp.author, wp.work
            """) {
            WorkPinCount(author: $0.string(0), work: $0.string(1), pinCount: Int($0.int(2)), quoteCount: Int($0.int(3)))
        }
    }

    /// Posters: unpinned works of pinned authors, ordered by author pin count (the query from schema.sql).
    public func recommendations() throws -> [Poster] {
        try query("""
            SELECT ap.author, wp.work, ap.pin_count,
                   (SELECT q.text FROM quotes q WHERE q.work_id = wp.work_id ORDER BY q.id LIMIT 1)
              FROM v_author_pin_counts ap
              JOIN v_work_pin_counts  wp ON wp.author_id = ap.author_id
             WHERE ap.pin_count >= 1
               AND wp.pin_count  = 0
             ORDER BY ap.pin_count DESC, ap.author ASC, wp.work ASC
            """) {
            Poster(author: $0.string(0), work: $0.string(1), authorPinCount: Int($0.int(2)), teaserQuote: $0.text(3))
        }
    }
}
