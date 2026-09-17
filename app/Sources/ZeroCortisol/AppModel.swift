import AppKit
import Foundation
import Observation
import ZeroCortisolCore

@MainActor
@Observable
final class AppModel {
    let resources: ResourcePaths
    private(set) var store: Store?
    private(set) var loadError: String?

    // Menu bar state
    var panelOpen = false

    // Today
    private(set) var todayKey = DayKey.today()
    private(set) var truth: Quote?
    private(set) var truthPinned = false
    private(set) var todayLog: DailyLog?

    // Counters
    private(set) var pinCount = 0
    private(set) var streak = 0
    private(set) var total = 0

    // Archive
    private(set) var tags: [Tag] = []
    private(set) var archivePins: [Pin] = []
    var archiveFilter: ArchiveFilter = .all {
        didSet { reloadArchive() }
    }

    // Dashboard
    private(set) var logs: [DailyLog] = []
    private(set) var trajectory: TrajectoryResult = .empty

    private(set) var lastError: String?

    init(resources: ResourcePaths = .locate()) {
        self.resources = resources
        do {
            store = try Store(path: AppPaths.database.path, resources: resources)
        } catch {
            loadError = "Could not open the database: \(error)"
        }
        refresh()
    }

    // MARK: - Loading

    func refresh() {
        guard let store else { return }
        todayKey = DayKey.today()
        attempt {
            truth = try store.truthOfDay(todayKey)
            truthPinned = try truth.map { try store.isPinned(quoteID: $0.id) } ?? false
            todayLog = try store.log(for: todayKey)
            pinCount = try store.pinCount()
            logs = try store.logs()
            streak = Streaks.streak(logDates: logs.map(\.date), today: todayKey)
            total = Streaks.total(logDates: logs.map(\.date))
            trajectory = Trajectory.compute(logs)
            tags = try store.tags()
        }
        if case .tag(let id) = archiveFilter, !tags.contains(where: { $0.id == id }) {
            archiveFilter = .all  // didSet reloads
        } else {
            reloadArchive()
        }
    }

    private func reloadArchive() {
        guard let store else { return }
        attempt { archivePins = try store.pins(archiveFilter) }
    }

    private func attempt(_ body: () throws -> Void) {
        do {
            try body()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    // MARK: - Pins

    func toggleTruthPin() {
        guard let store, let truth else { return }
        attempt {
            if try store.isPinned(quoteID: truth.id) {
                try store.unpin(quoteID: truth.id)
            } else {
                try store.pin(quoteID: truth.id)
            }
        }
        refresh()
    }

    func unpin(_ pin: Pin) {
        guard let store else { return }
        attempt { try store.unpin(pinID: pin.id) }
        refresh()
    }

    // MARK: - Tags

    func addTag(named name: String, to pin: Pin) {
        guard let store else { return }
        attempt {
            if let tag = try store.createTag(name) {
                try store.addTag(tagID: tag.id, toPin: pin.id)
            }
        }
        refresh()
    }

    func addTag(_ tag: Tag, to pin: Pin) {
        guard let store else { return }
        attempt { try store.addTag(tagID: tag.id, toPin: pin.id) }
        refresh()
    }

    func removeTag(_ tag: Tag, from pin: Pin) {
        guard let store else { return }
        attempt { try store.removeTag(tagID: tag.id, fromPin: pin.id) }
        refresh()
    }

    func createTag(named name: String) {
        guard let store else { return }
        attempt { _ = try store.createTag(name) }
        refresh()
    }

    func deleteTag(_ tag: Tag) {
        guard let store else { return }
        attempt { try store.deleteTag(id: tag.id) }
        refresh()
    }

    // MARK: - Tracker

    func saveToday(mood: Int, sleep: Int, strength: Int, stillness: Int) {
        guard let store else { return }
        let key = DayKey.today()
        attempt { try store.saveLog(DailyLog(date: key, mood: mood, sleep: sleep, strength: strength, stillness: stillness)) }
        refresh()
    }

    // MARK: - Web node

    /// Writes data.js + index.html into Application Support and returns the page URL.
    func exportWebNode() -> URL? {
        guard let store else { return nil }
        var url: URL?
        attempt {
            url = try WebExport.export(store: store, indexHTML: resources.webIndex, to: AppPaths.webDirectory)
        }
        return url
    }

    /// Exports the constellation page and shows it full screen.
    func openWebNode() {
        guard let url = exportWebNode() else { return }
        WebNodePanel.shared.show(url)
    }

    // MARK: - Menu bar images

    func menuBarImage(open: Bool) -> NSImage {
        let name = open ? "menubar_open" : "menubar_closed"
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for suffix in ["", "@2x"] {
            let url = resources.imagesDirectory.appendingPathComponent("\(name)\(suffix).png")
            if let rep = NSImageRep(contentsOf: url) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
            }
        }
        if image.representations.isEmpty {
            return NSImage(systemSymbolName: open ? "eye" : "eye.slash", accessibilityDescription: "zeroCortisol")
                ?? image
        }
        image.isTemplate = true
        image.accessibilityDescription = "zeroCortisol"
        return image
    }
}
