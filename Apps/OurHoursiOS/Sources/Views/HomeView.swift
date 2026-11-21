import CoreBluetooth
import OurHoursCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let onPair: () -> Void
    let onBurst: () -> Void
    let onOpenUnknownEnd: (ResolvedEncounter) -> Void

    var body: some View {
        let unknownEnds = model.resolvedEncounters.filter { $0.status == .unknownEnd }
        let latestUnknownEnd = unknownEnds.last

        VStack {
            Spacer(minLength: 50)
            if let start = model.activeSessionStartDate {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    let s = max(0, Int(tick.date.timeIntervalSince(start)))
                    VStack(spacing: 10) {
                        Text(
                            s < 3600
                                ? String(format: "%d:%02d", s / 60, s % 60)
                                : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                        )
                        .font(FoamFont.bold(72, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        Text("いっしょにいるよ")
                            .font(FoamFont.bold(15, relativeTo: .subheadline))
                            .foamCloudSurface(isTogether: true, compact: true)
                    }
                }
            }
            Spacer()
            FoamMascotView(
                isTogether: model.isTogetherNow,
                isPaired: model.snapshot.isPaired,
                onTapBurst: onBurst
            )
            Spacer()
            if model.isTogetherNow {
                if let pending = latestUnknownEnd {
                    Button { onOpenUnknownEnd(pending) } label: {
                        Label("終了不明の記録を確認（\(unknownEnds.count)件）", systemImage: "exclamationmark.circle")
                    }
                    .font(FoamFont.bold(14))
                    .foamButtonSurface()
                    .padding(.bottom, 10)
                }
            } else {
                VStack(spacing: 12) {
                    if !model.snapshot.isPaired {
                        Button("ペアを設定してはじめる", action: onPair)
                            .font(FoamFont.bold(16))
                            .foamButtonSurface()
                    } else {
                        VStack(spacing: 4) {
                            Text("今月 \(model.metDayCount(forMonth: .now))日 · \(FoamTheme.duration(model.monthlyRecordedSeconds(forMonth: .now)))")
                                .font(FoamFont.bold(16))
                            Text("累計 \(FoamTheme.duration(model.lifetimeRecordedSeconds()))")
                                .font(FoamFont.medium(13, relativeTo: .caption))
                                .foregroundStyle(FoamTheme.ink.opacity(0.76))
                        }
                        .foamCloudSurface(isTogether: false)
                    }
                    if CBManager.authorization == .denied || CBManager.authorization == .restricted
                        || model.snapshot.centralState == "unauthorized" || model.snapshot.peripheralState == "unauthorized" {
                        Label("自動記録にはBluetoothの許可が必要です", systemImage: "exclamationmark.triangle")
                            .font(FoamFont.bold(13))
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(FoamFont.bold(14))
                        .foamButtonSurface()
                    }
                    if let pending = latestUnknownEnd {
                        Button { onOpenUnknownEnd(pending) } label: {
                            Label("終了不明の記録を確認（\(unknownEnds.count)件）", systemImage: "exclamationmark.circle")
                        }
                        .font(FoamFont.bold(14))
                        .foamButtonSurface()
                    }
                    if let error = model.journalError {
                        Text(error).font(FoamFont.regular(12, relativeTo: .caption))
                    }
                }
                .padding(.bottom, 10)
            }
        }.padding(.horizontal)
    }
}
