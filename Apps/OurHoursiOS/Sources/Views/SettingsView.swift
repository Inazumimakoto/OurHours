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
            Section("記録") {
                Toggle("自動記録", isOn: Binding(
                    get: { model.isAutoRecordingEnabled }, set: { model.setAutoRecordingEnabled($0) }
                ))
            }
            Section("ペア設定") {
                if let pair = model.snapshot.pairConfiguration {
                    LabeledContent("ペアID", value: String(pair.pairID.uuidString.prefix(8)))
                    LabeledContent("この端末の役割", value: pair.localRole.shortCode)
                    LabeledContent("鍵の世代", value: String(pair.keyEpoch))
                    LabeledContent("設定日時", value: pair.createdAt.formatted())
                    if pair.localRole == .partnerA {
                        Button("招待QRコードを表示") { showPairing = true }
                    }
                    Button("ペア連携を解除（機種変更・再設定）", role: .destructive) { confirmUnpair = true }
                        .confirmationDialog("ペア連携を解除しますか？", isPresented: $confirmUnpair, titleVisibility: .visible) {
                            Button("解除する", role: .destructive) { model.unpair() }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("この端末での今後の認証と自動記録を直ちに停止します。双方の端末に保存済みのログは残ります。機種変更時は新しいiPhoneで新規の招待を作り、相手と再設定してください。再設定後、旧端末の鍵では認証できません。")
                        }
                } else {
                    Text("未設定")
                    Button("ペアを設定する") { showPairing = true }
                }
            }
            Section("Bluetooth") {
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
                }
            }
            Section("診断") {
                NavigationLink("BLE 診断ログ・書き出し") { LogsView() }
                Button("デバッグログを消去", role: .destructive) { confirmClear = true }
                    .confirmationDialog("この端末のログを消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("消去する", role: .destructive) { model.clearLogs() }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("記録中の区間を含め、保存した記録区間と診断イベントをすべて消去します。この操作は取り消せません。")
                    }
            }
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showPairing) { PairingView() }
    }
}

private struct StatusBadge: View {
    let title: String
    let active: Bool
    var body: some View {
        Text(title).font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
    }
}
