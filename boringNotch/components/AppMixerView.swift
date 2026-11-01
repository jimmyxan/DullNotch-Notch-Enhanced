//
//  AppMixerView.swift
//  boringNotch
//
//  Per-app volume mixer. Audio engine ported from OpenSoundSource (github.com/jimmyxan/OpenSoundSource):
//  CoreAudio process taps, no virtual driver. Helper processes (WebKit GPU, Teams, Chrome, Electron)
//  are grouped under the app that owns them.
//

import AppKit
import CoreAudio
import SwiftUI

// MARK: - CoreAudio helpers

private func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ qual: [UInt8] = [], as: T.Type) -> T? {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { p.deallocate() }
    let st = qual.withUnsafeBytes {
        AudioObjectGetPropertyData(obj, &addr, UInt32($0.count), $0.baseAddress, &size, p)
    }
    return st == noErr ? p.pointee : nil
}

private func processObject(pid: pid_t) -> AudioObjectID? {
    withUnsafeBytes(of: pid) { b in
        prop(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject, Array(b), as: AudioObjectID.self)
    }.flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
}

/// Every process CoreAudio knows about, as (audio object, pid, is playing).
private func audioProcesses() -> [(obj: AudioObjectID, pid: pid_t, playing: Bool)] {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { o in
        prop(o, kAudioProcessPropertyPID, as: pid_t.self).map {
            (o, $0, (prop(o, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0) != 0)
        }
    }
}

private func executablePath(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
}

/// The app macOS holds responsible for a process. Safari's audio plays from com.apple.WebKit.GPU,
/// a system XPC service outside Safari.app, whose responsible process is Safari.
// ponytail: libsystem SPI (stable for years); bundle-path match is the fallback
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePid(_ pid: pid_t) -> pid_t

private func defaultOutputUID() -> String? {
    guard let dev = prop(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self),
          let uid = prop(dev, kAudioDevicePropertyDeviceUID, as: CFString?.self).flatMap({ $0 }) else { return nil }
    return uid as String
}

/// Soft-knee limiter: identity up to `knee`, then tanh rolls off toward +/-1 so boosted audio never clips.
// ponytail: stateless waveshaper, not an envelope limiter; mild harmonics at heavy boost
@inline(__always)
private func softLimit(_ x: Float, knee: Float = 0.8) -> Float {
    let a = abs(x)
    if a <= knee { return x }
    return (x < 0 ? -1 : 1) * (knee + (1 - knee) * tanhf((a - knee) / (1 - knee)))
}

// MARK: - Per-app tap: mutes the app's own output and replays it scaled by `gain`

@available(macOS 14.2, *)
private final class AppTap {
    var gain: Float
    let pids: Set<pid_t>
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// `pids` = the app's main process plus every helper process that plays audio.
    init?(pids: Set<pid_t>, gain: Float) {
        self.gain = gain
        self.pids = pids
        let objs = pids.compactMap { processObject(pid: $0) }
        guard !objs.isEmpty, let outUID = defaultOutputUID() else { return nil }

        let desc = CATapDescription(stereoMixdownOfProcesses: objs)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return nil }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "BoringNotchMixer-\(UUID().uuidString.prefix(8))",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else { stop(); return nil }

        // ponytail: assumes float32 interleaved stereo tap; query kAudioTapPropertyFormat if exotic devices matter
        let ok = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { [unowned self] _, inData, _, outData, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let outs = UnsafeMutableAudioBufferListPointer(outData)
            for (i, ob) in outs.enumerated() {
                guard let dst = ob.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let dstN = Int(ob.mDataByteSize) / 4
                guard i < ins.count, let src = ins[i].mData?.assumingMemoryBound(to: Float.self) else {
                    memset(dst, 0, Int(ob.mDataByteSize)); continue
                }
                let n = min(dstN, Int(ins[i].mDataByteSize) / 4)
                let g = self.gain
                if g <= 1 { for k in 0..<n { dst[k] = src[k] * g } }          // cut: plain gain, bit-exact at 100%
                else { for k in 0..<n { dst[k] = softLimit(src[k] * g) } }  // boost: limited
                if n < dstN { memset(dst + n, 0, (dstN - n) * 4) }
            }
        }
        guard ok == noErr, AudioDeviceStart(aggID, procID) == noErr else { stop(); return nil }
    }

    func stop() {
        if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }
    deinit { stop() }
}

// MARK: - Model

struct MixerApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage?
}

@available(macOS 14.2, *)
@MainActor
final class AppVolumeModel: ObservableObject {
    static let shared = AppVolumeModel()

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var gains: [pid_t: Float] = [:]
    @Published private(set) var failed: String?            // app we could not tap (usually missing permission)

    /// Mixer tab on screen: refresh every second. Hidden: refresh every 3 s only while a tap is active. Otherwise no timer.
    var visible = false { didSet { if visible { refresh() }; updateTimer() } }

    private var taps: [pid_t: AppTap] = [:]
    private var groups: [pid_t: Set<pid_t>] = [:]          // owner app pid -> its audio-producing pids
    private var premute: [pid_t: Float] = [:]
    private var timer: Timer?
    private var ticks = 0

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // Default output changed (e.g. AirPods connected): recreate taps so they replay to the new device.
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (pid, t) in self.taps { self.taps[pid] = AppTap(pids: t.pids, gain: t.gain) }
            }
        }
    }

    func gain(_ pid: pid_t) -> Float { gains[pid] ?? 1 }

    private func updateTimer() {
        let needed = visible || !taps.isEmpty
        if needed, timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.5                                   // lets macOS coalesce wakeups
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        ticks += 1
        if visible || ticks % 3 == 0 { refresh() }
    }

    func refresh() {
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let me = ProcessInfo.processInfo.processIdentifier
        var g: [pid_t: Set<pid_t>] = [:]
        var playing: Set<pid_t> = []
        for proc in audioProcesses() where proc.pid != me {
            let path = executablePath(proc.pid) ?? ""
            // the process is an app itself, a process the app is responsible for (WebKit GPU), or a helper inside its bundle
            let resp = responsiblePid(proc.pid)
            let owner = regular.first { $0.processIdentifier == proc.pid }
                ?? regular.first { $0.processIdentifier == resp }
                ?? regular.filter { $0.bundleURL.map { path.hasPrefix($0.path + "/") } ?? false }
                          .max { ($0.bundleURL?.path.count ?? 0) < ($1.bundleURL?.path.count ?? 0) }
            if let o = owner {
                g[o.processIdentifier, default: []].insert(proc.pid)
                if proc.playing { playing.insert(o.processIdentifier) }
            }
        }
        groups = g

        // Only apps making sound now; apps with a custom volume stay visible so they can be reset.
        let new = regular.filter { playing.contains($0.processIdentifier) || taps[$0.processIdentifier] != nil }
            .map { MixerApp(id: $0.processIdentifier, name: $0.localizedName ?? "?", icon: $0.icon) }
            .sorted { $0.name < $1.name }
        // app quit: drop its tap so nothing stays muted. helpers changed (e.g. a call started): rebuild the tap.
        for (pid, tap) in taps {
            guard let now = g[pid] else { taps[pid] = nil; gains[pid] = nil; premute[pid] = nil; continue }
            if now != tap.pids { taps[pid] = AppTap(pids: now, gain: tap.gain) }
        }
        if new.map(\.id) != apps.map(\.id) { apps = new }
        updateTimer()
    }

    func setGain(_ pid: pid_t, _ g: Float) {
        defer { updateTimer() }
        if abs(g - 1) < 0.01 { taps[pid] = nil; gains[pid] = nil; return }   // unity: remove tap, zero overhead
        if let t = taps[pid] { t.gain = g }
        else if let t = AppTap(pids: groups[pid] ?? [pid], gain: g) { taps[pid] = t }
        else { failed = apps.first { $0.id == pid }?.name ?? "this app"; return }
        failed = nil
        gains[pid] = g
    }

    func toggleMute(_ pid: pid_t) {
        if gain(pid) > 0 { premute[pid] = gain(pid); setGain(pid, 0) } else { setGain(pid, premute[pid] ?? 1) }
    }
}

// MARK: - Views

@available(macOS 14.2, *)
struct AppMixerView: View {
    @ObservedObject private var model = AppVolumeModel.shared

    var body: some View {
        Group {
            if model.apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No apps are playing sound")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 28) {
                        ForEach(model.apps) { app in
                            VolumeFader(app: app, model: model)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .bottom) {
                    if let name = model.failed {
                        Text("Can't control \(name). Allow audio capture in System Settings › Privacy.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.apps)
        .onAppear { model.visible = true }
        .onDisappear { model.visible = false }
    }
}

@available(macOS 14.2, *)
private struct VolumeFader: View {
    let app: MixerApp
    @ObservedObject var model: AppVolumeModel

    @State private var dragging = false
    @State private var startGain: Float?          // gain when the drag began (relative dragging)
    @State private var snapped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxGain: Float = 1.5
    private let trackHeight: CGFloat = 92
    /// Drag sensitivity: points of travel per 100% of gain. Larger than the track so small hand movements
    /// give fine control; hold Option for 4x finer steps.
    private let pointsPerUnit: CGFloat = 110
    private var gain: Float { model.gain(app.id) }
    private var tint: Color { Color.hudColor }

    var body: some View {
        VStack(spacing: 6) {
            // Click the number to reset to 100%
            Button { model.setGain(app.id, 1) } label: {
                Text("\(Int((gain * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(gain > 1 ? Color.orange : .white.opacity(dragging || gain != 1 ? 0.95 : 0.55))
            }
            .buttonStyle(.plain)
            .help("Reset to 100%")

            track.frame(width: 36, height: trackHeight)

            Button { model.toggleMute(app.id) } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: app.icon ?? NSImage())
                        .resizable()
                        .frame(width: 24, height: 24)
                        .saturation(gain == 0 ? 0 : 1)
                        .opacity(gain == 0 ? 0.5 : 1)
                    if gain == 0 {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(.black.opacity(0.7), in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(gain == 0 ? "Unmute \(app.name)" : "Mute \(app.name)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue("\(Int((gain * 100).rounded())) percent")
        .accessibilityAdjustableAction { dir in
            let step: Float = dir == .increment ? 0.05 : -0.05
            model.setGain(app.id, min(maxGain, max(0, gain + step)))
        }
    }

    /// Thin vertical line with a round knob, OpenSoundSource style, rotated for the notch.
    private var track: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let knob: CGFloat = dragging ? 18 : 14
            let usable = h - 14                               // keep the knob fully inside the track
            let y = 7 + usable * CGFloat(1 - gain / maxGain)  // knob center
            let unityY = 7 + usable * CGFloat(1 - 1 / maxGain)
            let midX = geo.size.width / 2
            ZStack {
                // rail
                Capsule().fill(.white.opacity(0.14))
                    .frame(width: 4, height: h)
                // level up to 100%
                Capsule().fill(tint)
                    .frame(width: 4, height: max(0, h - max(y, unityY)))
                    .position(x: midX, y: (h + max(y, unityY)) / 2)
                // boost zone above 100%
                if gain > 1 {
                    Capsule().fill(Color.orange)
                        .frame(width: 4, height: unityY - y)
                        .position(x: midX, y: (unityY + y) / 2)
                }
                // 100% tick
                Capsule().fill(.white.opacity(0.4))
                    .frame(width: 12, height: 1.5)
                    .position(x: midX, y: unityY)
                // knob
                Circle().fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .shadow(color: (gain > 1 ? Color.orange : tint).opacity(dragging ? 0.9 : 0), radius: dragging ? 10 : 0)
                    .position(x: midX, y: y)
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: dragging)
            }
            .contentShape(Rectangle())                        // whole 36pt column is grabbable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if startGain == nil { startGain = gain; dragging = true }
                        // Relative drag: the knob never jumps to the click point; it moves with the hand.
                        let fine: CGFloat = NSEvent.modifierFlags.contains(.option) ? 0.25 : 1
                        var g = (startGain ?? gain) + Float(-v.translation.height / pointsPerUnit * fine)
                        g = min(maxGain, max(0, g))
                        // Magnetic 100% with hysteresis: catch within 3%, release past 6%
                        let catchZone: Float = snapped ? 0.06 : 0.03
                        let nearUnity = abs(g - 1) < catchZone
                        if nearUnity { g = 1 }
                        if nearUnity != snapped {
                            snapped = nearUnity
                            if nearUnity { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                        }
                        if g == 1 || abs(g - gain) >= 0.005 { model.setGain(app.id, g) }   // skip no-op updates
                    }
                    .onEnded { _ in startGain = nil; dragging = false }
            )
        }
    }
}
