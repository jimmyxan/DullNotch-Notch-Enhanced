//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // MacRemote (embedded helper app): its pairing token lives in its own preferences, out of the sandbox's reach
    func macRemoteToken(with reply: @escaping (String?) -> Void)
    func setMacRemoteToken(_ token: String, with reply: @escaping (Bool) -> Void)
    func stopMacRemote(with reply: @escaping (Bool) -> Void)
    /// Launch arguments are dropped when a sandboxed app opens another app, so the helper launches it.
    func launchMacRemote(at path: String, with reply: @escaping (String?) -> Void)
    /// AI plan usage ("claude" / "codex"). The helper reads the CLI's sign-in outside the sandbox and
    /// replies the HTTP status (0 = not signed in, -1 = network error) and the raw JSON body. Tokens never leave it.
    func aiUsage(_ provider: String, with reply: @escaping (Int, String?) -> Void)
    /// System monitor sensors that need IOKit outside the sandbox: GPU utilization %, average CPU and GPU
    /// die temperature in °C. -1 = not available on this Mac.
    func systemSensors(with reply: @escaping (Double, Double, Double) -> Void)
    /// Earliest running timer of the macOS Clock app: (fire time as unix seconds, duration in seconds).
    /// (-1, -1) = none running. Read outside the sandbox from the `com.apple.mobiletimerd` preferences.
    func clockTimer(with reply: @escaping (Double, Double) -> Void)
    /// Claude Code hooks in ~/.claude/settings.json. action: "status", "install" or "remove".
    /// Reply: 1 connected, 0 not connected, -1 no ~/.claude, -2 settings.json is not valid JSON, -3 write failed.
    func claudeHooks(_ action: String, with reply: @escaping (Int) -> Void)
    /// Claude Code sessions running a turn right now (~/.claude/sessions). -1 = this Claude Code doesn't keep that folder.
    func claudeBusySessions(with reply: @escaping (Int) -> Void)
}

