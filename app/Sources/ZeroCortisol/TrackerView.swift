import AppKit
import SwiftUI
import ZeroCortisolCore

/// Strict flow: mood → sleep → strength → stillness, then lock-in and collapse.
struct TrackerView: View {
    @Bindable var model: AppModel

    @State private var stage = 0
    @State private var values: [Int] = []
    @State private var justLocked = false
    @FocusState private var focused: Metric?

    private let order = Metric.allCases

    var body: some View {
        ZStack(alignment: .leading) {
            if let log = model.todayLog {
                condensed(log)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.35, anchor: .leading).combined(with: .opacity),
                        removal: .opacity))
            } else {
                flow
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: model.todayKey) { _, _ in resetFlow() }
    }

    // MARK: Input flow

    private var flow: some View {
        let metric = order[min(stage, order.count - 1)]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Personal Tracker:")
                    .font(.system(size: 12, weight: .semibold))
                Text(metric.rawValue)
                    .font(.system(size: 12, design: .monospaced))
                    .id(metric)
                    .transition(.push(from: .trailing).combined(with: .opacity))
                Menu {
                    ForEach(Scoring.valueRange, id: \.self) { value in
                        Button("\(value)") { select(value) }
                    }
                } label: {
                    Text("–")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minWidth: 18)
                }
                .menuStyle(.button)
                .fixedSize()
                .controlSize(.small)
                .focusable()
                .focused($focused, equals: metric)
                .id("menu-\(metric.rawValue)")
                .help("Select \(metric.rawValue) (1–9)")
                Spacer()
            }
            if !values.isEmpty {
                Text(zip(order, values).map { "\($0.short):\($1)" }.joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .onAppear { focused = metric }
    }

    private func select(_ value: Int) {
        guard values.count == stage, stage < order.count else { return }
        values.append(value)
        if stage < order.count - 1 {
            withAnimation(.snappy(duration: 0.22)) { stage += 1 }
            focused = order[stage]
        } else {
            lockIn()
        }
    }

    private func lockIn() {
        guard values.count == 4 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        justLocked = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) {
            model.saveToday(mood: values[0], sleep: values[1], strength: values[2], stillness: values[3])
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.25)) { justLocked = false }
        stage = 0
        values = []
    }

    private func resetFlow() {
        stage = 0
        values = []
    }

    // MARK: Condensed row

    private func condensed(_ log: DailyLog) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(log.condensed)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(justLocked ? 0.28 : 0))
            )
            Text("Streak: \(model.streak) | Total: \(model.total)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .help("Today is logged. Composite \(log.composite)/54")
    }
}
