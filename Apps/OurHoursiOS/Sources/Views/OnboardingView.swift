import CoreBluetooth
import CoreLocation
import OurHoursCore
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var pairingStage: PairingStage = .choices

    private enum Step: Int, CaseIterable {
        case welcome, profile, recording, permissions, pairing

        var title: String {
            switch self {
            case .welcome: "ようこそ、OurHoursへ"
            case .profile: "あなたのシャボン玉"
            case .recording: "アプリは終了しないでね"
            case .permissions: "権限のお願い"
            case .pairing: "ペアをつなぐ"
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            progressHeader
                .padding(.horizontal, 18)
                .padding(.top, 4)

            if step == .pairing {
                stepTitle
                    .padding(.horizontal, 18)
                PairingFlow(stage: $pairingStage, onSkip: finish, onFinish: finish)
            } else {
                explanation
                Button(step == .welcome ? "はじめる" : "次へ") { go(to: step.rawValue + 1) }
                    .buttonStyle(FoamPrimaryActionStyle())
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .background {
            ZStack {
                FoamTheme.sky(together: false)
                FoamAmbientBackgroundView(isTogether: false, softened: true)
            }
            .ignoresSafeArea()
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .onAppear { model.refreshPermissionStates() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.refreshPermissionStates() }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                Circle()
                    .fill(item.rawValue <= step.rawValue ? BubbleColorTheme.skyBlue.swatchGradient : inactiveDot)
                    .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1) }
                    .frame(width: item == step ? 14 : 10, height: item == step ? 14 : 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ステップ \(step.rawValue + 1) / \(Step.allCases.count)")
        .frame(maxWidth: .infinity, minHeight: 44)
        .overlay(alignment: .leading) {
            if step != .welcome && (step != .pairing || pairingStage == .choices) {
                FoamRoundIconButton(accessibilityLabel: "前のステップに戻る", action: { go(to: step.rawValue - 1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .overlay(alignment: .trailing) {
            Button(action: finish) {
                Text("スキップ")
                    .font(FoamFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink.opacity(0.76))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("オンボードをスキップ")
        }
    }

    private var inactiveDot: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.60), .white.opacity(0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var explanation: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    stepTitle
                    switch step {
                    case .welcome: welcome
                    case .profile: profile
                    case .recording: recording
                    case .permissions: OnboardingPermissionCards()
                    case .pairing: EmptyView()
                    }
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .defaultScrollAnchor(.top)
            .id(step)
            .transition(.opacity)
        }
    }

    private var stepTitle: some View {
        Text(step.title)
            .font(FoamFont.bold(26, relativeTo: .title2))
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            MascotBubbleAvatar(color: .skyBlue, size: 132)
            VStack(spacing: 1) {
                SoapBubbleSurface(seed: 1.6, wobbleScale: 0.2, animated: false)
                    .frame(width: 12, height: 12)
                    .offset(x: 17)
                SoapBubbleSurface(seed: 2.1, wobbleScale: 0.2, animated: false)
                    .frame(width: 17, height: 17)
                    .offset(x: 10)
            }
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text("ふたりで一緒にいた時間を自動で残すアプリだよ！")
                    .font(FoamFont.bold(17, relativeTo: .headline))
                Text("自動で記録するために Bluetooth と位置情報（常に）が必要なんだ。位置情報は Bluetooth の届かない時間を補うだけで、現在地が地図に出たり誰かに見られたりしないから安心してね。")
                    .font(FoamFont.regular(15, relativeTo: .subheadline))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SoapBubbleSurface(cornerStyle: .roundedRect(27), prominence: .vivid, seed: 1.2, wobbleScale: 0.4, animated: false)
            }
        }
    }

    private var profile: some View {
        VStack(spacing: 14) {
            MascotBubbleAvatar(color: model.localBubbleColor, size: 132, animated: true)

            FoamSoftCard {
                VStack(spacing: 3) {
                    BubbleColorSwatches(selection: model.localBubbleColor, onSelect: model.setLocalBubbleColor)
                    Text(model.localBubbleColor.displayName)
                        .font(FoamFont.bold(14, relativeTo: .subheadline))
                }
            }

            FoamSoftCard {
                OptionalProfileDateRow(
                    title: "自分の誕生日",
                    unsetTitle: "自分の誕生日を設定する（任意）",
                    showsClearButton: false,
                    showsTodayButton: false,
                    date: Binding(get: { model.localBirthday }, set: { model.setLocalBirthday($0) })
                )
            }
        }
    }

    private var recording: some View {
        VStack(spacing: 16) {
            TaskKillAnimationView()
            FoamSoftCard {
                Text("上にスワイプして終了すると、自動記録が止まってしまいます。")
                    .font(FoamFont.regular(15, relativeTo: .subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func go(to index: Int) {
        guard let next = Step(rawValue: index) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            step = next
        }
    }

    private func finish() {
        model.completeOnboarding()
        dismiss()
    }
}

private struct OnboardingPermissionCards: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            FoamSoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                        .font(FoamFont.bold(17, relativeTo: .headline))

                    if model.bluetoothAuthorization == .allowedAlways {
                        allowedBadge("許可済み")
                    } else if model.bluetoothAuthorization == .denied || model.bluetoothAuthorization == .restricted
                                || model.snapshot.centralState == "unauthorized" || model.snapshot.peripheralState == "unauthorized" {
                        Text("設定から許可してください")
                            .font(FoamFont.regular(14, relativeTo: .footnote))
                        settingsButton
                    } else {
                        Button("Bluetooth をオンにする", action: model.requestBluetoothPermission)
                            .buttonStyle(FoamCardActionStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FoamSoftCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("位置情報（任意）", systemImage: "location")
                        .font(FoamFont.bold(17, relativeTo: .headline))
                    Text("精度を上げる（Bluetooth だけでも使えます）")
                        .font(FoamFont.regular(14, relativeTo: .footnote))

                    let monitor = model.locationMonitor
                    if !(monitor.authorizationStatus == .authorizedAlways && monitor.isEnabled && !monitor.isReducedAccuracyWarning) {
                        Text("「Appの使用中は許可」のあと「常に許可」を選んでね（「1度だけ許可」だと「常に」にできません）")
                            .font(FoamFont.regular(13, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    switch monitor.authorizationStatus {
                    case .authorizedAlways where monitor.isEnabled:
                        if monitor.isReducedAccuracyWarning {
                            Text("「正確な位置情報」をオンにすると精度が上がります")
                                .font(FoamFont.regular(14, relativeTo: .footnote))
                            settingsButton
                        } else {
                            allowedBadge("許可済み（常に）")
                        }
                    case .authorizedWhenInUse where monitor.isEnabled:
                        Button("「常に」を許可する", action: monitor.enableAndRequestAuthorization)
                            .buttonStyle(FoamCardActionStyle())
                        Text("ポップアップが出ない場合は「設定を開く」から「常に」に変更してね")
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: openSettings) {
                            Text("設定を開く").underline()
                        }
                        .font(FoamFont.medium(14, relativeTo: .footnote))
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    case .denied, .restricted:
                        settingsButton
                    default:
                        Button("位置情報を許可する", action: monitor.enableAndRequestAuthorization)
                            .buttonStyle(FoamCardActionStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func allowedBadge(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(FoamFont.bold(14, relativeTo: .subheadline))
            .foregroundStyle(Color(red: 0.13, green: 0.36, blue: 0.31))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BubbleColorTheme.mint.glowColor.opacity(0.94), in: Capsule())
    }

    private var settingsButton: some View {
        Button("設定を開く", action: openSettings)
            .buttonStyle(FoamCardActionStyle())
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
