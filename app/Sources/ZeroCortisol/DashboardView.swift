import AppKit
import Charts
import SwiftUI
import ZeroCortisolCore

// MARK: - Palette (categorical slots 1–4, stepped separately for light and dark)

enum ChartPalette {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    static let blue = dynamic(light: 0x2A78D6, dark: 0x3987E5)
    static let orange = dynamic(light: 0xEB6834, dark: 0xD95926)
    static let aqua = dynamic(light: 0x1BAF7A, dark: 0x199E70)
    static let yellow = dynamic(light: 0xEDA100, dark: 0xC98500)
    static let actual = dynamic(light: 0x8A8984, dark: 0x9C9B95)

    static func color(for metric: Metric) -> Color {
        switch metric {
        case .mood: return blue
        case .sleep: return orange
        case .strength: return aqua
        case .stillness: return yellow
        }
    }
}

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            CompositeTab(logs: model.logs)
                .tabItem { Text("Composite Wellbeing") }
            SplitTab(logs: model.logs)
                .tabItem { Text("Split Scores") }
            TrajectoryTab(result: model.trajectory)
                .tabItem { Text("Current Trajectory") }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
        .toolbar {
            ToolbarItem {
                Button {
                    model.openWebNode()
                } label: {
                    Label("Web Node", systemImage: "sparkles")
                }
                .help("Open the constellation of your pins")
            }
        }
        .onAppear { model.refresh() }
    }
}

// MARK: - Shared pieces

private struct EmptyChartState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No logs yet", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Log mood, sleep, strength and stillness from the menu bar tracker. Charts appear after the first day.")
        }
    }
}

private struct TabHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func chartDate(_ key: String) -> Date { DayKey.date(key) ?? Date() }

private func nearest<T>(_ items: [T], to date: Date?, by keyPath: (T) -> Date) -> T? {
    guard let date else { return nil }
    return items.min { abs(keyPath($0).timeIntervalSince(date)) < abs(keyPath($1).timeIntervalSince(date)) }
}

private let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

private struct Tooltip: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.system(size: 11, weight: i == 0 ? .semibold : .regular, design: i == 0 ? .default : .monospaced))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

// MARK: - Tab 1: Composite

private struct CompositeTab: View {
    let logs: [DailyLog]
    @State private var selection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Composite Wellbeing",
                      subtitle: "Mood×1 + Sleep×1 + Strength×2 + Stillness×2  (range 6–54)")
            if logs.isEmpty {
                EmptyChartState()
            } else {
                let selected = nearest(logs, to: selection) { chartDate($0.date) }
                Chart {
                    ForEach(logs) { log in
                        LineMark(x: .value("Date", chartDate(log.date), unit: .day),
                                 y: .value("Composite", log.composite))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(ChartPalette.blue)
                        PointMark(x: .value("Date", chartDate(log.date), unit: .day),
                                  y: .value("Composite", log.composite))
                            .symbolSize(logs.count > 45 ? 0 : 36)
                            .foregroundStyle(ChartPalette.blue)
                    }
                    if let selected {
                        RuleMark(x: .value("Date", chartDate(selected.date), unit: .day))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Tooltip(lines: [shortDate.string(from: chartDate(selected.date)),
                                                "Composite \(selected.composite)",
                                                selected.condensed])
                            }
                    }
                }
                .chartYScale(domain: 6...54)
                .chartYAxis { AxisMarks(values: [6, 18, 30, 42, 54]) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                .chartXSelection(value: $selection)
            }
        }
    }
}

// MARK: - Tab 2: Split scores

private struct SplitPoint: Identifiable {
    let date: Date
    let metric: Metric
    let value: Int
    var id: String { "\(metric.rawValue)-\(date.timeIntervalSince1970)" }
}

private struct SplitTab: View {
    let logs: [DailyLog]
    @State private var selection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Split Scores", subtitle: "Each metric on its 1–9 scale. Weights in the composite are shown in the legend.")
            if logs.isEmpty {
                EmptyChartState()
            } else {
                let points = logs.flatMap { log in
                    Metric.allCases.map { SplitPoint(date: chartDate(log.date), metric: $0, value: $0.value(in: log)) }
                }
                let selected = nearest(logs, to: selection) { chartDate($0.date) }
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date, unit: .day),
                                 y: .value("Score", p.value),
                                 series: .value("Metric", p.metric.legendLabel))
                            .foregroundStyle(by: .value("Metric", p.metric.legendLabel))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    if let selected {
                        RuleMark(x: .value("Date", chartDate(selected.date), unit: .day))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Tooltip(lines: [shortDate.string(from: chartDate(selected.date))]
                                        + Metric.allCases.map { "\($0.legendLabel): \($0.value(in: selected))" })
                            }
                    }
                }
                .chartForegroundStyleScale(domain: Metric.allCases.map(\.legendLabel),
                                           range: Metric.allCases.map(ChartPalette.color(for:)))
                .chartLegend(position: .top, alignment: .leading, spacing: 10)
                .chartYScale(domain: 1...9)
                .chartYAxis { AxisMarks(values: [1, 3, 5, 7, 9]) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                .chartXSelection(value: $selection)
            }
        }
    }
}

// MARK: - Tab 3: Trajectory

private struct TrajectoryTab: View {
    let result: TrajectoryResult
    @State private var selection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Current Trajectory",
                      subtitle: "Last ≤30 days. Rises count fast (α 0.6), dips count slowly (α 0.1); a downward slope is softened ×0.25 in the 7-day projection.")
            if result.isEmpty {
                EmptyChartState()
            } else {
                legend
                Chart {
                    ForEach(result.actual, id: \.day) { p in
                        PointMark(x: .value("Date", chartDate(p.dateKey), unit: .day), y: .value("Composite", p.value))
                            .foregroundStyle(ChartPalette.actual)
                            .symbolSize(30)
                    }
                    ForEach(result.smoothed, id: \.day) { p in
                        LineMark(x: .value("Date", chartDate(p.dateKey), unit: .day), y: .value("Composite", p.value),
                                 series: .value("Series", "Smoothed"))
                            .foregroundStyle(ChartPalette.blue)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    ForEach(result.projection, id: \.day) { p in
                        LineMark(x: .value("Date", chartDate(p.dateKey), unit: .day), y: .value("Composite", p.value),
                                 series: .value("Series", "Projection"))
                            .foregroundStyle(ChartPalette.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                    }
                    if let hover = hoverLines {
                        RuleMark(x: .value("Date", hover.date, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Tooltip(lines: hover.lines)
                            }
                    }
                }
                .chartYScale(domain: 6...54)
                .chartYAxis { AxisMarks(values: [6, 18, 30, 42, 54]) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                .chartXSelection(value: $selection)

                summary
            }
        }
    }

    private var hoverLines: (date: Date, lines: [String])? {
        guard let selection else { return nil }
        let all = Set(result.smoothed.map(\.day) + result.projection.map(\.day))
        guard let day = all.min(by: { abs(chartDate(DayKey.key(forDayNumber: $0)).timeIntervalSince(selection)) < abs(chartDate(DayKey.key(forDayNumber: $1)).timeIntervalSince(selection)) }) else { return nil }
        let date = chartDate(DayKey.key(forDayNumber: day))
        var lines = [shortDate.string(from: date)]
        if let a = result.actual.first(where: { $0.day == day }) { lines.append("Actual     \(Int(a.value))") }
        if let s = result.smoothed.first(where: { $0.day == day }) { lines.append(String(format: "Smoothed   %.1f", s.value)) }
        if let p = result.projection.first(where: { $0.day == day }), result.smoothed.last?.day != day {
            lines.append(String(format: "Projection %.1f", p.value))
        }
        return (date, lines)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Circle().fill(ChartPalette.actual).frame(width: 7, height: 7)
                Text("Actual")
            }
            HStack(spacing: 5) {
                Capsule().fill(ChartPalette.blue).frame(width: 18, height: 2.5)
                Text("Smoothed")
            }
            HStack(spacing: 5) {
                Path { p in p.move(to: .init(x: 0, y: 1)); p.addLine(to: .init(x: 18, y: 1)) }
                    .stroke(ChartPalette.blue, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 18, height: 2)
                Text("7-day projection")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var summary: some View {
        let now = result.smoothed.last?.value ?? 0
        let ahead = result.projection.last?.value ?? now
        let arrow = result.appliedSlope > 0.05 ? "↗" : (result.appliedSlope < -0.05 ? "↘" : "→")
        return HStack(spacing: 18) {
            Text(String(format: "Smoothed now: %.1f", now))
            Text(String(format: "In 7 days: %.1f %@", ahead, arrow))
            Text("Days in window: \(result.actual.count)")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Developer snapshots (`ZeroCortisol --snapshot-charts <dir>`)

@MainActor
enum ChartSnapshots {
    static func render(model: AppModel, to directory: URL, dark: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let views: [(String, AnyView)] = [
            ("composite", AnyView(CompositeTab(logs: model.logs))),
            ("split", AnyView(SplitTab(logs: model.logs))),
            ("trajectory", AnyView(TrajectoryTab(result: model.trajectory))),
        ]
        for (name, view) in views {
            let content = view
                .padding(16)
                .frame(width: 760, height: 480)
                .background(dark ? Color(white: 0.12) : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
            else { continue }
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }
}
