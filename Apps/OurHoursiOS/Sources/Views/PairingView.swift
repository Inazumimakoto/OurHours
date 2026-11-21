import OurHoursCore
import SwiftUI
import UIKit

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var stage: PairingStage = .choices

    var body: some View {
        VStack(spacing: 8) {
            Text("ペア設定")
                .font(FoamFont.bold(20, relativeTo: .title3))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .trailing) {
                    FoamRoundIconButton(accessibilityLabel: "閉じる", action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

            PairingFlow(stage: $stage, autoShowExistingInvite: true, onFinish: { dismiss() })
        }
        .background {
            ZStack {
                FoamTheme.sky(together: model.isTogetherNow)
                FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
            }
            .ignoresSafeArea()
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
    }
}

enum PairingStage: Equatable {
    case choices
    case invite(String, existing: Bool)
    case completion(PeerRole)
}

struct PairingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var stage: PairingStage
    var autoShowExistingInvite = false
    var onSkip: (() -> Void)? = nil
    let onFinish: () -> Void

    @State private var manualURL = ""
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var scannedURL: String?

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 0).id("pairingTop")
                    switch stage {
                    case .choices:
                        if model.snapshot.isPaired {
                            existingPair
                        } else {
                            pairingChoices
                        }
                    case let .invite(url, existing):
                        InviteCodeCard(inviteURL: url, isTogether: model.isTogetherNow)
                        if existing {
                            Button(onSkip == nil ? "閉じる" : "ホームへ戻る", action: onFinish)
                                .buttonStyle(FoamPrimaryActionStyle())
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(FoamTheme.ink)
                                Text("相手が読み取ると自動で次へ進みます…")
                                    .font(FoamFont.regular(13.5, relativeTo: .footnote))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.74))
                            }
                            .padding(.top, 4)

                            Button("手動で次へ進む") {
                                move(to: .completion(.partnerA))
                            }
                            .buttonStyle(FoamPrimaryActionStyle())
                        }
                    case let .completion(role):
                        PairingCompletionForm(
                            role: role,
                            nickname: model.partnerNickname,
                            anniversary: model.anniversaryDate,
                            actionTitle: onSkip == nil ? "完了してはじめる" : "OurHoursをはじめる",
                            onFinish: onFinish
                        )
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(FoamFont.medium(14, relativeTo: .footnote))
                            .foregroundStyle(Color(red: 0.60, green: 0.19, blue: 0.23))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("pairingError")
                    }
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: stage) { scroll.scrollTo("pairingTop", anchor: .top) }
            .onChange(of: errorMessage) {
                if errorMessage != nil { scroll.scrollTo("pairingError", anchor: .bottom) }
            }
            .onChange(of: model.hasPartnerConnectedForCurrentPair) {
                advanceFromInviteIfPartnerJoined()
            }
            .task(id: stage) {
                guard case let .invite(_, existing) = stage, !existing else { return }
                advanceFromInviteIfPartnerJoined()
                try? await Task.sleep(for: .seconds(2))
                while !Task.isCancelled {
                    if case let .invite(_, existingNow) = stage, !existingNow {
                        if !model.isHistorySyncing {
                            await model.syncSharedHistoryNow()
                        }
                        advanceFromInviteIfPartnerJoined()
                        try? await Task.sleep(for: .seconds(3))
                    } else {
                        break
                    }
                }
            }
        }
        .onAppear {
            if autoShowExistingInvite, stage == .choices, let url = existingInviteURL {
                stage = .invite(url, existing: true)
            }
        }
        .sheet(isPresented: $showScanner, onDismiss: useScannedURL) {
            QRScannerView { value in
                scannedURL = value
                showScanner = false
            }
        }
    }

    private var existingInviteURL: String? {
        guard let pair = model.snapshot.pairConfiguration, pair.localRole == .partnerA else { return nil }
        return PairingPayloadCodec.encode(pair, for: .partnerB)
    }

    private func advanceFromInviteIfPartnerJoined() {
        guard case let .invite(_, existing) = stage, !existing else { return }
        guard model.hasPartnerConnectedForCurrentPair else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        move(to: .completion(.partnerA))
    }

    private var existingPair: some View {
        VStack(spacing: 14) {
            FoamSoftCard {
                Label("現在ペア連携済みです", systemImage: "checkmark.circle.fill")
                    .font(FoamFont.bold(17, relativeTo: .headline))
                    .frame(maxWidth: .infinity)
            }
            if let url = existingInviteURL {
                Button("招待QRコードを表示") { move(to: .invite(url, existing: true)) }
                    .font(FoamFont.bold(15, relativeTo: .subheadline))
                    .foamButtonSurface(wobble: false)
            }
            Button(onSkip == nil ? "閉じる" : "ホームへ戻る", action: onFinish)
                .buttonStyle(FoamPrimaryActionStyle())
        }
    }

    private var pairingChoices: some View {
        VStack(spacing: 16) {
            if onSkip == nil {
                ReleaseBubbleCard(title: "プライバシーと仕組み", isTogether: model.isTogetherNow, seed: 1.4) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("画面を閉じている間も、Bluetoothと暗号化した位置滞在ログの突き合わせで「一緒にいる時間」を自動記録します。")
                        Text("地図や相手の位置座標は画面に表示しません。自動記録や位置補完は設定でいつでも停止できます。")
                    }
                    .font(FoamFont.regular(14, relativeTo: .footnote))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("相手を招待する")
                    .font(FoamFont.bold(13.5, relativeTo: .footnote))
                    .foregroundStyle(FoamTheme.ink.opacity(0.76))
                    .padding(.horizontal, 6)
                Button(onSkip == nil ? "同意して招待QRコードを作成" : "招待QRコードを出す", systemImage: "qrcode", action: startInvite)
                    .buttonStyle(FoamPrimaryActionStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("相手の招待で設定する")
                    .font(FoamFont.bold(13.5, relativeTo: .footnote))
                    .foregroundStyle(FoamTheme.ink.opacity(0.76))
                    .padding(.horizontal, 6)

                Button(onSkip == nil ? "同意してQRコードを読み取る" : "QRコードを読み取る", systemImage: "qrcode.viewfinder") {
                    errorMessage = nil
                    showScanner = true
                }
                .buttonStyle(FoamPrimaryActionStyle())

                DisclosureGroup("招待URLを貼り付けて設定") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("ourhours://…", text: $manualURL, axis: .vertical)
                            .accessibilityLabel("招待URL")
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                        Button(onSkip == nil ? "同意して招待URLで設定" : "招待URLで設定") { completePairing(manualURL) }
                            .buttonStyle(FoamCardActionStyle())
                            .disabled(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 10)
                }
                .font(FoamFont.medium(14, relativeTo: .subheadline))
                .tint(FoamTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.46))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                        }
                )
            }

            if let onSkip {
                Button(action: onSkip) {
                    Text("今はひとりで始める")
                        .font(FoamFont.bold(15, relativeTo: .subheadline))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func move(to nextStage: PairingStage) {
        errorMessage = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            stage = nextStage
        }
    }

    private func startInvite() {
        do {
            let url = try model.startInvitePairing()
            move(to: .invite(url, existing: false))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func useScannedURL() {
        guard let scannedURL else { return }
        self.scannedURL = nil
        completePairing(scannedURL)
    }

    private func completePairing(_ url: String) {
        do {
            try model.completePairing(fromURLString: url.trimmingCharacters(in: .whitespacesAndNewlines))
            move(to: .completion(.partnerB))
        } catch is PairingPayloadError {
            errorMessage = "招待URLを読み取れません。相手のOurHoursに表示された招待URL全体を確認してください。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InviteCodeCard: View {
    let inviteURL: String
    let isTogether: Bool
    @State private var qrImage: CGImage?
    @State private var copied = false

    var body: some View {
        ReleaseBubbleCard(title: "相手を招待する", isTogether: isTogether, seed: 2.1) {
            VStack(spacing: 12) {
                if let qrImage {
                    Image(qrImage, scale: 1, label: Text("ペア招待用QRコード"))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 210)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    Text("相手のOurHoursでこのQRコードを読み取ってね。")
                        .font(FoamFont.regular(14, relativeTo: .footnote))
                        .multilineTextAlignment(.center)
                } else {
                    Text("QRコードを表示できません。招待URLを使用してください。")
                        .font(FoamFont.medium(14, relativeTo: .footnote))
                    Text(inviteURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button(copied ? "招待URLをコピーしました" : "招待URLをコピー", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.setItems(
                        [["public.utf8-plain-text": inviteURL]],
                        options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(300)]
                    )
                    copied = true
                }
                .buttonStyle(FoamCardActionStyle(fullWidth: false))
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: inviteURL, initial: true) {
            qrImage = PairingPayloadCodec.generateQRCodeCGImage(from: inviteURL)
        }
    }
}

private struct PairingCompletionForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nickname: String
    @State private var anniversary: CalendarDateValue?
    @State private var didEditAnniversary = false

    let role: PeerRole
    let actionTitle: String
    let onFinish: () -> Void

    init(role: PeerRole, nickname: String, anniversary: CalendarDateValue?, actionTitle: String, onFinish: @escaping () -> Void) {
        self.role = role
        self.actionTitle = actionTitle
        self.onFinish = onFinish
        _nickname = State(initialValue: nickname)
        _anniversary = State(initialValue: role == .partnerA ? (anniversary ?? CalendarDateValue(date: .now)) : anniversary)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("ふたりのプロフィール")
                .font(FoamFont.bold(25, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            ReleaseBubbleCard(title: "相手の呼び方", isTogether: model.isTogetherNow, seed: 2.1) {
                TextField("ニックネーム（任意）", text: $nickname)
                    .accessibilityLabel("相手の呼び方（任意）")
                    .textFieldStyle(.roundedBorder)
            }

            if role == .partnerA {
                FoamSoftCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("付き合った日（記念日）", isOn: Binding(
                            get: { anniversary != nil },
                            set: { enabled in
                                didEditAnniversary = true
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    anniversary = enabled ? CalendarDateValue(date: .now) : nil
                                }
                            }
                        ))
                        .toggleStyle(SoapBubbleToggleStyle(isTogether: model.isTogetherNow))
                        if anniversary != nil {
                            DatePicker("記念日", selection: Binding(
                                get: { min(anniversary?.toDate() ?? .now, .now) },
                                set: {
                                    didEditAnniversary = true
                                    anniversary = CalendarDateValue(date: $0)
                                }
                            ), in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        }
                    }
                }
            }

            Button(actionTitle) {
                model.setPartnerNickname(nickname)
                if role == .partnerA {
                    if let anniversary, didEditAnniversary || anniversary != model.anniversaryDate {
                        model.setAnniversaryDate(anniversary)
                    } else if anniversary == nil, didEditAnniversary, model.anniversaryDate != nil {
                        model.setAnniversaryDate(nil)
                    }
                }
                onFinish()
            }
            .buttonStyle(FoamPrimaryActionStyle())
        }
        .onChange(of: model.anniversaryDate) {
            if !didEditAnniversary, let synced = model.anniversaryDate { anniversary = synced }
        }
    }
}

struct FoamCardActionStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FoamFont.bold(15, relativeTo: .subheadline))
            .multilineTextAlignment(.center)
            .foregroundStyle(FoamTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background {
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.56 : 0.78))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
                    }
                    .shadow(color: FoamTheme.ink.opacity(0.06), radius: 5, y: 2)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct FoamPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FoamFont.bold(16, relativeTo: .body))
            .multilineTextAlignment(.center)
            .foregroundStyle(FoamTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                SoapBubbleSurface(prominence: .vivid, seed: 2.7, wobbleScale: 0.35, animated: false)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.5)
    }
}
