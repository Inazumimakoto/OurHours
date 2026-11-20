import SwiftUI
import OurHoursCore

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
                    Text(FoamTheme.duration(day.totalRecordedSeconds)).font(.largeTitle.bold())
                    if day.hasActiveSession { Label("記録中", systemImage: "dot.radiowaves.left.and.right") }
                    if day.hasUnknownEnd { Label("終了不明", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                }
                Section("一言メモ") {
                    TextField("この日のメモ", text: $memo, axis: .vertical)
                    Button("保存") {
                        model.saveMemo(dayKey: day.dayKey, text: memo)
                        if model.journalError == nil { memo = model.journal.dailyMemos[day.dayKey]?.text ?? "" }
                    }.disabled(memo == (day.memo ?? ""))
                }
                Section("その日の記録区間") {
                    ForEach(day.slices) { slice in
                        VStack(alignment: .leading, spacing: 5) {
                            let end = slice.sliceEnd.map { time($0) } ?? (slice.status == .active ? "記録中" : "終了不明")
                            Text("\(time(slice.sliceStart)) 〜 \(end)").font(.headline)
                            HStack {
                                Text(source(slice.source))
                                if let duration = slice.durationSeconds { Text(FoamTheme.duration(duration)) }
                            }.font(.caption)
                            if slice.status == .unknownEnd { Label("終了不明", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            if slice.status != .active {
                                Button(slice.status == .unknownEnd ? "終了時刻を補完" : "記録を編集") {
                                    if let encounter = model.resolvedEncounters.first(where: { $0.id == slice.encounterID }) {
                                        editor = slice.status == .unknownEnd ? .complete(encounter) : .edit(encounter)
                                    }
                                }
                            }
                        }
                    }
                    Button("＋ この日に記録を追加") { editor = .add(date) }
                }
                if let error = model.journalError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))
            .toolbar { Button("閉じる") { dismiss() } }
            .sheet(item: $editor) { mode in EncounterEditorSheet(mode: mode) }
            .onAppear { memo = day.memo ?? "" }
        }.fontDesign(.rounded)
    }

    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().second()) }
    private func source(_ source: EncounterSource) -> String {
        switch source { case .auto: "自動"; case .autoEdited: "修正済み"; case .manual: "手動" }
    }
}
