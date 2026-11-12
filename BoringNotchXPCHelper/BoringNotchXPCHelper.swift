//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import OSLog
import AppKit
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }

    // MARK: - MacRemote

    private static let macRemoteDomain = "local.macremote" as CFString

    @objc func macRemoteToken(with reply: @escaping (String?) -> Void) {
        CFPreferencesAppSynchronize(Self.macRemoteDomain)
        reply(CFPreferencesCopyAppValue("token" as CFString, Self.macRemoteDomain) as? String)
    }

    /// Only used while MacRemote is stopped: it reads the token at launch.
    @objc func setMacRemoteToken(_ token: String, with reply: @escaping (Bool) -> Void) {
        CFPreferencesSetAppValue("token" as CFString, token as CFString, Self.macRemoteDomain)
        reply(CFPreferencesAppSynchronize(Self.macRemoteDomain))
    }

    /// Replies nil on success, or the error message.
    @objc func launchMacRemote(at path: String, with reply: @escaping (String?) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--headless"]
        config.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { _, error in
            reply(error?.localizedDescription)
        }
    }

    @objc func stopMacRemote(with reply: @escaping (Bool) -> Void) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.macremote")
        apps.forEach { $0.terminate() }
        reply(!apps.isEmpty)
    }

    // MARK: - AI usage

    /// Uses the access token that Claude Code / Codex CLI already store. Read-only: it never refreshes
    /// tokens (refreshing would rotate the CLI's refresh token and sign it out); an expired token
    /// comes back as 401 and the user just opens the CLI once.
    static let log = Logger(subsystem: "theboringteam.boringnotch.helper", category: "aiUsage")

    @objc func aiUsage(_ provider: String, with reply: @escaping (Int, String?) -> Void) {
        var request: URLRequest
        switch provider {
        case "claude":
            guard let token = Self.claudeToken() else {
                Self.log.notice("aiUsage claude: no token found")
                return reply(0, nil)
            }
            request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case "codex":
            guard let (token, account) = Self.codexToken() else { return reply(0, nil) }
            request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        default:
            return reply(0, nil)
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if !(200..<300).contains(status) {
                Self.log.notice("aiUsage \(provider, privacy: .public): HTTP \(status, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
            }
            guard let http = response as? HTTPURLResponse else { return reply(-1, nil) }
            reply(http.statusCode, data.flatMap { String(data: $0, encoding: .utf8) })
        }.resume()
    }

    /// Claude Code keeps its OAuth sign-in in the login keychain (item "Claude Code-credentials"),
    /// or in ~/.claude/.credentials.json when the keychain isn't available.
    private static func claudeToken() -> String? {
        let security = Process()
        security.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        security.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        security.standardOutput = pipe
        security.standardError = FileHandle.nullDevice
        var data: Data?
        if (try? security.run()) != nil {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            security.waitUntilExit()
            if security.terminationStatus != 0 {
                log.notice("aiUsage claude: keychain read failed, security exit \(security.terminationStatus, privacy: .public)")
                data = nil
            }
        }
        if data == nil {
            data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/.credentials.json")
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    /// Codex CLI signed in with ChatGPT: $CODEX_HOME/auth.json (default ~/.codex).
    private static func codexToken() -> (String, String?)? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        guard let data = FileManager.default.contents(atPath: home + "/auth.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { return nil }
        return (access, tokens["account_id"] as? String)
    }
}

// MARK: - Clock timers

extension BoringNotchXPCHelper {
    /// Clock keeps its timers in `com.apple.mobiletimerd` › MTTimers › MTTimers[] › $MTTimer.
    /// Running = MTTimerState 3, with the fire date in MTTimerFireTime › $MTTimerDate › MTTimerTimeDate
    /// (seen on macOS 27.2). A stopped timer has state 1 and an interval instead of a date.
    // ponytail: private, undocumented format; paused timers are ignored. If Apple changes it, no timer shows.
    @objc func clockTimer(with reply: @escaping (Double, Double) -> Void) {
        let domain = "com.apple.mobiletimerd" as CFString
        CFPreferencesAppSynchronize(domain)
        let timers = (CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any])?["MTTimers"] as? [[String: Any]] ?? []
        let running: [(Date, Double)] = timers.compactMap { entry in
            guard let t = entry["$MTTimer"] as? [String: Any],
                  (t["MTTimerState"] as? NSNumber)?.intValue == 3,
                  let fire = ((t["MTTimerFireTime"] as? [String: Any])?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date,
                  let duration = (t["MTTimerDuration"] as? NSNumber)?.doubleValue, duration > 0 else { return nil }
            return (fire, duration)
        }
        guard let next = running.min(by: { $0.0 < $1.0 }) else { return reply(-1, -1) }
        reply(next.0.timeIntervalSince1970, next.1)
    }
}

// MARK: - Claude Code

extension BoringNotchXPCHelper {
    private static let claudeDir = NSHomeDirectory() + "/.claude"
    private static let hookMark = "dullnotch.agent."
    /// Event → state posted to the app (`ClaudeAgentStatus`).
    private static let hookEvents: [(event: String, state: String, matcher: String?)] = [
        ("UserPromptSubmit", "working", nil), ("PreToolUse", "working", "*"), ("PostToolUse", "working", "*"),
        ("Stop", "done", nil), ("Notification", "idle", nil), ("SessionEnd", "idle", nil),
    ]

    @objc func claudeHooks(_ action: String, with reply: @escaping (Int) -> Void) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: Self.claudeDir, isDirectory: &isDir), isDir.boolValue else { return reply(-1) }
        // Follow a symlink (dotfiles setups) so the atomic write replaces the real file, not the link.
        let url = URL(fileURLWithPath: Self.claudeDir + "/settings.json").resolvingSymlinksInPath()
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: url.path), !data.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return reply(-2) }
            settings = json
        }
        let hooks = settings["hooks"] as? [String: Any] ?? [:]

        func isOurs(_ entry: Any) -> Bool {
            ((entry as? [String: Any])?["hooks"] as? [[String: Any]] ?? [])
                .contains { ($0["command"] as? String)?.contains(Self.hookMark) == true }
        }
        let installed = Self.hookEvents.allSatisfy { (hooks[$0.event] as? [Any] ?? []).contains(where: isOurs) }
        if action == "status" { return reply(installed ? 1 : 0) }

        // Drop every entry of ours (also hand-made ones), then add the current set when installing.
        var updated = hooks.compactMapValues { value -> Any? in
            guard let list = value as? [Any] else { return value }
            let kept = list.filter { !isOurs($0) }
            return kept.isEmpty ? nil : kept
        }
        if action == "install" {
            for h in Self.hookEvents {
                var entry: [String: Any] = ["hooks": [["type": "command", "command": "/usr/bin/notifyutil -p \(Self.hookMark)\(h.state)"]]]
                if let matcher = h.matcher { entry["matcher"] = matcher }
                updated[h.event] = (updated[h.event] as? [Any] ?? []) + [entry]
            }
        }
        if updated.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = updated }

        let backup = url.path + ".dullnotch-backup"
        if !FileManager.default.fileExists(atPath: backup), FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.copyItem(atPath: url.path, toPath: backup)
        }
        guard let out = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              (try? (out + Data("\n".utf8)).write(to: url, options: .atomic)) != nil else { return reply(-3) }
        reply(action == "install" ? 1 : 0)
    }

    /// Claude Code keeps one file per running session, ~/.claude/sessions/<pid>.json, whose "status" it
    /// sets itself: "idle" between turns, something else while one runs. Esc fires no hook and, before any output,
    /// leaves no trace in the transcript, but it does turn the session idle.
    @objc func claudeBusySessions(with reply: @escaping (Int) -> Void) {
        let dir = URL(fileURLWithPath: Self.claudeDir + "/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return reply(-1) }
        let busy = files.filter { url in
            guard url.pathExtension == "json",
                  let data = FileManager.default.contents(atPath: url.path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  // Seen: "busy", "shell" (running a command), "waiting" (dialog open), "idle". Anything but idle is a turn in progress.
                  let status = json["status"] as? String, status != "idle",
                  let pid = (json["pid"] as? NSNumber)?.int32Value else { return false }
            return kill(pid, 0) == 0 // a session that crashed leaves its file behind
        }
        reply(busy.count)
    }
}

// MARK: - System sensors

extension BoringNotchXPCHelper {
    @objc func systemSensors(with reply: @escaping (Double, Double, Double) -> Void) {
        let temps = SMC.shared.averageTemperatures()
        reply(Self.gpuUtilization() ?? -1, temps.cpu ?? -1, temps.gpu ?? -1)
    }

    /// "Device Utilization %" published by the GPU driver (Apple silicon and recent AMD/Intel).
    private static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, value)
        }
        return best
    }
}

/// Minimal AppleSMC reader. On Apple silicon the die sensors are float keys:
/// Tp* = performance cores, Te* = efficiency cores, Tg* = GPU. The key list is enumerated once.
// ponytail: Apple silicon key prefixes only; Intel Macs (sp78 keys) report "not available".
private final class SMC {
    static let shared = SMC()

    private struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    /// Mirrors the kernel's SMCKeyData_t (80 bytes).
    private struct Param {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private lazy var keys: (cpu: [UInt32], gpu: [UInt32]) = enumerateKeys()

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            IOServiceOpen(service, mach_task_self_, 0, &connection)
            IOObjectRelease(service)
        }
    }

    func averageTemperatures() -> (cpu: Double?, gpu: Double?) {
        lock.lock(); defer { lock.unlock() }
        guard connection != 0 else { return (nil, nil) }
        func average(_ list: [UInt32]) -> Double? {
            let values = list.compactMap(readFloat).filter { $0 > 5 && $0 < 130 }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return (average(keys.cpu), average(keys.gpu))
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private func info(_ key: UInt32) -> KeyInfo? {
        var p = Param(); p.key = key; p.command = 9
        return call(&p)?.keyInfo
    }

    private func readBytes(_ key: UInt32) -> (KeyInfo, [UInt8])? {
        guard let i = info(key) else { return nil }
        var p = Param(); p.key = key; p.keyInfo.dataSize = i.dataSize; p.command = 5
        guard let out = call(&p) else { return nil }
        return (i, withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(min(i.dataSize, 32)))) })
    }

    private func readFloat(_ key: UInt32) -> Double? {
        guard let (i, bytes) = readBytes(key), i.dataType == Self.fourCC("flt "), bytes.count == 4 else { return nil }
        return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
    }

    private func enumerateKeys() -> (cpu: [UInt32], gpu: [UInt32]) {
        guard let (_, countBytes) = readBytes(Self.fourCC("#KEY")) else { return ([], []) }
        let count = countBytes.reduce(0) { $0 << 8 | UInt32($1) }
        var cpu: [UInt32] = [], gpu: [UInt32] = []
        for index in 0..<count {
            var p = Param(); p.command = 8; p.data32 = index
            guard let key = call(&p)?.key else { continue }
            let prefix = key >> 16
            guard prefix == Self.fourCC("Tp") || prefix == Self.fourCC("Te") || prefix == Self.fourCC("Tg"),
                  readFloat(key) != nil else { continue }
            if prefix == Self.fourCC("Tg") { gpu.append(key) } else { cpu.append(key) }
        }
        return (cpu, gpu)
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
}
