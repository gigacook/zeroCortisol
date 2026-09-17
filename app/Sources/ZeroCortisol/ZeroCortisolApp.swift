import AppKit
import SwiftUI
import ZeroCortisolCore

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--export-web") {
            exit(CommandLineTools.exportWeb(open: args.contains("--open")))
        }
        if let i = args.firstIndex(of: "--snapshot-charts"), i + 1 < args.count {
            // Developer aid: renders the dashboard charts to PNGs (uses ZC_HOME's database).
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            MainActor.assumeIsolated {
                let model = AppModel()
                for dark in [false, true] { try? ChartSnapshots.render(model: model, to: dir, dark: dark) }
            }
            exit(0)
        }
        if args.contains("--help") || args.contains("-h") {
            print("""
                ZeroCortisol — menu bar app.
                  --export-web [--open]        write data.js + index.html to Application Support/ZeroCortisol/web and exit
                  --snapshot-charts <dir>      render the dashboard charts to PNG files and exit (developer aid)
                Environment: ZC_HOME overrides the Application Support directory.
                """)
            exit(0)
        }
        ZeroCortisolApp.main()
    }
}

enum CommandLineTools {
    static func exportWeb(open: Bool) -> Int32 {
        let resources = ResourcePaths.locate()
        do {
            let store = try Store(path: AppPaths.database.path, resources: resources)
            let index = try WebExport.export(store: store, indexHTML: resources.webIndex, to: AppPaths.webDirectory)
            print("database: \(AppPaths.database.path) (quotes: \(try store.quoteCount()), pins: \(try store.pinCount()))")
            print("wrote: \(index.deletingLastPathComponent().appendingPathComponent("data.js").path)")
            print("wrote: \(index.path)")
            if open { NSWorkspace.shared.open(index) }
            return 0
        } catch {
            FileHandle.standardError.write("export failed: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar only (also set by LSUIElement in the bundle; this covers `swift run`).
        NSApp.setActivationPolicy(.accessory)
    }
}

struct ZeroCortisolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(nsImage: model.menuBarImage(open: model.panelOpen))
        }
        .menuBarExtraStyle(.window)

        Window("zeroCortisol Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
        .defaultSize(width: 780, height: 540)
        .windowResizability(.contentMinSize)
    }
}
