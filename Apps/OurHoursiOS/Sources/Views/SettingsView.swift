import OurHoursCore
import SwiftUI
import UIKit

struct SettingsView: View {
    var onReplayOnboarding: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showPairing = false
    @State private var confirmUnpair = false
    #if DEBUG
    @State private var confirmClear = false
    #endif

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        let state = model.snapshot
        ZStack {
            FoamTheme.sky(together: model.isTogetherNow)
                .ignoresSafeArea()
            FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        releasePairingSection
                        releaseProfileSection
                        releaseRecordingAndSyncSection(state: state)
                        releaseSupportSection
                        releaseVersionRow
                        if state.isPaired {
                            Button("ペア連携を解除（機種変更・再設定）", role: .destructive) {
                                confirmUnpair = true
                            }
                            .font(FoamFont.medium(12.5, relativeTo: .caption))
                            .foregroundStyle(Color.red.opacity(0.65))
                            .padding(.top, 2)
                            .padding(.bottom, 4)
                            .confirmationDialog("ペア連携を解除しますか？", isPresented: $confirmUnpair, titleVisibility: .visible) {
                                Button("解除する", role: .destructive) { model.unpair() }
                                Button("キャンセル", role: .cancel) {}
                            } message: {
                                Text("この端末での今後の認証と自動記録を直ちに停止します。双方の端末に保存済みのログは残ります。機種変更時は新しいiPhoneで新規の招待を作り、相手と再設定してください。再設定後、旧端末の鍵では認証できません。")
                            }
                        }
                        #if DEBUG
                        if ScreenshotScene.current == nil {
                            debugSection(state: state)
                        }
                        #endif
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
            }
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPairing) { PairingView() }
    }

    private var pairingStatusLabel: String {
        let name = model.partnerNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return model.isTogetherNow ? "いま一緒にいるよ" : "ペア連携中"
        }
        return model.isTogetherNow ? "\(name)と今一緒にいるよ" : "\(name)とペア連携中"
    }

    private var releaseProfileSection: some View {
        ReleaseBubbleCard(title: "プロフィールと記念日", isTogether: model.isTogetherNow, seed: 2.1) {
            VStack(alignment: .leading, spacing: 12) {
                Text("自分のシャボン玉")
                    .font(FoamFont.bold(15, relativeTo: .subheadline))
                BubbleColorSwatches(selection: model.localBubbleColor, onSelect: model.setLocalBubbleColor)

                Divider()
                OptionalProfileDateRow(
                    title: "自分の誕生日",
                    showsTodayButton: false,
                    date: Binding(get: { model.localBirthday }, set: { model.setLocalBirthday($0) })
                )

                Divider()
                OptionalProfileDateRow(
                    title: "記念日",
                    date: Binding(get: { model.anniversaryDate }, set: { model.setAnniversaryDate($0) })
                )

                Divider()
                calendarMarkSettingsLink
            }
        }
    }

    private var calendarMarkSettingsLink: some View {
        let anniversary = model.anniversaryMarkStyle
        let mine = model.myBirthdayMarkStyle
        let partner = model.partnerBirthdayMarkStyle

        return NavigationLink {
            CalendarMarkSettingsView()
        } label: {
            HStack(spacing: 8) {
                Text("カレンダーの印")
                    .font(FoamFont.bold(15, relativeTo: .subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    CalendarMarkIcon(symbolName: anniversary.symbolName, tint: anniversary.tintColor)
                    CalendarMarkIcon(symbolName: mine.symbolName, tint: mine.tintColor(for: model.localBubbleColor))
                    CalendarMarkIcon(symbolName: partner.symbolName, tint: partner.tintColor(for: model.partnerBubbleColor))
                }
                .font(.system(size: 13, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FoamTheme.ink.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("記念日 \(anniversary.displayName)、自分の誕生日 \(mine.displayName)、相手の誕生日 \(partner.displayName)")
    }

    // MARK: - Top Navigation

    private var topBar: some View {
        ZStack {
            Text("設定")
                .font(FoamFont.bold(20, relativeTo: .title3))
                .foregroundStyle(FoamTheme.ink)
            HStack {
                Spacer()
                FoamRoundIconButton(size: 40, accessibilityLabel: "閉じる") {
                    dismiss()
                } icon: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FoamTheme.ink.opacity(0.82))
                }
            }
        }
    }

    // MARK: - Region 1: Release Settings UI

    private var releasePairingSection: some View {
        ReleaseBubbleCard(title: "ペア", isTogether: model.isTogetherNow, seed: 1.4) {
            if let pair = model.snapshot.pairConfiguration {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(pairingStatusLabel)
                            .font(FoamFont.bold(12.5, relativeTo: .caption))
                            .foregroundStyle(model.isTogetherNow ? FoamTheme.warmAccent : FoamTheme.ink)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(model.isTogetherNow ? FoamTheme.cream.opacity(0.92) : Color.white.opacity(0.68))
                            )
                        Spacer(minLength: 8)
                        Text("累計 \(FoamTheme.duration(model.lifetimeRecordedSeconds()))")
                            .font(FoamFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(FoamTheme.ink)
                    }

                    Text("\(pair.createdAt.formatted(date: .long, time: .omitted)) から記録中")
                        .font(FoamFont.regular(12.5, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.ink.opacity(0.64))

                    Divider().overlay(FoamTheme.ink.opacity(0.08))

                    NavigationLink {
                        PartnerNicknameEditView()
                    } label: {
                        HStack(spacing: 8) {
                            Text("相手の呼び方")
                                .font(FoamFont.bold(15, relativeTo: .subheadline))
                                .foregroundStyle(FoamTheme.ink)
                            Spacer(minLength: 8)
                            Text(model.partnerNickname.isEmpty ? "未設定" : model.partnerNickname)
                                .font(FoamFont.regular(14, relativeTo: .subheadline))
                                .foregroundStyle(FoamTheme.ink.opacity(0.68))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(FoamTheme.ink.opacity(0.45))
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if pair.localRole == .partnerA {
                        Button("招待QRコードを表示") { showPairing = true }
                            .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("パートナーとペア設定すると、一緒にいた時間を自動で残せます")
                        .font(FoamFont.regular(13.5, relativeTo: .footnote))
                        .foregroundStyle(FoamTheme.ink.opacity(0.74))
                    Button("ペアを設定する") { showPairing = true }
                        .buttonStyle(FoamCardActionStyle(fullWidth: false))
                }
            }
        }
    }

    @ViewBuilder
    private func releaseRecordingAndSyncSection(state: EngineSnapshot) -> some View {
        let isAnySyncing = model.isHistorySyncing || model.isLocationSyncing

        ReleaseBubbleCard(title: "自動記録と同期", isTogether: model.isTogetherNow, seed: 2.8) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { model.isAutoRecordingEnabled },
                    set: { model.setAutoRecordingEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自動記録")
                            .font(FoamFont.bold(15.5, relativeTo: .body))
                        Text("近くにいる時間を自動で記録します")
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.64))
                    }
                }
                .toggleStyle(SoapBubbleToggleStyle(isTogether: model.isTogetherNow, seed: 1.3))

                Divider().overlay(FoamTheme.ink.opacity(0.08))

                Toggle(isOn: Binding(
                    get: { model.locationMonitor.isEnabled },
                    set: { enabled in
                        if enabled {
                            model.locationMonitor.enableAndRequestAuthorization()
                            Task { await model.syncLocationNow(requestFreshFix: true) }
                        } else {
                            model.locationMonitor.disable()
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("位置情報で精度を上げる")
                            .font(FoamFont.bold(15.5, relativeTo: .body))
                        Text("記録の取りこぼしを防ぎます")
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.64))
                    }
                }
                .toggleStyle(SoapBubbleToggleStyle(isTogether: model.isTogetherNow, seed: 2.9))

                if state.centralState == "unauthorized" || state.peripheralState == "unauthorized" {
                    Divider().overlay(FoamTheme.ink.opacity(0.08))
                    VStack(alignment: .leading, spacing: 8) {
                        Label("自動記録にはBluetoothの許可が必要です", systemImage: "exclamationmark.triangle.fill")
                            .font(FoamFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(.red)
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    }
                }

                if model.locationMonitor.needsSettingsGuidance {
                    Divider().overlay(FoamTheme.ink.opacity(0.08))
                    VStack(alignment: .leading, spacing: 8) {
                        Label("位置情報の許可を「常に」にすると精度が上がります", systemImage: "location.slash")
                            .font(FoamFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.warmAccent)
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    }
                }

                Divider().overlay(FoamTheme.ink.opacity(0.08))

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ふたりで同期")
                            .font(FoamFont.bold(15.5, relativeTo: .body))
                        Text(releaseSyncLabel(isPaired: state.isPaired, isAnySyncing: isAnySyncing))
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.64))
                    }
                    Spacer(minLength: 8)
                    Button("今すぐ同期") {
                        Task {
                            await model.syncSharedHistoryNow()
                            if model.locationMonitor.isEnabled {
                                await model.syncLocationNow(requestFreshFix: true)
                            }
                        }
                    }
                    .buttonStyle(FoamCardActionStyle(fullWidth: false))
                    .disabled(isAnySyncing || !state.isPaired)
                    .opacity((isAnySyncing || !state.isPaired) ? 0.5 : 1)
                }
            }
        }
    }

    private func releaseSyncLabel(isPaired: Bool, isAnySyncing: Bool) -> String {
        if isAnySyncing { return "同期中…" }
        switch model.historySyncState {
        case .idle:
            return isPaired ? "記録やメモを揃えます" : "ペア設定後に使えます"
        case .syncing:
            return "同期中…"
        case let .synced(date, _):
            return "\(date.formatted(date: .omitted, time: .shortened)) に同期済み"
        case .unavailable, .failed:
            return "あとで自動で同期します"
        }
    }

    private var releaseSupportSection: some View {
        ReleaseBubbleCard(title: "サポート・規約", isTogether: model.isTogetherNow, seed: 3.5) {
            VStack(alignment: .leading, spacing: 4) {
                if let onReplayOnboarding {
                    Button(action: onReplayOnboarding) {
                        HStack(spacing: 8) {
                            Text("はじめかたを見る")
                                .font(FoamFont.bold(15, relativeTo: .subheadline))
                                .foregroundStyle(FoamTheme.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(FoamTheme.ink.opacity(0.45))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(FoamTheme.ink.opacity(0.08))
                }

                supportExternalLink(
                    title: "プライバシーポリシー",
                    url: URL(string: "https://inazumimakoto.github.io/OurHours/privacy.html")!
                )

                Divider().overlay(FoamTheme.ink.opacity(0.08))

                supportExternalLink(
                    title: "サポート・お問い合わせ",
                    url: URL(string: "https://inazumimakoto.github.io/OurHours/support.html")!
                )
            }
        }
    }

    private func supportExternalLink(title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Text(title)
                    .font(FoamFont.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FoamTheme.ink.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var releaseVersionRow: some View {
        HStack {
            Text("バージョン")
                .font(FoamFont.medium(14, relativeTo: .subheadline))
                .foregroundStyle(FoamTheme.ink.opacity(0.76))
            Spacer()
            Text(appVersionLabel)
                .font(FoamFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(FoamTheme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(20),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 4.1,
                wobbleScale: 0.35,
                animated: false
            )
        }
    }

    // MARK: - Region 2: Plain Debug Section (Unstyled Developer Controls)

    #if DEBUG
    @ViewBuilder
    private func debugSection(state: EngineSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEBUG（開発・検証用）")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(FoamTheme.ink.opacity(0.55))
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                // 1. ペア内部情報
                debugBlock(title: "ペア内部情報") {
                    if let pair = state.pairConfiguration {
                        debugRow("ペアID", value: String(pair.pairID.uuidString.prefix(8)))
                        Divider()
                        debugRow("この端末の役割", value: pair.localRole.shortCode)
                        Divider()
                        debugRow("鍵の世代", value: String(pair.keyEpoch))
                        Divider()
                        debugRow("設定日時", value: pair.createdAt.formatted())
                    } else {
                        Text("未設定")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // 2. 記録・メモ同期（CloudKit）
                debugBlock(title: "記録・メモを同期（CloudKit）") {
                    debugRow("同期状態", value: model.historySyncStatusText)
                    Divider()
                    debugRow("保存先", value: model.pairSpaceStatusText)
                    Divider()
                    debugRow("相手のBLE記録", value: "\(model.syncedPeerSessionCount)件")
                    Divider()
                    Button("今すぐ記録・メモを同期") {
                        Task { await model.syncSharedHistoryNow() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(model.isHistorySyncing || !state.isPaired)
                }

                // 3. 位置情報補完デバッグ
                debugBlock(title: "位置情報補完デバッグ") {
                    HStack(alignment: .top) {
                        Text("取得状態")
                            .font(.subheadline)
                        Spacer(minLength: 12)
                        Text(model.locationMonitor.statusDescription)
                            .font(.caption)
                            .foregroundStyle(model.locationMonitor.isReducedAccuracyWarning ? .orange : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if let lastCapture = model.locationMonitor.lastCaptureDate {
                        Divider()
                        debugRow("直近の位置取得", value: lastCapture.formatted())
                    }
                    Divider()
                    debugRow("CloudKit 同期", value: model.locationSyncStatusText)
                    Divider()
                    debugRow("位置補完で一致", value: "\(model.locationMatchedSessions.count)件")
                    Divider()
                    Button("今すぐ位置情報を同期・突き合わせ") {
                        Task { await model.syncLocationNow(requestFreshFix: true) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .disabled(model.isLocationSyncing || !state.isPaired || !model.locationMonitor.isEnabled)
                }

                // 4. Bluetooth
                debugBlock(title: "Bluetooth") {
                    debugRow("Central", value: state.centralState)
                    Divider()
                    debugRow("Peripheral", value: state.peripheralState)
                    Divider()
                    HStack(spacing: 8) {
                        StatusBadge(title: state.isScanning ? "探索中" : "探索停止", active: state.isScanning)
                        StatusBadge(title: state.isAdvertising ? "広告中" : "広告停止", active: state.isAdvertising)
                    }
                    Divider()
                    debugRow("認証済みリンク", value: String(state.activeLinkCount))
                    ForEach(state.activeLinksSummary, id: \.self) { summary in
                        Text(summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text(state.activeSession == nil ? "直近の接続経路" : "接続経路")
                            .font(.subheadline)
                        Spacer()
                        if let path = state.activeSession?.connectionPath ?? state.lastConnectionPath {
                            StatusBadge(title: path.rawValue, active: state.activeSession != nil)
                        } else {
                            Text("未接続")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    debugRow("最終認証", value: state.lastAuthDate?.formatted() ?? "未認証")
                    if let error = state.lastErrorMessage {
                        Divider()
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // 5. 診断
                debugBlock(title: "診断") {
                    if let onReplayOnboarding {
                        Button("オンボードをもう一度見る", action: onReplayOnboarding)
                            .font(.subheadline.weight(.semibold))
                        Divider()
                    }
                    NavigationLink {
                        LogsView()
                    } label: {
                        HStack {
                            Text("BLE 診断ログ・書き出し")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                    Button("デバッグログを消去", role: .destructive) {
                        confirmClear = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .confirmationDialog("この端末のログを消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("消去する", role: .destructive) { model.clearLogs() }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("記録中の区間を含め、保存した記録区間と診断イベントをすべて消去します。この操作は取り消せません。")
                    }
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    }
            }
            .font(.system(.subheadline))
            .foregroundStyle(Color.primary)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func debugBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func debugRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
    #endif
}

private struct PartnerNicknameEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nicknameDraft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            FoamTheme.sky(together: model.isTogetherNow)
                .ignoresSafeArea()
            FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Text("相手の呼び方")
                        .font(FoamFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(FoamTheme.ink)
                    HStack {
                        FoamRoundIconButton(size: 40, accessibilityLabel: "戻る") {
                            dismiss()
                        } icon: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(FoamTheme.ink.opacity(0.82))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        ReleaseBubbleCard(title: "相手の呼び方", isTogether: model.isTogetherNow, seed: 1.8) {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("ニックネーム（任意）", text: $nicknameDraft)
                                    .accessibilityLabel("相手の呼び方（任意）")
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.done)
                                    .focused($isFocused)
                                    .onSubmit(save)

                                Text("設定のペア欄に表示される呼び方です（この端末のみ保存）")
                                    .font(FoamFont.regular(12.5, relativeTo: .caption))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.64))
                            }
                        }

                        Button("保存", action: save)
                            .buttonStyle(FoamPrimaryActionStyle())

                        if !nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !model.partnerNickname.isEmpty {
                            Button("未設定にする") {
                                model.setPartnerNickname("")
                                dismiss()
                            }
                            .font(FoamFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(FoamTheme.ink.opacity(0.72))
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            nicknameDraft = model.partnerNickname
        }
    }

    private func save() {
        model.setPartnerNickname(nicknameDraft)
        dismiss()
    }
}

private struct CalendarMarkSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            FoamTheme.sky(together: model.isTogetherNow)
                .ignoresSafeArea()
            FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        markCard(
                            title: "記念日の印",
                            seed: 1.8,
                            styles: AnniversaryMarkStyle.allCases,
                            selection: model.anniversaryMarkStyle,
                            onSelect: model.setAnniversaryMarkStyle
                        ) { style in
                            (style.displayName, style.symbolName, style.tintColor)
                        }

                        markCard(
                            title: "自分の誕生日の印",
                            seed: 2.1,
                            styles: BirthdayMarkStyle.allCases,
                            selection: model.myBirthdayMarkStyle,
                            onSelect: model.setMyBirthdayMarkStyle
                        ) { style in
                            (style.displayName, style.symbolName, style.tintColor(for: model.localBubbleColor))
                        }

                        markCard(
                            title: "相手の誕生日の印",
                            seed: 2.8,
                            styles: BirthdayMarkStyle.allCases,
                            selection: model.partnerBirthdayMarkStyle,
                            onSelect: model.setPartnerBirthdayMarkStyle
                        ) { style in
                            (style.displayName, style.symbolName, style.tintColor(for: model.partnerBubbleColor))
                        }

                        Text("バレンタイン・ホワイトデー・クリスマスは自動で表示されます。印の設定はこの端末ごとに保存されます。")
                            .font(FoamFont.regular(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.68))
                            .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
        }
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            FoamRoundIconButton(size: 40, accessibilityLabel: "戻る") {
                dismiss()
            } icon: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FoamTheme.ink.opacity(0.82))
            }
            Text("カレンダーの印")
                .font(FoamFont.bold(20, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Color.clear
                .frame(width: 40, height: 1)
                .accessibilityHidden(true)
        }
    }

    private func markCard<Style: Identifiable & Equatable>(
        title: String,
        seed: Double,
        styles: [Style],
        selection: Style,
        onSelect: @escaping (Style) -> Void,
        appearance: @escaping (Style) -> (title: String, symbolName: String?, tint: Color)
    ) -> some View {
        ReleaseBubbleCard(title: title, isTogether: model.isTogetherNow, seed: seed) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(styles) { style in
                    let mark = appearance(style)
                    let isSelected = selection == style
                    Button {
                        onSelect(style)
                    } label: {
                        VStack(spacing: 4) {
                            CalendarMarkIcon(symbolName: mark.symbolName, tint: mark.tint)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(height: 20)
                            Text(mark.title)
                                .font(FoamFont.bold(12.5, relativeTo: .caption))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Color.white.opacity(isSelected ? 0.86 : 0.52), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(isSelected ? FoamTheme.ink.opacity(0.36) : Color.white.opacity(0.72), lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(6)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)、\(mark.title)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

private struct CalendarMarkIcon: View {
    let symbolName: String?
    let tint: Color

    var body: some View {
        Image(systemName: symbolName ?? "circle.slash")
            .foregroundStyle(symbolName == nil ? FoamTheme.ink.opacity(0.60) : tint)
            .accessibilityHidden(true)
    }
}

struct OptionalProfileDateRow: View {
    let title: String
    var unsetTitle: String? = nil
    var clearTitle = "クリア"
    var showsClearButton = true
    var showsTodayButton = true
    @Binding var date: CalendarDateValue?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                setExpanded(!expanded)
            } label: {
                HStack(spacing: 8) {
                    Text(date == nil ? (unsetTitle ?? title) : title)
                    Spacer(minLength: 4)
                    if date != nil || unsetTitle == nil {
                        Text(date?.formattedJapanese ?? "未設定")
                            .foregroundStyle(FoamTheme.ink.opacity(0.72))
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(FoamFont.bold(15, relativeTo: .subheadline))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "展開中" : "折りたたみ")

            if expanded {
                DatePicker(title, selection: Binding(
                    get: { min(date?.toDate() ?? .now, .now) },
                    set: { date = CalendarDateValue(date: $0) }
                ), in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.compact)

                if (showsTodayButton && date == nil) || showsClearButton {
                    HStack(spacing: 16) {
                        if showsTodayButton && date == nil {
                            Button("今日に設定") { date = CalendarDateValue(date: .now) }
                        }
                        Spacer(minLength: 4)
                        if showsClearButton {
                            Button(clearTitle) {
                                if date != nil { date = nil }
                                setExpanded(false)
                            }
                            .disabled(date == nil && unsetTitle == nil)
                        }
                    }
                    .font(FoamFont.bold(14, relativeTo: .subheadline))
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            expanded = value
        }
    }
}

struct ReleaseBubbleCard<Content: View>: View {
    let title: String
    let isTogether: Bool
    let seed: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(FoamFont.bold(13.5, relativeTo: .footnote))
                .foregroundStyle(FoamTheme.ink.opacity(0.76))
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    SoapBubbleSurface(
                        cornerStyle: .roundedRect(24),
                        prominence: .standard,
                        isTogether: isTogether,
                        seed: seed,
                        wobbleScale: 0.35,
                        animated: false
                    )
                }
        }
    }
}

#if DEBUG
private struct StatusBadge: View {
    let title: String
    let active: Bool
    var body: some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
    }
}
#endif
