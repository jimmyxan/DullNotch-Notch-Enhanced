//
//  WeatherWidget.swift
//  boringNotch
//
//  Weather widget: Open-Meteo forecast (no API key), device location with
//  IP-geolocation fallback, condition-specific animations, offline mascot.
//

import CoreLocation
import Network
import SwiftUI

// MARK: - Model

enum WeatherKind {
    case clear, partly, cloudy, fog, drizzle, rain, snow, thunder

    /// WMO weather interpretation codes, as returned by Open-Meteo.
    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partly
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunder
        default: self = .cloudy
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partly: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Foggy"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .thunder: return "Thunderstorm"
        }
    }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partly: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    /// Sky gradient in the spirit of Apple's Weather app.
    func sky(isDay: Bool) -> [Color] {
        if !isDay {
            switch self {
            case .clear, .partly: return [Color(red: 0.05, green: 0.08, blue: 0.22), Color(red: 0.16, green: 0.2, blue: 0.4)]
            default: return [Color(red: 0.12, green: 0.14, blue: 0.2), Color(red: 0.24, green: 0.27, blue: 0.34)]
            }
        }
        switch self {
        case .clear: return [Color(red: 0.16, green: 0.47, blue: 0.9), Color(red: 0.4, green: 0.7, blue: 0.98)]
        case .partly: return [Color(red: 0.26, green: 0.5, blue: 0.84), Color(red: 0.55, green: 0.72, blue: 0.92)]
        case .cloudy, .fog: return [Color(red: 0.42, green: 0.5, blue: 0.6), Color(red: 0.62, green: 0.68, blue: 0.75)]
        case .drizzle, .rain: return [Color(red: 0.28, green: 0.35, blue: 0.46), Color(red: 0.46, green: 0.53, blue: 0.62)]
        case .snow: return [Color(red: 0.5, green: 0.6, blue: 0.72), Color(red: 0.75, green: 0.8, blue: 0.88)]
        case .thunder: return [Color(red: 0.18, green: 0.2, blue: 0.3), Color(red: 0.35, green: 0.36, blue: 0.48)]
        }
    }
}

struct WeatherReport: Equatable {
    enum Source { case device, ip }
    var city: String
    var temperature: Int
    var high: Int
    var low: Int
    var code: Int
    var isDay: Bool
    var source: Source

    var kind: WeatherKind { WeatherKind(code: code) }
}

// MARK: - Manager

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var report: WeatherReport?
    @Published private(set) var isOffline = false
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor()
    private var lastFetch: Date?
    private var timer: Timer?
    private var viewers = 0
    private var askedForLocation = false

    override init() {
        authorization = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        pathMonitor.pathUpdateHandler = { path in
            Task { @MainActor in WeatherManager.shared.networkChanged(online: path.status == .satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "weather.path"))
    }

    /// Refreshes every 15 min only while a weather widget is on screen.
    func start() {
        viewers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in WeatherManager.shared.refresh(force: true) }
        }
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh(force: Bool = false) {
        guard !isOffline else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 10 * 60, report != nil { return }
        isLoading = true
        switch authorization {
        case .authorizedAlways, .authorized:
            locationManager.requestLocation()
        case .notDetermined:
            // Every open of the notch lands here, so ask once per launch. Not persisted: macOS
            // forgets the answer when the code signature changes, and a saved flag would then
            // block the prompt and leave the widget on IP location for good.
            if !askedForLocation {
                askedForLocation = true
                locationManager.requestWhenInUseAuthorization()
            }
            Task { await fetchUsingIP() } // the widget should not wait for the answer
        default:
            Task { await fetchUsingIP() }
        }
    }

    /// Settings: ask again, or send the user to System Settings once macOS stops asking.
    func requestPreciseLocation() {
        if authorization == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private func networkChanged(online: Bool) {
        #if DEBUG
        // `open Boring\ Notch.app --args -simulateOffline` to preview the offline state.
        let online = online && !ProcessInfo.processInfo.arguments.contains("-simulateOffline")
        #endif
        guard isOffline == online else { return }
        isOffline = !online
        if online, viewers > 0 { refresh(force: true) }
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        if status != .notDetermined { refresh(force: true) }
    }

    fileprivate func gotLocation(_ location: CLLocation) {
        Task {
            let city = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.locality
            await fetch(lat: location.coordinate.latitude, lon: location.coordinate.longitude, city: city ?? "My Location", source: .device)
        }
    }

    fileprivate func locationFailed() {
        Task { await fetchUsingIP() }
    }

    // ponytail: single IP-geolocation provider; add a second one if ipwho.is proves flaky.
    private func fetchUsingIP() async {
        struct IPLocation: Decodable { let success: Bool; let latitude: Double?; let longitude: Double?; let city: String? }
        guard let url = URL(string: "https://ipwho.is/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ip = try? JSONDecoder().decode(IPLocation.self, from: data),
              ip.success, let lat = ip.latitude, let lon = ip.longitude
        else { isLoading = false; return }
        await fetch(lat: lat, lon: lon, city: ip.city ?? "—", source: .ip)
    }

    private func fetch(lat: Double, lon: Double, city: String, source: WeatherReport.Source) async {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Current
            let daily: Daily
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        if Locale.current.measurementSystem == .us {
            components.queryItems?.append(.init(name: "temperature_unit", value: "fahrenheit"))
        }
        defer { isLoading = false }
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data)
        else { return }
        // A slow IP lookup started before the permission was granted must not replace the real position.
        if source == .ip, report?.source == .device, authorization == .authorizedAlways { return }
        report = WeatherReport(
            city: city,
            temperature: Int(r.current.temperature_2m.rounded()),
            high: Int((r.daily.temperature_2m_max.first ?? r.current.temperature_2m).rounded()),
            low: Int((r.daily.temperature_2m_min.first ?? r.current.temperature_2m).rounded()),
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            source: source
        )
        lastFetch = Date()
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in WeatherManager.shared.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in WeatherManager.shared.gotLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in WeatherManager.shared.locationFailed() }
    }
}

// MARK: - Views

/// Small widget: city, big temperature, animated sky for the current condition.
struct WeatherWidget: View {
    @ObservedObject private var manager = WeatherManager.shared

    var body: some View {
        Group {
            if manager.isOffline {
                OfflineView()
            } else if let report = manager.report {
                WeatherContent(report: report)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
            }
        }
        .animation(.smooth(duration: 0.4), value: manager.isOffline)
        .animation(.smooth(duration: 0.4), value: manager.report)
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }
}

struct WeatherContent: View {
    let report: WeatherReport

    var body: some View {
        let kind = report.kind
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(report.city).lineLimit(1)
                if report.source == .device {
                    Image(systemName: "location.fill").font(.system(size: 8))
                }
            }
            .font(.system(size: 13, weight: .semibold))
            Text("\(report.temperature)°")
                .font(.system(size: 38, weight: .light))
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text("H:\(report.high)° L:\(report.low)°").font(.system(size: 11, weight: .medium))
                }
                Spacer(minLength: 0)
                AnimatedWeatherSymbol(kind: kind, isDay: report.isDay)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { WeatherSky(kind: kind, isDay: report.isDay) }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(report.city), \(report.temperature) degrees, \(kind.label), high \(report.high), low \(report.low)")
    }
}

/// Gradient sky plus falling rain / snow particles and lightning flashes.
private struct WeatherSky: View {
    let kind: WeatherKind
    let isDay: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: kind.sky(isDay: isDay), startPoint: .top, endPoint: .bottom)
            if [.partly, .cloudy, .fog].contains(kind) {
                DriftingHaze(fog: kind == .fog, dense: kind == .cloudy)
            }
            if [.drizzle, .rain, .thunder, .snow].contains(kind) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    Canvas { ctx, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let snow = kind == .snow
                        let count = kind == .drizzle ? 14 : 24
                        for i in 0..<count {
                            let seed = Double(i) * 37.13
                            let speed = snow ? 18 + seed.truncatingRemainder(dividingBy: 12) : 110 + seed.truncatingRemainder(dividingBy: 60)
                            let x0 = (seed * 13).truncatingRemainder(dividingBy: size.width)
                            let y = (t * speed + seed * 9).truncatingRemainder(dividingBy: size.height + 20) - 10
                            if snow {
                                let x = x0 + sin(t * 1.5 + seed) * 6
                                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.8)))
                            } else {
                                var p = Path()
                                p.move(to: CGPoint(x: x0, y: y))
                                p.addLine(to: CGPoint(x: x0 - 2, y: y + 9))
                                ctx.stroke(p, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                            }
                        }
                        if kind == .thunder {
                            // brief flash roughly every 4 s
                            let phase = t.truncatingRemainder(dividingBy: 4)
                            if phase < 0.12 {
                                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.25)))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Soft, blurred clouds (or fog bands) sliding slowly across the sky. Low frame rate, low opacity:
/// noticeable at a glance, never distracting.
private struct DriftingHaze: View {
    let fog: Bool
    let dense: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ctx.addFilter(.blur(radius: fog ? 8 : 6))
                if fog {
                    // three horizontal bands drifting at different speeds
                    for i in 0..<3 {
                        let speed = 4.0 + Double(i) * 2
                        let w = size.width * 1.4
                        let x = CGFloat((t * speed + Double(i) * 90).truncatingRemainder(dividingBy: Double(w + size.width))) - w
                        let y = size.height * (0.35 + CGFloat(i) * 0.2)
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: 14), cornerRadius: 7),
                                 with: .color(.white.opacity(0.16)))
                    }
                } else {
                    let count = dense ? 4 : 2
                    for i in 0..<count {
                        let speed = 5.0 + Double(i) * 1.7
                        let w: CGFloat = 70 + CGFloat(i % 2) * 30
                        let span = Double(size.width + w)
                        let x = CGFloat((t * speed + Double(i) * span / Double(count)).truncatingRemainder(dividingBy: span)) - w
                        let y = size.height * (0.18 + CGFloat(i % 3) * 0.17)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 0.38)),
                                 with: .color(.white.opacity(dense ? 0.14 : 0.18)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The condition glyph, with a gentle motion matching the weather.
private struct AnimatedWeatherSymbol: View {
    let kind: WeatherKind
    let isDay: Bool
    @State private var phase = false

    var body: some View {
        Image(systemName: kind.symbol(isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 26))
            .rotationEffect(.degrees(kind == .clear && isDay && phase ? 20 : 0))
            .offset(x: [.partly, .cloudy, .fog].contains(kind) ? (phase ? 3 : -3) : 0)
            .scaleEffect(kind == .clear && !isDay ? (phase ? 1.05 : 0.97) : 1)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: [.drizzle, .rain, .thunder, .snow].contains(kind))
            .onAppear {
                withAnimation(.easeInOut(duration: kind == .clear ? 6 : 3).repeatForever(autoreverses: true)) { phase = true }
            }
    }
}

/// No internet: the Claude Code mascot, crying.
private struct OfflineView: View {
    var body: some View {
        VStack(spacing: 8) {
            CryingMascot().frame(width: 72, height: 78)
            Text("No connection")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No internet connection")
    }
}

/// Pixel-art Claude Code mascot with sad eyes, sobbing bounce and falling tears.
struct CryingMascot: View {
    private static let shape: [String] = [
        "..########..",
        "..########..",
        "..########..",
        "############",
        "############",
        "..########..",
        "..#.#..#.#..",
        "..#.#..#.#..",
    ]
    private static let orange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cols = CGFloat(Self.shape[0].count)
                let px = min(size.width / cols, size.height / (CGFloat(Self.shape.count) + 5))
                let originX = (size.width - px * cols) / 2
                let sob = abs(sin(t * 5)) * px * 0.35
                let originY = px * 3.5 + sob

                // little storm cloud parked right above, raining on the mascot
                let cloudColor = Color(white: 0.62)
                let cx = size.width / 2
                for (dx, dy, r) in [(-1.6, 1.1, 0.9), (0.0, 0.8, 1.2), (1.6, 1.1, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + dx * px - r * px, y: dy * px - r * px * 0.6 + px * 0.4, width: r * px * 2, height: r * px * 1.4)),
                             with: .color(cloudColor))
                }
                ctx.fill(Path(roundedRect: CGRect(x: cx - 2.6 * px, y: 1.2 * px, width: 5.2 * px, height: 1.1 * px), cornerRadius: px * 0.5),
                         with: .color(cloudColor))
                for i in 0..<9 {
                    let seed = Double(i) * 0.37
                    let cycle = (t * 1.6 + seed).truncatingRemainder(dividingBy: 1)
                    let x = cx - 2.3 * px + CGFloat(i) * 0.58 * px
                    let y = 2.4 * px + CGFloat(cycle) * px * 3.2
                    var drop = Path()
                    drop.move(to: CGPoint(x: x, y: y))
                    drop.addLine(to: CGPoint(x: x - px * 0.15, y: y + px * 0.6))
                    ctx.stroke(drop, with: .color(Color(red: 0.55, green: 0.8, blue: 1).opacity(0.9 * (1 - cycle * 0.6))),
                               style: StrokeStyle(lineWidth: px * 0.28, lineCap: .round))
                }

                for (r, row) in Self.shape.enumerated() {
                    for (c, ch) in row.enumerated() where ch == "#" {
                        let rect = CGRect(x: originX + CGFloat(c) * px, y: originY + CGFloat(r) * px, width: px + 0.5, height: px + 0.5)
                        ctx.fill(Path(rect), with: .color(Self.orange))
                    }
                }
                // sad eyes: Clawd's dark eye blocks, with brows tilted up toward the middle
                for eyeCol in [3.0, 8.0] {
                    let x = originX + eyeCol * px
                    let eye = CGRect(x: x + px * 0.15, y: originY + 1.1 * px, width: px * 0.7, height: px * 0.9)
                    ctx.fill(Path(eye), with: .color(.black))
                    var brow = Path()
                    let inner = eyeCol < 6 ? x + px : x
                    let outer = eyeCol < 6 ? x : x + px
                    brow.move(to: CGPoint(x: outer, y: originY + 0.75 * px))
                    brow.addLine(to: CGPoint(x: inner, y: originY + 0.35 * px))
                    ctx.stroke(brow, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: px * 0.3, lineCap: .round))
                }
                // tears: a steady stream from each eye, drops falling and fading out of phase
                for (i, eyeCol) in [3.5, 8.5].enumerated() {
                    for k in 0..<2 {
                        let cycle = (t * 0.8 + Double(i) * 0.35 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                        let w = px * 0.75
                        let x = originX + eyeCol * px - w / 2
                        let y = originY + 2 * px + CGFloat(cycle) * px * 5.5
                        let drop = Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 1.4))
                        ctx.fill(drop, with: .color(Color(red: 0.35, green: 0.75, blue: 1).opacity(1 - cycle * 0.8)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
