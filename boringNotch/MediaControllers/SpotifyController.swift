//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI
import Defaults

class SpotifyController: MediaControllerProtocol {
    func setFavorite(_ favorite: Bool) async {
        //Placeholder
    }
    
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { false }

    private var notificationTask: Task<Void, Never>?
    
    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    private var webTask: Task<Void, Never>?
    
    init() {
        setupPlaybackStateChangeObserver()
        startWebPolling()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
        webTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }
    
    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }
    
    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    func updatePlaybackInfo() async {
        // Never talk to Spotify via AppleScript when it is closed: that would launch it.
        guard isActive() else { return }
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 10 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )

        publish(state, artworkURL: artworkURL)
    }

    /// Publishes a state, reusing the current artwork when unchanged and fetching new artwork otherwise.
    private func publish(_ newState: PlaybackState, artworkURL: String) {
        var state = newState
        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        playbackState = state

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        var updatedState = currentState
                        updatedState.artwork = data
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }
    
// MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        // App closed (info comes from the Web API): controls do nothing instead of launching Spotify.
        guard isActive() else { return }
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    

    // MARK: - Last.fm fallback (Spotify playing on another device, app closed on this Mac)
    // Spotify scrobbles to Last.fm server-side from every device, Free accounts included.

    private var lastfmTrackKey = ""                 // "artist|title" of the track being shown
    private var lastfmTrackStart = Date()           // first time we saw it: estimates elapsed time
    private var lastfmDuration: Double = 0

    private func startWebPolling() {
        webTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.lastfmTick() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// One Last.fm check. Returns seconds until the next one: 15 s while something plays,
    /// 60 s when idle or not configured, 30 s while the local Spotify app drives updates.
    private func lastfmTick() async -> Double {
        if isActive() { return 30 }
        let user = Defaults[.lastfmUser].trimmingCharacters(in: .whitespaces)
        let key = Defaults[.lastfmAPIKey].trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !key.isEmpty,
              let json = await lastfmCall(["method": "user.getrecenttracks", "user": user, "limit": "1"], key: key),
              let recent = json["recenttracks"] as? [String: Any] else { return 60 }
        // "track" is an array, or a single object when only one item
        let tracks = recent["track"] as? [[String: Any]] ?? (recent["track"] as? [String: Any]).map { [$0] } ?? []
        guard let track = tracks.first(where: { ($0["@attr"] as? [String: Any])?["nowplaying"] as? String == "true" }) else {
            if playbackState.isPlaying { var st = playbackState; st.isPlaying = false; playbackState = st }
            return 60
        }

        func text(_ k: String) -> String { (track[k] as? [String: Any])?["#text"] as? String ?? "" }
        let title = track["name"] as? String ?? ""
        let artist = text("artist")
        let trackKey = "\(artist)|\(title)"
        if trackKey != lastfmTrackKey {
            lastfmTrackKey = trackKey
            lastfmTrackStart = Date()
            // Duration is not in recent tracks: one extra call per new track. 0 when Last.fm doesn't know it.
            let info = await lastfmCall(["method": "track.getInfo", "artist": artist, "track": title], key: key)
            let ms = Double((info?["track"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
            lastfmDuration = ms / 1000
        }
        let elapsed = Date().timeIntervalSince(lastfmTrackStart)
        let artwork = (track["image"] as? [[String: Any]])?.last?["#text"] as? String ?? ""   // largest size is last
        let state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: true,
            title: title,
            artist: artist,
            album: text("album"),
            currentTime: lastfmDuration > 0 ? min(elapsed, lastfmDuration) : 0,
            duration: lastfmDuration,
            playbackRate: 1,
            lastUpdated: Date(),
            volume: playbackState.volume
        )
        publish(state, artworkURL: artwork)
        return 15
    }

    private func lastfmCall(_ params: [String: String], key: String) async -> [String: Any]? {
        var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        comps.queryItems = (params.merging(["api_key": key, "format": "json"]) { a, _ in a })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
