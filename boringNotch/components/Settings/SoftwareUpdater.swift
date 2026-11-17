//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//  DullNotch: Sparkle reads this fork's appcast, attached to every GitHub release
//  (SUFeedURL in Info.plist), and installs updates signed with the fork's EdDSA key.
//

import Sparkle
import SwiftUI

/// The app's only updater. Settings, the menu bar and the status item all use it.
@MainActor
enum Updater {
    static let controller: SPUStandardUpdaterController = {
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // Older builds saved SUEnableAutomaticChecks = false (the upstream feed was off), and saved
        // preferences win over Info.plist. Turn automatic updates on once; later the user's toggles rule.
        if !UserDefaults.standard.bool(forKey: "autoUpdatesTurnedOn") {
            c.updater.automaticallyChecksForUpdates = true
            c.updater.automaticallyDownloadsUpdates = true
            UserDefaults.standard.set(true, forKey: "autoUpdatesTurnedOn")
        }
        return c
    }()
    static var updater: SPUUpdater { controller.updater }
}

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates…") { Updater.controller.checkForUpdates(nil) }
    }
}

struct UpdaterSettingsView: View {
    @State private var check = Updater.updater.automaticallyChecksForUpdates
    @State private var install = Updater.updater.automaticallyDownloadsUpdates

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $check)
                .onChange(of: check) { Updater.updater.automaticallyChecksForUpdates = $1 }
            Toggle("Download and install updates automatically", isOn: $install)
                .onChange(of: install) { Updater.updater.automaticallyDownloadsUpdates = $1 }
                .disabled(!check)
        } header: {
            Text("Software updates")
        } footer: {
            Text("Updates are installed when you quit DullNotch.")
        }
    }
}

/// Shown once after the app version changes (Sparkle installs updates on quit, so this is the next launch):
/// a small pill under the notch for 4 s. Onboarding and the hello animation only run on the first launch ever.
@MainActor
enum UpdateBanner {
    private static var panel: NSPanel?

    static func show() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let version = Bundle.main.releaseVersionNumber ?? ""
        let view = NSHostingView(rootView:
            Label("DullNotch updated to \(version)", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black, in: Capsule()))
        let size = view.fittingSize
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                                            y: screen.visibleFrame.maxY - 8 - size.height,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.contentView = view
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; p.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; p.animator().alphaValue = 0 }) {
                p.orderOut(nil)
                panel = nil
            }
        }
    }
}
