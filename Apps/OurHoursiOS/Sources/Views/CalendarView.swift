import SwiftUI
import OurHoursCore

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Binding var displayedMonth: Date
    @State private var selected: Date?
    @State private var adding = false
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let first = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let summaries = model.daySummaries(forMonth: first)
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    monthButton(-1)
                    Text(first.formatted(.dateTime.year().month().locale(Locale(identifier: "ja_JP"))))
                        .font(.title.bold())
                    monthButton(1)
                }
                HStack {
                    let seconds = summaries.values.reduce(0) { $0 + $1.totalRecordedSeconds }
                    let days = summaries.values.count { !$0.slices.isEmpty }
                    Text("\(calendar.isDate(first, equalTo: .now, toGranularity: .month) ? "今月" : "月合計") \(FoamTheme.duration(seconds)) · \(days)日")
                    Button { adding = true } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                            .background { Image("FoamCalendarStamp").resizable() }
                    }.accessibilityLabel("記録を追加")
                }.font(.subheadline.bold())
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array("日月火水木金土"), id: \.self) { Text(String($0)).font(.caption.bold()) }
                    ForEach(0..<(calendar.component(.weekday, from: first) - 1), id: \.self) { _ in Color.clear }
                    ForEach(Array(calendar.range(of: .day, in: .month, for: first) ?? 1..<1), id: \.self) { day in
                        if let date = calendar.date(byAdding: .day, value: day - 1, to: first) {
                            let summary = summaries[EncounterCalendarAggregator.dayKey(for: date)]
                            Button { selected = date } label: {
                                CalendarDayCell(day: day, summary: summary)
                            }
                            .accessibilityLabel(Text(date, format: .dateTime.month().day()))
                            .accessibilityValue([summary.map { FoamTheme.duration($0.totalRecordedSeconds) }, summary?.hasUnknownEnd == true ? "終了不明" : nil, summary?.memo].compactMap { $0 }.joined(separator: "、"))
                        }
                    }
                }
            }.padding(.horizontal, 12)
        }
        .padding(.top, 62).buttonStyle(.plain)
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { DayDetailSheet(date: selected) }
        }
        .sheet(isPresented: $adding) {
            EncounterEditorSheet(mode: .add(calendar.isDate(first, equalTo: .now, toGranularity: .month) ? .now : first))
        }
    }

    private func monthButton(_ direction: Int) -> some View {
        Button {
            if let date = calendar.date(byAdding: .month, value: direction, to: displayedMonth) { displayedMonth = date }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right").frame(width: 44, height: 44)
        }.accessibilityLabel(direction < 0 ? "前の月" : "次の月")
    }
}

private struct CalendarDayCell: View {
    let day: Int
    let summary: DaySummary?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let intensity = summary?.bubbleIntensity ?? .none
        ZStack {
            if intensity != .none {
                let diameter: CGFloat = intensity == .large ? 51 : intensity == .medium ? 45 : 38
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || summary?.hasActiveSession != true)) { tick in
                    Image("FoamCalendarStamp").resizable().scaledToFit()
                        .shadow(color: intensity == .small ? .clear : FoamTheme.cream, radius: intensity == .large ? 7 : 3)
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(summary?.hasActiveSession == true ? 1 + sin(tick.date.timeIntervalSinceReferenceDate * 3) * 0.05 : 1)
                }
            }
            Text("\(day)").font(.headline.bold())
            if summary?.hasUnknownEnd == true { Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 13, y: -12) }
            if let memo = summary?.memo, !memo.isEmpty { Circle().fill(.purple.opacity(0.6)).frame(width: 5, height: 5).offset(y: 15) }
        }.frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
    }
}
