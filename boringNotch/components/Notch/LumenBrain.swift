//
//  LumenBrain.swift
//  boringNotch
//
//  State machine that decides what the Lumen mascot does next. Pure logic with no
//  timers and no UI: the renderer calls `update` once per frame while the notch is open
//  and `animationFinished` when the current animation ends. The notch closes when the
//  pointer leaves, so sleep cannot rely on input idle alone: Lumen also dozes off when
//  nobody has opened the notch for a while, and is found asleep on the next visit.
//

import Foundation

enum LumenMove: String, CaseIterable {
    case over, under, behind, vanish, slalom, orbit
    case sunBump, dance, read, push, knock
    case peek
    case wander, rest, absent

    /// Relative chance among the eligible ambient moves.
    var weight: Double {
        switch self {
        case .wander, .rest: return 4
        case .over, .behind, .absent: return 3
        case .peek, .orbit, .slalom: return 2
        case .sunBump, .dance, .read, .under, .vanish: return 1.5
        case .push, .knock: return 1
        }
    }

    /// Unscripted behaviour: idle drift and irregular blinks apply. The other moves keep their exact timing.
    var isUnscripted: Bool { self == .wander || self == .rest || self == .absent }

    /// Minimum time before the same move can start again.
    var cooldown: TimeInterval {
        switch self {
        case .push, .knock, .sunBump: return 180
        case .dance, .read: return 90
        case .wander, .rest, .absent: return 20
        default: return 45
        }
    }

    /// Moves that act on a widget need that widget on screen.
    func isAllowed(_ inputs: LumenInputs) -> Bool {
        switch self {
        case .dance: return inputs.hasMusicWidget && inputs.musicPlaying
        case .sunBump: return inputs.sunVisible
        case .read: return inputs.hasQuoteWidget
        case .orbit: return inputs.hasSmallWidget
        case .slalom, .push: return inputs.widgetCount >= 2
        default: return inputs.widgetCount >= 1
        }
    }
}

enum LumenPhase: Equatable {
    case hidden, asleep, waking, hovering, fallingAsleep
    case performing(LumenMove)
}

struct LumenInputs {
    var notchOpen = true
    var musicPlaying = false
    var lowPower = false
    /// Seconds since the pointer last moved.
    var pointerStillFor: TimeInterval = 0
    var widgetCount = 3
    var hasMusicWidget = true
    var hasQuoteWidget = true
    var hasSmallWidget = true
    /// The weather widget is on screen and shows a clear daytime sky.
    var sunVisible = false
}

struct LumenBrain {
    static let awayAfter: TimeInterval = 10 * 60 // notch closed this long: found asleep
    static let drowsyAfter: TimeInterval = 30 // notch open, pointer still this long: falls asleep
    static let minAsleep: TimeInterval = 2.5 // on screen asleep at least this long

    private(set) var phase: LumenPhase = .hidden
    private var phaseStart: TimeInterval = 0
    private var closedAt: TimeInterval?
    private var wasAsleep = false
    private var nextMoveAt: TimeInterval = 0
    private var lastStarted: [LumenMove: TimeInterval] = [:]
    private var lastMove: LumenMove?
    private var wasPlaying = false
    private var wantsDance = false
    private let random: () -> Double

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    mutating func update(_ inputs: LumenInputs, now: TimeInterval) {
        defer { wasPlaying = inputs.musicPlaying }
        if inputs.musicPlaying && !wasPlaying { wantsDance = true }
        if !inputs.musicPlaying { wantsDance = false }

        guard inputs.notchOpen else {
            if phase != .hidden {
                wasAsleep = phase == .asleep || phase == .fallingAsleep
                closedAt = now
                enter(.hidden, now)
            }
            return
        }

        if phase == .hidden {
            let away = closedAt.map { now - $0 >= Self.awayAfter } ?? true
            let sleeps = inputs.lowPower || (!inputs.musicPlaying && (wasAsleep || away))
            enter(sleeps ? .asleep : .hovering, now)
            scheduleNextMove(now, from: 1, to: 3)
            return
        }

        if inputs.lowPower {
            if phase != .asleep && phase != .fallingAsleep { enter(.fallingAsleep, now) }
            return
        }

        switch phase {
        case .asleep:
            let visitorMoved = now - phaseStart >= Self.minAsleep && inputs.pointerStillFor < 1
            if visitorMoved || wantsDance { enter(.waking, now) }
        case .fallingAsleep:
            if inputs.pointerStillFor < 1 || wantsDance { enter(.waking, now) }
        case .hovering:
            decide(inputs, now)
        case .hidden, .waking, .performing:
            break
        }
    }

    /// The renderer calls this when the current animation ends.
    mutating func animationFinished(now: TimeInterval) {
        switch phase {
        case .fallingAsleep: enter(.asleep, now)
        case .waking:
            enter(.hovering, now)
            scheduleNextMove(now, from: 0.5, to: 2)
        case .performing: finishMove(now)
        case .hidden, .asleep, .hovering: break
        }
    }

    private mutating func decide(_ inputs: LumenInputs, _ now: TimeInterval) {
        if wantsDance && LumenMove.dance.isAllowed(inputs) && isCooledDown(.dance, now) {
            wantsDance = false
            start(.dance, now)
        } else if !inputs.musicPlaying && inputs.pointerStillFor >= Self.drowsyAfter {
            enter(.fallingAsleep, now)
        } else if now >= nextMoveAt {
            if let move = pickAmbient(inputs, now) {
                start(move, now)
            } else {
                scheduleNextMove(now, from: 2, to: 4)
            }
        }
    }

    private func isCooledDown(_ move: LumenMove, _ now: TimeInterval) -> Bool {
        lastStarted[move].map { now - $0 >= move.cooldown } ?? true
    }

    private func pickAmbient(_ inputs: LumenInputs, _ now: TimeInterval) -> LumenMove? {
        let eligible = LumenMove.allCases.filter {
            $0 != lastMove && $0.isAllowed(inputs) && isCooledDown($0, now)
        }
        var roll = random() * eligible.reduce(0) { $0 + $1.weight }
        for move in eligible {
            roll -= move.weight
            if roll < 0 { return move }
        }
        return eligible.last
    }

    private mutating func start(_ move: LumenMove, _ now: TimeInterval) {
        lastStarted[move] = now
        lastMove = move
        enter(.performing(move), now)
    }

    private mutating func finishMove(_ now: TimeInterval) {
        enter(.hovering, now)
        // Mostly short pauses, sometimes a long one: even gaps would read as a timer.
        if random() < 0.3 {
            scheduleNextMove(now, from: 8, to: 24)
        } else {
            scheduleNextMove(now, from: 1, to: 6)
        }
    }

    private mutating func scheduleNextMove(_ now: TimeInterval, from low: Double, to high: Double) {
        nextMoveAt = now + low + (high - low) * random()
    }

    private mutating func enter(_ next: LumenPhase, _ now: TimeInterval) {
        phase = next
        phaseStart = now
    }

    #if DEBUG
    static let selfCheck: Void = {
        var brain = LumenBrain(random: { 0.5 })
        var inputs = LumenInputs()

        // First visit: found asleep. It stays asleep at least minAsleep, then the pointer wakes it.
        brain.update(inputs, now: 0)
        assert(brain.phase == .asleep, "found asleep on first open")
        brain.update(inputs, now: 1)
        assert(brain.phase == .asleep, "minAsleep holds")
        brain.update(inputs, now: 3)
        assert(brain.phase == .waking, "moving pointer wakes it")
        brain.animationFinished(now: 4)
        assert(brain.phase == .hovering, "awake after waking")

        // A still pointer puts it to sleep, unless music plays.
        inputs.pointerStillFor = 31
        brain.update(inputs, now: 5)
        assert(brain.phase == .fallingAsleep, "still pointer: falls asleep")
        brain.animationFinished(now: 8)
        assert(brain.phase == .asleep, "asleep after the settling animation")

        // Music wakes it and it dances first, even with a still pointer.
        inputs.musicPlaying = true
        brain.update(inputs, now: 9)
        assert(brain.phase == .waking, "music wakes it")
        brain.animationFinished(now: 10)
        brain.update(inputs, now: 10)
        assert(brain.phase == .performing(.dance), "dances when the music starts")
        brain.animationFinished(now: 16)
        brain.update(inputs, now: 16)
        assert(brain.phase == .hovering, "music keeps it awake")

        // Closing hides it. A short absence does not put it to sleep, a long one does.
        inputs.notchOpen = false
        brain.update(inputs, now: 17)
        assert(brain.phase == .hidden, "closed notch hides it")
        inputs = LumenInputs()
        brain.update(inputs, now: 20)
        assert(brain.phase == .hovering, "short absence: still awake")
        inputs.notchOpen = false
        brain.update(inputs, now: 21)
        inputs.notchOpen = true
        brain.update(inputs, now: 21 + awayAfter)
        assert(brain.phase == .asleep, "long absence: asleep")

        // Low power: asleep, and nothing wakes it.
        var saver = LumenBrain(random: { 0.5 })
        var low = LumenInputs()
        low.lowPower = true
        saver.update(low, now: 0)
        low.musicPlaying = true
        saver.update(low, now: 50)
        assert(saver.phase == .asleep, "low power never wakes")

        // Ambient moves respect widgets, cooldowns and never repeat back to back.
        var roll = 0.0
        var ambient = LumenBrain(random: {
            roll = (roll + 0.37).truncatingRemainder(dividingBy: 1)
            return roll
        })
        var noWidgets = LumenInputs()
        noWidgets.hasQuoteWidget = false
        noWidgets.widgetCount = 1
        noWidgets.hasSmallWidget = false
        ambient.update(noWidgets, now: 0)
        ambient.update(noWidgets, now: 3)
        ambient.animationFinished(now: 4)
        var previous: LumenMove?
        var seen = Set<String>()
        var clock = 4.0
        while clock < 1000 {
            ambient.update(noWidgets, now: clock)
            if case .performing(let move) = ambient.phase {
                assert(move != previous, "no back-to-back repeat")
                assert(move.isAllowed(noWidgets), "only allowed moves")
                seen.insert(move.rawValue)
                previous = move
                clock += 5
                ambient.animationFinished(now: clock)
            }
            clock += 1
        }
        assert(!seen.contains("read") && !seen.contains("orbit") && !seen.contains("push"), "missing widgets exclude moves")
        assert(seen.isSuperset(of: ["over", "vanish", "wander", "rest", "absent"]), "old and new ambient moves all run")
    }()
    #endif
}
