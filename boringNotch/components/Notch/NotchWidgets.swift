//
//  NotchWidgets.swift
//  boringNotch
//
//  Customizable home widgets (music, Bluetooth battery, calendar, mirror)
//  plus the Bluetooth battery reader and the Widgets settings pane.
//

import Defaults
import IOBluetooth
import SwiftUI

// MARK: - Model

enum NotchWidget: String, CaseIterable, Identifiable, Defaults.Serializable {
    case music, bluetoothBattery, calendar, mirror, weather

    var id: String { rawValue }

    /// Width units: large = 2, small = 1. The home fits 1 large + 2 small.
    var units: Int { self == .music ? 2 : 1 }
    static let maxUnits = 4

    static func fits(_ list: [NotchWidget]) -> Bool {
        list.reduce(0) { $0 + $1.units } <= maxUnits
    }

    /// Fixed widget widths: the open notch grows/shrinks with the widgets it holds.
    var width: CGFloat {
        switch self {
        case .music: return 330
        case .calendar: return 210
        case .bluetoothBattery, .mirror, .weather: return 150
        }
    }

    static let spacing: CGFloat = 14
    /// Below this the header (tabs + hardware notch + status icons) gets cramped.
    static let minHomeWidth: CGFloat = 500

    static func homeWidth(_ list: [NotchWidget]) -> CGFloat {
        let content = list.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, list.count - 1))
        return max(minHomeWidth, content)
    }

    var title: String {
        switch self {
        case .music: return "Music"
        case .bluetoothBattery: return "Bluetooth battery"
        case .calendar: return "Calendar"
        case .mirror: return "Mirror"
        case .weather: return "Weather"
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        case .bluetoothBattery: return "airpodspro"
        case .calendar: return "calendar"
        case .mirror: return "web.camera"
        case .weather: return "cloud.sun.fill"
        }
    }
}

extension Defaults.Keys {
    /// Initial value migrates the old `showCalendar` / `showMirror` toggles.
    /// Show the weather in place of the Bluetooth battery widget while no device is connected.
    static let weatherReplacesIdleBluetooth = Key<Bool>("weatherReplacesIdleBluetooth", default: true)

    static let homeWidgets = Key<[NotchWidget]>(
        "homeWidgets",
        default: [.music]
            + (UserDefaults.standard.bool(forKey: "showCalendar") ? [.calendar] : [])
            + (UserDefaults.standard.bool(forKey: "showMirror") ? [.mirror] : [])
    )
}

// MARK: - Bluetooth battery

struct BTDevice: Equatable {
    var name: String
    var single: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    /// AirPods/Beats expose per-bud and case levels; generic devices only a single value.
    var isDetailed: Bool { left != nil || right != nil || caseLevel != nil }

    var level: Int? {
        let buds = [left, right].compactMap { $0 }
        return buds.min() ?? single
    }

    var isApple: Bool { name.lowercased().contains("airpods") || name.lowercased().contains("beats") }

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods") { return "airpods" }
        if isDetailed { return "earbuds" }
        if n.contains("speaker") || n.contains("boom") || n.contains("jbl") || n.contains("sonos") { return "hifispeaker.fill" }
        return "headphones"
    }

    var caseSymbol: String {
        name.lowercased().contains("airpods pro") ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
    }
}

@MainActor
final class BluetoothBatteryManager: ObservableObject {
    static let shared = BluetoothBatteryManager()

    @Published private(set) var device: BTDevice?
    /// False until the first read finishes, so "no device" isn't assumed before we know.
    @Published private(set) var didRead = false
    private var timer: Timer?
    private var viewers = 0
    private var reading = false

    /// Polls every 30 s only while at least one widget is on screen (notch and/or settings preview).
    func start() {
        viewers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in BluetoothBatteryManager.shared.refresh() }
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    // ponytail: shows one "primary" device (AirPods-like first); add a picker if multi-device is needed.
    /// IOBluetooth can block while macOS waits on the Bluetooth permission prompt, so read off the main thread.
    func refresh() {
        guard !reading else { return }
        reading = true
        Task.detached(priority: .utility) {
            let next = Self.readPrimaryDevice()
            await MainActor.run {
                let manager = BluetoothBatteryManager.shared
                manager.reading = false
                manager.didRead = true
                if next != manager.device { manager.device = next }
            }
        }
    }

    nonisolated private static func readPrimaryDevice() -> BTDevice? {
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .map { d in
                BTDevice(
                    name: d.name ?? "Bluetooth",
                    single: percent(d, "batteryPercentSingle"),
                    left: percent(d, "batteryPercentLeft"),
                    right: percent(d, "batteryPercentRight"),
                    caseLevel: percent(d, "batteryPercentCase")
                )
            }
            .filter { $0.level != nil || $0.caseLevel != nil }
        return connected.first(where: \.isDetailed) ?? connected.first
    }

    /// Private-but-stable IOBluetoothDevice properties; 0 means "not reported".
    nonisolated private static func percent(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let v = (device.value(forKey: key) as? NSNumber)?.intValue,
              v > 0, v <= 100 else { return nil }
        return v
    }
}

// MARK: - Battery visuals

private func batteryGradient(_ level: Int) -> [Color] {
    switch level {
    case ..<20: return [Color(red: 1, green: 0.27, blue: 0.23), Color(red: 1, green: 0.45, blue: 0.35)]
    case ..<40: return [Color(red: 1, green: 0.62, blue: 0.04), Color(red: 1, green: 0.8, blue: 0.2)]
    default: return [Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 0.45, green: 0.95, blue: 0.55)]
    }
}

/// Apple-style ring: dim track, gradient arc that sweeps in when it appears.
private struct BatteryRing: View {
    let level: Int?
    var lineWidth: CGFloat = 4
    @State private var shown: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            if let level {
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(
                        AngularGradient(colors: batteryGradient(level), center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Double(shown))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: batteryGradient(level)[0].opacity(0.5), radius: 4)
            }
        }
        .onAppear { animate(to: level) }
        .onChange(of: level) { _, new in animate(to: new) }
    }

    private func animate(to level: Int?) {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.1)) {
            shown = CGFloat(level ?? 0) / 100
        }
    }
}

/// Glassy card used by the small widgets: soft vertical gradient + hairline highlight.
private struct WidgetCard: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(highlighted ? 0.16 : 0.11), .white.opacity(highlighted ? 0.08 : 0.04)],
                        startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white.opacity(highlighted ? 0.35 : 0.18), .white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

/// Small square widget: device glyph, name, animated ring. Tappable only for AirPods-like devices.
struct BluetoothBatteryWidget: View {
    @ObservedObject private var manager = BluetoothBatteryManager.shared
    var namespace: Namespace.ID
    var onExpand: () -> Void
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: 0) {
                if let device = manager.device {
                    Image(systemName: device.symbol)
                        .font(.system(size: 26, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: bounce)
                        .scaleEffect(hovering && device.isDetailed ? 1.05 : 1)
                        .matchedGeometryEffect(id: "btGlyph", in: namespace)
                        .frame(height: 30)
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 6)
                    Text(device.isDetailed ? "Tap for details" : "Connected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 1)
                    Spacer(minLength: 6)
                    ZStack {
                        BatteryRing(level: device.level, lineWidth: 4.5)
                        Text(device.level.map { "\($0)" } ?? "–")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    .matchedGeometryEffect(id: "btRing", in: namespace)
                } else {
                    Spacer()
                    Image(systemName: "headphones")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                    Text("No device")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.top, 6)
                    Spacer()
                }
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(WidgetCard(highlighted: hovering && (manager.device?.isDetailed ?? false)))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .scaleEffect(hovering && (manager.device?.isDetailed ?? false) ? 1.012 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .onAppear {
            BluetoothBatteryManager.shared.start()
            bounce += 1
        }
        .onDisappear { BluetoothBatteryManager.shared.stop() }
        .disabled(!(manager.device?.isDetailed ?? false))
        .accessibilityLabel(manager.device.map { "\($0.name), battery \($0.level ?? 0) percent" } ?? "No Bluetooth device")
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Expanded AirPods view: left / right / case, bars fill in one after another.
struct AirPodsDetailView: View {
    @ObservedObject private var manager = BluetoothBatteryManager.shared
    var namespace: Namespace.ID
    var onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        if let device = manager.device {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        BatteryRing(level: device.level, lineWidth: 3.5)
                            .matchedGeometryEffect(id: "btRing", in: namespace)
                        Image(systemName: device.symbol)
                            .font(.system(size: 20))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .matchedGeometryEffect(id: "btGlyph", in: namespace)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle(device))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isLow(device) ? batteryGradient(10)[0] : .white.opacity(0.5))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Close")
                }

                HStack(spacing: 10) {
                    let parts: [(String, String, Int?)] = [
                        ("Left", "airpod.left", device.left),
                        ("Right", "airpod.right", device.right),
                        ("Case", device.caseSymbol, device.caseLevel),
                    ]
                    // Only parts that report a level: a closed/away case simply isn't shown.
                    ForEach(Array(parts.filter { $0.2 != nil }.enumerated()), id: \.element.0) { i, part in
                        card(part.0, part.1, part.2 ?? 0, index: i)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { appeared = true }
        } else {
            Color.clear.onAppear(perform: onClose)
        }
    }

    private func isLow(_ d: BTDevice) -> Bool {
        [d.left, d.right, d.caseLevel].compactMap { $0 }.contains { $0 < 20 }
    }

    private func subtitle(_ d: BTDevice) -> String {
        if let c = d.caseLevel, c < 20 { return "Case low · \(c)%" }
        if let l = d.level, l < 20 { return "Battery low · \(l)%" }
        return "Connected"
    }

    private func card(_ title: String, _ symbol: String, _ level: Int, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                Spacer()
                Text("\(level)%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(level < 20 ? batteryGradient(level)[0] : .white)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: batteryGradient(level), startPoint: .leading, endPoint: .trailing))
                        .frame(width: appeared ? geo.size.width * CGFloat(level) / 100 : 0)
                        .shadow(color: batteryGradient(level)[0].opacity(0.5), radius: 3)
                }
            }
            .frame(height: 5)
            .animation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15 + Double(index) * 0.08), value: appeared)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .modifier(WidgetCard())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06), value: appeared)
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Settings

extension NotchWidget {
    /// Drag & drop rule for the settings preview. `target` nil = empty notch area.
    /// Existing widget: swap with target (or move to the end). New widget: insert before target,
    /// or replace it when there's no room. Returns nil when the result wouldn't fit.
    static func drop(_ w: NotchWidget, onto target: NotchWidget?, in list: [NotchWidget]) -> [NotchWidget]? {
        var list = list
        let to = target.flatMap { list.firstIndex(of: $0) }
        if let from = list.firstIndex(of: w) {
            if let to { list.swapAt(from, to) } else { list.append(list.remove(at: from)) }
            return list
        }
        guard let to else {
            list.append(w)
            return fits(list) ? list : nil
        }
        var inserted = list
        inserted.insert(w, at: to)
        if fits(inserted) { return inserted }
        list[to] = w
        return fits(list) ? list : nil
    }

    #if DEBUG
    static let dropSelfCheck: Void = {
        assert(drop(.calendar, onto: .music, in: [.music, .calendar]) == [.calendar, .music]) // swap
        assert(drop(.mirror, onto: nil, in: [.music, .calendar]) == [.music, .calendar, .mirror]) // append
        assert(drop(.mirror, onto: .calendar, in: [.music, .calendar, .bluetoothBattery]) == [.music, .mirror, .bluetoothBattery]) // replace
        assert(drop(.mirror, onto: nil, in: [.music, .calendar, .bluetoothBattery]) == nil) // full
    }()
    #endif
}

/// Generic, data-free look of each widget, drawn at real notch size (scaled by the caller).
private struct GenericWidgetTile: View {
    let widget: NotchWidget
    static let height: CGFloat = 136

    var body: some View {
        Group {
            switch widget {
            case .music: music
            case .calendar: calendar
            case .bluetoothBattery: battery
            case .mirror: mirror
            case .weather: weather
            }
        }
        .frame(width: widget.width, height: Self.height)
        .modifier(WidgetCard())
    }

    private func bar(_ w: CGFloat, _ o: Double = 0.25, h: CGFloat = 9) -> some View {
        Capsule().fill(.white.opacity(o)).frame(width: w, height: h)
    }

    private var music: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.45), Color(red: 0.55, green: 0.3, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92)
                .overlay(Image(systemName: "music.note").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 8) {
                bar(120, 0.85, h: 11)
                bar(80, 0.4)
                bar(170, 0.18, h: 5).overlay(alignment: .leading) { bar(60, 0.8, h: 5) }.padding(.top, 8)
                HStack(spacing: 26) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 24))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: 170)
                .padding(.top, 4)
            }
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOV").font(.system(size: 13, weight: .bold)).foregroundStyle(.red)
            Text("1").font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            HStack(spacing: 6) { Capsule().fill(.orange).frame(width: 3, height: 26); VStack(alignment: .leading, spacing: 5) { bar(110, 0.6); bar(70) } }
            HStack(spacing: 6) { Capsule().fill(.blue).frame(width: 3, height: 26); VStack(alignment: .leading, spacing: 5) { bar(90, 0.6); bar(60) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    private var battery: some View {
        VStack(spacing: 8) {
            Image(systemName: "airpodspro").font(.system(size: 26)).symbolRenderingMode(.hierarchical).foregroundStyle(.white)
            bar(80, 0.6)
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 4.5)
                Circle().trim(from: 0, to: 0.8)
                    .stroke(LinearGradient(colors: batteryGradient(80), startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("80").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
        }
    }

    private var weather: some View {
        WeatherContent(report: WeatherReport(city: "Cupertino", temperature: 22, high: 25, low: 14, code: 1, isDay: true, source: .device))
    }

    private var mirror: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [.white.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 80))
    }
}

struct WidgetsSettings: View {
    @Default(.homeWidgets) private var widgets
    @State private var targeted: NotchWidget?
    @State private var notchTargeted = false
    @State private var trayTargeted = false
    @State private var rejected = 0

    private let scale: CGFloat = 0.6
    private let widgetAnimation = Animation.spring(response: 0.45, dampingFraction: 0.82)
    private var used: Int { widgets.reduce(0) { $0 + $1.units } }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 18) {
                    notchPreview
                    tray
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Drag widgets into the notch. Drop on a widget to swap places (or replace it if there's no room); drag one back to the tray to remove it. Space used: \(used)/\(NotchWidget.maxUnits).")
            }

            if widgets.contains(.bluetoothBattery) {
                Section {
                    Defaults.Toggle(key: .weatherReplacesIdleBluetooth) {
                        Text("Show weather when no Bluetooth device is connected")
                    }
                    .disabled(widgets.contains(.weather))
                } footer: {
                    Text(widgets.contains(.weather)
                         ? "Weather is already in the notch."
                         : "The Bluetooth battery widget comes back as soon as a device connects.")
                }
            }

            if widgets.contains(.weather) || (widgets.contains(.bluetoothBattery) && Defaults[.weatherReplacesIdleBluetooth]) {
                WeatherLocationSettings()
            }

            Section("In the notch") {
                List {
                    ForEach(widgets) { w in
                        HStack {
                            Label(w.title, systemImage: w.systemImage)
                            Spacer()
                            Text(w.units == 2 ? "Large" : "Small").foregroundStyle(.secondary)
                            Button {
                                withAnimation(widgetAnimation) { widgets.removeAll { $0 == w } }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(w.title)")
                        }
                    }
                    .onMove { from, to in
                        withAnimation(widgetAnimation) { widgets.move(fromOffsets: from, toOffset: to) }
                    }
                }
            }
        }
        .navigationTitle("Widgets")
        .onAppear {
            #if DEBUG
            _ = NotchWidget.dropSelfCheck
            #endif
        }
    }

    private func apply(_ items: [String], onto target: NotchWidget?) -> Bool {
        guard let w = items.first.flatMap(NotchWidget.init(rawValue:)), w != target else { return false }
        guard let next = NotchWidget.drop(w, onto: target, in: widgets) else {
            withAnimation(.default) { rejected += 1 }
            return false
        }
        withAnimation(widgetAnimation) { widgets = next }
        return true
    }

    private func tile(_ w: NotchWidget) -> some View {
        GenericWidgetTile(widget: w)
            .scaleEffect(scale)
            .frame(width: w.width * scale, height: GenericWidgetTile.height * scale)
    }

    private var notchPreview: some View {
        let width = (NotchWidget.homeWidth(widgets) + openNotchHorizontalInset) * scale
        return VStack(spacing: 10 * scale) {
            // header: tabs · hardware notch · status
            HStack {
                HStack(spacing: 6) { ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 7, height: 7) } }
                Spacer()
                Capsule().fill(.white.opacity(0.25)).frame(width: 34, height: 7)
            }
            .padding(.horizontal, 22 * scale)
            .frame(height: 18)

            HStack(spacing: NotchWidget.spacing * scale) {
                if widgets.isEmpty {
                    Text("Drag a widget here")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: GenericWidgetTile.height * scale)
                }
                ForEach(widgets) { w in
                    tile(w)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: targeted == w ? 2 : 0)
                        }
                        .scaleEffect(targeted == w ? 1.04 : 1)
                        .draggable(w.rawValue) { tile(w) }
                        .dropDestination(for: String.self) { items, _ in apply(items, onto: w) }
                            isTargeted: { on in withAnimation(.spring(response: 0.3)) { targeted = on ? w : (targeted == w ? nil : targeted) } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel(w.title)
                }
            }
            .frame(width: NotchWidget.homeWidth(widgets) * scale)
        }
        .padding(.top, 6)
        .padding(.bottom, 12 * scale + 6)
        .frame(width: width)
        .background {
            NotchShape(topCornerRadius: cornerRadiusInsets.opened.top * scale, bottomCornerRadius: cornerRadiusInsets.opened.bottom)
                .fill(.black)
                .shadow(color: notchTargeted ? Color.accentColor.opacity(0.6) : .black.opacity(0.4), radius: 12, y: 6)
        }
        .modifier(Shake(trigger: rejected))
        .dropDestination(for: String.self) { items, _ in apply(items, onto: nil) } isTargeted: { notchTargeted = $0 }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.75), Color(red: 0.62, green: 0.3, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.55)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .animation(widgetAnimation, value: widgets)
    }

    private var tray: some View {
        let available = NotchWidget.allCases.filter { !widgets.contains($0) }
        return HStack(spacing: 14) {
            if available.isEmpty {
                Text("All widgets are in the notch").foregroundStyle(.secondary)
            }
            ForEach(available) { w in
                VStack(spacing: 6) {
                    tile(w)
                        .draggable(w.rawValue) { tile(w) }
                        .opacity(NotchWidget.fits(widgets + [w]) ? 1 : 0.55)
                    Text(w.title).font(.caption).foregroundStyle(.secondary)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("\(w.title), drag into the notch")
            }
        }
        .frame(maxWidth: .infinity, minHeight: GenericWidgetTile.height * scale + 30)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(trayTargeted ? Color.accentColor : .secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .dropDestination(for: String.self) { items, _ in
            guard let w = items.first.flatMap(NotchWidget.init(rawValue:)), widgets.contains(w) else { return false }
            withAnimation(widgetAnimation) { widgets.removeAll { $0 == w } }
            return true
        } isTargeted: { trayTargeted = $0 }
        .animation(widgetAnimation, value: widgets)
    }
}

/// Small horizontal shake used when a drop is rejected for lack of space.
private struct Shake: GeometryEffect {
    var trigger: Int
    var animatableData: CGFloat
    init(trigger: Int) { self.trigger = trigger; animatableData = CGFloat(trigger) }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Shows where the weather comes from and lets the user grant / fix location access.
private struct WeatherLocationSettings: View {
    @ObservedObject private var weather = WeatherManager.shared

    private var precise: Bool {
        weather.authorization == .authorizedAlways || weather.authorization == .authorized
    }

    var body: some View {
        Section {
            LabeledContent("Location") {
                if let report = weather.report {
                    Text("\(report.city) · \(report.source == .device ? "precise" : "approximate (IP)")")
                } else {
                    Text(weather.isOffline ? "Offline" : "Locating…")
                }
            }
            HStack {
                Button(precise ? "Location Settings…" : "Allow Precise Location…") {
                    weather.requestPreciseLocation()
                }
                Spacer()
                Button("Refresh") { weather.refresh(force: true) }
                    .disabled(weather.isLoading || weather.isOffline)
            }
            .onAppear { weather.refresh() }
        } header: {
            Text("Weather")
        } footer: {
            Text(precise
                 ? "Wrong place? Refresh, or review the permission in System Settings › Privacy & Security › Location Services."
                 : "Without location access the weather uses an approximate position based on your IP address.")
        }
    }
}
