import OurHoursCore
import SwiftUI

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var manualURL = ""
    @State private var invite: String?
    @State private var qrImage: CGImage?
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var scannedURL: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bluetoothとプライバシー") {
                    Text("画面を閉じている間も、ペアのiPhoneが近くにあった日と時間を推定して記録・共有します")
                    Text("この検証版では記録を端末内に保存します。自動記録は設定で停止できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("相手を招待する") {
                    if let invite {
                        if let qrImage {
                            Image(decorative: qrImage, scale: 1).interpolation(.none).resizable()
                                .scaledToFit().padding(20).background(.white)
                                .accessibilityLabel("ペア招待用QRコード")
                        }
                        Text(invite).font(.caption.monospaced()).textSelection(.enabled)
                        Button("招待URLをコピー") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": invite]],
                                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(300)])
                        }
                    } else if !model.snapshot.isPaired {
                        Button("同意して招待QRコードを作成") {
                            do { display(try model.startInvitePairing()) }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                if invite == nil && !model.snapshot.isPaired {
                    Section("相手の招待で設定する") {
                        Button("同意してQRコードを読み取る") { showScanner = true }
                        TextField("ourhours://… を貼り付け", text: $manualURL, axis: .vertical)
                            .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("同意して招待URLで設定") { complete(manualURL) }
                            .disabled(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            .navigationTitle("ペア設定")
            .toolbar { Button("閉じる") { dismiss() } }
            .onAppear {
                if invite == nil, let config = model.snapshot.pairConfiguration, config.localRole == .partnerA {
                    display(PairingPayloadCodec.encode(config, for: .partnerB))
                }
            }
            .sheet(isPresented: $showScanner, onDismiss: {
                if let scannedURL { self.scannedURL = nil; complete(scannedURL) }
            }) {
                QRScannerView { value in scannedURL = value; showScanner = false }
            }
        }
    }

    private func display(_ value: String) {
        invite = value
        qrImage = PairingPayloadCodec.generateQRCodeCGImage(from: value)
        errorMessage = qrImage == nil ? "QRコードを表示できません。招待URLを使用してください。" : nil
    }

    private func complete(_ value: String) {
        do {
            try model.completePairing(fromURLString: value)
            dismiss()
        } catch is PairingPayloadError {
            errorMessage = "招待URLを読み取れません。相手のOurHoursに表示された招待URL全体を確認してください。"
        } catch { errorMessage = error.localizedDescription }
    }
}
