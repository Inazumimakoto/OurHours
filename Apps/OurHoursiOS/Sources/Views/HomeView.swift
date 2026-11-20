import OurHoursCore
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showPairing = false
    @State private var showMerged = false

    var body: some View {
        let state = model.snapshot
        List {
            Section("ペア") {
                LabeledContent("ペア設定", value: state.isPaired ? "設定済み" : "未設定")
                if !state.isPaired {
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
            Section("最近の記録") {
                if state.sessions.isEmpty { Text("記録はまだありません").foregroundStyle(.secondary) }
                ForEach(state.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(20)) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("開始 \(session.startedAt.formatted())")
                        switch session.status {
                        case .unknownEnd:
                            Label("終了不明", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold()).padding(5)
                                .background(.orange.opacity(0.2), in: Capsule())
                        case .active: Text("記録中").foregroundStyle(.secondary)
                        case .completed:
                            if let end = session.endedAt, let seconds = session.durationSeconds {
                                Text("終了 \(end.formatted())")
                                Text("記録時間 \(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond)))")
                            }
                        }
                    }
                }
            }
            Section {
                DisclosureGroup("統合した参考区間", isExpanded: $showMerged) {
                    if showMerged {
                        let intervals = EncounterSession.mergedReferenceIntervals(from: state.sessions)
                        if intervals.isEmpty { Text("完了した区間はありません") }
                        ForEach(intervals.reversed()) { interval in
                            VStack(alignment: .leading) {
                                Text("\(interval.startedAt.formatted()) 〜 \(interval.endedAt.formatted())")
                                Text("参考時間 \(Duration.seconds(interval.durationSeconds).formatted(.time(pattern: .hourMinuteSecond)))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            } footer: {
                Text("同じペアの完了区間を、間隔が5分以内の場合にまとめて表示します。")
            }
        }
        .navigationTitle("ホーム")
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
