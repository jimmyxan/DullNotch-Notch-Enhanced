//
//  NotchProgress.swift
//  boringNotch
//
//  Progress of whatever is going on, shown on the closed notch. One source at a time,
//  by priority: Clock timer, file download, charging (only while it advances), AI quota.
//

import Combine
import SwiftUI

// MARK: - Logic (pure: compiles outside the app up to "MARK: - Live sources")

/// Declaration order is the priority order.
enum ProgressSource: String, CaseIterable, Identifiable {
    case timer, download, charging, aiQuota

    var id: String { rawValue }
    var title: String {
        switch self {
        case .timer: return "Clock timers"
        case .download: return "Downloads"
        case .charging: return "Charging"
        case .aiQuota: return "AI quota"
        }
    }
}

enum ProgressStyle: String, CaseIterable, Identifiable {
    case wings, wire, hybrid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wings: return "Wings"
        case .wire: return "Wire"
        case .hybrid: return "Hybrid"
        }
    }
}

struct ProgressItem: Equatable {
    var source: ProgressSource
    /// 0...1, nil = in progress but amount unknown.
    var fraction: Double?
    var label: String
    /// SF Symbol name, or an asset name when `isAsset`.
    var icon: String
    var isAsset = false
    var tint: Color
}

enum NotchProgressLogic {
    /// How long a charge may sit at the same level before it stops counting as advancing.
    static let chargeStallAfter: TimeInterval = 600
    /// How old the AI numbers may be and still be shown.
    static let quotaFreshFor: TimeInterval = 600

    static func pick(_ candidates: [ProgressSource: ProgressItem], enabled: Set<ProgressSource>) -> ProgressItem? {
        ProgressSource.allCases.lazy.filter(enabled.contains).compactMap { candidates[$0] }.first
    }

    /// `lastRise`: when the level last went up, or when charging began.
    static func chargingAdvances(isCharging: Bool, level: Double, lastRise: Date?, now: Date) -> Bool {
        guard isCharging, level < 100, let lastRise else { return false }
        return now.timeIntervalSince(lastRise) < chargeStallAfter
    }

    /// "34:04" under an hour, "1:05:09" above.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    #if DEBUG
    static let selfCheck: Void = {
        func item(_ s: ProgressSource) -> ProgressItem { ProgressItem(source: s, fraction: 0.5, label: "", icon: "", tint: .white) }
        let all = Set(ProgressSource.allCases)
        let everything = Dictionary(uniqueKeysWithValues: ProgressSource.allCases.map { ($0, item($0)) })
        assert(pick(everything, enabled: all)?.source == .timer)
        assert(pick(everything, enabled: all.subtracting([.timer]))?.source == .download)
        assert(pick([.charging: item(.charging), .aiQuota: item(.aiQuota)], enabled: all)?.source == .charging)
        assert(pick([.aiQuota: item(.aiQuota)], enabled: all)?.source == .aiQuota)
        assert(pick([.aiQuota: item(.aiQuota)], enabled: [.timer]) == nil)
        assert(pick([:], enabled: all) == nil)

        let now = Date(timeIntervalSince1970: 10_000)
        assert(chargingAdvances(isCharging: true, level: 40, lastRise: now.addingTimeInterval(-60), now: now))
        // stuck at 80% for 11 minutes: not shown
        assert(!chargingAdvances(isCharging: true, level: 80, lastRise: now.addingTimeInterval(-660), now: now))
        // it moves again: shown again
        assert(chargingAdvances(isCharging: true, level: 81, lastRise: now, now: now))
        assert(!chargingAdvances(isCharging: false, level: 40, lastRise: now, now: now))
        assert(!chargingAdvances(isCharging: true, level: 100, lastRise: now, now: now))
        assert(!chargingAdvances(isCharging: true, level: 40, lastRise: nil, now: now))

        assert(clock(2044) == "34:04" && clock(3909) == "1:05:09" && clock(0.2) == "0:01" && clock(-5) == "0:00")
    }()
    #endif
}

// MARK: - Live sources

import Defaults

extension ProgressSource: Defaults.Serializable {}
extension ProgressStyle: Defaults.Serializable {}

extension Defaults.Keys {
    static let progressEnabled = Key<Bool>("progressEnabled", default: true)
    static let progressStyle = Key<ProgressStyle>("progressStyle", default: .wings)
    static let progressSources = Key<[ProgressSource]>("progressSources", default: ProgressSource.allCases)
    static let progressOverridesMusic = Key<Bool>("progressOverridesMusic", default: true)
}

@MainActor
final class NotchProgressManager: ObservableObject {
    static let shared = NotchProgressManager()

    @Published private(set) var current: ProgressItem?

    private var enabled: Set<ProgressSource> = []
    private var housekeeping: Timer?
    private var secondTick: Timer?
    private var observers = Set<AnyCancellable>()

    private var clockTimer: (fires: Date, duration: TimeInterval)?
    private var lastLevel: Float?
    private var wasCharging = false
    private var lastRise: Date?
    private var watchingQuota = false
    private let downloads = DownloadProgressWatcher()

    private init() {
        #if DEBUG
        _ = NotchProgressLogic.selfCheck
        #endif
        let battery = BatteryStatusViewModel.shared
        battery.$levelBattery.combineLatest(battery.$isCharging)
            .receive(on: RunLoop.main)
            .sink { [weak self] level, charging in self?.batteryChanged(level: level, charging: charging) }
            .store(in: &observers)
        let ai = AIUsageManager.shared
        ai.$state.map { _ in () }.merge(with: ai.$updated.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.recompute() }
            .store(in: &observers)
        downloads.onChange = { [weak self] in self?.recompute() }
        Defaults.publisher(keys: .progressEnabled, .progressSources, .aiUsageProvider)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.configure() }
            .store(in: &observers)
    }

    /// Starts or stops the sources to match the settings.
    private func configure() {
        enabled = Defaults[.progressEnabled] ? Set(Defaults[.progressSources]) : []

        // ponytail: one 5 s tick polls the Clock timer and the Downloads folder and expires a stalled
        // charge; a new timer or download can take up to 5 s to appear. Use file events if that's too slow.
        if enabled.isEmpty {
            housekeeping?.invalidate()
            housekeeping = nil
        } else if housekeeping == nil {
            housekeeping = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in NotchProgressManager.shared.poll() }
            }
        }

        let wantsQuota = enabled.contains(.aiQuota)
        if wantsQuota != watchingQuota {
            watchingQuota = wantsQuota
            wantsQuota ? AIUsageManager.shared.start() : AIUsageManager.shared.stop()
        }
        if !enabled.contains(.timer) { clockTimer = nil }
        if !enabled.contains(.download) { downloads.stop() }
        poll()
    }

    private func poll() {
        if enabled.contains(.download) { downloads.scan() }
        pollClock()
    }

    private var askingClock = false

    private func pollClock() {
        guard enabled.contains(.timer) else { return recompute() }
        guard !askingClock else { return }
        askingClock = true
        Task {
            clockTimer = await XPCHelperClient.shared.clockTimer()
            askingClock = false
            recompute()
        }
    }

    private func batteryChanged(level: Float, charging: Bool) {
        if charging, !wasCharging || level > (lastLevel ?? level) { lastRise = Date() }
        if !charging { lastRise = nil }
        wasCharging = charging
        lastLevel = level
        recompute()
    }

    private func recompute() {
        let now = Date()
        var candidates: [ProgressSource: ProgressItem] = [:]

        if let timer = clockTimer, timer.fires > now {
            let left = timer.fires.timeIntervalSince(now)
            candidates[.timer] = ProgressItem(
                // 0.5% steps: the wire and ring redraw every few seconds, not every second.
                // A timer starts full and drains.
                source: .timer, fraction: (min(1, max(0, left / timer.duration)) * 200).rounded() / 200,
                label: NotchProgressLogic.clock(left), icon: "timer", tint: .orange)
        } else {
            clockTimer = nil
        }
        // The countdown needs a 1 Hz tick, and only while a timer runs. The same tick re-reads Clock,
        // so a timer stopped or paused by hand disappears within a second instead of at the next 5 s poll.
        if clockTimer != nil, secondTick == nil {
            secondTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in NotchProgressManager.shared.pollClock() }
            }
        } else if clockTimer == nil {
            secondTick?.invalidate()
            secondTick = nil
        }

        if let download = downloads.active {
            candidates[.download] = ProgressItem(
                source: .download, fraction: download,
                label: "\(Int((download * 100).rounded()))%",
                icon: "arrow.down.circle.fill", tint: .blue)
        } else if downloads.isBusy {
            candidates[.download] = ProgressItem(source: .download, fraction: nil, label: "", icon: "arrow.down.circle.fill", tint: .blue)
        }

        let battery = BatteryStatusViewModel.shared
        if NotchProgressLogic.chargingAdvances(isCharging: battery.isCharging, level: Double(battery.levelBattery), lastRise: lastRise, now: now) {
            candidates[.charging] = ProgressItem(
                source: .charging, fraction: Double(battery.levelBattery) / 100,
                label: "\(Int(battery.levelBattery))%", icon: "bolt.fill", tint: .green)
        }

        let ai = AIUsageManager.shared
        if case .ready(let usage) = ai.state, let session = usage.session ?? usage.weekly,
           let updated = ai.updated, now.timeIntervalSince(updated) < NotchProgressLogic.quotaFreshFor {
            let provider = Defaults[.aiUsageProvider]
            candidates[.aiQuota] = ProgressItem(
                source: .aiQuota, fraction: Double(session.remaining) / 100,
                label: "\(session.remaining)%", icon: provider.logo, isAsset: true, tint: provider.ringColors.outer)
        }

        let next = NotchProgressLogic.pick(candidates, enabled: enabled)
        if next != current { current = next }
    }
}

/// Files being downloaded into ~/Downloads. Browsers publish an `NSProgress` on the partial file;
/// subscribing to it gives the real fraction without parsing anything.
@MainActor
final class DownloadProgressWatcher {
    var onChange: (() -> Void)?

    private static let partialExtensions: Set<String> = ["download", "crdownload", "part"]
    private var subscribers: [URL: Any] = [:]
    private var published: [ObjectIdentifier: (progress: Progress, observation: NSKeyValueObservation)] = [:]
    private(set) var isBusy = false

    /// Fraction of the least advanced published download; nil = none publishes its progress.
    var active: Double? {
        published.values.map(\.progress).filter { !$0.isFinished && !$0.isCancelled && !$0.isIndeterminate }
            .map(\.fractionCompleted).min()
    }

    func scan() {
        // In the sandbox FileManager answers with the container's own Downloads; the entitlement is for the real one.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return }
        let folder = URL(fileURLWithPath: String(cString: home)).appendingPathComponent("Downloads", isDirectory: true)
        let partials = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? [])
            .filter { Self.partialExtensions.contains($0.pathExtension.lowercased()) }

        // Subscribe to each partial file; drop the ones that are gone.
        for url in partials where subscribers[url] == nil {
            subscribers[url] = Progress.addSubscriber(forFileURL: url) { [weak self] progress in
                Task { @MainActor in self?.add(progress) }
                return { Task { @MainActor in self?.remove(progress) } }
            }
        }
        for (url, subscriber) in subscribers where !partials.contains(url) {
            Progress.removeSubscriber(subscriber)
            subscribers[url] = nil
        }

        // Fallback for browsers that publish nothing: a partial file written in the last 30 s.
        let busy = partials.contains { url in
            // Safari's .download is a folder: the growing file is inside it.
            let inner = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
            return ([url] + inner).contains {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
                    .map { Date().timeIntervalSince($0) < 30 } ?? false
            }
        }
        if busy != isBusy {
            isBusy = busy
            onChange?()
        }
    }

    func stop() {
        subscribers.values.forEach(Progress.removeSubscriber)
        subscribers = [:]
        published = [:]
        isBusy = false
    }

    private func add(_ progress: Progress) {
        let observation = progress.observe(\.fractionCompleted) { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        published[ObjectIdentifier(progress)] = (progress, observation)
        onChange?()
    }

    private func remove(_ progress: Progress) {
        published[ObjectIdentifier(progress)] = nil
        onChange?()
    }
}

// MARK: - Views

/// Icon of the source, sized to the closed notch.
struct NotchProgressIcon: View {
    let item: ProgressItem

    var body: some View {
        Group {
            if item.isAsset {
                Image(item.icon).resizable().renderingMode(.template).scaledToFit().padding(2)
            } else {
                Image(systemName: item.icon).resizable().scaledToFit().padding(2)
            }
        }
        .foregroundStyle(item.tint)
        .accessibilityLabel("\(item.source.title) \(item.label)")
    }
}

/// Right wing: the countdown for a timer, a ring for everything else.
struct NotchProgressValue: View {
    let item: ProgressItem
    @State private var pulse = false

    var body: some View {
        if item.source == .timer {
            Text(item.label)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            ZStack {
                Circle().stroke(item.tint.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: item.fraction ?? 0.25)
                    .stroke(item.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(item.fraction == nil && pulse ? 270 : -90))
            }
            .padding(3)
            .animation(.smooth(duration: 0.4), value: item.fraction)
            .animation(item.fraction == nil ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: pulse)
            .onAppear { pulse = true }
        }
    }
}

/// Sides and bottom of the closed notch, pushed out by `grow` so a stroke sits just outside it:
/// anything drawn inside the outline is behind the camera housing and can't be seen.
struct NotchOutline: Shape {
    var grow: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = cornerRadiusInsets.closed.top - grow
        let radius = cornerRadiusInsets.closed.bottom + grow
        let (left, right, bottom) = (rect.minX + inset, rect.maxX - inset, rect.maxY + grow)
        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - radius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        return path
    }
}

/// Line that runs around the closed notch, following its shape. Give it the notch's own frame.
struct NotchProgressWire: View {
    let item: ProgressItem
    var lineWidth: CGFloat = 2
    @State private var pulse = false

    /// A timer about to end turns red; everything else keeps its colour.
    private var tint: Color {
        item.source == .timer && (item.fraction ?? 1) < 0.15 ? .red : item.tint
    }

    /// Faint at the start of the line, full colour at its moving end, so the eye lands on where it is now.
    /// The line runs left to right around the notch, so the end sits at about `fraction` of the width.
    private var gradient: LinearGradient {
        LinearGradient(
            stops: [.init(color: tint.opacity(0.3), location: 0), .init(color: tint, location: 1)],
            startPoint: .leading,
            endPoint: UnitPoint(x: max(0.05, item.fraction ?? 1), y: 0.5)
        )
    }

    var body: some View {
        let outline = NotchOutline(grow: lineWidth / 2)
        ZStack {
            outline.stroke(.black, lineWidth: lineWidth)
            outline.stroke(tint.opacity(0.18), lineWidth: lineWidth)
            outline
                .trim(from: 0, to: item.fraction ?? 1)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: tint.opacity(0.7), radius: 2.5)
                .opacity(item.fraction == nil ? (pulse ? 1 : 0.25) : 1)
        }
        .animation(.smooth(duration: 0.4), value: item.fraction)
        .animation(item.fraction == nil ? .easeInOut(duration: 0.9).repeatForever() : .default, value: pulse)
        .onAppear { pulse = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Settings

struct ProgressSettings: View {
    @Default(.progressEnabled) private var enabled
    @Default(.progressStyle) private var style
    @Default(.progressSources) private var sources
    @Default(.progressOverridesMusic) private var overridesMusic
    @Default(.aiUsageProvider) private var provider
    @ObservedObject private var ai = AIUsageManager.shared
    @ObservedObject private var progress = NotchProgressManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show progress on the closed notch", isOn: $enabled)
                LabeledContent("Showing now") {
                    Text(progress.current.map { "\($0.source.title) \($0.label)" } ?? "Nothing in progress")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Style", selection: $style) {
                    ForEach(ProgressStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Progress takes the place of music", isOn: $overridesMusic)
            } header: {
                Text("Appearance")
            } footer: {
                Text(styleHint + " The AI quota never replaces music.")
            }
            .disabled(!enabled)

            Section {
                ForEach(Array(ProgressSource.allCases.enumerated()), id: \.element) { index, source in
                    Toggle(isOn: binding(for: source)) {
                        HStack(spacing: 6) {
                            Text("\(index + 1). \(source.title)")
                            HoverInfo(text: hint(for: source))
                        }
                    }
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Only one is shown at a time. The first one in progress wins, in this order.")
            }
            .disabled(!enabled)

            ClaudeAgentSettingsSection()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Progress")
    }

    private var styleHint: String {
        switch style {
        case .wings: return "Wings: icon on the left, ring or time on the right."
        case .wire: return "Wire: a line that runs around the notch; the notch keeps its size."
        case .hybrid: return "Hybrid: the line, plus one icon on the left."
        }
    }

    private func hint(for source: ProgressSource) -> String {
        switch source {
        case .timer: return "A timer running in the macOS Clock app."
        case .download: return "A file being downloaded into your Downloads folder."
        case .charging: return "Shown only while the battery level is going up. A charge held at 80% is not shown."
        case .aiQuota:
            let connected: Bool = { if case .ready = ai.state { return true } else { return false } }()
            return connected
                ? "What is left of your \(provider.name) limit. Shown when nothing else is in progress."
                : "\(provider.name) is not connected. Set it up in Settings › Widgets by adding the AI usage widget."
        }
    }

    private func binding(for source: ProgressSource) -> Binding<Bool> {
        Binding(
            get: { sources.contains(source) },
            set: { on in sources = ProgressSource.allCases.filter { $0 == source ? on : sources.contains($0) } }
        )
    }
}
