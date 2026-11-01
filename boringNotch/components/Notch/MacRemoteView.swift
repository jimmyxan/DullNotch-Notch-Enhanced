//
//  MacRemoteView.swift
//  boringNotch
//
//  Notch tab for MacRemote (github.com/jimmyxan/MacRemote), embedded in the app bundle
//  under Contents/Helpers. Starts/stops it and shows the iPhone pairing QR code.
//

import AppKit
import CoreImage
import SwiftUI

@MainActor
final class MacRemoteManager: ObservableObject {
    static let shared = MacRemoteManager()

    enum State: Equatable {
        case stopped, starting
        case running(url: String)
        case failed(String)
    }

    @Published private(set) var state: State = .stopped

    static let bundleID = "local.macremote"
    static let port = 8765

    private var embeddedApp: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacRemote.app")
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    private init() {
        // Quit from its own menu bar item, or crashed: reflect it here.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == MacRemoteManager.bundleID else { return }
            Task { @MainActor in MacRemoteManager.shared.state = .stopped }
        }
    }

    /// Picks up an instance that is already running (also a standalone MacRemote install).
    func refresh() {
        guard isRunning else {
            if state != .starting { state = .stopped }
            return
        }
        Task { await loadURL() }
    }

    func start() {
        guard state != .starting else { return }
        if isRunning { return refresh() }
        guard FileManager.default.fileExists(atPath: embeddedApp.path) else {
            state = .failed("MacRemote is missing from this build.")
            return
        }
        state = .starting
        Task {
            if let error = await XPCHelperClient.shared.launchMacRemote(at: embeddedApp.path) {
                state = .failed(error)
            } else {
                await loadURL()
            }
        }
    }

    func stop() {
        Task {
            _ = await XPCHelperClient.shared.stopMacRemote()
            state = .stopped
        }
    }

    /// New pairing code: phones paired with the old link stop working.
    func regenerateCode() {
        Task {
            state = .starting
            _ = await XPCHelperClient.shared.stopMacRemote()
            for _ in 0..<20 where isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            _ = await XPCHelperClient.shared.setMacRemoteToken(bytes.map { String(format: "%02x", $0) }.joined())
            state = .stopped
            start()
        }
    }

    /// MacRemote creates its token on first launch, so give it a moment.
    private func loadURL() async {
        for _ in 0..<25 {
            if let token = await XPCHelperClient.shared.macRemoteToken(), !token.isEmpty {
                state = .running(url: "http://\(Self.lanIP() ?? "localhost"):\(Self.port)/?t=\(token)")
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        state = isRunning ? .failed("Couldn't read the pairing code.") : .stopped
    }

    /// Same rule as MacRemote: first private IPv4 on an en* interface.
    static func lanIP() -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: i.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") { return ip }
        }
        return nil
    }
}

/// MacRemote's own app icon, redrawn natively: blue→purple squircle with the Mac + iPhone glyph.
struct MacRemoteIcon: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.30, blue: 0.95), Color(red: 0.55, green: 0.20, blue: 0.85)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.4, green: 0.25, blue: 0.9).opacity(0.45), radius: 10, y: 3)
    }
}

struct MacRemoteView: View {
    @ObservedObject private var manager = MacRemoteManager.shared
    @State private var copied = false

    var body: some View {
        Group {
            switch manager.state {
            case .stopped: intro
            case .starting: starting
            case .running(let url): pairing(url)
            case .failed(let message): failure(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.state)
        .onAppear { manager.refresh() }
    }

    private var intro: some View {
        HStack(spacing: 20) {
            MacRemoteIcon(size: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text("MacRemote")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Control this Mac from your iPhone: volume, media, brightness, keyboard and touchpad. Same Wi-Fi only.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button { manager.start() } label: {
                    Label("Start MacRemote", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(LinearGradient(
                            colors: [Color(red: 0.3, green: 0.36, blue: 1), Color(red: 0.6, green: 0.28, blue: 0.92)],
                            startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .transition(.opacity)
    }

    private var starting: some View {
        HStack(spacing: 14) {
            MacRemoteIcon(size: 56)
            ProgressView().controlSize(.small)
            Text("Starting MacRemote…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .transition(.opacity)
    }

    private func pairing(_ url: String) -> some View {
        HStack(spacing: 18) {
            QRCodeImage(text: url)
                .frame(width: 118, height: 118)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .accessibilityLabel("Pairing QR code")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    MacRemoteIcon(size: 22)
                    Text("MacRemote is on")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Circle().fill(.green).frame(width: 7, height: 7)
                }
                Text("Scan with the iPhone camera, on the same Wi-Fi as this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Text(url.components(separatedBy: "?").first ?? url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                HStack(spacing: 8) {
                    pill(copied ? "Copied" : "Copy link", copied ? "checkmark" : "link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    pill("New code", "arrow.triangle.2.circlepath") { manager.regenerateCode() }
                    pill("Stop", "stop.fill", tint: Color(red: 1, green: 0.35, blue: 0.35)) { manager.stop() }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private func failure(_ message: String) -> some View {
        HStack(spacing: 16) {
            MacRemoteIcon(size: 56).saturation(0)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                pill("Try again", "arrow.clockwise") { manager.start() }
            }
        }
        .transition(.opacity)
    }

    private func pill(_ title: String, _ symbol: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Crisp QR code from CoreImage (nearest-neighbour scaling keeps the modules sharp).
private struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
        } else {
            Image(systemName: "qrcode").resizable().foregroundStyle(.black)
        }
    }

    private static func render(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
