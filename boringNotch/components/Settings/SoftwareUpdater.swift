//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//  DullNotch: updates come from this fork's GitHub releases, not the upstream Sparkle feed
//  (which would replace this build with the original Boring Notch).
//

import AppKit
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let updateNotifications = Key<Bool>("updateNotifications", default: true)
    /// "Remind me tomorrow": no automatic alert before this date.
    static let updateRemindAfter = Key<Date?>("updateRemindAfter")
}

/// Checks the latest GitHub release at launch and every 6 hours; when it's newer than this
/// build, asks the user to update now (opens the release page) or tomorrow.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repository = "jimmyxan/DullNotch-Notch-Enhanced"

    private var timer: Timer?
    private var alertShown = false

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Call once at launch.
    func activate() {
        Task { await check(manual: false) }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.check(manual: false) }
        }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `manual`: from "Check for Updates…", so it ignores the snooze and also reports "up to date" or errors.
    func check(manual: Bool) async {
        if !manual {
            guard Defaults[.updateNotifications] else { return }
            if let after = Defaults[.updateRemindAfter], Date() < after { return }
        }
        guard !alertShown else { return }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            if manual { show("Couldn't check for updates", "GitHub can't be reached right now. Try again later.") }
            return
        }

        let current = Bundle.main.releaseVersionNumber ?? "0"
        let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(latest, than: current) else {
            if manual { show("DullNotch is up to date", "You have the latest version (\(current)).") }
            return
        }
        offer(latest: latest, current: current, page: release.html_url)
    }

    private func offer(latest: String, current: String, page: URL) {
        alertShown = true
        defer { alertShown = false }
        let alert = NSAlert()
        alert.messageText = "DullNotch \(latest) is available"
        alert.informativeText = "You have version \(current). Download the new version from GitHub, unzip it and replace DullNotch in your Applications folder."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Remind Me Tomorrow")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        // Either way, ask again tomorrow if this build is still running then.
        Defaults[.updateRemindAfter] = Date().addingTimeInterval(24 * 3600)
        if response == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    private func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Numeric dotted comparison: "1.10.0" > "1.9.2", "1.2" == "1.2.0".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l > r }
        }
        return false
    }

    #if DEBUG
    static let selfCheck: Void = {
        assert(isNewer("1.10.0", than: "1.9.2") && isNewer("1.2.1", than: "1.2"))
        assert(!isNewer("1.2", than: "1.2.0") && !isNewer("1.1.9", than: "1.2.0"))
    }()
    #endif
}

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates…") {
            Task { await UpdateChecker.shared.check(manual: true) }
        }
    }
}

struct UpdaterSettingsView: View {
    var body: some View {
        Section {
            Defaults.Toggle(key: .updateNotifications) {
                Text("Tell me when a new version is available")
            }
        } header: {
            Text("Software updates")
        } footer: {
            Text("New versions are published on GitHub. You can update right away or be reminded the next day.")
        }
    }
}
