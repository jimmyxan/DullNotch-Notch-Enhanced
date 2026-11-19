// Draws the DullNotch app icon. Run: swiftc -O scripts/make_app_icon.swift -o /tmp/icon && /tmp/icon <dir>
// writes 16…1024 px PNGs into <dir>; copy them into AppIcon.appiconset by size (see Contents.json).
import SwiftUI
import AppKit

let S: CGFloat = 1024
let inset: CGFloat = 100          // macOS icon grid: 824 pt body inside 1024
let side = S - inset * 2

struct Icon: View {
    var main: some View {
        let sq = RoundedRectangle(cornerRadius: 185, style: .continuous)
        return ZStack {
            // Base: deep midnight glass
            sq.fill(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.24), Color(red: 0.03, green: 0.035, blue: 0.06)],
                                   startPoint: .top, endPoint: .bottom))
            // Aurora light living under the glass
            ZStack {
                glow(Color(red: 0.24, green: 0.90, blue: 0.78), 330).offset(x: -190, y: -150)
                glow(Color(red: 0.32, green: 0.45, blue: 1.0), 380).offset(x: 10, y: -90)
                glow(Color(red: 0.70, green: 0.38, blue: 1.0), 330).offset(x: 200, y: -170)
                glow(Color(red: 0.32, green: 0.45, blue: 1.0), 420).opacity(0.35).offset(y: 300)
            }
            // Wordmark
            Text("DullNotch")
                .font(.system(size: 104, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .offset(y: 215)
            // The open notch: one Liquid Glass panel hanging from the top edge
            notchPanel
                .offset(y: -side / 2 + 165)
            // Rim light
            Color.clear
        }
        .frame(width: side, height: side)
        .clipShape(sq)
        .overlay {
            sq.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 5)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        .frame(width: S, height: S)
    }
    var body: some View { main }

    var notchPanel: some View {
        let w: CGFloat = 640, h: CGFloat = 330
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 110, bottomTrailingRadius: 110, topTrailingRadius: 0, style: .continuous)
        return ZStack(alignment: .top) {
            shape.fill(.black.opacity(0.30))
            shape.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            // black hardware band melting into the glass, as in the app
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
            // the hardware notch, with its camera
            UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
                .fill(.black)
                .frame(width: 230, height: 58)
                .overlay {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.5), .black], center: .center, startRadius: 0, endRadius: 9))
                        .frame(width: 18, height: 18)
                        .offset(y: -4)
                }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
            content.padding(.top, 150)
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
    }

    func glow(_ c: Color, _ r: CGFloat) -> some View {
        Circle().fill(RadialGradient(colors: [c, c.opacity(0.5), c.opacity(0)], center: .center, startRadius: 0, endRadius: r)).frame(width: r * 2, height: r * 2)
    }

    var content: some View {
        HStack(spacing: 70) {
            HStack(alignment: .center, spacing: 16) {
                ForEach([0.45, 0.85, 0.6, 1.0, 0.55], id: \.self) { v in
                    Capsule().fill(LinearGradient(colors: [.white, .white.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 110 * v)
                }
            }
            .frame(height: 110)
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 18)
                Circle().trim(from: 0, to: 0.68)
                    .stroke(LinearGradient(colors: [Color(red: 0.45, green: 0.95, blue: 0.85), Color(red: 0.55, green: 0.6, blue: 1.0)], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 104, height: 104)
        }
    }
}

@MainActor func render(_ size: Int, _ path: String) {
    let r = ImageRenderer(content: Icon().frame(width: S, height: S).scaleEffect(CGFloat(size) / S).frame(width: CGFloat(size), height: CGFloat(size)))
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("render") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
MainActor.assumeIsolated {
    if CommandLine.arguments.count > 1 {
        // icon.swift <dir>: write every size the appiconset needs, named <size>.png
        for s in [16, 32, 64, 128, 256, 512, 1024] { render(s, "\(CommandLine.arguments[1])/\(s).png") }
    } else { render(1024, "icon.png") }
}
