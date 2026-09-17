import AppKit
import SwiftUI
import ZeroCortisolCore

struct PanelView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            TruthOfDayView(model: model)

            Text("Pins: \(model.pinCount) | Streak: \(model.streak)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()
            TrackerView(model: model)
            Divider()
            ArchiveView(model: model)
            Divider()

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }
                Button {
                    model.openWebNode()
                } label: {
                    Label("Web Node", systemImage: "sparkles")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)

            if let error = model.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(PanelWindowObserver { open in
            if model.panelOpen != open { model.panelOpen = open }
            if open { model.refresh() }
        })
        .onAppear {
            model.panelOpen = true
            model.refresh()
        }
        .onDisappear { model.panelOpen = false }
    }
}

// MARK: - Truth of the Day

struct TruthOfDayView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRUTH OF THE DAY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let truth = model.truth {
                    Button {
                        model.toggleTruthPin()
                    } label: {
                        Image(systemName: model.truthPinned ? "pin.fill" : "pin")
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .help(model.truthPinned ? "Unpin \(truth.id)" : "Pin this quote")
                    .accessibilityLabel(model.truthPinned ? "Unpin" : "Pin")
                }
            }

            if let truth = model.truth {
                // Long passages scroll inside a fixed maximum height.
                ViewThatFits(in: .vertical) {
                    quoteText(truth)
                    ScrollView(.vertical) { quoteText(truth).padding(.trailing, 6) }
                        .frame(height: 170)
                }
                .frame(maxHeight: 170)

                Text("— \(truth.author), \(truth.work)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No quotes available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quoteText(_ quote: Quote) -> some View {
        Text(quote.text)
            .font(.system(size: 14, weight: .regular, design: .serif))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Panel open/closed detection

/// Reports whether the hosting MenuBarExtra window is shown (key and visible).
struct PanelWindowObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            guard let window else { return }
            let center = NotificationCenter.default
            let report: (Notification) -> Void = { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                let open = window.isVisible && window.occlusionState.contains(.visible) && window.isKeyWindow
                DispatchQueue.main.async { self?.onChange?(open) }
            }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                tokens.append(center.addObserver(forName: name, object: window, queue: .main, using: report))
            }
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
