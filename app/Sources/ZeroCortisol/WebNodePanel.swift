import AppKit
import WebKit

/// Borderless windows refuse key status by default; the node view needs keys (Esc, D).
private final class NodeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen constellation view. Esc closes it (and the dashboard) instantly.
@MainActor
final class WebNodePanel: NSObject {
    static let shared = WebNodePanel()

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

        let webView = WKWebView(frame: .zero)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView

        self.window = window
        self.webView = webView
        return window
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
