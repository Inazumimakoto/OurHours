import OurHoursCore
import SwiftUI

enum EncounterEditorMode: Identifiable {
    case add(Date), edit(ResolvedEncounter), complete(ResolvedEncounter)
    var id: String {
        switch self {
        case let .add(date): "add-\(date.timeIntervalSinceReferenceDate)"
        case let .edit(record): "edit-\(record.id)"
        case let .complete(record): "complete-\(record.id)"
        }
    }
    var title: String {
        switch self { case .add: "記録を追加"; case .edit: "記録を編集"; case .complete: "終了時刻を補完" }
    }
}

struct EncounterEditorSheet: View {
    let mode: EncounterEditorMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var confirmDeletion = false

    init(mode: EncounterEditorMode) {
        self.mode = mode
        let initial: Date
        let finish: Date?
        switch mode {
        case let .add(date):
            initial = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            finish = nil
        case let .edit(record), let .complete(record):
            initial = record.startedAt
            finish = record.endedAt
        }
        _start = State(initialValue: initial)
        _end = State(initialValue: finish ?? initial.addingTimeInterval(1800))
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .complete = mode {
                    LabeledContent("開始", value: start.formatted(date: .abbreviated, time: .standard))
                } else {
                    DatePicker("開始", selection: $start)
                }
                DatePicker("終了", selection: $end)
                if end <= start {
                    Text("終了時刻は開始時刻より後に設定してください。")
                        .font(FoamFont.medium(14))
                        .foregroundStyle(.red)
                }
                if let error = model.journalError {
                    Text(error).font(FoamFont.regular(14)).foregroundStyle(.red)
                }
                switch mode {
                case let .edit(record), let .complete(record):
                    Button("記録を削除", role: .destructive) { confirmDeletion = true }
                        .font(FoamFont.bold(16))
                        .confirmationDialog("この記録を削除しますか？", isPresented: $confirmDeletion, titleVisibility: .visible) {
                            Button("削除", role: .destructive) {
                                model.deleteResolvedEncounter(record)
                                if model.journalError == nil { dismiss() }
                            }
                        }
                case .add:
                    EmptyView()
                }
            }
            .font(FoamFont.medium(16))
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.font(FoamFont.medium(16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(FoamFont.bold(16))
                        .disabled(end <= start)
                }
            }
        }
        .font(FoamFont.medium(16))
    }

    private func save() {
        guard end > start else { return }
        switch mode {
        case .add: model.addManualEncounter(startedAt: start, endedAt: end)
        case let .edit(record): model.updateResolvedEncounter(record, startedAt: start, endedAt: end)
        case let .complete(record): model.completeUnknownEnd(sessionID: record.id, startedAt: record.startedAt, endedAt: end)
        }
        if model.journalError == nil { dismiss() }
    }
}
