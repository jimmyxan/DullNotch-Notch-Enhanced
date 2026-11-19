//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation
import Defaults

enum OnboardingStep {
    case welcome
    case look
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case musicPermission
    case musicAnimation
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .look
                    }
                }
                .transition(.opacity)

            case .look:
                LookStepView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "DullNotch includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "DullNotch can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await requestCalendarPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "DullNotch can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await requestRemindersPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .accessibilityPermission
                                }
                            }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    )
                    .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the DullNotch HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            step = .musicAnimation
                        }
                    }
                )
                .transition(.opacity)

            case .musicAnimation:
                OnboardingPage(title: "Music Animation",
                               subtitle: "Plays next to the album art in the closed notch while music is on.") {
                    ScrollView { MusicVisualizerPicker().padding(.horizontal, 24) }
                } onContinue: {
                    withAnimation(.easeInOut(duration: 0.6)) { step = .finished }
                }
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }
    
    func requestAccessibilityPermission() async {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
    }
}

// MARK: - Look

/// Title, subtitle, content and a Continue button, on the same background as the other steps.
private struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 28)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            content
            Spacer(minLength: 0)
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

/// Liquid Glass level (starts at 100%) and the closed-notch progress style.
private struct LookStepView: View {
    let onContinue: () -> Void
    @Default(.glassIntensity) private var glass
    @Default(.progressStyle) private var style

    var body: some View {
        OnboardingPage(title: "Make It Yours",
                       subtitle: "Pick a look now. You can change it any time in Settings.") {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Liquid Glass").font(.headline)
                    glassPreview
                    HStack {
                        Slider(value: $glass, in: 0...1, step: 0.05)
                        Text("\(Int(glass * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("0% keeps the classic black notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Progress on the closed notch").font(.headline)
                    HStack(spacing: 10) {
                        ForEach(ProgressStyle.allCases) { styleCard($0) }
                    }
                    Text(style.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
        } onContinue: { onContinue() }
        .onAppear { glass = 1 }
    }

    /// The real open-notch background over a colourful backdrop, so the slider shows what you get.
    private var glassPreview: some View {
        let shape = NotchShape(topCornerRadius: 8, bottomCornerRadius: 18)
        return ZStack(alignment: .top) {
            LinearGradient(colors: [.indigo, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 40) {
                Circle().fill(.yellow).frame(width: 46)
                Circle().fill(.mint).frame(width: 30)
                Circle().fill(.pink).frame(width: 54)
            }
            .offset(y: 30)
            NotchBackground(isOpen: true, shape: shape, notchHeight: 12)
                .clipShape(shape)
                .overlay {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.85)).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(.white.opacity(0.9)).frame(width: 90, height: 7)
                            Capsule().fill(.white.opacity(0.5)).frame(width: 60, height: 6)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                }
                .frame(width: 250, height: 76)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func styleCard(_ s: ProgressStyle) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { style = s }
        } label: {
            VStack(spacing: 8) {
                StylePreview(style: s)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style == s ? Color.effectiveAccent : .secondary.opacity(0.3),
                                          lineWidth: style == s ? 2 : 1)
                    }
                Text(s.title).font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small drawing of the closed notch in each progress style.
private struct StylePreview: View {
    let style: ProgressStyle
    private let notch = CGSize(width: 58, height: 18)
    private let wing: CGFloat = 22
    private let tint = Color.blue // a download, as on the real notch

    var body: some View {
        let left = style == .wire ? 0 : wing
        let right = style == .wings ? wing : 0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: left)
                    .opacity(left > 0 ? 1 : 0)
                Color.clear.frame(width: notch.width)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(tint, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 10, height: 10)
                    .frame(width: right)
                    .opacity(right > 0 ? 1 : 0)
            }
            .frame(height: notch.height)
            .background(.black, in: shape)
            if style != .wings {
                // The wire runs around the resting notch, just outside it.
                shape
                    .stroke(tint, lineWidth: 2)
                    .frame(width: notch.width + 4, height: notch.height + 2)
                    .offset(x: left / 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
