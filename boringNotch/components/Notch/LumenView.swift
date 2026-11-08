//
//  LumenView.swift
//  boringNotch
//
//  Draws the Lumen mascot: pixel sprite, animation routes across the widgets and the two
//  canvases that sit behind and in front of the widget row. LumenBrain decides what to do;
//  this file decides how it looks. Nothing here runs while the notch is closed.
//

import SwiftUI

// MARK: - Sprite

enum LumenWingShape: String { case open, up, down, fold, wrap, wrap2 }
enum LumenEye: String { case open, left, right, wide, blink, happy, sleep, half, yawn }
enum LumenLegs: String { case tuck, perch }

/// 28 x 20 pixels. Each layer stores its left half (14 columns) and is mirrored.
enum LumenSprite {
    static let width = 28
    static let height = 20

    private struct Layer {
        var y: Int
        var rows: [String]
        var overBody = false
    }

    private static let wings: [LumenWingShape: Layer] = [
        .open: Layer(y: 3, rows: [
            "..zzz.........", ".zxxxzz.......", "zxxvvvxzz.....", "zxvvddvvxxz...", "zxvdssdvvvxz..",
            "zxvdsLsdvvvxz.", "zxvdssdvvvvxx.", ".zxvddvvvvxxz.", "..zxxvvvxxzz..", "...zzxxzzv....",
            "...zxxvvvxz...", "..zxvvssvvxz..", "..zxvvssvvxz..", "...zxvvvvxz...", "....zzxxzz....",
        ]),
        .up: Layer(y: 0, rows: [
            ".zz...........", "zxxz..........", "zxvxz.........", "zxvvxz........", ".zxdsvxz......",
            ".zxdsdvxz.....", "..zxvdvvxz....", "..zxvvvvvxz...", "...zxvvvvvxz..", "....zxvvvvxz..",
            ".....zxvvxxz..", ".....zxvvvxz..", "......zxssxz..", "......zzxxzz..",
        ]),
        .down: Layer(y: 6, rows: [
            ".......zzxxzz.", ".....zzxvvvxz.", "...zzxvvvvvxz.", ".zzxvvddvvvxz.", "zxxvvdssdvvxz.",
            "zxvvdssLdvxz..", "zxvvvddvvvxz..", ".zxvvvvvxxz...", "..zxxxxzz.....", "...zzxvvxz....",
            "....zxvssxz...", ".....zxvvxz...", "......zzzz....",
        ]),
        .fold: Layer(y: 6, rows: [
            "........zz....", ".......zxxz...", "......zxvvxz..", ".....zxvsvxz..", ".....zxvsvvxz.",
            "....zxvvvvvxz.", "....zxvvdvvxz.", "....zxvvdvvxz.", "....zxvvvvxz..", ".....zxvvvxz..",
            "......zxxxz...", ".......zzz....",
        ]),
        // Asleep: wings wrapped over the lantern like a blanket, with a slit of light left open.
        .wrap: Layer(y: 10, rows: [
            ".......zz.....", "......zxxz....", ".....zxvvxz...", ".....zxvvvxz..", "....zxvsvvvx..",
            "....zxvsvvvx..", "....zxvvvvvx..", ".....zxvvvvx..", "......zxvvx...", ".......zzzz...",
        ], overBody: true),
        .wrap2: Layer(y: 10, rows: [
            ".......zz.....", "......zxxz....", ".....zxvvxz...", "....zxvvvvxz..", "...zxvsvvvvx..",
            "...zxvsvvvvx..", "...zxvvvvvvx..", "....zxvvvvvx..", "......zxvvx...", ".......zzzz...",
        ], overBody: true),
    ]
    private static let antennae = [
        Layer(y: 0, rows: ["......Aa......", ".......aAa....", "........aA....", ".........aA..."]),
        Layer(y: 0, rows: [".....Aa.......", "......aAa.....", "........aA....", ".........aA..."]),
        Layer(y: 2, rows: ["......aAaa....", ".........aA..."]), // drooping while asleep
    ]
    private static let body = Layer(y: 3, rows: [
        "..........ffff", ".........fffff", "........ffffff", "........ffffff", "........ffffff",
        "........Ffffff", ".........ccFff", ".........FFfFf", "........FfFfFf", ".........FfFFf",
        "..........OGLL", ".........OGLLL", ".........BBBBB", "..........GLLL", "..........OGLL",
        "...........BBB", "............OG",
    ])
    private static let legs: [LumenLegs: Layer] = [
        .tuck: Layer(y: 12, rows: ["........g.....", ".......g......"]),
        .perch: Layer(y: 15, rows: ["........g.....", ".......g......", ".......g......", ".......gg....."]),
    ]
    private static let eyes: [LumenEye: [String]] = [
        .open: ["WEE", "EEE", "EEE"], .left: ["WEE", "EEE", "EEE"], .right: ["EEW", "EEE", "EEE"],
        .wide: ["WEE", "EEW", "EEE"], .blink: ["fff", "EEE", "fff"], .happy: ["fEf", "EfE", "fff"],
        .sleep: ["fff", "fff", "EEE"], .half: ["fff", "EEE", "WEE"], .yawn: ["fff", "EEE", "fff"],
    ]
    private static let palette: [Character: UInt32] = [
        "m": 0x7A3B3B, "z": 0xC8BBE6, "x": 0x8A7CB8, "v": 0x574A7C, "d": 0x2B2442, "s": 0xF2CC84,
        "a": 0x9C8557, "A": 0xD9BF87, "f": 0xF8ECD4, "F": 0xD6BB90, "c": 0xEAA890, "B": 0x7B5226,
        "g": 0x8E7A5C, "E": 0x211829, "W": 0xFFFFFF,
    ]
    /// Lantern colours by brightness level: dim, normal, bright.
    private static let lantern: [Character: [UInt32]] = [
        "L": [0xD9C391, 0xFFF0C4, 0xFFFBE6], "G": [0xB68F4F, 0xF4CB78, 0xFFE09A], "O": [0x8F6A35, 0xD9983F, 0xEBA953],
    ]

    struct Frame: Hashable {
        var wing: LumenWingShape
        var antenna: Int
        var legs: LumenLegs
        var eye: LumenEye
        var level: Int
    }

    struct Pixel {
        var x: Int
        var y: Int
        var rgb: UInt32
    }

    private static var pixelCache: [Frame: [Pixel]] = [:]
    private static var imageCache: [Frame: CGImage] = [:]

    static func pixels(_ f: Frame) -> [Pixel] {
        if let hit = pixelCache[f] { return hit }
        var grid = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        func stamp(_ layer: Layer) {
            for (j, row) in layer.rows.enumerated() {
                for (i, ch) in row.enumerated() where ch != "." {
                    grid[layer.y + j][i] = ch
                    grid[layer.y + j][width - 1 - i] = ch
                }
            }
        }
        let wing = wings[f.wing]!
        if !wing.overBody { stamp(wing) }
        stamp(legs[f.legs]!)
        stamp(body)
        stamp(antennae[f.antenna])
        if wing.overBody { stamp(wing) }
        if f.eye == .yawn { for j in 9...10 { for i in 13...14 { grid[j][i] = "m" } } }
        // The eyes are not mirrored, so both catch the light from the same side.
        for (j, row) in eyes[f.eye]!.enumerated() {
            for (i, ch) in row.enumerated() {
                grid[6 + j][9 + i] = ch
                grid[6 + j][16 + i] = ch
            }
        }
        var out: [Pixel] = []
        for (j, row) in grid.enumerated() {
            for (i, ch) in row.enumerated() where ch != "." {
                out.append(Pixel(x: i, y: j, rgb: lantern[ch]?[f.level] ?? palette[ch]!))
            }
        }
        pixelCache[f] = out
        return out
    }

    static func image(_ f: Frame) -> CGImage {
        if let hit = imageCache[f] { return hit }
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for p in pixels(f) {
            ctx.setFillColor(red: CGFloat(p.rgb >> 16 & 255) / 255, green: CGFloat(p.rgb >> 8 & 255) / 255, blue: CGFloat(p.rgb & 255) / 255, alpha: 1)
            ctx.fill(CGRect(x: p.x, y: height - 1 - p.y, width: 1, height: 1))
        }
        let image = ctx.makeImage()!
        imageCache[f] = image
        return image
    }
}

// MARK: - Routes

enum LumenCardKind { case music, weather, quote, other }

struct LumenCard: Equatable {
    var id: String
    var kind: LumenCardKind
    var rect: CGRect
    /// False when the widget has a solid background: Lumen cannot be seen behind it.
    var isGlass = true
}

struct LumenPose {
    enum Wing { case flap, slow, fixed(LumenWingShape) }

    var x: CGFloat = 0
    var y: CGFloat = 0
    var flip: CGFloat = 1 // -1 hangs upside down from y
    var behind = false
    var dissolve = 1.0 // 0 invisible, 1 solid
    var wing = Wing.flap
    var legs = LumenLegs.tuck
    var antenna: Int?
    var eye: LumenEye?
    var glow = 1.0
    var level: Int?
    var scale: CGFloat = 1
    var noLift = false
    var knock = false
    var burst = false
    var zzz = false
    var flareAt: CGPoint?
    var flare = 0.0
    var pushedCard: String?
    var push = CGSize.zero

    func at(_ x: CGFloat, _ y: CGFloat) -> LumenPose {
        var copy = self
        copy.x = x
        copy.y = y
        return copy
    }

    var isVisible: Bool { dissolve > 0 && x > -50 }
    var isFreeFlying: Bool { !behind && flip == 1 }
}

struct LumenSegment {
    enum Kind { case plain, fadeIn, fadeOut, hide }

    var duration: Double
    var kind = Kind.plain
    var style = LumenPose()
    var pose: (Double) -> LumenPose
}

private func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }

enum LumenRoutes {
    /// `wander` is how far, in points, a free flight strays from the straight line. Every such
    /// flight gets its own pace and curve, and still starts and ends exactly where it was sent.
    static func fly(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ style: LumenPose = LumenPose(), arc: CGFloat = 0, speed: CGFloat = 85, wander: CGFloat = 0) -> LumenSegment {
        let distance = hypot(x1 - x0, y1 - y0)
        let sway = wander * min(1, distance / 120)
        let normal = distance > 0 ? CGVector(dx: -(y1 - y0) / distance, dy: (x1 - x0) / distance) : .zero
        let turns = Double.random(in: 1.2...2.6), phase = Double.random(in: 0...(2 * .pi))
        let hesitation = wander > 0 ? Double.random(in: 0...0.05) : 0
        let pace = wander > 0 ? speed * .random(in: 0.75...1.2) : speed
        return LumenSegment(duration: max(0.3, Double(distance / pace))) { p in
            let e = ease(min(1, max(0, p + hesitation * sin(p * 4 * .pi))))
            let offset = sway * CGFloat(sin(e * .pi) * sin(e * 2 * .pi * turns + phase))
            return style.at(
                lerp(x0, x1, e) + normal.dx * offset,
                lerp(y0, y1, e) - arc * 4 * CGFloat(e * (1 - e)) + normal.dy * offset
            )
        }
    }

    static func stay(_ x: CGFloat, _ y: CGFloat, _ duration: Double, _ style: LumenPose = LumenPose()) -> LumenSegment {
        LumenSegment(duration: duration) { _ in style.at(x, y) }
    }

    static func fade(_ x: CGFloat, _ y: CGFloat, appearing: Bool, _ style: LumenPose = LumenPose()) -> LumenSegment {
        LumenSegment(duration: 0.55, kind: appearing ? .fadeIn : .fadeOut, style: style.at(x, y)) { p in
            var pose = style.at(x, y)
            pose.dissolve = appearing ? p : 1 - p
            return pose
        }
    }

    static func hide(_ duration: Double = 0.3) -> LumenSegment {
        LumenSegment(duration: duration, kind: .hide) { _ in
            var pose = LumenPose().at(-99, 0)
            pose.dissolve = 0
            return pose
        }
    }

    private static func style(_ edit: (inout LumenPose) -> Void) -> LumenPose {
        var pose = LumenPose()
        edit(&pose)
        return pose
    }

    /// The route for a move, written so it starts and ends with a dissolve. `bridged` removes
    /// the dissolves that are not needed when Lumen is already flying in the open.
    static func route(_ move: LumenMove, cards unsorted: [LumenCard]) -> [LumenSegment] {
        let cards = unsorted.sorted { $0.rect.minX < $1.rect.minX }
        guard let first = cards.first, let last = cards.last else { return [] }
        let top = first.rect.minY
        let flight = top - 6
        let behind = style { $0.behind = true }

        switch move {
        case .over:
            var x = first.rect.minX + 29
            var segments = [fade(x, flight, appearing: true)]
            for (i, card) in cards.enumerated() {
                let end = card.rect.maxX - 21
                segments.append(fly(x, flight, end, flight))
                x = end
                if i + 1 < cards.count {
                    let landing = cards[i + 1].rect.minX + 25
                    segments.append(fly(x, flight, landing, flight, arc: 12))
                    x = landing
                }
            }
            return segments + [fade(x, flight, appearing: false), hide()]

        case .under:
            // The room below the widgets is smaller than the sprite: the top of the body stays behind the glass.
            let y = (cards.map(\.rect.maxY).max() ?? first.rect.maxY) - 8
            let hanging = style {
                $0.flip = -1
                $0.behind = true
                $0.noLift = true
                $0.legs = .perch
                $0.wing = .slow
            }
            let start = last.rect.maxX - 19, end = first.rect.minX + 19
            return [fade(start, y, appearing: true, hanging), fly(start, y, end, y, hanging, speed: 62), fade(end, y, appearing: false, hanging), hide()]

        case .behind:
            let card = (cards.first(where: \.isGlass) ?? first).rect
            let y = card.maxY - 38
            let start = card.minX + 21, end = min(card.minX + 309, card.maxX - 21)
            return [fade(start, y, appearing: true, behind), fly(start, y, end, y, behind), stay(end, y, 0.8, behind), fly(end, y, start, y, behind), fade(start, y, appearing: false, behind), hide()]

        case .vanish:
            let start = min(first.rect.minX + 169, first.rect.maxX - 21), edge = first.rect.minX + 21
            let back = last.rect.maxX - 17, stop = max(last.rect.minX + 21, back - 102)
            return [
                fade(start, flight, appearing: true), fly(start, flight, edge, flight), fade(edge, flight, appearing: false), hide(0.4),
                fade(back, flight, appearing: true), fly(back, flight, stop, flight),
                stay(stop, flight, 0.8, style { $0.eye = .happy }), fade(stop, flight, appearing: false), hide(),
            ]

        case .wander:
            // A few stops anywhere along the row, in any order, sometimes pausing at one.
            func stop() -> CGPoint {
                let spot = hoverPoint(near: randomX(cards), cards: cards)
                return CGPoint(x: spot.x, y: spot.y + .random(in: -5...7))
            }
            var point = stop()
            var segments = [fade(point.x, point.y, appearing: true)]
            for _ in 0..<Int.random(in: 2...4) {
                let next = stop()
                segments.append(fly(point.x, point.y, next.x, next.y, wander: 9))
                if Bool.random() { segments.append(stay(next.x, next.y, .random(in: 0.4...2))) }
                point = next
            }
            return segments + [fade(point.x, point.y, appearing: false), hide()]

        case .absent:
            // Gone for a few seconds, back somewhere else. `bridged` adds the fade out.
            let spot = hoverPoint(near: randomX(cards), cards: cards)
            return [hide(.random(in: 2.5...11)), fade(spot.x, spot.y, appearing: true)]

        case .rest:
            // Lands on a widget and stays there: mostly still, an occasional look or wing shift.
            let spot = hoverPoint(near: randomX(cards), cards: cards)
            let seat = spot.y < top ? CGPoint(x: spot.x, y: top) : spot
            let above = seat.y - 6
            func sitting(_ edit: (inout LumenPose) -> Void = { _ in }) -> LumenPose {
                style {
                    $0.legs = .perch
                    $0.noLift = true
                    $0.wing = .fixed(.fold)
                    edit(&$0)
                }
            }
            var segments = [fade(seat.x, above, appearing: true), fly(seat.x, above, seat.x, seat.y, sitting(), speed: 14)]
            for _ in 0..<Int.random(in: 2...4) {
                segments.append(stay(seat.x, seat.y, .random(in: 2...6), sitting()))
                let fidget = [
                    sitting { $0.eye = .left }, sitting { $0.eye = .right },
                    sitting { $0.wing = .fixed(.open) }, sitting { $0.wing = .fixed(.up) },
                ].randomElement()!
                segments.append(stay(seat.x, seat.y, .random(in: 0.25...0.8), fidget))
            }
            return segments + [stay(seat.x, seat.y, .random(in: 0.5...2), sitting()), fly(seat.x, seat.y, seat.x, above, speed: 32)]

        case .slalom:
            let start = first.rect.minX - 15, end = last.rect.maxX + 15
            return [LumenSegment(duration: 8) { p in
                let forward = p < 0.5
                let x = lerp(start, end, ease(forward ? p * 2 : (1 - p) * 2))
                let index = cards.firstIndex { x < $0.rect.maxX + 7 } ?? cards.count - 1
                var pose = LumenPose().at(x, first.rect.midY + 5 + sin(x * 0.045) * 20)
                pose.behind = (index % 2 == 1) == forward
                pose.dissolve = min(1, min(p, 1 - p) * 20)
                return pose
            }, hide()]

        case .orbit:
            let card = (cards.first { $0.rect.width <= 220 } ?? first).rect
            return [LumenSegment(duration: 5.6) { p in
                let a = p * .pi * 4 - .pi
                var pose = LumenPose().at(card.midX + (card.width / 2 + 13) * cos(a), card.midY + 10 + (card.height / 2 + 5) * sin(a))
                pose.behind = sin(a) > 0
                pose.dissolve = min(1, min(p, 1 - p) * 12)
                return pose
            }, hide()]

        case .sunBump:
            let card = (cards.first { $0.kind == .weather } ?? last).rect
            let sun = CGPoint(x: card.maxX - 28, y: card.maxY - 28)
            let sx = sun.x, sy = sun.y + 10
            let eager = style { $0.eye = .wide }
            let cardID = (cards.first { $0.kind == .weather } ?? last).id
            return [
                fade(card.minX - 60, flight, appearing: true), fly(card.minX - 60, flight, sx - 30, sy - 30, eager),
                LumenSegment(duration: 3.4) { p in
                    let away = abs(sin(p * .pi * 5)), hit = away < 0.14
                    var pose = LumenPose().at(sx - 30 * away, sy - 30 * away)
                    pose.eye = .wide
                    pose.glow = 1.4
                    pose.flareAt = sun
                    pose.flare = hit ? 1 : 0.25
                    if hit {
                        pose.pushedCard = cardID
                        pose.push = CGSize(width: 0, height: 1.5)
                    }
                    return pose
                },
                stay(sx - 30, sy - 30, 0.7, style { $0.eye = .happy }), fly(sx - 30, sy - 30, card.maxX + 15, flight),
                fade(card.maxX + 15, flight, appearing: false), hide(),
            ]

        case .dance:
            let card = (cards.first { $0.kind == .music } ?? first).rect
            let reach = min(85, card.width / 2 - 30)
            return [
                fade(card.midX - reach - 30, flight, appearing: true), fly(card.midX - reach - 30, flight, card.midX, top - 10),
                LumenSegment(duration: 6.5) { p in
                    let a = p * .pi * 6
                    var pose = LumenPose().at(card.midX + reach * sin(a), top - 10 + 15 * sin(2 * a))
                    pose.eye = .happy
                    pose.glow = 1.3
                    pose.scale = 1 + abs(sin(a * 2.5)) * 0.08
                    return pose
                },
                fade(card.midX, top - 10, appearing: false), hide(),
            ]

        case .read:
            let card = (cards.first { $0.kind == .quote } ?? last).rect
            let left = card.minX + 15, right = min(card.minX + 81, card.maxX - 20)
            let line1 = card.minY + 52, line2 = card.minY + 72
            let reading = style { $0.glow = 1.3 }
            return [
                fade(card.minX + 41, flight, appearing: true), fly(card.minX + 41, flight, left, line1),
                fly(left, line1, right, line1, reading, speed: 26), fly(right, line1, left, line2, reading, speed: 70),
                fly(left, line2, right, line2, reading, speed: 26),
                stay(right, line2, 0.8, style { $0.glow = 1.3; $0.eye = .happy }), fade(right, line2, appearing: false), hide(),
            ]

        case .push:
            let index = max(0, cards.count - 2)
            let target = cards[index]
            let gap = index + 1 < cards.count ? (target.rect.maxX + cards[index + 1].rect.minX) / 2 : target.rect.maxX + 7
            let y = target.rect.midY + 5
            // Never pushes a widget into its left neighbour.
            let room = index > 0 ? max(0, target.rect.minX - cards[index - 1].rect.maxX - 2) : 9
            let shove = min(9, room)
            func pushing(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ eye: LumenEye) -> LumenPose {
                var pose = LumenPose().at(x, y)
                pose.eye = eye
                pose.glow = eye == .wide ? 1.4 : 1
                pose.pushedCard = target.id
                pose.push = CGSize(width: dx, height: 0)
                return pose
            }
            return [
                fade(gap + 94, y, appearing: true), fly(gap + 94, y, gap + 4, y, style { $0.eye = .left }),
                LumenSegment(duration: 1.2) { p in pushing(gap + 4 - shove * CGFloat(ease(p)), y, -shove * CGFloat(ease(p)), .wide) },
                LumenSegment(duration: 0.45) { _ in pushing(gap + 4 - shove, y, -shove, .wide) },
                LumenSegment(duration: 1.1) { p in
                    pushing(gap + 4 - shove + 50 * CGFloat(ease(p)), y - 14 * CGFloat(ease(p)), -shove * CGFloat(exp(-5 * p) * cos(14 * p)), .happy)
                },
                fade(gap + 45, y - 14, appearing: false), hide(),
            ]

        case .knock:
            let card = cards.first(where: \.isGlass) ?? first
            let x = card.rect.midX, y = card.rect.maxY - 44
            return [
                fade(x - 96, y, appearing: true, behind), fly(x - 96, y, x, y, behind),
                LumenSegment(duration: 3.6) { p in
                    let near = max(0, sin(p * .pi * 6))
                    var pose = LumenPose().at(x, y)
                    pose.behind = true
                    pose.scale = 1 + CGFloat(near) * 0.55
                    pose.eye = near > 0.5 ? .wide : .open
                    pose.knock = near > 0.93
                    if pose.knock {
                        pose.pushedCard = card.id
                        pose.push = CGSize(width: 0, height: 1.5)
                    }
                    return pose
                },
                stay(x, y, 0.5, style { $0.behind = true; $0.eye = .happy }), fade(x, y, appearing: false, behind), hide(),
            ]

        case .peek:
            let hiding = style {
                $0.behind = true
                $0.wing = .fixed(.fold)
                $0.noLift = true
            }
            func looking(_ eye: LumenEye) -> LumenPose {
                var pose = hiding
                pose.eye = eye
                return pose
            }
            // With no spot clear of the header its head would stay hidden.
            guard hasQuietSpot(cards) else { return route(.over, cards: cards) }
            let a = quietSpot(near: first.rect.midX, cards: cards)
            let b = quietSpot(near: last.rect.midX, cards: cards)
            let low = top + 40, high = top + 12
            return [
                fade(a, low, appearing: true, hiding), fly(a, low, a, high, looking(.open), speed: 45),
                stay(a, high, 0.8, looking(.left)), stay(a, high, 0.8, looking(.right)),
                fly(a, high, a, low, hiding, speed: 70), fly(a, low, b, low, hiding),
                fly(b, low, b, high, looking(.wide), speed: 60), stay(b, high, 1, looking(.happy)),
                fade(b, high, appearing: false, hiding), hide(),
            ]
        }
    }

    /// Joins a route to wherever Lumen is now: no dissolve when it can just fly there.
    static func bridged(_ route: [LumenSegment], from current: LumenPose) -> [LumenSegment] {
        guard let head = route.first else { return [] }
        var segments = route
        if head.kind == .fadeIn && head.style.isFreeFlying && current.isVisible && current.isFreeFlying {
            segments[0] = fly(current.x, current.y, head.style.x, head.style.y, head.style, wander: 9)
        } else if current.isVisible {
            segments.insert(fade(current.x, current.y, appearing: false, current), at: 0)
        }
        let n = segments.count
        if n >= 2, segments[n - 1].kind == .hide, segments[n - 2].kind == .fadeOut, segments[n - 2].style.isFreeFlying {
            segments.removeLast(2)
        }
        return segments
    }

    private static let cameraReach: CGFloat = 108

    /// Any position along the widget row.
    static func randomX(_ cards: [LumenCard]) -> CGFloat {
        guard let low = cards.map(\.rect.minX).min(), let high = cards.map(\.rect.maxX).max() else { return 0 }
        return .random(in: (low + 25)...max(low + 25, high - 25))
    }

    private static func middle(of cards: [LumenCard]) -> CGFloat {
        guard let low = cards.map(\.rect.minX).min(), let high = cards.map(\.rect.maxX).max() else { return 0 }
        return (low + high) / 2
    }

    /// Just beside the hardware notch the header is empty: the tabs end before it and the status
    /// icons start well after it. Only spots that lie on a widget count.
    private static func quietSpots(_ cards: [LumenCard]) -> [CGFloat] {
        let center = middle(of: cards)
        return [center - cameraReach, center + cameraReach].filter { spot in
            cards.contains { $0.rect.minX + 16 <= spot && spot <= $0.rect.maxX - 16 }
        }
    }

    static func hasQuietSpot(_ cards: [LumenCard]) -> Bool { !quietSpots(cards).isEmpty }

    static func quietSpot(near x: CGFloat, cards: [LumenCard]) -> CGFloat {
        quietSpots(cards).min { abs($0 - x) < abs($1 - x) } ?? x
    }

    /// Where Lumen settles to sleep. With a single widget under the hardware notch there is no
    /// clear edge to sit on, so it sits lower, on the widget itself, with its head in view.
    static func perch(near x: CGFloat, cards: [LumenCard]) -> CGPoint {
        let top = cards.map(\.rect.minY).min() ?? 0
        if hasQuietSpot(cards) { return CGPoint(x: quietSpot(near: x, cards: cards), y: top) }
        let center = cards.map(\.rect.midX).min { abs($0 - x) < abs($1 - x) } ?? x
        return CGPoint(x: center, y: top + 22)
    }

    /// Where Lumen waits between moves: anywhere, except where the header would hide it.
    static func hoverPoint(near x: CGFloat, cards: [LumenCard]) -> CGPoint {
        let top = cards.map(\.rect.minY).min() ?? 0
        if abs(x - middle(of: cards)) >= cameraReach { return CGPoint(x: x, y: top - 6) }
        if hasQuietSpot(cards) { return CGPoint(x: quietSpot(near: x, cards: cards), y: top - 6) }
        return perch(near: x, cards: cards)
    }

    static func hover(from current: LumenPose, cards: [LumenCard]) -> [LumenSegment] {
        let here = current.isVisible && current.isFreeFlying
        let spot = hoverPoint(near: current.x, cards: cards)
        let rest = LumenSegment(duration: .infinity) { _ in LumenPose().at(spot.x, spot.y) }
        if here { return abs(spot.x - current.x) < 1 && abs(spot.y - current.y) < 1 ? [rest] : [fly(current.x, current.y, spot.x, spot.y, wander: 5), rest] }
        let leave = current.isVisible ? [fade(current.x, current.y, appearing: false, current)] : []
        return leave + [fade(spot.x, spot.y, appearing: true), rest]
    }

    static func fallingAsleep(from current: LumenPose, perch: CGPoint) -> [LumenSegment] {
        let x = perch.x, top = perch.y, flight = top - 6
        let drowsy = style { $0.wing = .slow; $0.eye = .half }
        let perched = style { $0.legs = .perch; $0.noLift = true; $0.wing = .slow; $0.eye = .half }
        var lead: [LumenSegment]
        if current.isVisible && current.isFreeFlying {
            lead = [fly(current.x, current.y, x, flight, drowsy, speed: 50)]
        } else {
            lead = current.isVisible ? [fade(current.x, current.y, appearing: false, current)] : []
            lead.append(fade(x, flight, appearing: true, drowsy))
        }
        var folding = perched
        folding.wing = .fixed(.fold)
        folding.antenna = 2
        folding.glow = 0.7
        return lead + [
            // Circles once looking for a spot, lands, yawns, then wraps itself in its wings.
            LumenSegment(duration: 1.8) { p in
                let a = p * .pi * 2
                return drowsy.at(x + 16 * sin(a), flight + 3 * (1 - cos(a)))
            },
            fly(x, flight, x, top, perched, speed: 14),
            stay(x, top, 1.2, style { $0.legs = .perch; $0.noLift = true; $0.wing = .slow; $0.eye = .yawn }),
            stay(x, top, 0.6, folding),
            LumenSegment(duration: 0.9) { p in
                var pose = folding.at(x, top)
                pose.wing = .fixed(.wrap)
                pose.eye = .sleep
                pose.glow = 0.7 + (0.35 - 0.7) * p
                return pose
            },
        ]
    }

    /// Breathes about every 5 seconds. Every 11 seconds a short shiver, as if dreaming.
    static func asleep(perch: CGPoint, clock: @escaping () -> Double) -> [LumenSegment] {
        let x = perch.x, top = perch.y
        return [LumenSegment(duration: .infinity) { _ in
            let t = clock()
            let breath = (sin(t * 1.25) + 1) / 2
            let dreaming = t.truncatingRemainder(dividingBy: 11) < 0.4
            var pose = LumenPose().at(x, top)
            pose.wing = .fixed(dreaming ? .fold : breath > 0.5 ? .wrap2 : .wrap)
            pose.antenna = dreaming ? 1 : 2
            pose.legs = .perch
            pose.eye = .sleep
            pose.noLift = true
            pose.glow = 0.2 + 0.3 * breath
            pose.level = breath > 0.72 ? 1 : 0
            pose.zzz = !dreaming
            return pose
        }]
    }

    static func waking(from current: LumenPose, perch: CGPoint) -> [LumenSegment] {
        let x = current.isVisible ? current.x : perch.x, y = current.isVisible ? current.y : perch.y
        func perched(_ wing: LumenWingShape, _ antenna: Int, _ eye: LumenEye) -> LumenPose {
            style {
                $0.legs = .perch
                $0.noLift = true
                $0.wing = .fixed(wing)
                $0.antenna = antenna
                $0.eye = eye
            }
        }
        return [
            stay(x, y, 0.45, perched(.fold, 1, .wide)),
            stay(x, y, 0.6, perched(.up, 0, .happy)),
            LumenSegment(duration: 0.45) { p in
                var pose = perched(.open, 0, .blink).at(x + sin(p * 40) * 1.2, y)
                pose.burst = true
                return pose
            },
            fly(x, y, x, y - 6, style { $0.wing = .slow }, speed: 32),
        ]
    }

    #if DEBUG
    static let selfCheck: Void = {
        func card(_ id: String, _ kind: LumenCardKind, _ x: CGFloat, _ width: CGFloat, height: CGFloat = 126, glass: Bool = true) -> LumenCard {
            LumenCard(id: id, kind: kind, rect: CGRect(x: x, y: 40, width: width, height: height), isGlass: glass)
        }
        for _ in 0..<50 {
            let path = fly(10, 20, 300, 60, wander: 9)
            let start = path.pose(0), end = path.pose(1)
            assert(abs(start.x - 10) < 0.01 && abs(start.y - 20) < 0.01, "a wandering flight starts where it should")
            assert(abs(end.x - 300) < 0.01 && abs(end.y - 60) < 0.01, "a wandering flight ends where it should")
        }
        let layouts: [[LumenCard]] = [
            [card("alone", .other, 175, 150)], // centred under the hardware notch
            [card("solid", .weather, 175, 150, glass: false)],
            [card("large", .quote, 85, 330)],
            [card("a", .other, 96, 150), card("b", .weather, 260, 150, glass: false)],
            [card("m", .music, 0, 330), card("w", .weather, 344, 150, glass: false), card("q", .quote, 508, 150)],
            [card("m", .other, 0, 150, height: 84, glass: false), card("c", .other, 164, 210), card("n", .other, 388, 150), card("u", .other, 552, 150)],
        ]
        for cards in layouts {
            let flying = LumenPose().at(10, 10)
            for move in LumenMove.allCases {
                let route = LumenRoutes.route(move, cards: cards)
                assert(!route.isEmpty, "\(move) has a route")
                for segment in route {
                    assert(segment.duration > 0 && segment.duration.isFinite, "\(move) has finite segments")
                    for p in [0, 0.5, 1.0] {
                        let pose = segment.pose(p)
                        assert(pose.x.isFinite && pose.y.isFinite, "\(move) stays on screen")
                    }
                }
                let joined = bridged(route, from: flying)
                assert(joined.allSatisfy { $0.duration.isFinite }, "\(move) still ends")
            }
            // It leaves, stays away for a while, and comes back visible: never stuck out of sight.
            let absent = bridged(route(.absent, cards: cards), from: flying)
            assert(absent.first?.kind == .fadeOut && absent.last?.kind == .fadeIn, "absent leaves and returns")
            assert(absent.contains { $0.kind == .hide && $0.duration >= 2.5 }, "absent lasts seconds")
            // It sits still, then takes off again.
            let rest = bridged(route(.rest, cards: cards), from: flying)
            assert(rest.contains { $0.pose(0).noLift && $0.duration >= 2 }, "rest sits still")
            assert(rest.last.map { !$0.pose(1).noLift && $0.pose(1).isVisible } == true, "rest ends flying")
            // Lumen never rests where the header hides its head.
            for x in stride(from: CGFloat(0), through: 700, by: 50) {
                let center = middle(of: cards)
                let resting = [perch(near: x, cards: cards), hoverPoint(near: x, cards: cards)]
                for point in resting {
                    assert(abs(point.x - center) >= cameraReach || point.y > 40, "clear of the camera at \(x)")
                }
                let spot = perch(near: x, cards: cards)
                assert(cards.contains { $0.rect.minX <= spot.x && spot.x <= $0.rect.maxX }, "perches on a widget")
            }
        }
    }()
    #endif
}

// MARK: - Director

/// What one animation frame shows. Both canvases draw the same value.
struct LumenFrame {
    struct Mote {
        var x, y, vx, vy: CGFloat
        var life: Double
    }

    struct Ring {
        var x, y: CGFloat
        var life: Double
    }

    var pose = LumenPose().at(-99, 0)
    var sprite = LumenSprite.Frame(wing: .open, antenna: 0, legs: .tuck, eye: .open, level: 1)
    var cards: [LumenCard] = []
    var motes: [Mote] = []
    var rings: [Ring] = []
    var time = 0.0
    var wobble = CGSize.zero
}

/// Runs the brain and the current animation. Both canvases call `frame(at:)`;
/// only the first call for a given timestamp advances anything.
@MainActor
final class LumenDirector: ObservableObject {
    static let shared = LumenDirector()

    @Published private(set) var offsets: [String: CGSize] = [:]
    @Published private(set) var isAsleep = false

    private var brain = LumenBrain()
    private var segments: [LumenSegment] = []
    private var elapsed = 0.0
    private var phaseShown = LumenPhase.hidden
    private var current = LumenPose().at(-99, 0)
    private var lastFrame = LumenFrame()
    private var lastDate: Date?
    private var perch: CGPoint?
    private var layout: [CGRect] = []
    private var lastMouse = CGPoint.zero
    private var lastMouseMove = 0.0
    private var lift = 1.0
    private var drift = 0.0
    private var clock = 0.0
    private var previousX: CGFloat?
    private var wasKnocking = false
    private var motes: [LumenFrame.Mote] = []
    private var rings: [LumenFrame.Ring] = []

    func frame(at date: Date, cards: [LumenCard], inputs: LumenInputs) -> LumenFrame {
        // The first layout pass has no widget positions yet: every route would start at the origin.
        guard !cards.isEmpty else { return LumenFrame() }
        if date == lastDate { return lastFrame }
        let dt = lastDate.map { min(0.25, max(0, date.timeIntervalSince($0))) } ?? 0
        lastDate = date
        let now = date.timeIntervalSinceReferenceDate
        clock = now

        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            lastMouseMove = now
        }
        var inputs = inputs
        inputs.pointerStillFor = now - lastMouseMove

        brain.update(inputs, now: now)
        if brain.phase != phaseShown { show(brain.phase, cards: cards) }
        adapt(to: cards, now: now)

        elapsed += dt
        if isFinished {
            brain.animationFinished(now: now)
            if brain.phase != phaseShown { show(brain.phase, cards: cards) }
        }

        let pose = currentPose(dt: dt)
        advanceEffects(pose, dt: dt)
        publish(pose)

        var frame = LumenFrame()
        frame.pose = pose
        frame.sprite = sprite(for: pose, time: now)
        frame.cards = cards
        frame.motes = motes
        frame.rings = rings
        frame.time = now
        // Scripted moves keep the original bob. Otherwise slower, unrelated frequencies are added
        // so no loop shows, and both fade in and out so that changing behaviour does not jump.
        let aloft = pose.noLift ? 0.0 : 1.0
        let k = 1 - exp(-dt * 5)
        lift += (aloft - lift) * k
        drift += ((isUnscripted ? aloft : 0) - drift) * k
        let bob = isUnscripted ? lift : aloft
        frame.wobble = CGSize(
            width: sin(now * 1.9) * 1.2 * bob + (sin(now * 0.53 + 1) * 2.2 + sin(now * 3.7) * 0.5) * drift,
            height: sin(now * 3.1) * 1.6 * bob + (sin(now * 0.71 + 2) * 2.4 + sin(now * 5.3) * 0.4) * drift
        )
        previousX = pose.x
        current = pose
        lastFrame = frame
        return frame
    }

    /// Widgets were added, removed, reordered or swapped: every position in the current
    /// animation is stale. A move ends here, and anything else starts again from the new layout.
    private func adapt(to cards: [LumenCard], now: TimeInterval) {
        let rects = cards.map(\.rect.integral)
        guard rects != layout else { return }
        let isFirstLayout = layout.isEmpty
        layout = rects
        perch = nil
        guard !isFirstLayout else { return }
        switch phaseShown {
        case .hidden, .waking:
            break
        case .performing:
            brain.animationFinished(now: now)
            show(brain.phase, cards: cards)
        case .asleep, .hovering, .fallingAsleep:
            show(phaseShown, cards: cards)
        }
    }

    var phase: LumenPhase { brain.phase }

    /// Waiting between moves or in a move with no script. Everything else keeps its exact timing.
    private var isUnscripted: Bool {
        switch phaseShown {
        case .hovering: return true
        case .performing(let move): return move.isUnscripted
        case .hidden, .asleep, .waking, .fallingAsleep: return false
        }
    }

    /// The widget row left the screen: notch closed or another tab.
    func stageDisappeared() {
        var closed = LumenInputs()
        closed.notchOpen = false
        brain.update(closed, now: Date().timeIntervalSinceReferenceDate)
        phaseShown = .hidden
        segments = []
        current = LumenPose().at(-99, 0)
        lastDate = nil
        layout = []
        motes = []
        rings = []
        if !offsets.isEmpty { offsets = [:] }
    }

    private var isFinished: Bool {
        let total = segments.reduce(0) { $0 + $1.duration }
        return !segments.isEmpty && total.isFinite && elapsed >= total
    }

    private func show(_ phase: LumenPhase, cards: [LumenCard]) {
        #if DEBUG
        NSLog("Lumen: %@", String(describing: phase))
        #endif
        phaseShown = phase
        elapsed = 0
        let spot = perch ?? LumenRoutes.perch(near: cards.first { $0.kind == .weather }?.rect.midX ?? cards.last?.rect.midX ?? 0, cards: cards)
        switch phase {
        case .hidden:
            segments = []
        case .asleep:
            perch = spot
            segments = LumenRoutes.asleep(perch: spot) { [unowned self] in self.clock }
        case .fallingAsleep:
            let near = LumenRoutes.perch(near: current.isVisible ? current.x : spot.x, cards: cards)
            perch = near
            segments = LumenRoutes.fallingAsleep(from: current, perch: near)
        case .waking:
            segments = LumenRoutes.waking(from: current, perch: spot)
        case .hovering:
            var from = current
            if !from.isVisible { from.x = LumenRoutes.randomX(cards) }
            segments = LumenRoutes.hover(from: from, cards: cards)
        case .performing(let move):
            segments = LumenRoutes.bridged(LumenRoutes.route(move, cards: cards), from: current)
        }
    }

    private func currentPose(dt: Double) -> LumenPose {
        var t = elapsed
        for segment in segments {
            if t <= segment.duration {
                return segment.pose(segment.duration.isFinite ? min(1, t / segment.duration) : 0)
            }
            t -= segment.duration
        }
        return segments.last?.pose(1) ?? LumenPose().at(-99, 0)
    }

    private func advanceEffects(_ pose: LumenPose, dt: Double) {
        var flying = pose.dissolve >= 1 && !pose.noLift && !pose.behind
        if case .fixed(.fold) = pose.wing { flying = false }
        let rate = pose.burst ? 0.6 : flying ? 0.35 : pose.zzz ? 0.02 : 0
        if motes.count < 60 && Double.random(in: 0..<1) < rate {
            let rising = pose.zzz
            motes.append(LumenFrame.Mote(
                x: pose.x + .random(in: -13...13), y: pose.y - (rising ? 4 : 10),
                vx: .random(in: -3...3), vy: rising ? -5 : .random(in: 6...16), life: 1))
        }
        motes = motes.compactMap { mote in
            var m = mote
            m.life -= dt * 0.9
            m.x += m.vx * dt
            m.y += m.vy * dt
            return m.life > 0 ? m : nil
        }
        if pose.knock && !wasKnocking { rings.append(LumenFrame.Ring(x: pose.x, y: pose.y - 10, life: 1)) }
        wasKnocking = pose.knock
        rings = rings.compactMap { ring in
            var r = ring
            r.life -= dt * 2
            return r.life > 0 ? r : nil
        }
    }

    private func sprite(for pose: LumenPose, time: Double) -> LumenSprite.Frame {
        let wing: LumenWingShape
        switch pose.wing {
        case .fixed(let shape): wing = shape
        case .flap, .slow:
            let cycle: [LumenWingShape] = [.open, .up, .open, .down]
            var rate = 15.0
            if case .slow = pose.wing { rate = 7 }
            wing = cycle[Int(time * rate + (isUnscripted ? sin(time * 0.7) * 2.5 : 0)) % 4]
        }
        let dx = previousX.map { pose.x - $0 } ?? 0
        var eye = pose.eye ?? (dx > 0.25 ? .right : dx < -0.25 ? .left : .open)
        let blinks = isUnscripted ? sin(time * 1.9) * sin(time * 0.73) > 0.9 : time.truncatingRemainder(dividingBy: 3.3) < 0.13
        if pose.eye == nil && blinks { eye = .blink }
        let twitches = isUnscripted ? sin(time * 1.3) * sin(time * 0.47) > 0.88 : time.truncatingRemainder(dividingBy: 2.6) < 0.22
        let antenna = pose.antenna ?? (twitches ? 1 : 0)
        let level = pose.level ?? (pose.glow < 0.6 ? 0 : pose.glow > 1.2 ? 2 : sin(time * 2) > 0.72 ? 2 : 1)
        return LumenSprite.Frame(wing: wing, antenna: antenna, legs: pose.legs, eye: eye, level: level)
    }

    /// Published values change a view, so they cannot change while a view is being drawn.
    private func publish(_ pose: LumenPose) {
        var next: [String: CGSize] = [:]
        if let id = pose.pushedCard { next[id] = pose.push }
        let asleep = phaseShown == .asleep
        guard next != offsets || asleep != isAsleep else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.offsets != next { self.offsets = next }
            if self.isAsleep != asleep { self.isAsleep = asleep }
        }
    }
}

#if DEBUG
extension LumenDirector {
    static let selfCheckOnce: Void = selfCheck()

    /// A layout change must end the current move, and never leave Lumen stuck in it.
    static func selfCheck() {
        let director = LumenDirector()
        var cards = [
            LumenCard(id: "m", kind: .music, rect: CGRect(x: 0, y: 40, width: 330, height: 126)),
            LumenCard(id: "w", kind: .other, rect: CGRect(x: 344, y: 40, width: 150, height: 126)),
        ]
        var inputs = LumenInputs()
        inputs.musicPlaying = true
        let start = Date()
        var t = 0.0
        func run(until phase: (LumenPhase) -> Bool) -> Bool {
            let end = t + 120
            while t < end {
                t += 1.0 / 24
                _ = director.frame(at: start.addingTimeInterval(t), cards: cards, inputs: inputs)
                if phase(director.phase) { return true }
            }
            return false
        }
        func isMoving(_ phase: LumenPhase) -> Bool {
            if case .performing = phase { return true }
            return false
        }
        assert(run(until: isMoving), "starts moving")
        cards.append(LumenCard(id: "q", kind: .quote, rect: CGRect(x: 508, y: 40, width: 150, height: 126)))
        t += 1.0 / 24
        _ = director.frame(at: start.addingTimeInterval(t), cards: cards, inputs: inputs)
        assert(director.phase == .hovering, "a new widget ends the move")
        assert(run(until: isMoving), "keeps going with the new layout")
        cards.removeAll { $0.id == "w" }
        t += 1.0 / 24
        _ = director.frame(at: start.addingTimeInterval(t), cards: cards, inputs: inputs)
        assert(director.phase == .hovering, "a removed widget ends the move")
        director.stageDisappeared()
        assert(director.phase == .hidden, "leaving hides it")
    }
}
#endif

// MARK: - Painting

enum LumenPainter {
    private static let warm = Color(red: 0.98, green: 0.89, blue: 0.63)

    /// Only the area around Lumen is redrawn: the light, the dust and the Zs all stay inside it.
    static func region(for f: LumenFrame) -> CGRect {
        CGRect(x: (f.pose.x - 104).rounded(), y: (f.pose.y - 114).rounded(), width: 208, height: 208)
    }

    static func hasContent(_ f: LumenFrame, behind: Bool) -> Bool {
        if behind { return f.pose.behind && f.pose.isVisible }
        return f.pose.isVisible || !f.motes.isEmpty || !f.rings.isEmpty
    }

    static func paint(_ g: inout GraphicsContext, _ f: LumenFrame, behind: Bool) {
        if !behind { paintLight(&g, f, region: region(for: f)) }
        if f.pose.behind == behind && f.pose.dissolve > 0 { paintCreature(&g, f) }
        if !behind { paintEffects(&g, f) }
    }

    /// Lumen lights whatever widget it is near.
    private static func paintLight(_ g: inout GraphicsContext, _ f: LumenFrame, region: CGRect) {
        let p = f.pose
        guard p.isVisible else { return }
        let center = CGPoint(x: p.x, y: p.y - 10 * p.flip)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [warm.opacity(0.3 * p.dissolve * min(1.3, p.glow)), warm.opacity(0)]),
            center: center, startRadius: 0, endRadius: 84)
        for card in f.cards where card.rect.intersects(region) {
            var layer = g
            layer.blendMode = .plusLighter
            layer.fill(Path(roundedRect: card.rect, cornerRadius: 22, style: .continuous), with: shading)
        }
        if let sun = p.flareAt, p.flare > 0 {
            var layer = g
            layer.blendMode = .plusLighter
            let radius = 28 + p.flare * 22
            layer.fill(
                Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.47).opacity(0.55 * p.flare), .clear]),
                    center: sun, startRadius: 6, endRadius: radius))
        }
    }

    private static func paintCreature(_ g: inout GraphicsContext, _ f: LumenFrame) {
        let p = f.pose
        var ctx = g
        ctx.translateBy(x: p.x + f.wobble.width, y: p.y + f.wobble.height)
        ctx.scaleBy(x: p.scale, y: p.flip * p.scale)

        let halo = min(1.3, p.glow) * 0.3 * p.dissolve
        ctx.fill(Path(ellipseIn: CGRect(x: -46, y: -56, width: 92, height: 92)), with: .radialGradient(
            Gradient(colors: [warm.opacity(halo), warm.opacity(0)]),
            center: CGPoint(x: 0, y: -10), startRadius: 2, endRadius: 46))

        let w = CGFloat(LumenSprite.width), h = CGFloat(LumenSprite.height)
        if p.dissolve < 1 {
            // Pixels scatter upward as it dissolves.
            for px in LumenSprite.pixels(f.sprite) {
                let n = noise(px.x, px.y)
                guard n <= p.dissolve else { continue }
                let scatter = CGFloat(1 - p.dissolve)
                let rect = CGRect(x: -w / 2 + CGFloat(px.x) + CGFloat(n - 0.5) * scatter * 30,
                                  y: -h + CGFloat(px.y) - scatter * 34 * CGFloat(n), width: 1.05, height: 1.05)
                ctx.fill(Path(rect), with: .color(color(px.rgb)))
            }
        } else {
            let image = Image(decorative: LumenSprite.image(f.sprite), scale: 1).interpolation(.none)
            ctx.draw(ctx.resolve(image), in: CGRect(x: -w / 2, y: -h, width: w, height: h))
        }
    }

    private static func paintEffects(_ g: inout GraphicsContext, _ f: LumenFrame) {
        for mote in f.motes {
            g.fill(Path(CGRect(x: mote.x, y: mote.y, width: 1, height: 1)),
                   with: .color(color(mote.life > 0.5 ? 0xFFE7AE : 0xD9A551).opacity(mote.life * 0.8)))
        }
        for ring in f.rings {
            let r = 10 + CGFloat(1 - ring.life) * 30
            g.stroke(Path(ellipseIn: CGRect(x: ring.x - r, y: ring.y - r, width: r * 2, height: r * 2)),
                     with: .color(color(0xFFF0C4).opacity(ring.life * 0.8)), lineWidth: 1)
        }
        guard f.pose.zzz else { return }
        // Pixel Zs rise from the head, slow as the breath, in the lantern's colour.
        for n in 0..<3 {
            let u = (f.time * 0.22 + Double(n) / 3).truncatingRemainder(dividingBy: 1)
            let size = CGFloat(1 + Int(u * 2.4))
            let x = (f.pose.x + 11 + CGFloat(u) * 14 + CGFloat(sin(u * 7)) * 2).rounded()
            let y = (f.pose.y - 20 - CGFloat(u) * 17).rounded()
            let shade = color(0xF4CB78).opacity(sin(u * .pi) * 0.9)
            for (j, row) in ["111", "010", "111"].enumerated() {
                for (i, bit) in row.enumerated() where bit == "1" {
                    g.fill(Path(CGRect(x: x + CGFloat(i) * size, y: y + CGFloat(j) * size, width: size, height: size)), with: .color(shade))
                }
            }
        }
    }

    private static func noise(_ x: Int, _ y: Int) -> Double {
        let n = sin(Double(x) * 12.9898 + Double(y) * 78.233) * 43758.5453
        return n - n.rounded(.down)
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

// MARK: - View

/// Ticks Lumen with a plain timer. A TimelineView keeps the whole hosting view on a busy display
/// cycle between its updates: that cost about 10% of a core even with nothing drawn. The timer only
/// wakes the app when a frame is due, and only the two layers observe it, not the widgets.
@MainActor
final class LumenClock: ObservableObject {
    static let shared = LumenClock()

    @Published private(set) var now = Date()

    private var timer: Timer?
    private var interval: TimeInterval = 0

    func run(every seconds: TimeInterval) {
        guard seconds != interval || timer == nil else { return }
        stop()
        interval = seconds
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        timer.tolerance = seconds * 0.2 // lets the system group wake-ups
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// One of the two layers around the widget row. Its canvas covers only the area around Lumen
/// and may extend past the row, so Lumen can fly above the widgets; the notch shape clips the rest.
struct LumenLayerView: View {
    let behind: Bool
    let cards: [LumenCard]
    let inputs: () -> LumenInputs

    @ObservedObject private var clock = LumenClock.shared
    @ObservedObject private var director = LumenDirector.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sleep barely changes from frame to frame.
    private var interval: TimeInterval { director.isAsleep ? 0.2 : 1.0 / 24 }

    var body: some View {
        let frame = director.frame(at: clock.now, cards: cards, inputs: inputs())
        ZStack {
            if LumenPainter.hasContent(frame, behind: behind) {
                let region = LumenPainter.region(for: frame)
                Canvas { g, _ in
                    g.translateBy(x: -region.minX, y: -region.minY)
                    LumenPainter.paint(&g, frame, behind: behind)
                }
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { clock.run(every: interval) } }
        .onChange(of: interval) { _, seconds in if !reduceMotion { clock.run(every: seconds) } }
        .onDisappear { clock.stop() }
    }
}
