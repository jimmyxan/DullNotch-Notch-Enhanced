//
//  PomodoroWidget.swift
//  boringNotch
//
//  Pomodoro in a small widget: pick the focus and break lengths, start, and the card fills
//  with colour as the time goes. A stretch that ends waits for an answer; it never moves on
//  by itself. On the closed notch the countdown is a wire and the end of a stretch is a signal.
//

import Foundation

// MARK: - Logic (pure: compiles outside the app up to "MARK: - Live")

enum PomodoroPhase: Equatable {
    case setup, focus, focusDone, rest, restDone, summary
}

/// Every change takes `now`, so the whole session can be replayed in a test.
struct PomodoroSession: Equatable {
    /// What "+5 min" adds to a focus that ran out.
    static let extra: TimeInterval = 300

    private(set) var phase = PomodoroPhase.setup
    var focusLength: TimeInterval = 1500
    var restLength: TimeInterval = 300
    /// Length of the stretch in progress: the focus, the break, or a 5-minute extension.
    private(set) var length: TimeInterval = 0
    /// When the stretch ends. Nil while paused or waiting for an answer.
    private(set) var ends: Date?
    /// What is left of a paused stretch.
    private(set) var left: TimeInterval = 0
    private(set) var focusTotal: TimeInterval = 0
    private(set) var restTotal: TimeInterval = 0
    /// Start of the running time not yet added to a total.
    private var counted: Date?

    var isRunning: Bool { ends != nil }
    var isPaused: Bool { (phase == .focus || phase == .rest) && ends == nil }

    func remaining(at now: Date) -> TimeInterval {
        ends.map { max(0, $0.timeIntervalSince(now)) } ?? left
    }

    /// 1 = the whole stretch is still ahead, 0 = over.
    func fractionLeft(at now: Date) -> Double {
        length > 0 ? min(1, remaining(at: now) / length) : 0
    }

    /// Adds the time run since `counted` to the total of the current phase. Time past `ends` does not count.
    private mutating func bank(_ now: Date) {
        guard let from = counted else { return }
        let spent = max(0, min(now, ends ?? now).timeIntervalSince(from))
        if phase == .focus { focusTotal += spent } else if phase == .rest { restTotal += spent }
        counted = nil
    }

    private mutating func run(_ next: PomodoroPhase, for seconds: TimeInterval, now: Date) {
        bank(now)
        phase = next
        length = seconds
        ends = now.addingTimeInterval(seconds)
        counted = now
    }

    mutating func start(now: Date) {
        focusTotal = 0
        restTotal = 0
        counted = nil
        run(.focus, for: focusLength, now: now)
    }

    /// Ends the stretch when its time is up. Safe to call late: only the time up to `ends` counts.
    mutating func tick(now: Date) {
        guard let ends, now >= ends else { return }
        bank(now)
        self.ends = nil
        left = 0
        phase = phase == .focus ? .focusDone : .restDone
    }

    mutating func togglePause(now: Date) {
        guard phase == .focus || phase == .rest else { return }
        if let ends {
            left = max(0, ends.timeIntervalSince(now))
            bank(now)
            self.ends = nil
        } else {
            ends = now.addingTimeInterval(left)
            counted = now
        }
    }

    mutating func extend(now: Date) {
        guard phase == .focusDone else { return }
        run(.focus, for: Self.extra, now: now)
    }

    mutating func startRest(now: Date) {
        guard phase == .focusDone else { return }
        run(.rest, for: restLength, now: now)
    }

    /// The answer after a break, or "Skip" during one.
    mutating func resumeFocus(now: Date) {
        guard phase == .restDone || phase == .rest else { return }
        run(.focus, for: focusLength, now: now)
    }

    mutating func end(now: Date) {
        guard phase != .setup else { return }
        bank(now)
        ends = nil
        phase = .summary
    }

    mutating func reset() {
        phase = .setup
        ends = nil
        counted = nil
    }

    /// "42s", "25m", "1h 15m".
    static func spent(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        let m = s / 60
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    #if DEBUG
    static let selfCheck: Void = {
        func at(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }
        var s = PomodoroSession()
        s.start(now: at(0))
        assert(s.phase == .focus && s.remaining(at: at(600)) == 900 && s.fractionLeft(at: at(600)) == 0.6)

        // 400 s of pause do not count as focus
        s.togglePause(now: at(600))
        assert(s.isPaused && s.focusTotal == 600 && s.remaining(at: at(900)) == 900)
        s.togglePause(now: at(1000))
        s.tick(now: at(1899))
        assert(s.phase == .focus)
        // a late tick counts the time up to the end only
        s.tick(now: at(1950))
        assert(s.phase == .focusDone && s.focusTotal == 1500 && !s.isRunning)

        // nothing moves on without an answer
        s.tick(now: at(5000))
        assert(s.phase == .focusDone)
        s.startRest(now: at(5000))
        s.extend(now: at(5000)) // not after the break has begun
        assert(s.phase == .rest)
        s.end(now: at(5000))
        s.reset()

        s.start(now: at(0))
        s.tick(now: at(1500))
        s.extend(now: at(2000))
        assert(s.phase == .focus && s.remaining(at: at(2000)) == 300)
        s.tick(now: at(2300))
        assert(s.phase == .focusDone && s.focusTotal == 1800)
        s.startRest(now: at(2400))
        s.tick(now: at(2700))
        assert(s.phase == .restDone && s.restTotal == 300)
        s.resumeFocus(now: at(3000))
        s.end(now: at(3060))
        assert(s.phase == .summary && s.focusTotal == 1860 && s.restTotal == 300)
        s.reset()
        assert(s.phase == .setup && !s.isRunning)

        // skipping a break counts only the part taken
        s.start(now: at(0))
        s.tick(now: at(1500))
        s.startRest(now: at(1500))
        s.resumeFocus(now: at(1560))
        assert(s.phase == .focus && s.restTotal == 60)

        assert(spent(42) == "42s" && spent(1500) == "25m" && spent(4500) == "1h 15m" && spent(0) == "0s")
    }()
    #endif
}

/// The sound of a focus that ends: two rising bell notes, about a second. Built here, so the app ships no audio file.
enum PomodoroChime {
    static let wav: Data = {
        let rate = 44_100.0
        let notes: [(hz: Double, at: Double)] = [(1318.5, 0), (1975.5, 0.11)] // E6, then B6
        let count = Int(rate * 0.95)
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        // 16-bit mono PCM in a WAV header
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(count * 2))
        for i in 0..<count {
            let t = Double(i) / rate
            var v = 0.0
            for note in notes where t >= note.at {
                let age = t - note.at
                // 4 ms attack so it does not click, then it rings out like a bell; the octave above adds the shine
                let envelope = min(1, age / 0.004) * exp(-age * 6)
                v += envelope * (sin(2 * .pi * note.hz * age) + 0.25 * sin(4 * .pi * note.hz * age))
            }
            put(Int16(max(-1, min(1, v * 0.3)) * 32767))
        }
        return data
    }()
}

// MARK: - Live

import AppKit
import Defaults
import SwiftUI

extension PomodoroChime {
    private static var playing: NSSound?

    /// A new NSSound each time, with no device set: it plays on the Mac's default output at that moment.
    @MainActor static func play() {
        playing = NSSound(data: wav)
        playing?.play()
    }
}

extension Defaults.Keys {
    static let pomodoroFocusMinutes = Key<Int>("pomodoroFocusMinutes", default: 25)
    static let pomodoroBreakMinutes = Key<Int>("pomodoroBreakMinutes", default: 5)
}

// ponytail: the session lives in memory, so quitting the app ends it. Save `session` if that ever matters.
@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    /// Changes on a start, a pause, an answer: not every second.
    @Published private(set) var session = PomodoroSession()
    /// What is left of the stretch in 0.5% steps, for the wire on the closed notch. Nil when there is no stretch.
    @Published private(set) var wire: Double?
    private var ticker: Timer?

    private init() {
        #if DEBUG
        _ = PomodoroSession.selfCheck
        // For trying it out: `--args -pomodoroDebugFocus 3` starts a 3-minute focus at launch.
        let minutes = UserDefaults.standard.integer(forKey: "pomodoroDebugFocus")
        if minutes > 0 {
            start()
            change { $0.focusLength = TimeInterval(minutes * 60); $0.start(now: $1) }
        }
        #endif
    }

    func start() {
        change {
            $0.focusLength = TimeInterval(Defaults[.pomodoroFocusMinutes] * 60)
            $0.restLength = TimeInterval(Defaults[.pomodoroBreakMinutes] * 60)
            $0.start(now: $1)
        }
    }
    func togglePause() { change { $0.togglePause(now: $1) } }
    func extend() { change { $0.extend(now: $1) } }
    func startRest() { change { $0.startRest(now: $1) } }
    func resumeFocus() { change { $0.resumeFocus(now: $1) } }
    func end() { change { $0.end(now: $1) } }
    func reset() { change { session, _ in session.reset() } }

    /// Colour of the stretch that is over and waits for an answer.
    var waitingTint: Color? {
        switch session.phase {
        case .focusDone: return .orange
        case .restDone: return .green
        default: return nil
        }
    }

    /// The countdown as the closed notch draws it. A focus about to end turns red, like a Clock timer.
    var progressItem: ProgressItem? {
        guard let wire else { return nil }
        let focus = session.phase == .focus
        return ProgressItem(
            source: .pomodoro, fraction: wire, label: focus ? "Focus" : "Break", icon: "timer",
            tint: focus ? (wire < 0.15 ? .red : .orange) : .green)
    }

    private func change(_ edit: (inout PomodoroSession, Date) -> Void) {
        var next = session
        edit(&next, Date())
        if next != session { session = next }
        sync()
    }

    /// Ends a stretch whose time is up, refreshes the wire, and keeps the 1 s tick only while a stretch runs.
    private func sync() {
        let now = Date()
        var next = session
        next.tick(now: now)
        if next != session {
            if next.phase == .focusDone { PomodoroChime.play() }
            session = next
        }

        let inStretch = session.phase == .focus || session.phase == .rest
        let fraction = inStretch ? (session.fractionLeft(at: now) * 200).rounded() / 200 : nil
        if fraction != wire { wire = fraction }

        if session.isRunning, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in PomodoroManager.shared.sync() }
            }
        } else if !session.isRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }
}

// MARK: - Widget

/// One row of waves, two card widths long, so sliding it by one width loops without a seam.
private struct PomodoroWave: Shape {
    var phase: Double
    /// False: only the crest line, for a stroke.
    var closed = true

    func path(in rect: CGRect) -> Path {
        let (length, mid) = (rect.width / 2, rect.height / 2)
        var path = Path()
        for x in stride(from: 0, through: rect.width, by: 3) {
            let point = CGPoint(x: x, y: mid - (mid - 0.5) * sin(2 * .pi * x / length + phase))
            x == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// The surface of the colour: two waves sliding past each other while the time runs, still when it does not.
/// Only the offset is animated, so the paths are drawn once.
private struct PomodoroSurface: View {
    let tint: Color
    let width: CGFloat
    let flowing: Bool
    static let height: CGFloat = 5
    @State private var drift = false

    private func slide(_ seconds: Double) -> Animation {
        flowing ? .linear(duration: seconds).repeatForever(autoreverses: false) : .smooth(duration: 0.4)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            PomodoroWave(phase: .pi / 2)
                .fill(tint.opacity(0.28))
                .frame(width: width * 2)
                .offset(x: drift ? 0 : -width)
                .animation(slide(6.5), value: drift)
            PomodoroWave(phase: 0)
                .fill(tint.opacity(0.55))
                .overlay { PomodoroWave(phase: 0, closed: false).stroke(tint, lineWidth: 1) }
                .frame(width: width * 2)
                .offset(x: drift ? -width : 0)
                .animation(slide(4), value: drift)
        }
        .frame(width: width, height: Self.height, alignment: .leading)
        .onAppear { drift = flowing }
        .onChange(of: flowing) { _, now in drift = now }
    }
}

/// Card whose colour rises from the bottom to `level` (0...1).
private struct PomodoroCard<Content: View>: View {
    var level: Double = 0
    var tint: Color = .orange
    /// The surface moves: a stretch is running.
    var flowing = false
    /// No session yet: a blurred glow of the focus colour at the bottom, still, in place of the level.
    var glow = false
    /// The colour never goes below this while a stretch runs: a focus rises from here, a break drains to here.
    static var base: Double { 0.1 }
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { geo in
                    if glow {
                        ZStack(alignment: .bottom) {
                            Ellipse().fill(Color.orange.opacity(0.6))
                                .frame(width: geo.size.width * 1.1, height: geo.size.height * 0.5)
                                .offset(y: geo.size.height * 0.28)
                            Circle().fill(Color(red: 1, green: 0.35, blue: 0.3).opacity(0.5))
                                .frame(width: geo.size.width * 0.5)
                                .offset(x: -geo.size.width * 0.3, y: geo.size.height * 0.26)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .blur(radius: 22)
                        .transition(.opacity)
                    }
                    VStack(spacing: 0) {
                        PomodoroSurface(tint: tint, width: geo.size.width, flowing: flowing)
                        Rectangle()
                            .fill(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                            .frame(height: geo.size.height * min(1, max(0, level)))
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(level > 0 ? 1 : 0)
                }
            }
            // One second per step: the level moves without a jump between two ticks.
            .animation(.linear(duration: 1), value: level)
            .modifier(WidgetCard())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PomodoroWidget: View {
    @ObservedObject private var pomodoro = PomodoroManager.shared
    @Default(.pomodoroFocusMinutes) private var focusMinutes
    @Default(.pomodoroBreakMinutes) private var breakMinutes
    @State private var hovering = false
    /// A click opens the choice too, for who has no pointer to hover with.
    @State private var pinned = false

    var body: some View {
        let session = pomodoro.session
        Group {
            switch session.phase {
            case .setup: setup
            case .focus, .rest:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    PomodoroRunningFace(session: session, now: context.date)
                }
                .contentShape(Rectangle())
                .onTapGesture { pomodoro.togglePause() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
            case .focusDone: focusDone
            case .restDone: restDone
            case .summary: summary(session)
            }
        }
        .animation(.smooth(duration: 0.3), value: session.phase)
        .onChange(of: session.phase) { _, _ in pinned = false }
    }

    /// At rest nothing looks started: an invitation in the Quote widget's serif over a soft glow of the
    /// focus colour. The choice of the times comes up under the pointer and leaves with it.
    private var setup: some View {
        let choosing = hovering || pinned
        return PomodoroCard(glow: true) {
            if choosing {
                VStack(alignment: .leading, spacing: 0) {
                    PomodoroCap("Focus")
                    chips([15, 25, 45, 60], selection: $focusMinutes).padding(.top, 3)
                    PomodoroCap("Break").padding(.top, 6)
                    chips([5, 10, 15], selection: $breakMinutes).padding(.top, 3)
                    Spacer(minLength: 6)
                    PomodoroPill("Start", fill: .white) { pomodoro.start() }
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start your\nfocus")
                        .font(.system(size: 21, weight: .light, design: .serif))
                        .lineSpacing(1)
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                    HStack(spacing: 7) {
                        Rectangle().fill(.white.opacity(0.6)).frame(width: 12, height: 0.5)
                        Text("\(focusMinutes) MIN  ·  \(breakMinutes) BREAK")
                            .font(.system(size: 8.5, weight: .medium))
                            .kerning(1.2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Start your focus: \(focusMinutes) minutes, then \(breakMinutes) minutes of break. Choose the times.")
                .accessibilityAddTraits(.isButton)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { pinned = true }
        .animation(.smooth(duration: 0.25), value: choosing)
    }

    private var focusDone: some View {
        PomodoroCard(level: 1, tint: .orange) {
            HStack {
                PomodoroCap("Focus done", color: .white)
                Spacer(minLength: 0)
                PomodoroEndButton()
            }
            Spacer(minLength: 0)
            Text("Time's up")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PomodoroPill("+5 min", fill: .black.opacity(0.35), text: .white) { pomodoro.extend() }
                PomodoroPill("Break", fill: .white) { pomodoro.startRest() }
            }
        }
    }

    private var restDone: some View {
        PomodoroCard(level: PomodoroCard<EmptyView>.base, tint: .green) {
            PomodoroCap("Break over", color: .green)
            Spacer(minLength: 0)
            Text("Ready?")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PomodoroPill("End", fill: .white.opacity(0.1), text: .white) { pomodoro.end() }
                PomodoroPill("Focus", fill: .orange) { pomodoro.resumeFocus() }
            }
        }
    }

    private func summary(_ session: PomodoroSession) -> some View {
        PomodoroCard {
            PomodoroCap("Session")
            total("Focus", session.focusTotal, .orange).padding(.top, 8)
            total("Break", session.restTotal, .green).padding(.top, 6)
            Spacer(minLength: 6)
            PomodoroPill("Done", fill: .white) { pomodoro.reset() }
        }
    }

    private func total(_ title: String, _ seconds: TimeInterval, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Text(PomodoroSession.spent(seconds))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    private func chips(_ values: [Int], selection: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                let on = value == selection.wrappedValue
                Button { selection.wrappedValue = value } label: {
                    Text("\(value)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) minutes")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.smooth(duration: 0.2), value: selection.wrappedValue)
    }
}

/// A stretch in progress or paused. Also the look of the widget in Settings.
struct PomodoroRunningFace: View {
    let session: PomodoroSession
    let now: Date
    var still = false

    /// 25 minutes of focus with 15:32 to go: the look shown in Settings.
    static var sample: PomodoroRunningFace {
        var session = PomodoroSession()
        let start = Date(timeIntervalSince1970: 0)
        session.start(now: start)
        return PomodoroRunningFace(session: session, now: start.addingTimeInterval(568), still: true)
    }

    var body: some View {
        let focus = session.phase == .focus
        let left = session.fractionLeft(at: now)
        // Focus fills the card, a break drains it.
        let base = PomodoroCard<EmptyView>.base
        PomodoroCard(level: base + (1 - base) * (focus ? 1 - left : left), tint: focus ? .orange : .green, flowing: session.isRunning && !still) {
            HStack(spacing: 8) {
                PomodoroCap(session.isPaused ? "Paused" : focus ? "Focus" : "Break")
                Spacer(minLength: 0)
                if !focus {
                    Button("Skip") { PomodoroManager.shared.resumeFocus() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                PomodoroEndButton()
            }
            Spacer(minLength: 0)
            Text(NotchProgressLogic.clock(session.remaining(at: now)))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(session.isPaused ? "Tap to resume" : "Tap to pause")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct PomodoroCap: View {
    let text: String
    var color = Color.white.opacity(0.5)

    init(_ text: String, color: Color = .white.opacity(0.5)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct PomodoroPill: View {
    let title: String
    let fill: Color
    var text = Color.black
    let action: () -> Void

    init(_ title: String, fill: Color, text: Color = .black, action: @escaping () -> Void) {
        self.title = title
        self.fill = fill
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Ends the session from any stretch and goes to the totals.
private struct PomodoroEndButton: View {
    var body: some View {
        Button { PomodoroManager.shared.end() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Circle().fill(.black.opacity(0.3)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End session")
        .help("End session")
    }
}

// MARK: - Closed notch

/// Left wing, when it is free: the card in miniature, its level surging to the brim.
struct PomodoroWingGlyph: View {
    let tint: Color
    @State private var full = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
            .fill(tint.opacity(0.22))
            .overlay {
                Rectangle().fill(tint).scaleEffect(y: full ? 1 : 0.4, anchor: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .shadow(color: tint.opacity(full ? 0.8 : 0.15), radius: full ? 4 : 1)
            .padding(3)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: full)
            .onAppear { full = true }
            .accessibilityLabel("Pomodoro: time is up")
    }
}

/// When the wings are taken: the full card overflows. A drop swells under the right end of the
/// notch, stretches, falls and fades, again and again until the answer comes.
struct PomodoroDrip: View {
    let tint: Color
    static let size = CGSize(width: 6, height: 22)

    private struct Drop {
        var scale = 0.0
        var stretch = 1.0
        var fall = 0.0
        var opacity = 1.0
    }

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .shadow(color: tint.opacity(0.8), radius: 2.5)
            .keyframeAnimator(initialValue: Drop(), repeating: true) { drop, value in
                drop
                    .scaleEffect(x: value.scale / value.stretch.squareRoot(), y: value.scale * value.stretch, anchor: .top)
                    .offset(y: value.fall)
                    .opacity(value.opacity)
            } keyframes: { _ in
                // Every track lasts 2.1 s and ends invisible, so the loop restarts unseen.
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1, duration: 0.8)
                    LinearKeyframe(1, duration: 1.3)
                }
                KeyframeTrack(\.stretch) {
                    LinearKeyframe(1, duration: 0.8)
                    CubicKeyframe(1.6, duration: 0.3)
                    CubicKeyframe(1, duration: 0.3)
                    LinearKeyframe(1, duration: 0.7)
                }
                KeyframeTrack(\.fall) {
                    LinearKeyframe(0, duration: 1.1)
                    LinearKeyframe(15, duration: 0.5, timingCurve: .easeIn)
                    LinearKeyframe(15, duration: 0.5)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 1.35)
                    LinearKeyframe(0, duration: 0.25)
                    LinearKeyframe(0, duration: 0.5)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
