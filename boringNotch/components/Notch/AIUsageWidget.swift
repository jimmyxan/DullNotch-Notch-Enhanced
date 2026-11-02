//
//  AIUsageWidget.swift
//  boringNotch
//
//  Small home widget: Claude or Codex plan limits as two concentric rings
//  (outer = 5-hour window, inner = weekly window), showing what is left.
//

import Defaults
import SwiftUI

// MARK: - Model

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var name: String { self == .claude ? "Claude" : "Codex" }
    var logo: String { self == .claude ? "claude-logo" : "codex-logo" }

    /// Claude: brand orange, softer orange inside. Codex: monochrome.
    var ringColors: (outer: Color, inner: Color) {
        switch self {
        case .claude: return (Color(red: 0.85, green: 0.47, blue: 0.34), Color(red: 0.96, green: 0.70, blue: 0.56))
        case .codex: return (.white, .white.opacity(0.55))
        }
    }

    var signInHint: String { "Set it up in Settings › Widgets" }
}

struct AIUsageWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?

    var remaining: Int { Int((100 - min(max(usedPercent, 0), 100)).rounded()) }
}

struct AIUsage: Equatable {
    var session: AIUsageWindow?
    var weekly: AIUsageWindow?
    var plan: String?

    /// Claude `/api/oauth/usage`: `five_hour` / `seven_day` with `utilization` (0-100) and ISO `resets_at`.
    /// Codex `/backend-api/wham/usage`: `rate_limit.primary_window` / `secondary_window` with `used_percent`
    /// and `reset_at` (unix seconds) or `reset_after_seconds`.
    static func parse(_ body: String, provider: AIProvider, now: Date = Date()) -> AIUsage? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }

        switch provider {
        case .claude:
            func window(_ key: String) -> AIUsageWindow? {
                guard let w = json[key] as? [String: Any], let used = number(w["utilization"]) else { return nil }
                return AIUsageWindow(usedPercent: used, resetsAt: (w["resets_at"] as? String).flatMap(parseISO))
            }
            let usage = AIUsage(session: window("five_hour"), weekly: window("seven_day"), plan: nil)
            return usage.session == nil && usage.weekly == nil ? nil : usage
        case .codex:
            guard let limits = json["rate_limit"] as? [String: Any] else { return nil }
            func window(_ key: String) -> AIUsageWindow? {
                guard let w = limits[key] as? [String: Any], let used = number(w["used_percent"]) else { return nil }
                let reset = number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                    ?? number(w["reset_after_seconds"]).map { now.addingTimeInterval($0) }
                return AIUsageWindow(usedPercent: used, resetsAt: reset)
            }
            let usage = AIUsage(session: window("primary_window"), weekly: window("secondary_window"), plan: json["plan_type"] as? String)
            return usage.session == nil && usage.weekly == nil ? nil : usage
        }
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    #if DEBUG
    static let parseSelfCheck: Void = {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let claude = parse(#"{"five_hour":{"utilization":28.0,"resets_at":"2026-11-02T18:00:00.123+00:00"},"seven_day":{"utilization":61,"resets_at":null}}"#, provider: .claude)
        assert(claude?.session?.remaining == 72 && claude?.session?.resetsAt != nil && claude?.weekly?.remaining == 39)
        let codex = parse(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"reset_after_seconds":600},"secondary_window":{"used_percent":55.4,"reset_at":1000500}}}"#, provider: .codex, now: now)
        assert(codex?.session?.remaining == 90 && codex?.session?.resetsAt == now.addingTimeInterval(600))
        assert(codex?.weekly?.remaining == 45 && codex?.plan == "plus")
        assert(parse(#"{"error":"x"}"#, provider: .claude) == nil && parse("nope", provider: .codex) == nil)
    }()
    #endif
}

enum AIUsageState: Equatable {
    case loading
    case ready(AIUsage)
    case notSignedIn
    case expired
    case offline
}

/// "2h10m", "45m", "3d4h": no spaces so it fits half of a small widget.
func compactCountdown(to date: Date?, now: Date = Date()) -> String {
    guard let date else { return "–" }
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let (d, h, m) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
    if d > 0 { return h > 0 ? "\(d)d\(h)h" : "\(d)d" }
    if h > 0 { return "\(h)h\(m)m" }
    return "\(m)m"
}

// MARK: - Views

/// Two concentric rings: dim tracks, arcs sweep in to what's left.
struct AIUsageRings: View {
    let usage: AIUsage?
    let colors: (outer: Color, inner: Color)
    var lineWidth: CGFloat = 6
    @State private var shown: (CGFloat, CGFloat) = (0, 0)

    var body: some View {
        ZStack {
            ring(shown.0, colors.outer, inset: 0)
            ring(shown.1, colors.inner, inset: lineWidth + 2.5)
        }
        .onAppear { animate() }
        .onChange(of: usage) { _, _ in animate() }
    }

    private func ring(_ value: CGFloat, _ color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 3)
        }
        .padding(inset + lineWidth / 2)
    }

    private func animate() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) {
            shown = (CGFloat(usage?.session?.remaining ?? 0) / 100, CGFloat(usage?.weekly?.remaining ?? 0) / 100)
        }
    }
}

/// Data-driven body of the widget, also used (with sample data) by the settings preview.
struct AIUsageContent: View {
    let provider: AIProvider
    let state: AIUsageState
    var hovering = false

    private var usage: AIUsage? { if case .ready(let u) = state { return u } else { return nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(provider.logo)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(provider == .claude ? provider.ringColors.outer : .white)
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if let plan = usage?.plan {
                    Text(plan.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            switch state {
            case .ready, .loading:
                AIUsageRings(usage: usage, colors: provider.ringColors)
                    .frame(width: 66, height: 66)
                    .overlay { if state == .loading { ProgressView().controlSize(.small) } }
                    .frame(maxHeight: .infinity)
                legend
            case .notSignedIn:
                message("person.crop.circle.badge.questionmark", "Not signed in", provider.signInHint)
            case .expired:
                message("clock.arrow.circlepath", "Sign-in expired", "Open \(provider == .claude ? "Claude Code" : "Codex") once to renew it")
            case .offline:
                message("wifi.slash", "Can't reach \(provider.name)", "Showing nothing until it's back")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Claude gets a faint warm glow; Codex stays pure black glass.
            if provider == .claude {
                RadialGradient(colors: [provider.ringColors.outer.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 80)
            }
        }
        .modifier(WidgetCard(highlighted: hovering))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Remaining percentages; on hover, time to each reset.
    private var legend: some View {
        HStack(spacing: 8) {
            item("5h", usage?.session, provider.ringColors.outer)
            item("7d", usage?.weekly, provider.ringColors.inner)
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .frame(height: 14)
    }

    private func item(_ label: String, _ window: AIUsageWindow?, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.white.opacity(0.5))
            Text(hovering ? compactCountdown(to: window?.resetsAt) : window.map { "\($0.remaining)%" } ?? "–")
                .foregroundStyle((window?.remaining ?? 100) < 10 ? Color(red: 1, green: 0.4, blue: 0.35) : .white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.75)
        }
        .lineLimit(1)
    }

    private func message(_ symbol: String, _ title: String, _ hint: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(hint)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
    }

    private var accessibilityText: String {
        guard let usage else { return "\(provider.name) usage unavailable" }
        let s = usage.session.map { "\($0.remaining) percent left in the 5 hour window" } ?? ""
        let w = usage.weekly.map { "\($0.remaining) percent left this week" } ?? ""
        return "\(provider.name): \(s), \(w)"
    }
}

// MARK: - Live data

extension AIProvider: Defaults.Serializable {}

extension Defaults.Keys {
    static let aiUsageProvider = Key<AIProvider>("aiUsageProvider", default: .claude)
}

@MainActor
final class AIUsageManager: ObservableObject {
    static let shared = AIUsageManager()

    @Published private(set) var state: AIUsageState = .loading
    @Published private(set) var updated: Date?
    /// Last HTTP status, shown in settings when something goes wrong.
    @Published private(set) var lastStatus: Int?
    private var timer: Timer?
    private var viewers = 0
    private var loading = false

    /// Polls every 2 min only while a widget is visible; limits move slowly.
    func start() {
        viewers += 1
        if updated.map({ Date().timeIntervalSince($0) > 60 }) ?? true { refresh() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in AIUsageManager.shared.refresh() }
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Call after switching provider: drops the other service's numbers.
    func providerChanged() {
        state = .loading
        updated = nil
        refresh()
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        let provider = Defaults[.aiUsageProvider]
        Task {
            let (status, body) = await XPCHelperClient.shared.aiUsage(provider.rawValue)
            loading = false
            guard provider == Defaults[.aiUsageProvider] else { return refresh() }
            lastStatus = status
            let next: AIUsageState
            switch status {
            case 0: next = .notSignedIn
            case 401, 403: next = .expired
            case 200..<300:
                next = body.flatMap { AIUsage.parse($0, provider: provider) }.map(AIUsageState.ready) ?? .offline
            default:
                // keep the last good numbers through a transient failure
                if case .ready = state { return }
                next = .offline
            }
            updated = Date()
            if next != state { state = next }
        }
    }
}

/// Small widget wired to live data.
struct AIUsageWidget: View {
    @ObservedObject private var manager = AIUsageManager.shared
    @Default(.aiUsageProvider) private var provider
    @State private var hovering = false

    var body: some View {
        AIUsageContent(provider: provider, state: manager.state, hovering: hovering)
            .animation(.smooth(duration: 0.3), value: hovering)
            .animation(.smooth(duration: 0.4), value: manager.state)
            .onHover { hovering = $0 }
            .onAppear {
                #if DEBUG
                _ = AIUsage.parseSelfCheck
                #endif
                manager.start()
            }
            .onDisappear { manager.stop() }
    }
}

/// Settings › Widgets section, shown while the widget is in the notch.
struct AIUsageSettings: View {
    @ObservedObject private var manager = AIUsageManager.shared
    @Default(.aiUsageProvider) private var provider
    @State private var showSteps = false

    private var connected: Bool { if case .ready = manager.state { return true } else { return false } }

    var body: some View {
        Section {
            Picker("Service", selection: $provider) {
                ForEach(AIProvider.allCases) { p in Text(p.name).tag(p) }
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) { _, _ in manager.providerChanged() }

            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                }
            }

            if connected {
                DisclosureGroup("How to connect", isExpanded: $showSteps) { steps }
            } else {
                steps
            }

            HStack {
                Button("Open Terminal") {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                                       configuration: NSWorkspace.OpenConfiguration())
                }
                Spacer()
                if let updated = manager.updated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                }
                Button("Refresh") { manager.refresh() }
            }
            .onAppear { manager.refresh() }
        } header: {
            Text("AI usage")
        } footer: {
            Text("No API key needed: the widget reuses the sign-in of the \(provider == .claude ? "Claude Code" : "Codex") command-line tool. The sign-in stays on this Mac and is only sent to \(provider == .claude ? "Anthropic" : "OpenAI") to read your limits.")
        }
    }

    @ViewBuilder
    private var steps: some View {
        switch provider {
        case .claude:
            StepRow(number: 1, title: "Install Claude Code",
                    detail: "Skip this if you already use Claude Code. In Terminal, paste:",
                    command: "curl -fsSL https://claude.ai/install.sh | bash")
            StepRow(number: 2, title: "Sign in with your Claude account",
                    detail: "Run the command below. Choose \u{201C}Claude account with subscription\u{201D}, approve in the browser, then type /exit. Needs a Pro or Max plan.",
                    command: "claude")
            StepRow(number: 3, title: "Come back and press Refresh",
                    detail: "Status turns green. If it says the sign-in expired, run claude once more.",
                    command: nil)
        case .codex:
            StepRow(number: 1, title: "Install Codex",
                    detail: "Skip this if you already use Codex. In Terminal, paste:",
                    command: "npm install -g @openai/codex")
            StepRow(number: 2, title: "Sign in with your ChatGPT account",
                    detail: "Run the command below and choose \u{201C}Sign in with ChatGPT\u{201D}. Needs a Plus, Pro or Team plan.",
                    command: "codex login")
            StepRow(number: 3, title: "Come back and press Refresh",
                    detail: "Status turns green. If it says the sign-in expired, open Codex once more.",
                    command: nil)
        }
    }

    private var statusText: String {
        switch manager.state {
        case .loading: return "Checking…"
        case .ready(let u): return "Connected" + (u.plan.map { " · \($0.capitalized)" } ?? "")
        case .notSignedIn: return "Not signed in yet"
        case .expired: return "Sign-in expired"
        case .offline:
            let code = manager.lastStatus.map { $0 > 0 ? " (HTTP \($0))" : " (no connection)" } ?? ""
            return "Can't reach \(provider.name)" + code
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .ready: return .green
        case .loading: return .secondary
        case .expired, .offline: return .orange
        case .notSignedIn: return .red
        }
    }
}

/// One numbered setup step, with an optional command and a Copy button.
private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let command: String?
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let command {
                    HStack {
                        Text(command)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
