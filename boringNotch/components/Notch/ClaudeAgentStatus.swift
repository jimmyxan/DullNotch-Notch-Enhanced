//
//  ClaudeAgentStatus.swift
//  boringNotch
//
//  What Claude Code is doing, shown on the closed notch. Claude Code hooks (installed by the helper,
//  Settings › Progress › Connect Claude Code) post Darwin notifications with
//  `notifyutil -p dullnotch.agent.<state>`: a notification never launches the app, or a stray build of it.
//  Esc fires no hook, so while working the helper also reads ~/.claude/sessions.
//

import Defaults
import notify
import SwiftUI

extension Defaults.Keys {
    static let claudeAgentEnabled = Key<Bool>("claudeAgentEnabled", default: true)
}

@MainActor
final class ClaudeAgentStatus: ObservableObject {
    /// Waiting for input or a permission is `hidden`: the notch only speaks up while Claude works or just finished.
    enum Phase { case hidden, working, done }

    static let shared = ClaudeAgentStatus()

    @Published private(set) var phase = Phase.hidden
    /// Which working animation this turn gets, drawn at random when work starts: the hammer or the keyboard.
    private(set) var hammers = false
    /// Which finish animation this turn gets, drawn at random when it finishes: coffee break or cheer.
    private(set) var coffee = false

    private var expiry: Task<Void, Never>?
    private var interruptWatch: Task<Void, Never>?
    private var tokens: [Int32] = []

    private init() {
        for (name, phase) in [("dullnotch.agent.working", Phase.working), ("dullnotch.agent.done", .done), ("dullnotch.agent.idle", .hidden)] {
            var token: Int32 = 0
            notify_register_dispatch(name, &token, .main) { _ in
                MainActor.assumeIsolated { ClaudeAgentStatus.shared.set(phase) }
            }
            tokens.append(token)
        }
    }

    // ponytail: one global state for every Claude Code session; key it by session_id if two sessions at once get confusing.
    // `working` still expires after 10 min without events, in case Claude Code dies without a SessionEnd;
    // a single Bash longer than that hides the mascot until its PostToolUse brings it back.
    func set(_ next: Phase) {
        expiry?.cancel()
        // Switched off: stay hidden and don't poll the helper.
        guard Defaults[.claudeAgentEnabled] || next == .hidden else { return set(.hidden) }
        if next == .working, phase != .working {
            hammers = Bool.random()
            watchForInterrupt()
        }
        if next == .done, phase != .done { coffee = Bool.random() }
        if next != .working { interruptWatch?.cancel() }
        if phase != next { phase = next }
        let after: Double? = next == .done ? 20 : next == .working ? 600 : nil
        guard let after else { return }
        expiry = Task {
            try? await Task.sleep(for: .seconds(after))
            guard !Task.isCancelled else { return }
            set(.hidden)
        }
    }

    /// Esc fires no hook. Claude Code marks each session busy or idle in ~/.claude/sessions; when none has
    /// been busy for two checks in a row (2 s apart, so a Stop hook arriving meanwhile wins), Claude was stopped.
    private func watchForInterrupt() {
        interruptWatch?.cancel()
        interruptWatch = Task {
            var idleChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let busy = await XPCHelperClient.shared.claudeBusySessions()
                guard !Task.isCancelled, busy >= 0 else { return } // -1: older Claude Code, the 10 min expiry applies
                idleChecks = busy == 0 ? idleChecks + 1 : 0
                if idleChecks == 2 { return set(.hidden) }
            }
        }
    }
}

/// Claude's mascot in pixel art: types on a keyboard while working, cheers with its arms up when done.
struct ClaudeMascotView: View {
    let phase: ClaudeAgentStatus.Phase
    @State private var tick = 0
    // Exists only while the mascot is on screen. Not a TimelineView: see STORY.md, Decisions.
    private let clock = Timer.publish(every: 1.0 / 6, tolerance: 0.03, on: .main, in: .common).autoconnect()

    private typealias Pixel = (row: Int, col: Int, ink: Character)

    private static let desk = [
        "............",
        "..oooooooo..",
        "..oooooooo..",
        "..okooooko..",
        "..okooooko..",
        "..oooooooo..",
        "..oooooooo..",
        "............",
        ".hghghghghg.",
        ".gggggggggg.",
        "............",
    ]
    /// Left hand on a key, both up, right hand on a key, both up.
    private static let typing: [[Pixel]] = {
        let up: [Pixel] = [(5, 1, "a"), (6, 1, "a"), (5, 10, "a"), (6, 10, "a")]
        return [
            [(4, 10, "a"), (5, 10, "a"), (6, 1, "a"), (7, 1, "a"), (8, 2, "w")],
            up,
            [(4, 1, "a"), (5, 1, "a"), (6, 10, "a"), (7, 10, "a"), (8, 9, "w")],
            up,
        ]
    }()

    private static let forge = [
        "............",
        "............",
        "............",
        ".oooooooo...",
        ".oooooooo...",
        ".oookooko...",
        ".oookooko...",
        ".oooooooo...",
        ".oooooooo.hh",
        ".o.o..o.o.gg",
        "............",
    ]
    /// Hammer up, up, half way, hit, hit, half way: one blow a second. On the hit the block flashes,
    /// sparks fly and the eyes squint.
    private static let hammer: [[Pixel]] = {
        let up: [Pixel] = [(6, 9, "a"), (5, 10, "b"), (4, 10, "b"), (3, 10, "b"), (1, 10, "m"), (1, 11, "m"), (2, 10, "m"), (2, 11, "m")]
        let mid: [Pixel] = [(6, 9, "a"), (6, 10, "b"), (5, 11, "m"), (6, 11, "m"), (7, 11, "m")]
        let hit: [Pixel] = [(7, 9, "a"), (6, 10, "m"), (6, 11, "m"), (7, 10, "m"), (7, 11, "m"),
                            (5, 9, "y"), (4, 11, "y"), (5, 8, "y"), (8, 11, "w"), (5, 4, "o"), (5, 7, "o")]
        return [up, up, mid, hit, hit, mid]
    }()

    private static let cheer = [
        "............",
        ".a........a.",
        ".a........a.",
        ".aooooooooa.",
        "..okkookko..",
        "..oooooooo..",
        "..oooooooo..",
        "..oooooooo..",
        "..o.o..o.o..",
        "............",
        "............",
    ]
    private static let sparkles: [Pixel] = [(0, 0, "y"), (1, 11, "y"), (5, 0, "y")]

    /// Coffee break: steaming mug, eyes half shut, one sip half way through.
    private static let cafe = [
        "............",
        "............",
        "............",
        ".oooooooo...",
        ".oooooooo...",
        ".okkookko...",
        ".oooooooo...",
        ".oooooooo...",
        ".oooooooo...",
        ".o.o..o.o...",
        "............",
    ]
    private static let steam: [[Pixel]] = [[(5, 10, "h"), (4, 11, "h"), (3, 10, "h")], [(5, 11, "h"), (4, 10, "h"), (3, 11, "h")]]

    var body: some View {
        Canvas { context, size in
            let hammers = ClaudeAgentStatus.shared.hammers
            let coffee = ClaudeAgentStatus.shared.coffee
            let rows = phase == .working ? (hammers ? Self.forge : Self.desk) : (coffee ? Self.cafe : Self.cheer)
            var grid = rows.map(Array.init)
            var lift = 0
            if phase == .working {
                let pose = hammers ? Self.hammer[tick % 6] : Self.typing[tick % 4]
                for p in pose { grid[p.row][p.col] = p.ink }
            } else if coffee {
                let sip = (8...11).contains(tick % 24) // every 4 s the mug rises one pixel and the steam stops
                let top = sip ? 5 : 6
                let mug: [Pixel] = [(top, 10, "n"), (top, 11, "n"), (top + 1, 10, "w"), (top + 1, 11, "w"), (top + 1, 9, "a")]
                for p in mug + (sip ? [] : Self.steam[tick % 4 / 2]) { grid[p.row][p.col] = p.ink }
            } else if tick % 6 >= 3, tick % 6 <= 4 {
                // One hop a second, sparkles at the top of it, until it fades out.
                lift = 1
                for p in Self.sparkles { grid[p.row][p.col] = p.ink }
            }
            let px = min(size.width / 12, size.height / 11)
            let origin = CGPoint(x: (size.width - px * 12) / 2, y: (size.height - px * 11) / 2)
            for (r, row) in grid.enumerated() {
                for (c, ink) in row.enumerated() {
                    guard let color = Self.color(ink) else { continue }
                    let y = r - (ink == "y" ? 0 : lift)
                    // The extra 0.3 pt hides the seams antialiasing leaves between pixels.
                    context.fill(Path(CGRect(x: origin.x + CGFloat(c) * px, y: origin.y + CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(color))
                }
            }
        }
        .onReceive(clock) { _ in
            // Runs for the 20 s of "done" too: a cheer that stops after 2 s reads as frozen.
            tick += 1
        }
        .onChange(of: phase) { tick = 0 }
        .accessibilityLabel(phase == .working ? "Claude is working" : "Claude finished")
    }

    private static func color(_ ink: Character) -> Color? {
        switch ink {
        case "o": return Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
        case "a": return Color(red: 0.72, green: 0.37, blue: 0.27) // arms, a shade darker so they read apart
        case "k": return .black
        case "h": return Color(white: 0.55)
        case "g": return Color(white: 0.32)
        case "w": return .white
        case "m": return Color(white: 0.79) // hammer head
        case "b": return Color(red: 0.54, green: 0.35, blue: 0.2) // handle
        case "n": return Color(red: 0.42, green: 0.25, blue: 0.16) // coffee
        case "y": return .yellow
        default: return nil
        }
    }
}

/// Section for Settings › Progress. The helper edits ~/.claude/settings.json: the app's sandbox can't.
struct ClaudeAgentSettingsSection: View {
    @Default(.claudeAgentEnabled) private var enabled
    /// Helper code: 1 connected, 0 not, -1 no Claude Code, -2 unreadable settings, -3 failure; nil = asking.
    @State private var hooks: Int?

    var body: some View {
        Section {
            Toggle("Show what Claude Code is doing", isOn: $enabled)
            LabeledContent {
                Button(hooks == 1 ? "Disconnect" : "Connect Claude Code") {
                    let action = hooks == 1 ? "remove" : "install"
                    hooks = nil
                    Task { hooks = await XPCHelperClient.shared.claudeHooks(action) }
                }
                .disabled(hooks == nil || hooks == -1 || hooks == -2)
            } label: {
                Text(status).foregroundStyle(hooks == 1 ? .primary : .secondary)
            }
        } header: {
            Text("Claude Code")
        } footer: {
            Text("Connecting adds a few hooks to ~/.claude/settings.json (a backup is kept next to it). The mascot types while Claude works, cheers for 20 seconds when it finishes, and hides while Claude waits for you or after you press Esc.")
        }
        .task { hooks = await XPCHelperClient.shared.claudeHooks("status") }
    }

    private var status: String {
        switch hooks {
        case nil: return "Checking…"
        case 1: return "Connected"
        case 0: return "Not connected"
        case -1: return "Claude Code not found"
        case -2: return "~/.claude/settings.json is not valid JSON"
        default: return "Couldn't update the settings"
        }
    }
}
