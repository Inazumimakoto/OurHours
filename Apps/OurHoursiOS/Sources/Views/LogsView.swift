import OurHoursCore
import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var category: EventCategory?
    @State private var query = ""

    var body: some View {
        List {
            Section {
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
                let events = model.snapshot.recentEvents.filter {
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
        .navigationTitle("ログ")
    }

    private func exportLink(_ title: String, format: LogExport.Format) -> some View {
        ShareLink(item: model.export(format), preview: SharePreview(format.rawValue)) {
            Label(title, systemImage: "square.and.arrow.up")
        }
    }
}
