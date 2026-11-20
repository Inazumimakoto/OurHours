import SwiftUI
import CoreBluetooth
import OurHoursCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let onPair: () -> Void
    let onBurst: () -> Void
    let onCalendar: (Date) -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 50)
            if let start = model.activeSessionStartDate {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    let s = max(0, Int(tick.date.timeIntervalSince(start)))
                    VStack {
                        Text(s < 3600 ? String(format: "%d:%02d", s / 60, s % 60) : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60))
                            .font(.system(size: 74, weight: .heavy, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("いっしょにいるよ").font(.subheadline.bold()).foamPill()
                    }
                }
            }
            Spacer()
            FoamMascotView(isTogether: model.isTogetherNow, onTapBurst: onBurst)
            Spacer()
            if !model.isTogetherNow {
                VStack(spacing: 8) {
                    if !model.snapshot.isPaired {
                        Button("ペアを設定してはじめる", action: onPair)
                    } else {
                        Text("今月 \(model.metDayCount(forMonth: .now))日 · \(FoamTheme.duration(model.monthlyRecordedSeconds(forMonth: .now)))")
                        Text("累計 \(FoamTheme.duration(model.lifetimeRecordedSeconds()))")
                            .font(.caption.bold())
                            .foregroundStyle(FoamTheme.ink.opacity(0.72))
                    }
                    if CBManager.authorization == .denied || CBManager.authorization == .restricted || model.snapshot.centralState == "unauthorized" || model.snapshot.peripheralState == "unauthorized" {
                        Label("自動記録にはBluetoothの許可が必要です", systemImage: "exclamationmark.triangle")
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    if let pending = model.resolvedEncounters.last(where: { $0.status == .unknownEnd }) {
                        Button { onCalendar(pending.startedAt) } label: {
                            Label("終了不明の記録を確認", systemImage: "exclamationmark.circle")
                        }
                    }
                    if let error = model.journalError { Text(error).font(.caption) }
                }.font(.subheadline.bold()).foamPill()
            }
        }.padding(.horizontal)
    }
}
