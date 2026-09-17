import Foundation

/// Locations of the bundled seed data, schema, web page and menu bar images.
///
/// In the packaged app everything lives in `Contents/Resources` (with `web/index.html`).
/// When run from the source tree (`swift run`, tests) the repo layout is used instead:
/// `data/`, `web/` and `app/Resources/`.
public struct ResourcePaths: Sendable {
    public let quotes: URL
    public let corpusMeta: URL
    public let schema: URL
    public let webIndex: URL
    public let imagesDirectory: URL

    public init(quotes: URL, corpusMeta: URL, schema: URL, webIndex: URL, imagesDirectory: URL) {
        self.quotes = quotes
        self.corpusMeta = corpusMeta
        self.schema = schema
        self.webIndex = webIndex
        self.imagesDirectory = imagesDirectory
    }

    /// Flat bundle layout rooted at a `Resources` directory.
    public static func bundle(_ resources: URL) -> ResourcePaths {
        ResourcePaths(
            quotes: resources.appendingPathComponent("quotes.json"),
            corpusMeta: resources.appendingPathComponent("corpus_meta.json"),
            schema: resources.appendingPathComponent("schema.sql"),
            webIndex: resources.appendingPathComponent("web/index.html"),
            imagesDirectory: resources
        )
    }

    /// Source-tree layout rooted at the repository root.
    public static func repository(_ root: URL) -> ResourcePaths {
        ResourcePaths(
            quotes: root.appendingPathComponent("data/quotes.json"),
            corpusMeta: root.appendingPathComponent("data/corpus_meta.json"),
            schema: root.appendingPathComponent("data/schema.sql"),
            webIndex: root.appendingPathComponent("web/index.html"),
            imagesDirectory: root.appendingPathComponent("app/Resources")
        )
    }

    /// Repository root derived from this source file's location (app/Sources/ZeroCortisolCore/…).
    public static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ZeroCortisolCore
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // app
            .deletingLastPathComponent()  // repo root
    }

    public var isComplete: Bool {
        let fm = FileManager.default
        return [quotes, corpusMeta, schema].allSatisfy { fm.fileExists(atPath: $0.path) }
    }

    /// Prefers `Bundle.main.resourceURL`; falls back to the repository layout for development.
    public static func locate(bundle: Bundle = .main) -> ResourcePaths {
        if let res = bundle.resourceURL {
            let candidate = ResourcePaths.bundle(res)
            if candidate.isComplete { return candidate }
        }
        return ResourcePaths.repository(repositoryRoot)
    }
}

public enum AppPaths {
    /// `~/Library/Application Support/ZeroCortisol`, overridable with `ZC_HOME` (used for smoke tests).
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ZC_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ZeroCortisol", isDirectory: true)
    }

    public static var database: URL { supportDirectory.appendingPathComponent("zc.sqlite") }
    public static var webDirectory: URL { supportDirectory.appendingPathComponent("web", isDirectory: true) }
}
