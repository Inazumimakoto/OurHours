import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showPairing = false
    @State private var confirmUnpair = false
    @State private var confirmClear = false

    var body: some View {
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
            Section("診断") {
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
