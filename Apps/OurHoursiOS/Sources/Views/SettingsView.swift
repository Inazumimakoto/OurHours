import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showPairing = false
    @State private var confirmUnpair = false
    @State private var confirmClear = false

    var body: some View {
        let state = model.snapshot
        Form {
            Section {
                Toggle("自動記録", isOn: Binding(
                    get: { model.isAutoRecordingEnabled }, set: { model.setAutoRecordingEnabled($0) }
                ))
            } header: {
                Text("記録").font(FoamFont.bold(13, relativeTo: .footnote))
            }
            Section {
                LabeledContent("同期状態") {
                    Text(model.historySyncStatusText)
                        .font(FoamFont.medium(13, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("相手のBLE記録", value: "\(model.syncedPeerSessionCount)件")
                Button("今すぐ記録・メモを同期") {
                    Task { await model.syncSharedHistoryNow() }
                }
                .font(FoamFont.bold(15))
                .disabled(model.isHistorySyncing || !model.snapshot.isPaired)
                Text("片方しか検知できなかった BLE 記録・終了不明の自動補完・手動編集・一言メモを、ペアの共有鍵で E2EE 暗号化して CloudKit 経由で同期します。")
                    .font(FoamFont.regular(12.5, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            } header: {
                Text("ふたりで記録・メモを同期（CloudKit）").font(FoamFont.bold(13, relativeTo: .footnote))
            }
            Section {
                Toggle("位置情報で取りこぼしを補完", isOn: Binding(
                    get: { model.locationMonitor.isEnabled },
                    set: { enabled in
                        if enabled {
                            model.locationMonitor.enableAndRequestAuthorization()
                            Task { await model.syncLocationNow(requestFreshFix: true) }
                        } else {
                            model.locationMonitor.disable()
                        }
                    }
                ))
                LabeledContent("取得状態") {
                    Text(model.locationMonitor.statusDescription)
                        .font(FoamFont.medium(13, relativeTo: .caption))
                        .foregroundStyle(model.locationMonitor.isReducedAccuracyWarning ? .orange : .secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let lastCapture = model.locationMonitor.lastCaptureDate {
                    LabeledContent("直近の位置取得", value: lastCapture.formatted())
                }
                LabeledContent("CloudKit 同期") {
                    Text(model.locationSyncStatusText)
                        .font(FoamFont.medium(13, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("位置補完で一致", value: "\(model.locationMatchedSessions.count)件")
                Button("今すぐ位置情報を同期・突き合わせ") {
                    Task { await model.syncLocationNow(requestFreshFix: true) }
                }
                .font(FoamFont.bold(15))
                .disabled(model.isLocationSyncing || !model.snapshot.isPaired || !model.locationMonitor.isEnabled)
                Text("ペアの共有鍵で暗号化した滞在ログだけを CloudKit 経由で突き合わせ、Bluetooth が切れた時間帯を自動補完します。地図や座標の画面共有は行わず、生の座標は 14 日で自動削除されます。")
                    .font(FoamFont.regular(12.5, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                if model.locationMonitor.needsSettingsGuidance {
                    Button("設定で「常に」＋「正確な位置情報オン」を確認") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(FoamFont.bold(14))
                }
            } header: {
                Text("位置情報による取りこぼし補完（正確な位置 × CloudKit）").font(FoamFont.bold(13, relativeTo: .footnote))
            }
            Section {
                if let pair = model.snapshot.pairConfiguration {
                    LabeledContent("ペアID", value: String(pair.pairID.uuidString.prefix(8)))
                    LabeledContent("この端末の役割", value: pair.localRole.shortCode)
                    LabeledContent("鍵の世代", value: String(pair.keyEpoch))
                    LabeledContent("設定日時", value: pair.createdAt.formatted())
                    if pair.localRole == .partnerA {
                        Button("招待QRコードを表示") { showPairing = true }
                            .font(FoamFont.bold(16))
                    }
                    Button("ペア連携を解除（機種変更・再設定）", role: .destructive) { confirmUnpair = true }
                        .font(FoamFont.bold(16))
                        .confirmationDialog("ペア連携を解除しますか？", isPresented: $confirmUnpair, titleVisibility: .visible) {
                            Button("解除する", role: .destructive) { model.unpair() }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("この端末での今後の認証と自動記録を直ちに停止します。双方の端末に保存済みのログは残ります。機種変更時は新しいiPhoneで新規の招待を作り、相手と再設定してください。再設定後、旧端末の鍵では認証できません。")
                        }
                } else {
                    Text("未設定")
                    Button("ペアを設定する") { showPairing = true }
                        .font(FoamFont.bold(16))
                }
            } header: {
                Text("ペア設定").font(FoamFont.bold(13, relativeTo: .footnote))
            }
            Section {
                LabeledContent("Central", value: state.centralState)
                LabeledContent("Peripheral", value: state.peripheralState)
                HStack {
                    StatusBadge(title: state.isScanning ? "探索中" : "探索停止", active: state.isScanning)
                    StatusBadge(title: state.isAdvertising ? "広告中" : "広告停止", active: state.isAdvertising)
                }
                LabeledContent("認証済みリンク", value: String(state.activeLinkCount))
                ForEach(state.activeLinksSummary, id: \.self) { Text($0).font(.caption.monospaced()) }
                LabeledContent(state.activeSession == nil ? "直近の接続経路" : "接続経路") {
                    if let path = state.activeSession?.connectionPath ?? state.lastConnectionPath {
                        StatusBadge(title: path.rawValue, active: state.activeSession != nil)
                    } else { Text("未接続") }
                }
                LabeledContent("最終認証", value: state.lastAuthDate?.formatted() ?? "未認証")
                if let error = state.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if state.centralState == "unauthorized" || state.peripheralState == "unauthorized" {
                    Label("自動記録にはBluetoothの許可が必要です。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(FoamFont.bold(16))
                }
            } header: {
                Text("Bluetooth").font(FoamFont.bold(13, relativeTo: .footnote))
            }
            Section {
                NavigationLink("BLE 診断ログ・書き出し") { LogsView() }
                Button("デバッグログを消去", role: .destructive) { confirmClear = true }
                    .font(FoamFont.bold(16))
                    .confirmationDialog("この端末のログを消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("消去する", role: .destructive) { model.clearLogs() }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("記録中の区間を含め、保存した記録区間と診断イベントをすべて消去します。この操作は取り消せません。")
                    }
            } header: {
                Text("診断").font(FoamFont.bold(13, relativeTo: .footnote))
            }
        }
        .font(FoamFont.medium(16))
        .navigationTitle("設定")
        .sheet(isPresented: $showPairing) { PairingView() }
    }
}

private struct StatusBadge: View {
    let title: String
    let active: Bool
    var body: some View {
        Text(title)
            .font(FoamFont.bold(12, relativeTo: .caption))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
    }
}
