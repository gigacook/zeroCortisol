import AppKit
import WebKit

/// Always-on-top panel that shows the constellation page next to the menu bar flyout.
@MainActor
final class WebNodePanel: NSObject, NSWindowDelegate {
    static let shared = WebNodePanel()

    private var panel: NSPanel?
    private var webView: WKWebView?

    func show(_ url: URL) {
        let panel = self.panel ?? makePanel()
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Web Node"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 720, height: 460)
        panel.backgroundColor = NSColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1)
        panel.delegate = self

        let webView = WKWebView(frame: panel.contentView?.bounds ?? .zero)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        panel.contentView?.addSubview(webView)

        self.panel = panel
        self.webView = webView
        return panel
    }

    /// Top-right of the screen, just under the menu bar, left of where the flyout drops down.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { panel.center(); return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = max(visible.minX + 12, visible.maxX - size.width - 380)
        let y = visible.maxY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
