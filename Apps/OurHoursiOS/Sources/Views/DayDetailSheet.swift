import OurHoursCore
import SwiftUI

struct DayDetailSheet: View {
    let date: Date
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var memo = ""
    @State private var editor: EncounterEditorMode?

    var body: some View {
        let day = model.daySummary(for: date)
        NavigationStack {
            List {
                Section {
                    Text(FoamTheme.duration(day.totalRecordedSeconds))
                        .font(FoamFont.bold(32, relativeTo: .largeTitle))
                    if day.hasActiveSession {
                        Label("記録中", systemImage: "dot.radiowaves.left.and.right")
                            .font(FoamFont.medium(15))
                    }
                    if day.hasUnknownEnd {
                        Label("終了不明", systemImage: "exclamationmark.circle")
                            .font(FoamFont.medium(15))
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    TextField("この日のメモ", text: $memo, axis: .vertical)
                        .font(FoamFont.regular(16))
                    Button("保存") {
                        model.saveMemo(dayKey: day.dayKey, text: memo)
                        if model.journalError == nil { memo = model.journal.dailyMemos[day.dayKey]?.text ?? "" }
                    }
                    .font(FoamFont.bold(16))
                    .disabled(memo == (day.memo ?? ""))
                } header: {
                    Text("一言メモ").font(FoamFont.bold(13, relativeTo: .footnote))
                }
                Section {
                    ForEach(day.slices) { slice in
                        VStack(alignment: .leading, spacing: 5) {
                            let end = slice.sliceEnd.map { time($0) } ?? (slice.status == .active ? "記録中" : "終了不明")
                            Text("\(time(slice.sliceStart)) 〜 \(end)")
                                .font(FoamFont.bold(17, relativeTo: .headline))
                            HStack {
                                Text(source(slice.source))
                                if let duration = slice.durationSeconds { Text(FoamTheme.duration(duration)) }
                            }
                            .font(FoamFont.medium(12.5, relativeTo: .caption))
                            if slice.status == .unknownEnd {
                                Label("終了不明", systemImage: "exclamationmark.triangle.fill")
                                    .font(FoamFont.medium(14))
                                    .foregroundStyle(.orange)
                            }
                            if slice.status != .active {
                                Button(slice.status == .unknownEnd ? "終了時刻を補完" : "記録を編集") {
                                    if let encounter = model.resolvedEncounters.first(where: { $0.id == slice.encounterID }) {
                                        editor = slice.status == .unknownEnd ? .complete(encounter) : .edit(encounter)
                                    }
                                }
                                .font(FoamFont.bold(15))
                            }
                        }
                    }
                    Button("＋ この日に記録を追加") { editor = .add(date) }
                        .font(FoamFont.bold(16))
                } header: {
                    Text("その日の記録区間").font(FoamFont.bold(13, relativeTo: .footnote))
                }
                if let error = model.journalError {
                    Text(error).font(FoamFont.regular(14)).foregroundStyle(.red)
                }
            }
            .font(FoamFont.medium(16))
            .navigationTitle(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))
            .toolbar { Button("閉じる") { dismiss() }.font(FoamFont.bold(16)) }
            .sheet(item: $editor) { mode in EncounterEditorSheet(mode: mode) }
            .onAppear { memo = day.memo ?? "" }
        }
        .font(FoamFont.medium(16))
    }

    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().second()) }
    private func source(_ source: EncounterSource) -> String {
        switch source {
        case .auto: "自動（BLE）"
        case .locationMatched: "位置補完"
        case .autoEdited: "修正済み"
        case .manual: "手動"
        }
    }
}
