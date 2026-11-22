import OurHoursCore
import SwiftUI
import UIKit

struct LogsView: View {
    var showsCloseButton: Bool = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var category: EventCategory?
    @State private var query = ""
    @State private var didCopySummary = false

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        let state = model.snapshot
        List {
            Section {
                statusRow("アプリ", value: appVersionText)
                statusRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "不明")
                if let pair = state.pairConfiguration {
                    statusRow(
                        "ペア状態",
                        value: "ペア済み（\(pair.localRole.shortCode)・世代 \(pair.keyEpoch)・ID \(String(pair.pairID.uuidString.prefix(8)))）"
                    )
                } else {
                    statusRow("ペア状態", value: "未設定")
                }
                statusRow("Bluetooth", value: "C:\(state.centralState) / P:\(state.peripheralState)")
                statusRow(
                    "探索 / 広告",
                    value: "\(state.isScanning ? "探索中" : "停止") / \(state.isAdvertising ? "広告中" : "停止")（リンク \(state.activeLinkCount)）"
                )
                statusRow("最終認証", value: state.lastAuthDate?.formatted(date: .numeric, time: .shortened) ?? "未認証")
                if let error = state.lastErrorMessage {
                    statusRow("直近エラー", value: error)
                }
                statusRow("CloudKit 保存先", value: model.pairSpaceStatusText.replacingOccurrences(of: "\n", with: " / "))
                statusRow("履歴同期", value: model.historySyncStatusText)
                statusRow("位置補完", value: "\(model.locationMonitor.statusDescription) / 一致 \(model.locationMatchedSessions.count)件")
                statusRow("位置同期", value: model.locationSyncStatusText)
            } header: {
                Text("現在の状態").font(FoamFont.bold(13, relativeTo: .footnote))
            }

            Section {
                Button {
                    UIPasteboard.general.string = model.diagnosticSummaryText()
                    didCopySummary = true
                } label: {
                    HStack {
                        Label(
                            didCopySummary ? "診断サマリーをコピーしました" : "診断サマリーをコピー",
                            systemImage: didCopySummary ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        Spacer()
                    }
                }
                exportLink("すべてのログ（JSON）", format: .json)
                exportLink("記録区間（CSV）", format: .sessions)
                exportLink("イベント（CSV）", format: .events)
            } header: {
                Text("全件を書き出す").font(FoamFont.bold(13, relativeTo: .footnote))
            }

            Section {
                Picker("カテゴリ", selection: $category) {
                    Text("すべて").tag(nil as EventCategory?)
                    ForEach(EventCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                let events = state.recentEvents.filter {
                    (category == nil || $0.category == category)
                        && (query.isEmpty || $0.kind.localizedCaseInsensitiveContains(query)
                            || $0.message.localizedCaseInsensitiveContains(query))
                }.sorted { $0.timestamp > $1.timestamp }
                if events.isEmpty {
                    Text("該当するイベントはありません").foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.kind).font(FoamFont.bold(17, relativeTo: .headline))
                        Text(event.message).font(FoamFont.regular(15))
                        Text("\(event.category.rawValue) · \(event.timestamp.formatted(date: .numeric, time: .standard))")
                            .foregroundStyle(.secondary)
                            .font(FoamFont.regular(12, relativeTo: .caption))
                    }
                }
            } header: {
                Text("診断イベント").font(FoamFont.bold(13, relativeTo: .footnote))
            }
        }
        .font(FoamFont.medium(16))
        .searchable(text: $query, prompt: "種類・メッセージで検索")
        .navigationTitle("診断ログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(FoamFont.medium(14, relativeTo: .subheadline))
            Spacer(minLength: 8)
            Text(value)
                .font(FoamFont.regular(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func exportLink(_ title: String, format: LogExport.Format) -> some View {
        ShareLink(item: model.export(format), preview: SharePreview(format.rawValue)) {
            Label(title, systemImage: "square.and.arrow.up")
        }
    }
}
