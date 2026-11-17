//
//  LottieView.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-14.
//

import AppKit
import SwiftUI
import Lottie

/// Loops a bundled Lottie animation at 24 fps; stops while `playing` is false.
struct LottieView: NSViewRepresentable {
    let animation: LottieAnimation?
    var speed: Double = 1
    var playing = true

    /// Loads a Lottie JSON stored as a data asset in Assets.xcassets. Decoded once per name.
    static func bundled(_ name: String) -> LottieAnimation? {
        if let cached = cache[name] { return cached }
        let animation = NSDataAsset(name: name).flatMap { try? LottieAnimation.from(data: $0.data) }
        cache[name] = animation
        return animation
    }
    @MainActor private static var cache: [String: LottieAnimation?] = [:]

    func makeNSView(context: Context) -> LottiePlayerView { LottiePlayerView() }

    /// Take the space SwiftUI offers; otherwise the animation's own size (64 pt) spills out of the notch.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LottiePlayerView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 20, height: 20))
    }

    func updateNSView(_ nsView: LottiePlayerView, context: Context) {
        nsView.update(animation: animation, speed: speed, playing: playing)
    }
}

/// Music animations published after a release: `animations/manifest.json` plus `<id>.json` files on the
/// repo's main branch. Pushing there makes them appear in every installed copy, no app update needed.
/// Downloaded files are kept in Application Support, so they also work offline.
@MainActor
final class RemoteAnimations: ObservableObject {
    static let shared = RemoteAnimations()

    struct Item: Codable, Identifiable, Equatable {
        let id: String
        let title: String
    }

    @Published private(set) var items: [Item] = []
    private var cache: [String: LottieAnimation] = [:]
    private var timer: Timer?

    /// `-animationsURL <url>` (a launch argument) points at another folder, for tests.
    private static var base: URL {
        URL(string: UserDefaults.standard.string(forKey: "animationsURL")
            ?? "https://raw.githubusercontent.com/jimmyxan/DullNotch-Notch-Enhanced/main/animations/")!
    }
    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RemoteAnimations", isDirectory: true)
    private static var manifest: URL { folder.appendingPathComponent("manifest.json") }

    private init() {
        items = (try? Data(contentsOf: Self.manifest)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }

    /// Call once at launch: syncs now and every 6 hours.
    func activate() {
        Task { await sync() }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await RemoteAnimations.shared.sync() }
        }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func animation(_ id: String) -> LottieAnimation? {
        if let cached = cache[id] { return cached }
        let animation = (try? Data(contentsOf: file(id))).flatMap { try? LottieAnimation.from(data: $0) }
        cache[id] = animation
        return animation
    }

    // ponytail: a file is downloaded once per id; to change a published animation, publish it under a new id.
    func sync() async {
        guard let (data, _) = try? await URLSession.shared.data(from: Self.base.appendingPathComponent("manifest.json")),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return }  // offline: keep what we have
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var ready: [Item] = []
        for item in list where Self.isValid(item.id) {
            let file = file(item.id)
            if !FileManager.default.fileExists(atPath: file.path) {
                guard let (json, _) = try? await URLSession.shared.data(from: Self.base.appendingPathComponent("\(item.id).json")),
                      json.count < 2_000_000, (try? LottieAnimation.from(data: json)) != nil,
                      (try? json.write(to: file, options: .atomic)) != nil else { continue }
            }
            ready.append(item)
        }
        if ready != items { items = ready }
        try? JSONEncoder().encode(ready).write(to: Self.manifest, options: .atomic)
    }

    /// The id becomes a file name: letters, digits and dashes only.
    nonisolated static func isValid(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9-]{1,40}$", options: .regularExpression) != nil
    }

    private func file(_ id: String) -> URL { Self.folder.appendingPathComponent("\(id).json") }

    #if DEBUG
    static let selfCheck: Void = {
        assert(isValid("orbit-3d") && !isValid("../x") && !isValid("A") && !isValid(""))
    }()
    #endif
}

/// Plays on Core Animation (rendered by WindowServer, ~0% app CPU) with every animation capped at
/// 24 fps, like the spectrogram. Uncapped, Lottie follows the display rate (120 Hz on ProMotion).
final class LottiePlayerView: NSView {
    private static let frameRate = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(renderingEngine: .coreAnimation))
    private var playing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Autoresizing, not Auto Layout: the animation's intrinsic size (64 pt) would beat the constraints.
        animationView.frame = bounds
        animationView.autoresizingMask = [.width, .height]
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        addSubview(animationView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(animation: LottieAnimation?, speed: Double, playing: Bool) {
        if animationView.animation !== animation { animationView.animation = animation }
        animationView.animationSpeed = speed
        self.playing = playing
        sync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sync()
    }

    private func sync() {
        let shouldPlay = playing && window != nil
        if shouldPlay, !animationView.isAnimationPlaying {
            animationView.play()
            // Lottie builds its CAAnimations lazily over the next layout passes; one pass sometimes
            // missed some, so cap again a little later. Capping twice is harmless.
            for delay in [0.0, 0.5, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self.map { Self.cap($0.animationView.layer) }
                }
            }
        } else if !shouldPlay, animationView.isAnimationPlaying {
            animationView.pause()
        }
    }

    /// Re-adds every running animation with a 24 fps frame-rate range.
    private static func cap(_ layer: CALayer?) {
        guard let layer else { return }
        for key in layer.animationKeys() ?? [] {
            guard let copy = layer.animation(forKey: key)?.copy() as? CAAnimation else { continue }
            capped(copy)
            layer.add(copy, forKey: key)
        }
        layer.sublayers?.forEach(cap)
        cap(layer.mask)  // gradients are drawn through a mask layer that carries the animation
    }

    /// Lottie wraps each property in a CAAnimationGroup; the children keep their own (display) rate.
    private static func capped(_ animation: CAAnimation) {
        animation.preferredFrameRateRange = frameRate
        if let group = animation as? CAAnimationGroup {
            group.animations = group.animations?.map { child in
                let copy = child.copy() as! CAAnimation
                capped(copy)
                return copy
            }
        }
    }
}
