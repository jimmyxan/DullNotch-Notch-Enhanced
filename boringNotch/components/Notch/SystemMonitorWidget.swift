//
//  SystemMonitorWidget.swift
//  boringNotch
//
//  Small home widget: up to two system metrics (CPU, memory, GPU, CPU / GPU temperature),
//  each with its current value and a sparkline of the last 2 minutes.
//

import Combine
import Darwin
import Defaults
import SwiftUI

// MARK: - Model

enum SystemMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, cpuTemp, gpuTemp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .cpuTemp: return "CPU temp"
        case .gpuTemp: return "GPU temp"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "cube.transparent"
        case .cpuTemp, .gpuTemp: return "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .cpu: return Color(red: 0.25, green: 0.6, blue: 1)
        case .memory: return Color(red: 0.2, green: 0.82, blue: 0.45)
        case .gpu: return Color(red: 0.69, green: 0.45, blue: 1)
        case .cpuTemp: return Color(red: 1, green: 0.62, blue: 0.2)
        case .gpuTemp: return Color(red: 1, green: 0.38, blue: 0.5)
        }
    }

    var isTemperature: Bool { self == .cpuTemp || self == .gpuTemp }

    /// Fixed scale so peaks read the same every time (no auto-zoom on noise).
    var range: ClosedRange<Double> { isTemperature ? 20...105 : 0...100 }

    func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        return isTemperature ? "\(Int(value.rounded()))°" : "\(Int(value.rounded()))%"
    }
}

struct MetricSample: Equatable {
    var time: Date
    var value: Double
}

// MARK: - Views

/// Line + soft area over a fixed time window, newest at the right edge.
struct Sparkline: View {
    let samples: [MetricSample]
    let range: ClosedRange<Double>
    let color: Color
    var window: TimeInterval = 120
    var now = Date()

    var body: some View {
        GeometryReader { geo in
            let points = samples.map { s in
                CGPoint(
                    x: geo.size.width * CGFloat(1 - min(max(now.timeIntervalSince(s.time) / window, 0), 1)),
                    y: geo.size.height * CGFloat(1 - (min(max(s.value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound))
                )
            }
            if points.count > 1 {
                let line = Path { p in p.addLines(points) }
                let area = Path { p in
                    p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) } // addLines would start a new subpath
                    p.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                    p.closeSubpath()
                }
                area.fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Circle().fill(color).frame(width: 4, height: 4).position(points[points.count - 1])
            }
        }
    }
}

/// Data-driven body, also used with sample data by the settings preview.
struct SystemMonitorContent: View {
    let metrics: [SystemMetric]
    let history: [SystemMetric: [MetricSample]]
    var hovering = false
    var now = Date()

    var body: some View {
        VStack(spacing: 10) {
            ForEach(metrics) { metric in
                row(metric)
                if metric != metrics.last { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WidgetCard(highlighted: hovering))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metrics.map { "\($0.title) \($0.format(history[$0]?.last?.value))" }.joined(separator: ", "))
    }

    private func row(_ metric: SystemMetric) -> some View {
        let samples = history[metric] ?? []
        let peak = samples.map(\.value).max()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(metric.color)
                Text(hovering ? "Peak" : metric.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(metric.format(hovering ? peak : samples.last?.value))
                    .font(.system(size: metrics.count == 1 ? 24 : 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Sparkline(samples: samples, range: metric.range, color: metric.color, now: now)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Live data

extension SystemMetric: Defaults.Serializable {}

extension Defaults.Keys {
    /// One or two metrics, in display order.
    static let systemMonitorMetrics = Key<[SystemMetric]>("systemMonitorMetrics", default: [.cpu, .memory])
}

/// Samples on one fixed 3 s grid for as long as the widget is in the home layout, so the
/// graph is always the full last 2 minutes, with the same resolution whether the notch is
/// open or not. Each CPU point is the true average since the previous one (tick deltas), so
/// short spikes still show. Cost per sample: microseconds for CPU / memory, a few ms for the
/// sensors (read only when chosen). The timer has tolerance so macOS can batch wake-ups,
/// and it stops by itself while the Mac sleeps.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    static let interval: TimeInterval = 3

    @Published private(set) var history: [SystemMetric: [MetricSample]] = [:]
    @Published private(set) var now = Date()

    private var timer: Timer?
    private var previousTicks: [UInt32]?
    private var sampling = false
    private var cancellables: Set<AnyCancellable> = []

    /// Call once at launch.
    func activate() {
        Defaults.publisher(.homeWidgets).sink { [weak self] _ in self?.reschedule() }.store(in: &cancellables)
        // keep the history of metrics still shown; drop only the ones removed
        Defaults.publisher(.systemMonitorMetrics).sink { [weak self] change in
            self?.history = self?.history.filter { change.newValue.contains($0.key) } ?? [:]
        }.store(in: &cancellables)
    }

    private func reschedule() {
        guard Defaults[.homeWidgets].contains(.systemMonitor) else {
            timer?.invalidate()
            timer = nil
            history = [:]
            previousTicks = nil
            return
        }
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in SystemMonitor.shared.sample() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        guard !sampling else { return }
        let metrics = Defaults[.systemMonitorMetrics]
        let time = Date()
        var values: [SystemMetric: Double] = [:]
        if metrics.contains(.cpu), let cpu = cpuUsage() { values[.cpu] = cpu }
        if metrics.contains(.memory), let mem = Self.memoryUsage() { values[.memory] = mem }
        guard metrics.contains(where: { $0 == .gpu || $0.isTemperature }) else { return append(values, at: time) }
        sampling = true
        Task {
            let sensors = await XPCHelperClient.shared.systemSensors()
            sampling = false
            values[.gpu] = sensors.gpu
            values[.cpuTemp] = sensors.cpuTemp
            values[.gpuTemp] = sensors.gpuTemp
            append(values.filter { metrics.contains($0.key) }, at: time)
        }
    }

    private func append(_ values: [SystemMetric: Double], at time: Date) {
        var next = history
        for (metric, value) in values {
            next[metric, default: []].append(MetricSample(time: time, value: value))
            next[metric]?.removeAll { time.timeIntervalSince($0.time) > 125 }
        }
        now = time
        history = next
    }

    /// Busy share of all cores since the previous call.
    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }
        let delta = zip(ticks, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (total - delta[2]) / total * 100 : nil
    }

    /// Activity Monitor's "Memory Used": app memory + wired + compressed.
    nonisolated static func memoryUsage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = Double(stats.internal_page_count) - Double(stats.purgeable_count)
            + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return min(100, pages * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100)
    }
}

/// Small widget wired to live data.
struct SystemMonitorWidget: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @Default(.systemMonitorMetrics) private var metrics
    @State private var hovering = false

    var body: some View {
        SystemMonitorContent(metrics: metrics, history: monitor.history, hovering: hovering, now: monitor.now)
            .animation(.smooth(duration: 0.25), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Settings › Widgets section, shown while the widget is in the notch.
struct SystemMonitorSettings: View {
    @Default(.systemMonitorMetrics) private var metrics

    var body: some View {
        Section {
            Picker("Top", selection: slot(0)) {
                ForEach(SystemMetric.allCases) { m in Label(m.title, systemImage: m.symbol).tag(Optional(m)) }
            }
            Picker("Bottom", selection: slot(1)) {
                Text("None").tag(SystemMetric?.none)
                ForEach(SystemMetric.allCases.filter { $0 != metrics.first }) { m in
                    Label(m.title, systemImage: m.symbol).tag(Optional(m))
                }
            }
        } header: {
            Text("System monitor")
        } footer: {
            Text("Each metric shows its current value and the last 2 minutes. Hover the widget to see the peak. Temperatures are averages of the CPU and GPU die sensors (Apple silicon).")
        }
    }

    /// Slot 0 always has a metric; slot 1 is optional and never repeats slot 0.
    private func slot(_ index: Int) -> Binding<SystemMetric?> {
        Binding(
            get: { metrics.indices.contains(index) ? metrics[index] : nil },
            set: { new in
                var list = metrics
                if index == 0 {
                    guard let new else { return }
                    list[0] = new
                    if list.count > 1, list[1] == new { list.remove(at: 1) }
                } else if let new {
                    list = [list[0], new]
                } else {
                    list = [list[0]]
                }
                metrics = list
            }
        )
    }
}
