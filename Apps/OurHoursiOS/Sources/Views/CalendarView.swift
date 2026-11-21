import OurHoursCore
import SwiftUI

private struct SelectedDayRoute: Identifiable {
    let id = UUID()
    let date: Date
    let startAdding: Bool
}

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var displayedMonth: Date

    @State private var selectedRoute: SelectedDayRoute?
    @State private var gridWidth: CGFloat = 340
    @State private var monthEpoch = 0
    @State private var bubblesRevealed = true
    @State private var transitionDirection = 1
    @State private var transitionTask: Task<Void, Never>?

    // Continuous 3-month horizontal carousel: drags smoothly across prev / current / next
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDrag: Bool?
    @State private var suppressDayTapUntil = Date.distantPast
    @State private var isAnimatingCommit = false

    private let calendar = Calendar.current
    private let pageSpacing: CGFloat = 24

    var body: some View {
        let currentFirst = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let prevFirst = calendar.date(byAdding: .month, value: -1, to: currentFirst) ?? currentFirst
        let nextFirst = calendar.date(byAdding: .month, value: 1, to: currentFirst) ?? currentFirst
        let monthComponents = calendar.dateComponents([.year, .month], from: currentFirst)
        let year = monthComponents.year ?? 2026
        let month = monthComponents.month ?? 1
        let summaries = model.daySummaries(forMonth: currentFirst)
        let pageStride = gridWidth + pageSpacing

        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    monthButton(-1)
                    Text(currentFirst.formatted(.dateTime.year().month().locale(Locale(identifier: "ja_JP"))))
                        .font(FoamFont.bold(24, relativeTo: .title))
                        .id("title-\(year)-\(month)")
                    monthButton(1)
                }

                HStack(spacing: 16) {
                    let seconds = summaries.values.reduce(0) { $0 + $1.totalRecordedSeconds }
                    let days = summaries.values.count { !$0.slices.isEmpty }
                    Text("\(calendar.isDate(currentFirst, equalTo: .now, toGranularity: .month) ? "今月" : "月合計") \(FoamTheme.duration(seconds)) · \(days)日")
                        .font(FoamFont.bold(15, relativeTo: .subheadline))
                        .foamCloudSurface(isTogether: model.isTogetherNow, compact: true)

                    Button {
                        let targetDate = calendar.isDate(currentFirst, equalTo: .now, toGranularity: .month) ? .now : currentFirst
                        selectedRoute = SelectedDayRoute(date: targetDate, startAdding: true)
                    } label: {
                        Image("FoamSettingsLather")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .shadow(color: FoamTheme.ink.opacity(0.08), radius: 5, y: 2)
                            .overlay { FoamPlusIcon() }
                    }
                    .buttonStyle(CalendarBounceButtonStyle())
                    .accessibilityLabel("記録を追加")
                }

                ZStack(alignment: .top) {
                    CalendarMonthPageView(
                        monthFirst: prevFirst,
                        gridWidth: gridWidth,
                        bubblesRevealed: false,
                        monthEpoch: monthEpoch,
                        transitionDirection: transitionDirection,
                        reduceMotion: reduceMotion,
                        canTapDay: { isHorizontalDrag != true && !isAnimatingCommit && Date.now >= suppressDayTapUntil },
                        onSelectDay: { selectedRoute = SelectedDayRoute(date: $0, startAdding: false) }
                    )
                    .frame(width: gridWidth, alignment: .top)
                    .offset(x: -pageStride + dragOffset)

                    CalendarMonthPageView(
                        monthFirst: currentFirst,
                        gridWidth: gridWidth,
                        bubblesRevealed: bubblesRevealed,
                        monthEpoch: monthEpoch,
                        transitionDirection: transitionDirection,
                        reduceMotion: reduceMotion,
                        canTapDay: { isHorizontalDrag != true && !isAnimatingCommit && Date.now >= suppressDayTapUntil },
                        onSelectDay: { selectedRoute = SelectedDayRoute(date: $0, startAdding: false) }
                    )
                    .frame(width: gridWidth, alignment: .top)
                    .offset(x: dragOffset)

                    CalendarMonthPageView(
                        monthFirst: nextFirst,
                        gridWidth: gridWidth,
                        bubblesRevealed: false,
                        monthEpoch: monthEpoch,
                        transitionDirection: transitionDirection,
                        reduceMotion: reduceMotion,
                        canTapDay: { isHorizontalDrag != true && !isAnimatingCommit && Date.now >= suppressDayTapUntil },
                        onSelectDay: { selectedRoute = SelectedDayRoute(date: $0, startAdding: false) }
                    )
                    .frame(width: gridWidth, alignment: .top)
                    .offset(x: pageStride + dragOffset)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .clipped()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                    if newWidth > 0 { gridWidth = newWidth }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard !isAnimatingCommit else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if isHorizontalDrag == nil {
                                isHorizontalDrag = abs(dx) > abs(dy) * 1.05
                            }
                            guard isHorizontalDrag == true else { return }
                            if abs(dx) > 4 {
                                suppressDayTapUntil = Date.now.addingTimeInterval(0.75)
                            }
                            dragOffset = max(-pageStride, min(pageStride, dx))
                        }
                        .onEnded { value in
                            let wasHorizontal = isHorizontalDrag == true
                            isHorizontalDrag = nil
                            guard wasHorizontal else {
                                if !isAnimatingCommit, dragOffset != 0 {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) {
                                        dragOffset = 0
                                    }
                                }
                                return
                            }
                            suppressDayTapUntil = Date.now.addingTimeInterval(0.45)
                            guard !isAnimatingCommit else { return }
                            let dx = value.translation.width
                            let predicted = value.predictedEndTranslation.width
                            if abs(dx) > gridWidth * 0.22 || abs(predicted) > 140 {
                                commitMonthTransition(direction: dx < 0 ? 1 : -1, currentFirst: currentFirst)
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 62)
        .buttonStyle(.plain)
        .onDisappear { transitionTask?.cancel() }
        .fullScreenCover(item: $selectedRoute) { route in
            DayDetailSheet(date: route.date, startAdding: route.startAdding)
        }
    }

    private func monthButton(_ direction: Int) -> some View {
        let currentFirst = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        return Button {
            guard !isAnimatingCommit else { return }
            commitMonthTransition(direction: direction, currentFirst: currentFirst)
        } label: {
            Image("FoamSettingsLather")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .shadow(color: FoamTheme.ink.opacity(0.08), radius: 4, y: 2)
                .overlay { FoamChevronIcon(direction: direction) }
        }
        .buttonStyle(CalendarBounceButtonStyle())
        .accessibilityLabel(direction < 0 ? "前の月" : "次の月")
    }

    private func commitMonthTransition(direction: Int, currentFirst: Date) {
        let dir = direction >= 0 ? 1 : -1
        guard let target = calendar.date(byAdding: .month, value: dir, to: currentFirst) else { return }
        transitionTask?.cancel()

        if reduceMotion {
            displayedMonth = target
            monthEpoch += 1
            dragOffset = 0
            isAnimatingCommit = false
            bubblesRevealed = true
            return
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        transitionDirection = dir
        isAnimatingCommit = true
        let pageStride = gridWidth + pageSpacing

        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGFloat(-dir) * pageStride
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                isAnimatingCommit = false
                return
            }

            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                displayedMonth = target
                monthEpoch += 1
                dragOffset = 0
                bubblesRevealed = false
            }

            isAnimatingCommit = false

            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
            bubblesRevealed = true
        }
    }
}

private struct CalendarMonthPageView: View {
    @Environment(AppModel.self) private var model
    let monthFirst: Date
    let gridWidth: CGFloat
    let bubblesRevealed: Bool
    let monthEpoch: Int
    let transitionDirection: Int
    let reduceMotion: Bool
    let canTapDay: () -> Bool
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let monthComponents = calendar.dateComponents([.year, .month], from: monthFirst)
        let year = monthComponents.year ?? 2026
        let month = monthComponents.month ?? 1
        let leadingBlanks = calendar.component(.weekday, from: monthFirst) - 1
        let daysCount = calendar.range(of: .day, in: .month, for: monthFirst)?.count ?? 0
        let summaries = model.daySummaries(forMonth: monthFirst)
        let colWidth = max(40, gridWidth / 7)

        ZStack(alignment: .top) {
            // Layer 1: Organic white soap-foam puffs & overnight bridges locked directly to dates
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<7, id: \.self) { _ in
                    Color.clear.frame(height: 20)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 52)
                }
                ForEach(1...max(1, daysCount), id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthFirst) {
                        let summary = summaries[EncounterCalendarAggregator.dayKey(for: date)]
                        let gridIndex = leadingBlanks + (day - 1)
                        let col = gridIndex % 7
                        let row = gridIndex / 7
                        CalendarDayFoamLayer(
                            year: year,
                            month: month,
                            day: day,
                            col: col,
                            row: row,
                            daysCount: daysCount,
                            colWidth: colWidth,
                            summary: summary,
                            bubblesRevealed: bubblesRevealed,
                            monthEpoch: monthEpoch,
                            transitionDirection: transitionDirection,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
            .compositingGroup()
            .shadow(color: FoamTheme.ink.opacity(0.08), radius: 5, y: 2)
            .allowsHitTesting(false)

            // Layer 2: Weekday headers, day numerals, badges, and tap buttons
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array("日月火水木金土"), id: \.self) { weekday in
                    Text(String(weekday))
                        .font(FoamFont.bold(13, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.ink.opacity(0.75))
                        .frame(height: 20)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 52)
                }
                ForEach(1...max(1, daysCount), id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthFirst) {
                        let summary = summaries[EncounterCalendarAggregator.dayKey(for: date)]
                        Button {
                            guard canTapDay() else { return }
                            onSelectDay(date)
                        } label: {
                            CalendarDayLabelCell(day: day, summary: summary)
                        }
                        .accessibilityLabel(Text(date, format: .dateTime.month().day()))
                        .accessibilityValue(
                            [
                                summary.map { FoamTheme.duration($0.totalRecordedSeconds) },
                                summary?.hasUnknownEnd == true ? "終了不明" : nil,
                                summary?.memo
                            ]
                            .compactMap { $0 }
                            .joined(separator: "、")
                        )
                    }
                }
            }
        }
    }
}

private struct CalendarDayFoamLayer: View {
    let year: Int
    let month: Int
    let day: Int
    let col: Int
    let row: Int
    let daysCount: Int
    let colWidth: CGFloat
    let summary: DaySummary?
    let bubblesRevealed: Bool
    let monthEpoch: Int
    let transitionDirection: Int
    let reduceMotion: Bool

    private var puffAssetName: String {
        let names = ["FoamDayPuffA", "FoamDayPuffB", "FoamDayPuffC"]
        let hash = abs(year &* 37 &+ month &* 13 &+ day &* 19)
        return names[hash % names.count]
    }

    private var puffRotationDegrees: Double {
        let hash = ((year &* 53 &+ month &* 29 &+ day &* 17) % 37) - 18
        return Double(hash)
    }

    private var puffFlipX: CGFloat {
        ((year + month * 3 + day * 5) % 2 == 0) ? 1 : -1
    }

    private var popDelay: Double {
        let sweepColumn = transitionDirection >= 0 ? (6 - col) : col
        let jitter = Double((day * 7 + month * 3) % 5) * 0.011
        return Double(sweepColumn) * 0.025 + Double(row) * 0.014 + jitter
    }

    var body: some View {
        let intensity = summary?.bubbleIntensity ?? .none
        ZStack {
            if intensity != .none, let summary {
                let diameter: CGFloat = switch intensity {
                case .none: 0
                case .small: 42
                case .medium: 48
                case .large: 54
                }

                if summary.continuesFromPreviousDay && (col == 0 || day == 1) {
                    HStack(spacing: 2) {
                        Image("FoamSudDrop").resizable().frame(width: 6, height: 6).offset(y: -3)
                        Image("FoamDayBridge")
                            .resizable()
                            .frame(width: colWidth * 0.44, height: 22)
                            .scaleEffect(x: -1, y: 1)
                    }
                    .offset(x: -colWidth * 0.34)
                }

                if summary.continuesToNextDay {
                    if col < 6 && day < daysCount {
                        Image("FoamDayBridge")
                            .resizable()
                            .frame(width: colWidth * 0.96, height: 34)
                            .offset(x: colWidth * 0.50)
                    } else {
                        HStack(spacing: 2) {
                            Image("FoamDayBridge")
                                .resizable()
                                .frame(width: colWidth * 0.44, height: 22)
                            Image("FoamSudDrop").resizable().frame(width: 6, height: 6).offset(y: -4)
                        }
                        .offset(x: colWidth * 0.34)
                    }
                }

                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !summary.hasActiveSession)) { tick in
                    let activePulse: CGFloat = summary.hasActiveSession
                        ? 1 + CGFloat(sin(tick.date.timeIntervalSinceReferenceDate * 3)) * 0.055
                        : 1
                    Image(puffAssetName)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(x: puffFlipX, y: 1)
                        .rotationEffect(.degrees(puffRotationDegrees))
                        .frame(width: diameter, height: diameter)
                        .shadow(
                            color: intensity == .small ? .clear : FoamTheme.cream,
                            radius: intensity == .large ? 7 : 3
                        )
                        .scaleEffect(activePulse)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .scaleEffect(bubblesRevealed ? 1.0 : 0.06)
        .opacity(bubblesRevealed ? 1.0 : 0.0)
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.42, dampingFraction: 0.56).delay(bubblesRevealed ? popDelay : 0),
            value: bubblesRevealed
        )
        .id("foam-\(year)-\(month)-\(monthEpoch)-\(day)")
    }
}

private struct CalendarDayLabelCell: View {
    let day: Int
    let summary: DaySummary?

    var body: some View {
        ZStack {
            Text("\(day)")
                .font(FoamFont.bold(16, relativeTo: .headline))
                .foregroundStyle(FoamTheme.ink)
            if summary?.hasUnknownEnd == true {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .offset(x: 13, y: -13)
            }
            if let memo = summary?.memo, !memo.isEmpty {
                Circle()
                    .fill(Color.purple.opacity(0.65))
                    .frame(width: 5, height: 5)
                    .offset(y: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

private struct CalendarBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
