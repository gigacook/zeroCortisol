import AppKit
import WebKit
import ZeroCortisolCore

/// Borderless windows refuse key status by default; the node view needs keys (Esc, D).
private final class NodeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// What the page gets back after logging today: the fresh counters, or why it failed.
struct LogReply {
    let composite: Int
    let streak: Int
    let total: Int
}

/// Full-screen constellation view. Esc closes it (and the dashboard) instantly.
@MainActor
final class WebNodePanel: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = WebNodePanel()

    /// Saves today's scores from the page's action bar. Set by AppModel before showing.
    var onLog: ((_ mood: Int, _ sleep: Int, _ strength: Int, _ stillness: Int) -> LogReply?)?

    private var window: NSWindow?
    private var webView: WKWebView?
    private var keyMonitor: Any?

    func show(_ url: URL) {
        let window = self.window ?? makeWindow()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen { window.setFrame(screen.frame, display: true) }
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        installKeyMonitor()
    }

    /// Closes the node view and every other open zeroCortisol window.
    func closeAll() {
        removeKeyMonitor()
        window?.orderOut(nil)
        for other in NSApp.windows where other.identifier?.rawValue.contains("dashboard") == true {
            other.close()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NodeWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = NSColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1)

        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "zc")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView

        self.window = window
        self.webView = webView
        return window
    }

    /// `window.webkit.messageHandlers.zc.postMessage({type: "log", mood, sleep, strength, stillness})`
    /// resolves with `{composite, streak, total}` or rejects with a message.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "log" else {
            return replyHandler(nil, "Unknown message")
        }
        let values = ["mood", "sleep", "strength", "stillness"].compactMap { (body[$0] as? NSNumber)?.intValue }
        guard values.count == 4, values.allSatisfy(Scoring.valueRange.contains) else {
            return replyHandler(nil, "Scores must be 1–9")
        }
        guard let reply = onLog?(values[0], values[1], values[2], values[3]) else {
            return replyHandler(nil, "Couldn't save today's log")
        }
        replyHandler(["composite": reply.composite, "streak": reply.streak, "total": reply.total], nil)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.closeAll() }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
