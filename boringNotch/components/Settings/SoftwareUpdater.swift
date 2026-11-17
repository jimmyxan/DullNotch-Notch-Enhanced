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
