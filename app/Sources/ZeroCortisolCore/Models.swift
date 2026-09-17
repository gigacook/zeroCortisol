import Foundation

// MARK: - Corpus

public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let author: String
    public let work: String
    public let relevance: String
    public let themes: [String]

    public init(id: String, text: String, author: String, work: String, relevance: String, themes: [String]) {
        self.id = id
        self.text = text
        self.author = author
        self.work = work
        self.relevance = relevance
        self.themes = themes
    }
}

/// Shape of one entry in `data/quotes.json`.
struct QuoteRecord: Decodable {
    let id: String
    let quote: String
    let author: String
    let work: String
    let source_file: String
    let themes: [String]
    let relevance: String
}

/// Shape of `data/corpus_meta.json`.
struct CorpusMeta: Decodable {
    struct Author: Decodable {
        let name: String
        let works: [Work]
    }
    struct Work: Decodable {
        let title: String
        let source_file: String?
        let quote_count: Int?
    }
    let authors: [Author]
}

// MARK: - Pins and tags

public struct Tag: Codable, Hashable, Identifiable, Sendable {
    public let id: Int64
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Pin: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let quote: Quote
    public let pinnedAt: String
    public let tags: [Tag]

    public init(id: Int64, quote: Quote, pinnedAt: String, tags: [Tag]) {
        self.id = id
        self.quote = quote
        self.pinnedAt = pinnedAt
        self.tags = tags
    }
}

public enum ArchiveFilter: Hashable, Sendable {
    case all
    case untagged
    case tag(Int64)
}

// MARK: - Daily tracker

public struct DailyLog: Codable, Hashable, Identifiable, Sendable {
    public let date: String  // YYYY-MM-DD
    public let mood: Int
    public let sleep: Int
    public let strength: Int
    public let stillness: Int

    public var id: String { date }

    public init(date: String, mood: Int, sleep: Int, strength: Int, stillness: Int) {
        self.date = date
        self.mood = mood
        self.sleep = sleep
        self.strength = strength
        self.stillness = stillness
    }

    public var composite: Int { Scoring.composite(self) }

    /// The condensed tracker row, e.g. `M:7 Sl:6 St:8 Sti:5`.
    public var condensed: String { "M:\(mood) Sl:\(sleep) St:\(strength) Sti:\(stillness)" }
}

// MARK: - Recommendations

public struct Poster: Codable, Hashable, Sendable {
    public let author: String
    public let work: String
    public let authorPinCount: Int
    public let teaserQuote: String?

    public init(author: String, work: String, authorPinCount: Int, teaserQuote: String?) {
        self.author = author
        self.work = work
        self.authorPinCount = authorPinCount
        self.teaserQuote = teaserQuote
    }
}

public struct AuthorPinCount: Codable, Hashable, Sendable {
    public let author: String
    public let pinCount: Int
}

public struct WorkPinCount: Codable, Hashable, Sendable {
    public let author: String
    public let work: String
    public let pinCount: Int
    public let quoteCount: Int
}
