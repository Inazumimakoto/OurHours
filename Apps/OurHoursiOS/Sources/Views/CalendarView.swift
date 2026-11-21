import OurHoursCore
import SwiftUI

struct SelectedDayRoute: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let startAdding: Bool
    var focusEncounterID: UUID? = nil
}

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var displayedMonth: Date
    @Binding var pendingRoute: SelectedDayRoute?

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
                        SoapBubbleSurface(
                            cornerStyle: .capsule,
                            prominence: .standard,
                            isTogether: model.isTogetherNow,
                            seed: 1.9,
                            wobbleScale: 0.85
                        )
                        .frame(width: 44, height: 44)
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
        .onAppear { consumePendingRouteIfNeeded() }
        .onChange(of: pendingRoute) { _, _ in consumePendingRouteIfNeeded() }
        .onDisappear { transitionTask?.cancel() }
        .fullScreenCover(item: $selectedRoute) { route in
            DayDetailSheet(
                date: route.date,
                startAdding: route.startAdding,
                focusEncounterID: route.focusEncounterID
            )
        }
    }

    private func consumePendingRouteIfNeeded() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        selectedRoute = route
    }

    private func monthButton(_ direction: Int) -> some View {
        let currentFirst = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        return Button {
            guard !isAnimatingCommit else { return }
            commitMonthTransition(direction: direction, currentFirst: currentFirst)
        } label: {
            SoapBubbleSurface(
                cornerStyle: .capsule,
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: direction < 0 ? 4.1 : 5.3,
                wobbleScale: 0.85
            )
            .frame(width: 42, height: 42)
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

private enum CalendarDayBubbleRender: Equatable {
    case none
    case standalone(diameter: CGFloat, intensity: BubbleIntensity)
    case runStart(span: Int, hasActiveSession: Bool)
    case runContinuation
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
            // Layer 1: Single shared-timer glossy soap-bubble layer for crisp met days & rounded overnight capsules
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !bubblesRevealed || summaries.isEmpty)) { timeline in
                let sharedPhase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 1.15
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<7, id: \.self) { _ in
                        Color.clear.frame(height: 20)
                    }
                    ForEach(0..<leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(height: 52)
                    }
                    ForEach(1...max(1, daysCount), id: \.self) { day in
                        let gridIndex = leadingBlanks + (day - 1)
                        let col = gridIndex % 7
                        let row = gridIndex / 7
                        let summary = summaryForDay(day, daysCount: daysCount, summaries: summaries)
                        let layout = bubbleLayout(
                            for: day,
                            col: col,
                            leadingBlanks: leadingBlanks,
                            daysCount: daysCount,
                            summaries: summaries
                        )
                        CalendarDayFoamLayer(
                            year: year,
                            month: month,
                            day: day,
                            col: col,
                            row: row,
                            colWidth: colWidth,
                            summary: summary,
                            bubbleRender: layout.render,
                            hasLeadingWrapDot: layout.hasLeadingWrapDot,
                            hasTrailingWrapDot: layout.hasTrailingWrapDot,
                            bubblesRevealed: bubblesRevealed,
                            monthEpoch: monthEpoch,
                            transitionDirection: transitionDirection,
                            isTogether: model.isTogetherNow,
                            sharedPhase: sharedPhase,
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
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
                        let badges = calendarBadges(on: date)
                        let details = [
                            summary.map { FoamTheme.duration($0.totalRecordedSeconds) },
                            summary?.hasUnknownEnd == true ? "終了不明" : nil,
                            summary?.memo
                        ].compactMap { $0 }
                        Button {
                            guard canTapDay() else { return }
                            onSelectDay(date)
                        } label: {
                            CalendarDayLabelCell(day: day, summary: summary, badges: badges)
                        }
                        .accessibilityLabel(Text(date, format: .dateTime.month().day()))
                        .accessibilityValue((details + badges.map(\.title)).joined(separator: "、"))
                    }
                }
            }
        }
    }

    private func calendarBadges(on date: Date) -> [ResolvedSpecialDayBadge] {
        let events = model.visibleCalendarSpecialDayEvents(on: date)
        return SpecialDayBadgeResolver.badges(for: events, model: model)
    }

    private func summaryForDay(_ day: Int, daysCount: Int, summaries: [String: DaySummary]) -> DaySummary? {
        guard day >= 1, day <= daysCount,
              let date = calendar.date(byAdding: .day, value: day - 1, to: monthFirst) else {
            return nil
        }
        return summaries[EncounterCalendarAggregator.dayKey(for: date)]
    }

    private func isConnectedToNext(
        day: Int,
        leadingBlanks: Int,
        daysCount: Int,
        summaries: [String: DaySummary]
    ) -> Bool {
        guard day >= 1, day < daysCount else { return false }
        let col = (leadingBlanks + day - 1) % 7
        guard col < 6 else { return false }
        guard let current = summaryForDay(day, daysCount: daysCount, summaries: summaries),
              let next = summaryForDay(day + 1, daysCount: daysCount, summaries: summaries) else {
            return false
        }
        return current.bubbleIntensity != .none
            && next.bubbleIntensity != .none
            && current.continuesToNextDay
            && next.continuesFromPreviousDay
    }

    private func bubbleLayout(
        for day: Int,
        col: Int,
        leadingBlanks: Int,
        daysCount: Int,
        summaries: [String: DaySummary]
    ) -> (render: CalendarDayBubbleRender, hasLeadingWrapDot: Bool, hasTrailingWrapDot: Bool) {
        let summary = summaryForDay(day, daysCount: daysCount, summaries: summaries)
        let intensity = summary?.bubbleIntensity ?? .none
        let hasLeadingWrapDot = intensity != .none && summary?.continuesFromPreviousDay == true && (col == 0 || day == 1)
        let hasTrailingWrapDot = intensity != .none && summary?.continuesToNextDay == true && (col == 6 || day == daysCount)

        if day > 1 && isConnectedToNext(day: day - 1, leadingBlanks: leadingBlanks, daysCount: daysCount, summaries: summaries) {
            return (.runContinuation, hasLeadingWrapDot, hasTrailingWrapDot)
        }

        if isConnectedToNext(day: day, leadingBlanks: leadingBlanks, daysCount: daysCount, summaries: summaries) {
            var endDay = day
            var anyActive = summary?.hasActiveSession == true
            while isConnectedToNext(day: endDay, leadingBlanks: leadingBlanks, daysCount: daysCount, summaries: summaries) {
                endDay += 1
                if summaryForDay(endDay, daysCount: daysCount, summaries: summaries)?.hasActiveSession == true {
                    anyActive = true
                }
            }
            return (.runStart(span: endDay - day + 1, hasActiveSession: anyActive), hasLeadingWrapDot, hasTrailingWrapDot)
        }

        guard intensity != .none else {
            return (.none, false, false)
        }
        let diameter: CGFloat = switch intensity {
        case .none: 0
        case .small: 38
        case .medium: 44
        case .large: 49
        }
        return (.standalone(diameter: diameter, intensity: intensity), hasLeadingWrapDot, hasTrailingWrapDot)
    }
}

private struct CalendarDayFoamLayer: View {
    let year: Int
    let month: Int
    let day: Int
    let col: Int
    let row: Int
    let colWidth: CGFloat
    let summary: DaySummary?
    let bubbleRender: CalendarDayBubbleRender
    let hasLeadingWrapDot: Bool
    let hasTrailingWrapDot: Bool
    let bubblesRevealed: Bool
    let monthEpoch: Int
    let transitionDirection: Int
    let isTogether: Bool
    let sharedPhase: Double
    let reduceMotion: Bool

    private var popDelay: Double {
        let sweepColumn = transitionDirection >= 0 ? (6 - col) : col
        let jitter = Double((day * 7 + month * 3) % 5) * 0.011
        return Double(sweepColumn) * 0.025 + Double(row) * 0.014 + jitter
    }

    var body: some View {
        let intensity = summary?.bubbleIntensity ?? .none
        let isActivePulse = switch bubbleRender {
        case let .runStart(_, hasActive): hasActive
        default: summary?.hasActiveSession == true
        }
        let activePulse: CGFloat = (!reduceMotion && isActivePulse)
            ? 1 + CGFloat(sin(sharedPhase * 3.1)) * 0.055
            : 1

        ZStack {
            if intensity != .none {
                switch bubbleRender {
                case .none, .runContinuation:
                    EmptyView()

                case let .standalone(diameter, bubbleIntensity):
                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: .vivid,
                        isTogether: isTogether,
                        seed: Double(day) * 0.73 + Double(month),
                        wobbleScale: bubbleIntensity == .large ? 1.15 : 0.95,
                        externalPhase: sharedPhase
                    )
                    .frame(width: diameter, height: diameter)
                    .shadow(
                        color: bubbleIntensity == .small
                            ? .clear
                            : FoamTheme.cream.opacity(bubbleIntensity == .large ? 0.90 : 0.50),
                        radius: bubbleIntensity == .large ? 8 : 4
                    )
                    .scaleEffect(activePulse)

                case let .runStart(span, _):
                    let pillHeight: CGFloat = 44
                    let pillWidth = colWidth * CGFloat(span - 1) + pillHeight
                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: .vivid,
                        isTogether: isTogether,
                        seed: Double(day) * 0.61 + Double(month),
                        wobbleScale: 1.05,
                        externalPhase: sharedPhase
                    )
                    .frame(width: pillWidth, height: pillHeight)
                    .shadow(color: FoamTheme.cream.opacity(0.65), radius: 5)
                    .scaleEffect(activePulse)
                    .offset(x: colWidth * CGFloat(span - 1) * 0.5)
                }

                if hasLeadingWrapDot {
                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: .vivid,
                        isTogether: isTogether,
                        seed: Double(day),
                        wobbleScale: 0.4,
                        externalPhase: sharedPhase
                    )
                    .frame(width: 10, height: 10)
                    .offset(x: -colWidth * 0.44, y: -2)
                }

                if hasTrailingWrapDot {
                    SoapBubbleSurface(
                        cornerStyle: .capsule,
                        prominence: .vivid,
                        isTogether: isTogether,
                        seed: Double(day) + 0.5,
                        wobbleScale: 0.4,
                        externalPhase: sharedPhase
                    )
                    .frame(width: 10, height: 10)
                    .offset(x: colWidth * 0.44, y: -2)
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
    let badges: [ResolvedSpecialDayBadge]

    var body: some View {
        let hasRecord = (summary?.bubbleIntensity ?? .none) != .none
        let offsets = badgeOffsets
        let symbolSize: CGFloat = badges.count <= 1 ? 10.5 : 9.0

        ZStack {
            Text("\(day)")
                .font(hasRecord ? FoamFont.bold(16.5, relativeTo: .headline) : FoamFont.regular(15, relativeTo: .headline))
                .foregroundStyle(hasRecord ? FoamTheme.ink : FoamTheme.ink.opacity(0.30))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            ForEach(Array(badges.prefix(offsets.count).enumerated()), id: \.element.id) { index, badge in
                badgeIcon(badge, symbolSize: symbolSize)
                    .offset(x: offsets[index].x, y: offsets[index].y)
            }

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

    private var badgeOffsets: [CGPoint] {
        if summary?.hasUnknownEnd == true {
            return [
                CGPoint(x: -13, y: -13),
                CGPoint(x: -13, y: 13),
                CGPoint(x: 13, y: 13),
                CGPoint(x: -14, y: 0)
            ]
        }
        return [
            CGPoint(x: -13, y: -13),
            CGPoint(x: 13, y: -13),
            CGPoint(x: -13, y: 13),
            CGPoint(x: 13, y: 13)
        ]
    }

    private func badgeIcon(_ badge: ResolvedSpecialDayBadge, symbolSize: CGFloat) -> some View {
        Image(systemName: badge.symbolName)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(badge.tint)
            .shadow(color: .white.opacity(0.75), radius: 1.4, x: 0, y: 0)
            .accessibilityHidden(true)
    }
}

private struct CalendarBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
