import OurHoursCore
import SwiftUI

private enum TimelineKnobEdge: Equatable {
    case start, end
}

private enum TimelineTarget: Equatable {
    case existing(ResolvedEncounter)
    case draft

    static func == (lhs: TimelineTarget, rhs: TimelineTarget) -> Bool {
        switch (lhs, rhs) {
        case (.draft, .draft):
            return true
        case let (.existing(a), .existing(b)):
            if a.id == b.id { return true }
            let aIDs = Set(a.linkedSessionIDs.isEmpty ? [a.id] : a.linkedSessionIDs)
            let bIDs = Set(b.linkedSessionIDs.isEmpty ? [b.id] : b.linkedSessionIDs)
            return !aIDs.isDisjoint(with: bIDs)
        default:
            return false
        }
    }

    var encounter: ResolvedEncounter? {
        if case let .existing(enc) = self { return enc }
        return nil
    }
}

private struct ActiveKnobDrag {
    let target: TimelineTarget
    let edge: TimelineKnobEdge
    let dayStart: Date
    let referenceNow: Date
    let fixedOtherDate: Date
    let originalStartDate: Date
    let originalEndDate: Date?
    let frozenScale: DayTimelineScale
    let initialMinute: Int
    var currentMinute: Int
    var anchorZoomMinute: Double
    var startFingerY: CGFloat?
    var didTriggerMergeHaptic = false
}

private struct PendingKnobAdjustment: Equatable {
    let target: TimelineTarget
    let itemID: String
    let dayStart: Date
    let originalStart: Date
    let originalEnd: Date?
    let originalStatus: SessionStatus
    var proposedStart: Date
    var proposedEnd: Date?
}

private struct InlineTimeEditorState: Identifiable {
    let id = UUID()
    let target: TimelineTarget
    var focus: TimelineKnobEdge
    let dayStart: Date
    let originalStart: Date
    let originalEnd: Date?
    let hasUnknownOriginalEnd: Bool
    let isActiveTarget: Bool
    let referenceNow: Date
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var didTouchStart: Bool
    var didTouchEnd: Bool
    var didChangeWheel = false

    mutating func setFocus(_ newFocus: TimelineKnobEdge) {
        focus = newFocus
    }

    var effectiveStart: Date {
        guard target == .draft || didTouchStart else { return originalStart }
        return dayStart.addingTimeInterval(Double((startHour * 60 + startMinute) * 60))
    }

    var effectiveEnd: Date {
        if target == .draft || didTouchEnd || hasUnknownOriginalEnd {
            let clampedMinute = endHour == 24 ? 24 * 60 : (endHour * 60 + endMinute)
            return dayStart.addingTimeInterval(Double(clampedMinute * 60))
        }
        if let originalEnd {
            return originalEnd
        }
        let clampedMinute = endHour == 24 ? 24 * 60 : (endHour * 60 + endMinute)
        return dayStart.addingTimeInterval(Double(clampedMinute * 60))
    }

    var displayStartMinuteOnDay: Int {
        if target == .draft || didTouchStart {
            return startHour * 60 + startMinute
        }
        return max(0, min(1440, Int(floor(originalStart.timeIntervalSince(dayStart) / 60.0))))
    }

    var displayEndMinuteOnDay: Int {
        if target == .draft || didTouchEnd || hasUnknownOriginalEnd {
            return endHour == 24 ? 1440 : (endHour * 60 + endMinute)
        }
        if let originalEnd {
            return max(0, min(1440, Int(ceil(originalEnd.timeIntervalSince(dayStart) / 60.0))))
        }
        return endHour == 24 ? 1440 : (endHour * 60 + endMinute)
    }

    var focusedMinuteOnDay: Int {
        focus == .start ? displayStartMinuteOnDay : displayEndMinuteOnDay
    }

    var hasPendingMutation: Bool {
        switch target {
        case .draft:
            return true
        case .existing:
            if isActiveTarget { return didTouchStart }
            return hasUnknownOriginalEnd || didTouchStart || didTouchEnd
        }
    }

    func isValid(at now: Date) -> Bool {
        if isActiveTarget {
            return effectiveStart <= max(originalStart, max(referenceNow, now))
        }
        return effectiveEnd > effectiveStart
    }
}

private struct TimelineRenderItem: Identifiable {
    let id: String
    let target: TimelineTarget
    let sliceStartMinute: Int
    let sliceEndMinute: Int
    let status: SessionStatus
    let continuesFromPreviousDay: Bool
    let continuesToNextDay: Bool
    let durationSeconds: TimeInterval?
    let canEditStart: Bool
    let canEditEnd: Bool
    let dayKey: String
}

private struct TimelineLayoutPlan {
    let fullInlineIDs: Set<String>
    let compactLabelYByID: [String: CGFloat]
}

/// Full-screen vertical day timeline page with clean sky typography, soft note card with corner foam tufts,
/// dynamic timeline bounds, and a speech-bubble wheel.
struct DayDetailSheet: View {
    let date: Date
    let startAdding: Bool
    let focusEncounterID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentDate: Date
    @State private var memo = ""
    @State private var lastSyncedMemo = ""
    @FocusState private var isMemoFocused: Bool

    @State private var selectedItemID: String?
    @State private var activeDrag: ActiveKnobDrag?
    @State private var pendingDragAdjustment: PendingKnobAdjustment?
    @State private var inlineEditor: InlineTimeEditorState?
    @State private var confirmDeleteTarget: ResolvedEncounter?
    @State private var zoomFactor: Double = 1.0
    @State private var zoomFocusMinute: Double = 810.0
    @State private var didHandleInitialAdd = false
    @State private var didHandleInitialFocus = false

    private let timelinePadTop: CGFloat = 22
    private let timelinePadBottom: CGFloat = 26
    private let unifiedAxisX: CGFloat = 56
    private let labelLeadX: CGFloat = 76

    init(date: Date, startAdding: Bool = false, focusEncounterID: UUID? = nil) {
        self.date = date
        self.startAdding = startAdding
        self.focusEncounterID = focusEncounterID
        _currentDate = State(initialValue: date)
    }

    private var normalizedMemo: String {
        memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: currentDate)
    }

    var body: some View {
        let day = model.daySummary(for: currentDate)
        let badges = SpecialDayBadgeResolver.badges(for: model.visibleCalendarSpecialDayEvents(on: currentDate), model: model)
        let activeDayStart = dayStart
        let liveMinutes = liveExtraMinutes(dayStart: activeDayStart)
        let computedScale = DayTimelineScale.compute(
            for: day.slices,
            dayStart: activeDayStart,
            extraMinutes: liveMinutes
        )
        let effectiveScale = activeDrag?.frozenScale ?? computedScale

        GeometryReader { screenGeo in
            let items = buildRenderItems(day: day, dayStart: activeDayStart)
            let availableAxisHeight = max(390, screenGeo.size.height - 310)
            let denseMinimumHeight = items.count > 1 ? CGFloat(items.count - 1) * 32.0 + 40.0 : 0
            let axisHeight = max(availableAxisHeight, denseMinimumHeight)

            ZStack(alignment: .bottom) {
                FoamTheme.sky(together: model.isTogetherNow)
                    .ignoresSafeArea()
                FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(currentDayKey: day.dayKey, day: day, dayStart: activeDayStart)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ScrollView {
                        VStack(spacing: 12) {
                            heroDurationCloud(day: day)
                                .padding(.top, 2)

                            if !badges.isEmpty {
                                SpecialDayPillsRow(badges: badges)
                            }

                            memoCloudCard(dayKey: day.dayKey)

                            if let dragStatus = dragStatusInfo(for: activeDrag) {
                                Text(dragStatus.text)
                                    .font(FoamFont.bold(12.5, relativeTo: .caption))
                                    .foregroundStyle(dragStatus.isMerging ? FoamTheme.warmAccent : FoamTheme.ink.opacity(0.78))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.92), in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(
                                            dragStatus.isMerging ? FoamTheme.warmAccent.opacity(0.45) : Color.white,
                                            lineWidth: 1.2
                                        )
                                    }
                                    .shadow(color: FoamTheme.ink.opacity(0.08), radius: 6, y: 2)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            } else if inlineEditor == nil, let pending = pendingDragAdjustment {
                                pendingAdjustmentBar(pending: pending)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            timelineViewport(
                                items: items,
                                day: day,
                                dayStart: activeDayStart,
                                scale: effectiveScale,
                                axisHeight: axisHeight
                            )

                            if let error = model.journalError {
                                Text(error)
                                    .font(FoamFont.medium(13))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 54)
                    }
                    .scrollDisabled(activeDrag != nil)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .confirmationDialog(
            "この記録を削除しますか？",
            isPresented: Binding(
                get: { confirmDeleteTarget != nil },
                set: { if !$0 { confirmDeleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let victim = confirmDeleteTarget {
                Button("削除する", role: .destructive) {
                    model.deleteResolvedEncounter(victim)
                    inlineEditor = nil
                    pendingDragAdjustment = nil
                    selectedItemID = nil
                    confirmDeleteTarget = nil
                }
            }
        }
        .onAppear {
            let initial = day.memo ?? ""
            memo = initial
            lastSyncedMemo = initial
            if startAdding && !didHandleInitialAdd {
                didHandleInitialAdd = true
                Task { @MainActor in
                    openDraftEditor(day: day, dayStart: activeDayStart)
                }
            } else if let focusID = focusEncounterID, !didHandleInitialFocus {
                didHandleInitialFocus = true
                let targetID = "\(focusID.uuidString)_\(day.dayKey)"
                if day.slices.contains(where: { $0.id == targetID }) {
                    selectedItemID = targetID
                } else if let fallback = day.slices.first(where: { $0.status == .unknownEnd }) {
                    selectedItemID = fallback.id
                }
            }
        }
        .onChange(of: isMemoFocused) { _, focused in
            if !focused {
                commitMemoIfNeeded(dayKey: day.dayKey)
            }
        }
        .onChange(of: day.memo) { _, newValue in
            let updated = newValue ?? ""
            if !isMemoFocused && normalizedMemo == lastSyncedMemo {
                memo = updated
            }
            lastSyncedMemo = updated
        }
        .onDisappear {
            commitMemoIfNeeded(dayKey: EncounterCalendarAggregator.dayKey(for: currentDate))
        }
    }

    // MARK: - Top Navigation

    @ViewBuilder
    private func topBar(currentDayKey: String, day: DaySummary, dayStart: Date) -> some View {
        HStack {
            FoamRoundIconButton(accessibilityLabel: "カレンダーに戻る") {
                isMemoFocused = false
                inlineEditor = nil
                pendingDragAdjustment = nil
                selectedItemID = nil
                commitMemoIfNeeded(dayKey: currentDayKey)
                dismiss()
            } icon: {
                FoamChevronIcon(direction: -1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    moveDay(by: -1, from: currentDayKey)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FoamTheme.ink.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("前の日")

                Text(formattedDayTitle(currentDate))
                    .font(FoamFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(FoamTheme.ink.opacity(0.86))

                Button {
                    moveDay(by: 1, from: currentDayKey)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FoamTheme.ink.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("次の日")
            }

            Spacer()

            FoamRoundIconButton(accessibilityLabel: "時間を追加") {
                isMemoFocused = false
                commitMemoIfNeeded(dayKey: currentDayKey)
                openDraftEditor(day: day, dayStart: dayStart)
            } icon: {
                FoamPlusIcon()
            }
        }
    }

    // MARK: - Hero Total Hours + Compact "+?"

    @ViewBuilder
    private func heroDurationCloud(day: DaySummary) -> some View {
        let parts = FoamDurationFormatter.heroParts(for: day.totalRecordedSeconds)
        let unknownColor = Color(red: 0.78, green: 0.42, blue: 0.06)

        VStack(spacing: 2) {
            if day.totalRecordedSeconds > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if parts.hours > 0 {
                        Text("\(parts.hours)")
                            .font(FoamFont.bold(40, relativeTo: .largeTitle))
                        Text("時間")
                            .font(FoamFont.bold(19, relativeTo: .title3))
                        if parts.minutes > 0 {
                            Text("\(parts.minutes)")
                                .font(FoamFont.bold(34, relativeTo: .title))
                            Text("分")
                                .font(FoamFont.bold(17, relativeTo: .headline))
                        }
                    } else if parts.minutes > 0 {
                        Text("\(parts.minutes)")
                            .font(FoamFont.bold(40, relativeTo: .largeTitle))
                        Text("分")
                            .font(FoamFont.bold(19, relativeTo: .title3))
                    } else {
                        Text("\(parts.seconds)")
                            .font(FoamFont.bold(40, relativeTo: .largeTitle))
                        Text("秒")
                            .font(FoamFont.bold(19, relativeTo: .title3))
                    }

                    if day.hasUnknownEnd {
                        Text("+?")
                            .font(FoamFont.bold(24, relativeTo: .title2))
                            .foregroundStyle(unknownColor)
                            .padding(.leading, 4)
                    }
                }
                .foregroundStyle(FoamTheme.ink)
            } else if day.hasUnknownEnd {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("?")
                        .font(FoamFont.bold(38, relativeTo: .largeTitle))
                        .foregroundStyle(unknownColor)
                    Text("時間")
                        .font(FoamFont.bold(19, relativeTo: .title3))
                        .foregroundStyle(FoamTheme.ink)
                }
            } else if day.hasActiveSession {
                Text("いま一緒")
                    .font(FoamFont.bold(28, relativeTo: .title))
                    .foregroundStyle(FoamTheme.ink)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("0")
                        .font(FoamFont.bold(38, relativeTo: .largeTitle))
                    Text("時間")
                        .font(FoamFont.bold(19, relativeTo: .title3))
                }
                .foregroundStyle(FoamTheme.ink.opacity(0.42))
            }

            if day.hasActiveSession {
                Text("いま一緒")
                    .font(FoamFont.bold(11.5, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.warmAccent)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Soft Rounded Note Field + Corner Foam Tufts

    @ViewBuilder
    private func memoCloudCard(dayKey: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField(
                "",
                text: $memo,
                prompt: Text("この日のひとこと…")
                    .foregroundStyle(FoamTheme.ink.opacity(0.46)),
                axis: .vertical
            )
            .font(FoamFont.medium(15, relativeTo: .body))
            .foregroundStyle(FoamTheme.ink)
            .lineLimit(2...5)
            .focused($isMemoFocused)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

            if normalizedMemo != lastSyncedMemo {
                Button {
                    commitMemoIfNeeded(dayKey: dayKey)
                    isMemoFocused = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("保存")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(FoamTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(22),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 5.2,
                wobbleScale: 0.35,
                animated: false
            )
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: normalizedMemo != lastSyncedMemo)
    }

    // MARK: - Unified Spine Timeline Viewport

    @ViewBuilder
    private func timelineViewport(
        items: [TimelineRenderItem],
        day: DaySummary,
        dayStart: Date,
        scale: DayTimelineScale,
        axisHeight: CGFloat
    ) -> some View {
        let activeMergeIDs = activeMergeCandidateIDs()
        let totalHeight = axisHeight + timelinePadTop + timelinePadBottom
        let activeSelectedID = resolveSelectedID(items: items)
        let hasFocus = activeSelectedID != nil || activeDrag != nil
        let layoutPlan = computeTimelineLayout(
            for: items,
            scale: scale,
            axisHeight: axisHeight
        )

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Full-width tap catcher to deselect or commit/close open popover
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTimelineBackdropTap()
                    }

                // Unified axis spine & dynamic boundary ticks
                timelineGraduations(scale: scale, axisHeight: axisHeight)

                // Encounter bars along the same axis spine
                ForEach(items) { item in
                    let isSelected = (activeSelectedID == item.id)
                    let isDraggingItem = (activeDrag?.target == item.target)
                    let isAbsorbedTarget = item.target.encounter.map { activeMergeIDs.contains($0.id) } ?? false
                    let isDimmed = hasFocus && !isSelected && !isDraggingItem && !isAbsorbedTarget

                    timelineItemView(
                        item: item,
                        scale: scale,
                        axisHeight: axisHeight,
                        dayStart: dayStart,
                        isSelected: isSelected,
                        isFullInline: layoutPlan.fullInlineIDs.contains(item.id),
                        isDimmed: isDimmed,
                        isHighlightedForMerge: isAbsorbedTarget,
                        defaultLabelY: layoutPlan.compactLabelYByID[item.id] ?? rawCenterY(for: item, scale: scale, axisHeight: axisHeight)
                    )
                }

                if items.isEmpty {
                    VStack(spacing: 6) {
                        Text("右上の ＋ から")
                        Text("時間を追加できます")
                    }
                    .font(FoamFont.medium(13.5, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .position(x: geo.size.width * 0.56, y: timelinePadTop + axisHeight * 0.44)
                    .allowsHitTesting(false)
                }

                // Speech-bubble inline time picker pointing at the tapped Start/End timestamp
                if let editor = inlineEditor {
                    inlineSpeechBubbleView(
                        editor: editor,
                        scale: scale,
                        axisHeight: axisHeight,
                        containerSize: geo.size,
                        items: items
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .coordinateSpace(name: "dayTimeline")
        .clipped()
    }

    @ViewBuilder
    private func timelineGraduations(scale: DayTimelineScale, axisHeight: CGFloat) -> some View {
        let topTickY = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(scale.minMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )
        let bottomTickY = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(scale.maxMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )

        // Single vertical timeline spine centered at unifiedAxisX
        Capsule()
            .fill(FoamTheme.ink.opacity(0.16))
            .frame(width: 2, height: max(2, bottomTickY - topTickY))
            .position(x: unifiedAxisX, y: (topTickY + bottomTickY) * 0.5)
            .allowsHitTesting(false)

        boundaryTick(hour: scale.minHour, y: topTickY)
        boundaryTick(hour: scale.maxHour, y: bottomTickY)

        // Fine hourly/15-min ticks along the same spine when zoomed during 4x long-press drag
        if zoomFactor > 1.2 {
            let totalH = axisHeight + timelinePadTop + timelinePadBottom
            ForEach(scale.minHour...scale.maxHour, id: \.self) { hour in
                if hour > scale.minHour && hour < scale.maxHour {
                    let hY = timelinePadTop + CGFloat(
                        scale.yPosition(
                            forMinute: Double(hour * 60),
                            viewportHeight: Double(axisHeight),
                            zoomFactor: zoomFactor,
                            focusMinute: zoomFocusMinute
                        )
                    )
                    if hY >= 6 && hY <= totalH - 6 {
                        HStack(spacing: 4) {
                            Text("\(hour):00")
                                .font(FoamFont.medium(10.5, relativeTo: .caption2))
                                .foregroundStyle(FoamTheme.ink.opacity(0.50))
                                .frame(width: 38, alignment: .trailing)
                            Rectangle()
                                .fill(FoamTheme.ink.opacity(0.24))
                                .frame(width: 12, height: 1)
                        }
                        .position(x: 30, y: hY)
                        .allowsHitTesting(false)
                    }
                }

                if hour < scale.maxHour {
                    ForEach([15, 30, 45], id: \.self) { qMin in
                        let qY = timelinePadTop + CGFloat(
                            scale.yPosition(
                                forMinute: Double(hour * 60 + qMin),
                                viewportHeight: Double(axisHeight),
                                zoomFactor: zoomFactor,
                                focusMinute: zoomFocusMinute
                            )
                        )
                        if qY >= 6 && qY <= totalH - 6 {
                            Rectangle()
                                .fill(FoamTheme.ink.opacity(qMin == 30 ? 0.20 : 0.10))
                                .frame(width: qMin == 30 ? 9 : 5, height: 1)
                                .position(x: unifiedAxisX - (qMin == 30 ? 6.5 : 4.5), y: qY)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func boundaryTick(hour: Int, y: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text("\(hour):00")
                .font(FoamFont.bold(11.5, relativeTo: .caption2))
                .foregroundStyle(FoamTheme.ink.opacity(0.58))
                .frame(width: 40, alignment: .trailing)
            Capsule()
                .fill(FoamTheme.ink.opacity(0.32))
                .frame(width: 14, height: 2)
        }
        .position(x: 31, y: y)
        .allowsHitTesting(false)
    }

    // MARK: - Encounter Bar + Default Duration vs Selected Start/End

    @ViewBuilder
    private func timelineItemView(
        item: TimelineRenderItem,
        scale: DayTimelineScale,
        axisHeight: CGFloat,
        dayStart: Date,
        isSelected: Bool,
        isFullInline: Bool,
        isDimmed: Bool,
        isHighlightedForMerge: Bool,
        defaultLabelY: CGFloat
    ) -> some View {
        let topY = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(item.sliceStartMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )
        let rawBottomY = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(item.sliceEndMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )
        let actualSpan = max(2, rawBottomY - topY)
        let rawCenterY = (topY + rawBottomY) * 0.5
        let isDraggingItem = (activeDrag?.target == item.target)
        let showsKnobs = isSelected || isDraggingItem
        let minBarHeight: CGFloat = showsKnobs ? 36 : 12
        let visualSpan = max(minBarHeight, actualSpan)
        let visualTopY = actualSpan >= minBarHeight ? topY : (rawCenterY - visualSpan * 0.5)
        let visualBottomY = visualTopY + visualSpan

        // Merge highlight halo
        if isHighlightedForMerge {
            Capsule()
                .fill(FoamTheme.warmAccent.opacity(0.22))
                .frame(width: 28, height: visualSpan + 16)
                .position(x: unifiedAxisX, y: rawCenterY)
                .allowsHitTesting(false)
        }

        // Soap encounter pillar sitting cleanly on unifiedAxisX (tap to toggle selection)
        TimelineSoapStem(
            status: item.status,
            height: visualSpan,
            isSelected: isSelected || isDraggingItem,
            reduceMotion: reduceMotion
        )
        .frame(width: 44, height: max(36, visualSpan + 8))
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: item)
        }
        .position(x: unifiedAxisX, y: rawCenterY)
        .opacity(isDimmed ? 0.34 : 1.0)
        .zIndex(isSelected || isDraggingItem ? 4 : 1)

        if showsKnobs {
            let labelGap = visualBottomY - visualTopY
            let extraSpread: CGFloat = labelGap < 38 ? (38 - labelGap) * 0.5 : 0
            let startLabelY = visualTopY - extraSpread
            let endLabelY = visualBottomY + extraSpread

            // Top Pearl Knob (Start)
            timelineKnob(
                isWarning: false,
                isActiveDrag: isDraggingItem && activeDrag?.edge == .start,
                target: item.target,
                edge: .start,
                minute: item.sliceStartMinute,
                visualY: visualTopY,
                dayStart: dayStart,
                scale: scale,
                axisHeight: axisHeight,
                editable: item.canEditStart
            )
            .zIndex(6)

            // Bottom end control or live indicator
            timelineKnob(
                isWarning: item.status == .unknownEnd,
                isActiveDrag: isDraggingItem && activeDrag?.edge == .end,
                target: item.target,
                edge: .end,
                minute: item.sliceEndMinute,
                visualY: visualBottomY,
                dayStart: dayStart,
                scale: scale,
                axisHeight: axisHeight,
                editable: item.canEditEnd,
                isLiveEnd: item.status == .active
            )
            .zIndex(6)

            // Start Timestamp Pill
            let isEditingStart = inlineEditor?.target == item.target && inlineEditor?.focus == .start
            Button {
                openInlineEditor(for: item, focus: .start, dayStart: dayStart)
            } label: {
                HStack(spacing: 4) {
                    Text(formatMinute(item.sliceStartMinute))
                        .font(FoamFont.bold(15.5, relativeTo: .headline))
                        .foregroundStyle(FoamTheme.ink)
                    if item.continuesFromPreviousDay {
                        Text("前日〜")
                            .font(FoamFont.bold(9.5, relativeTo: .caption2))
                            .foregroundStyle(FoamTheme.ink.opacity(0.60))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isEditingStart ? Color.white : Color.white.opacity(0.76))
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isEditingStart ? FoamTheme.ink.opacity(0.28) : Color.white,
                                    lineWidth: isEditingStart ? 1.4 : 1.0
                                )
                        }
                        .shadow(color: FoamTheme.ink.opacity(isEditingStart ? 0.10 : 0.04), radius: 4, y: 1)
                )
            }
            .buttonStyle(TimelineTapButtonStyle())
            .disabled(!item.canEditStart)
            .frame(width: 96, alignment: .leading)
            .position(x: labelLeadX + 48, y: startLabelY)
            .zIndex(5)

            // Optional subtle duration readout centered inside tall selected bars
            if endLabelY - startLabelY >= 64 && item.status == .completed {
                let durSec = item.durationSeconds ?? TimeInterval(max(0, (item.sliceEndMinute - item.sliceStartMinute) * 60))
                Text(FoamDurationFormatter.compactDuration(durSec))
                    .font(FoamFont.medium(12, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.55))
                    .frame(width: 96, alignment: .leading)
                    .position(x: labelLeadX + 54, y: (startLabelY + endLabelY) * 0.5)
                    .allowsHitTesting(false)
                    .zIndex(4)
            }

            // End Timestamp Pill
            let isEditingEnd = inlineEditor?.target == item.target && inlineEditor?.focus == .end
            Button {
                openInlineEditor(for: item, focus: .end, dayStart: dayStart)
            } label: {
                HStack(spacing: 4) {
                    if item.status == .unknownEnd && item.target != .draft {
                        Text("?")
                            .font(FoamFont.bold(15.5, relativeTo: .headline))
                            .foregroundStyle(Color(red: 0.78, green: 0.42, blue: 0.06))
                    } else if item.status == .active {
                        Text("記録中")
                            .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                            .foregroundStyle(FoamTheme.warmAccent)
                    } else {
                        Text(formatMinute(item.sliceEndMinute))
                            .font(FoamFont.bold(15.5, relativeTo: .headline))
                            .foregroundStyle(FoamTheme.ink)
                        if item.continuesToNextDay {
                            Text("〜翌日")
                                .font(FoamFont.bold(9.5, relativeTo: .caption2))
                                .foregroundStyle(FoamTheme.ink.opacity(0.60))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isEditingEnd ? Color.white : (item.status == .unknownEnd ? Color.orange.opacity(0.14) : Color.white.opacity(0.76)))
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isEditingEnd ? FoamTheme.ink.opacity(0.28) : Color.white,
                                    lineWidth: isEditingEnd ? 1.4 : 1.0
                                )
                        }
                        .shadow(color: FoamTheme.ink.opacity(isEditingEnd ? 0.10 : 0.04), radius: 4, y: 1)
                )
            }
            .buttonStyle(TimelineTapButtonStyle())
            .disabled(!item.canEditEnd)
            .frame(width: 96, alignment: .leading)
            .position(x: labelLeadX + 48, y: endLabelY)
            .zIndex(5)
        } else if isFullInline {
            // Non-overlapping tall bar: show Start + Duration + End directly without collapsing
            Button {
                openInlineEditor(for: item, focus: .start, dayStart: dayStart)
            } label: {
                HStack(spacing: 4) {
                    Text(formatMinute(item.sliceStartMinute))
                        .font(FoamFont.bold(15, relativeTo: .headline))
                        .foregroundStyle(FoamTheme.ink.opacity(0.88))
                    if item.continuesFromPreviousDay {
                        Text("前日〜")
                            .font(FoamFont.bold(9.5, relativeTo: .caption2))
                            .foregroundStyle(FoamTheme.ink.opacity(0.58))
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.56), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(TimelineTapButtonStyle())
            .disabled(!item.canEditStart)
            .frame(width: 96, alignment: .leading)
            .position(x: labelLeadX + 48, y: topY)
            .opacity(isDimmed ? 0.24 : 1.0)
            .allowsHitTesting(!hasActiveInlineEditor)
            .zIndex(2)

            Button {
                toggleSelection(for: item)
            } label: {
                Group {
                    if item.status == .unknownEnd && item.target != .draft {
                        Text("+?")
                            .font(FoamFont.bold(12.5, relativeTo: .caption))
                            .foregroundStyle(Color(red: 0.78, green: 0.42, blue: 0.06))
                    } else if item.status == .active {
                        Text("いま一緒")
                            .font(FoamFont.bold(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.warmAccent)
                    } else {
                        let durSec = item.durationSeconds ?? TimeInterval(max(0, (item.sliceEndMinute - item.sliceStartMinute) * 60))
                        Text(FoamDurationFormatter.compactDuration(durSec))
                            .font(FoamFont.medium(12.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.60))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(TimelineTapButtonStyle())
            .frame(width: 96, alignment: .leading)
            .position(x: labelLeadX + 54, y: rawCenterY)
            .opacity(isDimmed ? 0.24 : 1.0)
            .allowsHitTesting(!hasActiveInlineEditor)
            .zIndex(2)

            Button {
                openInlineEditor(for: item, focus: .end, dayStart: dayStart)
            } label: {
                HStack(spacing: 4) {
                    if item.status == .unknownEnd && item.target != .draft {
                        Text("?")
                            .font(FoamFont.bold(15, relativeTo: .headline))
                            .foregroundStyle(Color(red: 0.78, green: 0.42, blue: 0.06))
                    } else if item.status == .active {
                        Text("記録中")
                            .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                            .foregroundStyle(FoamTheme.warmAccent)
                    } else {
                        Text(formatMinute(item.sliceEndMinute))
                            .font(FoamFont.bold(15, relativeTo: .headline))
                            .foregroundStyle(FoamTheme.ink.opacity(0.88))
                        if item.continuesToNextDay {
                            Text("〜翌日")
                                .font(FoamFont.bold(9.5, relativeTo: .caption2))
                                .foregroundStyle(FoamTheme.ink.opacity(0.58))
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(item.status == .unknownEnd ? Color.orange.opacity(0.14) : Color.white.opacity(0.56))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(TimelineTapButtonStyle())
            .disabled(!item.canEditEnd)
            .frame(width: 96, alignment: .leading)
            .position(x: labelLeadX + 48, y: rawBottomY)
            .opacity(isDimmed ? 0.24 : 1.0)
            .allowsHitTesting(!hasActiveInlineEditor)
            .zIndex(2)
        } else {
            // Default view: anti-collision duration-only label beside bar (leader line if nudged)
            if abs(defaultLabelY - rawCenterY) > 7 {
                Path { path in
                    path.move(to: CGPoint(x: unifiedAxisX + 9, y: rawCenterY))
                    path.addLine(to: CGPoint(x: labelLeadX - 5, y: defaultLabelY))
                }
                .stroke(FoamTheme.ink.opacity(isDimmed ? 0.10 : 0.22), lineWidth: 1)
                .allowsHitTesting(false)
            }

            Button {
                toggleSelection(for: item)
            } label: {
                defaultDurationPill(for: item)
            }
            .buttonStyle(TimelineTapButtonStyle())
            .frame(width: 140, alignment: .leading)
            .position(x: labelLeadX + 70, y: defaultLabelY)
            .opacity(isDimmed ? 0.24 : 1.0)
            .allowsHitTesting(!hasActiveInlineEditor)
            .zIndex(2)
        }
    }

    private var hasActiveInlineEditor: Bool {
        inlineEditor != nil
    }

    @ViewBuilder
    private func defaultDurationPill(for item: TimelineRenderItem) -> some View {
        Group {
            if item.status == .unknownEnd && item.target != .draft {
                Text("+?")
                    .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(Color(red: 0.78, green: 0.42, blue: 0.06))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            } else if item.status == .active {
                Text("いま一緒")
                    .font(FoamFont.bold(13, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.warmAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.75), in: Capsule())
            } else {
                let durSec = item.durationSeconds ?? TimeInterval(max(0, (item.sliceEndMinute - item.sliceStartMinute) * 60))
                Text(FoamDurationFormatter.compactDuration(durSec))
                    .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink.opacity(0.84))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Selected Pearl Knobs (Tap -> Wheel, Long-Press -> 4x Zoom Drag)

    @ViewBuilder
    private func timelineKnob(
        isWarning: Bool,
        isActiveDrag: Bool,
        target: TimelineTarget,
        edge: TimelineKnobEdge,
        minute: Int,
        visualY: CGFloat,
        dayStart: Date,
        scale: DayTimelineScale,
        axisHeight: CGFloat,
        editable: Bool,
        isLiveEnd: Bool = false
    ) -> some View {
        let knobCapsule = Capsule()
            .fill(
                isWarning
                    ? LinearGradient(
                        colors: [Color(red: 1.0, green: 0.96, blue: 0.88), Color(red: 1.0, green: 0.90, blue: 0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [.white, Color(red: 0.90, green: 0.92, blue: 0.97)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
            .frame(width: isActiveDrag ? 28 : 22, height: isActiveDrag ? 13 : 10)
            .overlay {
                if isWarning {
                    Capsule().strokeBorder(Color.orange.opacity(0.72), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                } else {
                    Capsule().strokeBorder(isActiveDrag ? FoamTheme.ink.opacity(0.55) : Color.white, lineWidth: 1.3)
                }
            }
            .shadow(color: FoamTheme.ink.opacity(isActiveDrag ? 0.22 : 0.14), radius: isActiveDrag ? 6 : 3, y: 1.5)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(isActiveDrag ? 1.12 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isActiveDrag)

        if isLiveEnd {
            Circle()
                .fill(FoamTheme.warmAccent.opacity(0.72))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                }
                .position(x: unifiedAxisX, y: visualY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if editable {
            knobCapsule
                .onTapGesture {
                    openInlineEditorForKnob(target: target, edge: edge, dayStart: dayStart)
                }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.22)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("dayTimeline")))
                        .onChanged { value in
                            switch value {
                            case .first(true):
                                break
                            case let .second(true, drag):
                                if activeDrag == nil {
                                    startKnobDrag(
                                        target: target,
                                        edge: edge,
                                        dayStart: dayStart,
                                        initialMinute: minute,
                                        frozenScale: scale,
                                        fingerY: drag?.location.y
                                    )
                                }
                                if let drag {
                                    updateKnobDrag(fingerY: drag.location.y, axisHeight: axisHeight)
                                }
                            default:
                                break
                            }
                        }
                        .onEnded { _ in
                            if activeDrag != nil {
                                finishKnobDrag()
                            }
                        }
                )
                .position(x: unifiedAxisX, y: visualY)
        } else {
            knobCapsule
                .position(x: unifiedAxisX, y: visualY)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Speech Bubble Inline Time Wheel Popover (IMG_7068.JPG)

    @ViewBuilder
    private func inlineSpeechBubbleView(
        editor: InlineTimeEditorState,
        scale: DayTimelineScale,
        axisHeight: CGFloat,
        containerSize: CGSize,
        items: [TimelineRenderItem]
    ) -> some View {
        let bubbleLeftX: CGFloat = 132
        let tailWidth: CGFloat = 10
        let totalBubbleWidth: CGFloat = min(224, max(190, containerSize.width - bubbleLeftX - 4))
        let bubbleHeight: CGFloat = editor.isActiveTarget ? 232 : ((editor.target == .draft || editor.hasUnknownOriginalEnd) ? 242 : 210)
        let totalH = axisHeight + timelinePadTop + timelinePadBottom

        // Point the `<` tail directly at the focused timestamp pill's Y
        let anchorY: CGFloat = {
            if let focusedItem = items.first(where: { $0.target == editor.target }) {
                let tY = timelinePadTop + CGFloat(
                    scale.yPosition(
                        forMinute: Double(focusedItem.sliceStartMinute),
                        viewportHeight: Double(axisHeight),
                        zoomFactor: zoomFactor,
                        focusMinute: zoomFocusMinute
                    )
                )
                let bY = timelinePadTop + CGFloat(
                    scale.yPosition(
                        forMinute: Double(focusedItem.sliceEndMinute),
                        viewportHeight: Double(axisHeight),
                        zoomFactor: zoomFactor,
                        focusMinute: zoomFocusMinute
                    )
                )
                let span = max(36, bY - tY)
                let vTop = (bY - tY) >= 36 ? tY : ((tY + bY) * 0.5 - span * 0.5)
                let vBot = vTop + span
                let spread: CGFloat = (vBot - vTop) < 38 ? (38 - (vBot - vTop)) * 0.5 : 0
                return editor.focus == .start ? (vTop - spread) : (vBot + spread)
            }
            return timelinePadTop + CGFloat(
                scale.yPosition(
                    forMinute: Double(editor.focusedMinuteOnDay),
                    viewportHeight: Double(axisHeight),
                    zoomFactor: zoomFactor,
                    focusMinute: zoomFocusMinute
                )
            )
        }()

        let minTopY: CGFloat = 4
        let maxTopY: CGFloat = max(minTopY, totalH - bubbleHeight - 4)
        let topY = min(maxTopY, max(minTopY, anchorY - bubbleHeight * 0.5))
        let tailLocalY = min(bubbleHeight - 28, max(28, anchorY - topY))

        let previewNow = max(editor.referenceNow, Date())
        let currentLive = editor.target.encounter.flatMap { model.currentResolvedEncounter(for: $0) }
        let mergePlan = self.mergePlan(for: editor, now: previewNow)
        let (isValid, invalidMessage): (Bool, String) = {
            if editor.isActiveTarget {
                if currentLive == nil {
                    return (false, "この記録は削除されました")
                } else if !editor.hasPendingMutation || mergePlan != nil {
                    return (true, "")
                } else {
                    return (false, currentLive?.status == .completed
                        ? "終了は開始より後にしてね"
                        : "開始は現在時刻より前にしてね")
                }
            } else if editor.target != .draft && currentLive == nil {
                return (false, "この記録は削除されました")
            } else {
                return (editor.effectiveEnd > editor.effectiveStart, "終了は開始より後にしてね")
            }
        }()

        VStack(spacing: 7) {
            if editor.isActiveTarget {
                Text("開始時刻（記録中）")
                    .font(FoamFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(FoamTheme.warmAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FoamTheme.cream.opacity(0.65), in: Capsule())
            } else if editor.target == .draft || editor.hasUnknownOriginalEnd {
                HStack(spacing: 4) {
                    focusToggleChip(
                        label: "開始 \(formatMinute(editor.startHour * 60 + editor.startMinute))",
                        active: editor.focus == .start
                    ) {
                        inlineEditor?.setFocus(.start)
                    }
                    focusToggleChip(
                        label: "終了 \(editor.endHour == 24 ? "24:00" : formatMinute(editor.endHour * 60 + editor.endMinute))",
                        active: editor.focus == .end
                    ) {
                        inlineEditor?.setFocus(.end)
                    }
                }
            }

            // Dual wheel pickers framed with center selection rectangle (IMG_7068.JPG)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FoamTheme.sky(together: model.isTogetherNow).opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(FoamTheme.ink.opacity(0.22), lineWidth: 1.2)
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 6)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    if editor.focus == .start {
                        Picker("時", selection: Binding(
                            get: { inlineEditor?.startHour ?? editor.startHour },
                            set: { newVal in
                                guard inlineEditor?.startHour != newVal else { return }
                                inlineEditor?.startHour = newVal
                                inlineEditor?.didTouchStart = true
                                inlineEditor?.didChangeWheel = true
                            }
                        )) {
                            ForEach(0..<24, id: \.self) { hr in
                                Text("\(hr)").tag(hr)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 64, height: 128)
                        .clipped()

                        Text(":")
                            .font(FoamFont.bold(18, relativeTo: .headline))
                            .foregroundStyle(FoamTheme.ink)
                            .padding(.horizontal, 2)

                        Picker("分", selection: Binding(
                            get: { inlineEditor?.startMinute ?? editor.startMinute },
                            set: { newVal in
                                guard inlineEditor?.startMinute != newVal else { return }
                                inlineEditor?.startMinute = newVal
                                inlineEditor?.didTouchStart = true
                                inlineEditor?.didChangeWheel = true
                            }
                        )) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 64, height: 128)
                        .clipped()
                    } else {
                        Picker("時", selection: Binding(
                            get: { inlineEditor?.endHour ?? editor.endHour },
                            set: { newVal in
                                guard inlineEditor?.endHour != newVal else { return }
                                inlineEditor?.endHour = newVal
                                if newVal == 24 {
                                    inlineEditor?.endMinute = 0
                                }
                                inlineEditor?.didTouchEnd = true
                                inlineEditor?.didChangeWheel = true
                            }
                        )) {
                            ForEach(0...24, id: \.self) { hr in
                                Text("\(hr)").tag(hr)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 64, height: 128)
                        .clipped()

                        Text(":")
                            .font(FoamFont.bold(18, relativeTo: .headline))
                            .foregroundStyle(FoamTheme.ink)
                            .padding(.horizontal, 2)

                        Picker("分", selection: Binding(
                            get: { inlineEditor?.endMinute ?? editor.endMinute },
                            set: { newVal in
                                guard inlineEditor?.endMinute != newVal else { return }
                                inlineEditor?.endMinute = newVal
                                inlineEditor?.didTouchEnd = true
                                inlineEditor?.didChangeWheel = true
                            }
                        )) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .disabled((inlineEditor?.endHour ?? editor.endHour) == 24)
                        .frame(width: 64, height: 128)
                        .clipped()
                    }
                }
            }

            if !isValid {
                Text(invalidMessage)
                    .font(FoamFont.bold(10.5, relativeTo: .caption2))
                    .foregroundStyle(.red)
            } else if mergePlan?.didMerge == true {
                Text(mergePlan?.keepsActiveSession == true && currentLive?.status != .active
                    ? "記録中の時間とくっつきます"
                    : "隣の記録とくっつきます")
                    .font(FoamFont.bold(10.5, relativeTo: .caption2))
                    .foregroundStyle(FoamTheme.warmAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(FoamTheme.cream.opacity(0.65), in: Capsule())
            }

            HStack {
                if editor.target == .draft || editor.isActiveTarget {
                    Button("キャンセル") {
                        inlineEditor = nil
                        if editor.target == .draft {
                            selectedItemID = nil
                        }
                    }
                    .font(FoamFont.medium(11.5, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.62))
                    .buttonStyle(.plain)
                } else if let enc = editor.target.encounter {
                    Button(role: .destructive) {
                        confirmDeleteTarget = enc
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(width: 30, height: 28)
                            .background(Color.red.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("削除")
                }

                Spacer()

                Button {
                    commitInlineEditor()
                } label: {
                    Text(mergePlan?.didMerge == true ? "くっつける" : "決定")
                        .font(FoamFont.bold(12.5, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            isValid ? FoamTheme.ink : FoamTheme.ink.opacity(0.28),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
        }
        .padding(.leading, tailWidth + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(width: totalBubbleWidth, height: editor.isActiveTarget ? bubbleHeight : nil)
        .background {
            SpeechBubbleShape(cornerRadius: 22, tailWidth: tailWidth, tailHeight: 16, tailY: tailLocalY)
                .fill(Color.white.opacity(0.96))
                .overlay {
                    SpeechBubbleShape(cornerRadius: 22, tailWidth: tailWidth, tailHeight: 16, tailY: tailLocalY)
                        .stroke(Color.white, lineWidth: 1.5)
                }
                .shadow(color: FoamTheme.ink.opacity(0.16), radius: 14, y: 5)
        }
        .environment(\.colorScheme, .light)
        .position(x: bubbleLeftX + totalBubbleWidth * 0.5, y: topY + bubbleHeight * 0.5)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .zIndex(20)
    }

    @ViewBuilder
    private func focusToggleChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FoamFont.bold(11, relativeTo: .caption2))
                .foregroundStyle(active ? .white : FoamTheme.ink.opacity(0.74))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    active ? FoamTheme.ink : Color.black.opacity(0.05),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeline Data, Layout & Anti-Collision Helpers

    private func buildRenderItems(day: DaySummary, dayStart: Date) -> [TimelineRenderItem] {
        var items: [TimelineRenderItem] = []
        let liveEndMinute = min(1440, Int(ceil(Date.now.timeIntervalSince(dayStart) / 60.0)))

        for slice in day.slices {
            let encounter = model.resolvedEncounters.first { $0.id == slice.encounterID }
            let target = encounter.map { TimelineTarget.existing($0) } ?? .draft

            var sMin = max(0, min(1440, Int(floor(slice.sliceStart.timeIntervalSince(dayStart) / 60.0))))
            var eMin: Int
            if let end = slice.sliceEnd {
                eMin = max(sMin, min(1440, Int(ceil(end.timeIntervalSince(dayStart) / 60.0))))
            } else if slice.status == .unknownEnd {
                eMin = min(1440, sMin + 45)
            } else {
                eMin = liveEndMinute
            }

            let isPendingTarget = (activeDrag == nil && inlineEditor == nil && pendingDragAdjustment?.target == target)

            if let drag = activeDrag, drag.target == target {
                if drag.edge == .start {
                    sMin = drag.currentMinute
                } else {
                    eMin = drag.currentMinute
                }
            } else if let editor = inlineEditor, editor.target == target {
                sMin = editor.displayStartMinuteOnDay
                if !editor.isActiveTarget {
                    eMin = editor.displayEndMinuteOnDay
                }
            } else if isPendingTarget, let pending = pendingDragAdjustment {
                sMin = max(0, min(1440, Int(floor(pending.proposedStart.timeIntervalSince(dayStart) / 60.0))))
                if let end = pending.proposedEnd {
                    eMin = max(sMin, min(1440, Int(ceil(end.timeIntervalSince(dayStart) / 60.0))))
                }
            }

            if slice.status == .active {
                eMin = min(1440, max(sMin + 15, liveEndMinute))
            }
            let status: SessionStatus = (inlineEditor?.target == target && slice.status == .unknownEnd && inlineEditor?.didTouchEnd == true)
                || (activeDrag?.target == target && activeDrag?.edge == .end)
                || (isPendingTarget && pendingDragAdjustment?.originalStatus != .active)
                ? .completed
                : slice.status

            let itemDuration: TimeInterval? = isPendingTarget
                ? pendingDragAdjustment.flatMap { pending in
                    pending.proposedEnd.map { max(0, $0.timeIntervalSince(pending.proposedStart)) }
                }
                : slice.durationSeconds

            items.append(
                TimelineRenderItem(
                    id: slice.id,
                    target: target,
                    sliceStartMinute: sMin,
                    sliceEndMinute: max(sMin, eMin),
                    status: status,
                    continuesFromPreviousDay: slice.fullStart < slice.sliceStart,
                    continuesToNextDay: (slice.sliceEnd.flatMap { se in slice.fullEnd.map { $0 > se } }) ?? false,
                    durationSeconds: itemDuration,
                    canEditStart: encounter != nil,
                    canEditEnd: slice.status != .active && encounter != nil,
                    dayKey: slice.dayKey
                )
            )
        }

        if let editor = inlineEditor, editor.target == .draft {
            let sMin = editor.startHour * 60 + editor.startMinute
            let eMin = editor.endHour == 24 ? 1440 : (editor.endHour * 60 + editor.endMinute)
            items.append(
                TimelineRenderItem(
                    id: "draft",
                    target: .draft,
                    sliceStartMinute: sMin,
                    sliceEndMinute: max(sMin + 5, eMin),
                    status: .completed,
                    continuesFromPreviousDay: false,
                    continuesToNextDay: false,
                    durationSeconds: TimeInterval(max(0, eMin - sMin) * 60),
                    canEditStart: true,
                    canEditEnd: true,
                    dayKey: day.dayKey
                )
            )
            items.sort { $0.sliceStartMinute < $1.sliceStartMinute }
        }

        return items
    }

    private func resolveSelectedID(items: [TimelineRenderItem]) -> String? {
        if let editor = inlineEditor {
            if editor.target == .draft { return "draft" }
            if let match = items.first(where: { $0.target == editor.target }) {
                return match.id
            }
        }
        if let pending = pendingDragAdjustment, items.contains(where: { $0.id == pending.itemID }) {
            return pending.itemID
        }
        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
            return selectedItemID
        }
        return nil
    }

    private func rawCenterY(for item: TimelineRenderItem, scale: DayTimelineScale, axisHeight: CGFloat) -> CGFloat {
        let y0 = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(item.sliceStartMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )
        let y1 = timelinePadTop + CGFloat(
            scale.yPosition(
                forMinute: Double(item.sliceEndMinute),
                viewportHeight: Double(axisHeight),
                zoomFactor: zoomFactor,
                focusMinute: zoomFocusMinute
            )
        )
        return (y0 + y1) * 0.5
    }

    private func computeTimelineLayout(
        for items: [TimelineRenderItem],
        scale: DayTimelineScale,
        axisHeight: CGFloat
    ) -> TimelineLayoutPlan {
        guard !items.isEmpty else {
            return TimelineLayoutPlan(fullInlineIDs: [], compactLabelYByID: [:])
        }

        struct ItemMetrics {
            let item: TimelineRenderItem
            let topY: CGFloat
            let bottomY: CGFloat
            var span: CGFloat { bottomY - topY }
            var centerY: CGFloat { (topY + bottomY) * 0.5 }
        }

        let metrics: [ItemMetrics] = items.map { item in
            let tY = timelinePadTop + CGFloat(
                scale.yPosition(
                    forMinute: Double(item.sliceStartMinute),
                    viewportHeight: Double(axisHeight),
                    zoomFactor: zoomFactor,
                    focusMinute: zoomFocusMinute
                )
            )
            let bY = timelinePadTop + CGFloat(
                scale.yPosition(
                    forMinute: Double(item.sliceEndMinute),
                    viewportHeight: Double(axisHeight),
                    zoomFactor: zoomFactor,
                    focusMinute: zoomFocusMinute
                )
            )
            return ItemMetrics(item: item, topY: tY, bottomY: max(tY, bY))
        }
        .sorted { lhs, rhs in
            if lhs.topY == rhs.topY {
                if lhs.bottomY == rhs.bottomY { return lhs.item.id < rhs.item.id }
                return lhs.bottomY < rhs.bottomY
            }
            return lhs.topY < rhs.topY
        }

        // Pass 1: Tentatively show Start + Duration + End inline on bars >= 54pt tall
        var fullInlineIDs = Set<String>()
        for m in metrics where m.span >= 54 {
            fullInlineIDs.insert(m.item.id)
        }

        // Pass 2: If adjacent full-inline bars are closer than 24pt, collapse the shorter one
        var removedOverlap = true
        while removedOverlap {
            removedOverlap = false
            let activeFull = metrics.filter { fullInlineIDs.contains($0.item.id) }
            if activeFull.count >= 2 {
                for i in 0..<(activeFull.count - 1) {
                    let prev = activeFull[i]
                    let next = activeFull[i + 1]
                    if next.topY - prev.bottomY < 24 {
                        let dropID = prev.span < next.span ? prev.item.id : next.item.id
                        fullInlineIDs.remove(dropID)
                        removedOverlap = true
                        break
                    }
                }
            }
        }

        // Pass 3: Place compact duration-only labels avoiding both full-inline bands and each other
        let occupiedBands: [(lower: CGFloat, upper: CGFloat)] = metrics
            .filter { fullInlineIDs.contains($0.item.id) }
            .map { ($0.topY - 12, $0.bottomY + 12) }

        let compactMetrics = metrics.filter { !fullInlineIDs.contains($0.item.id) }
        guard !compactMetrics.isEmpty else {
            return TimelineLayoutPlan(fullInlineIDs: fullInlineIDs, compactLabelYByID: [:])
        }

        let minSpacing: CGFloat = 25
        let topBound: CGFloat = max(14, timelinePadTop - 6)
        let bottomBound: CGFloat = timelinePadTop + axisHeight + max(10, timelinePadBottom - 12)

        func pushClearOfOccupied(_ y: CGFloat, upward: Bool) -> CGFloat {
            var current = y
            var changed = true
            var guardCount = 0
            while changed && guardCount <= occupiedBands.count {
                changed = false
                guardCount += 1
                if upward {
                    for band in occupiedBands.reversed() where current > band.lower - 13 && current < band.upper + 13 {
                        current = band.lower - 13
                        changed = true
                    }
                } else {
                    for band in occupiedBands where current > band.lower - 13 && current < band.upper + 13 {
                        current = band.upper + 13
                        changed = true
                    }
                }
            }
            return current
        }

        var compactYs = [CGFloat]()
        compactYs.reserveCapacity(compactMetrics.count)
        for m in compactMetrics {
            var candidate = min(bottomBound, max(topBound, m.centerY))
            if let prev = compactYs.last {
                candidate = max(candidate, prev + minSpacing)
            }
            candidate = pushClearOfOccupied(candidate, upward: false)
            compactYs.append(candidate)
        }

        if let last = compactYs.last, last > bottomBound {
            compactYs[compactYs.count - 1] = max(topBound, pushClearOfOccupied(bottomBound, upward: true))
            for i in stride(from: compactYs.count - 2, through: 0, by: -1) {
                var candidate = min(compactYs[i], compactYs[i + 1] - minSpacing)
                candidate = pushClearOfOccupied(candidate, upward: true)
                compactYs[i] = max(topBound, candidate)
            }
        }

        var labelYByID: [String: CGFloat] = [:]
        for (m, y) in zip(compactMetrics, compactYs) {
            labelYByID[m.item.id] = y
        }
        return TimelineLayoutPlan(fullInlineIDs: fullInlineIDs, compactLabelYByID: labelYByID)
    }

    private func toggleSelection(for item: TimelineRenderItem) {
        if inlineEditor != nil {
            commitInlineEditorOnBackdropTap()
            return
        }
        if let pending = pendingDragAdjustment {
            if pending.target == item.target {
                return
            }
            pendingDragAdjustment = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            if selectedItemID == item.id {
                selectedItemID = nil
            } else {
                selectedItemID = item.id
            }
        }
    }

    private func handleTimelineBackdropTap() {
        isMemoFocused = false
        if inlineEditor != nil {
            commitInlineEditorOnBackdropTap()
            return
        }
        if pendingDragAdjustment != nil {
            return
        }
        if selectedItemID != nil {
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84)) {
                selectedItemID = nil
            }
        }
    }

    private func liveExtraMinutes(dayStart: Date) -> [Int] {
        var extra: [Int] = []
        if let drag = activeDrag {
            extra.append(drag.currentMinute)
        }
        if let editor = inlineEditor {
            extra.append(editor.displayStartMinuteOnDay)
            if !editor.isActiveTarget {
                extra.append(editor.displayEndMinuteOnDay)
            }
        }
        if let pending = pendingDragAdjustment {
            extra.append(max(0, min(1440, Int(floor(pending.proposedStart.timeIntervalSince(dayStart) / 60.0)))))
            if let end = pending.proposedEnd {
                extra.append(max(0, min(1440, Int(ceil(end.timeIntervalSince(dayStart) / 60.0)))))
            }
        }
        return extra
    }

    private func activeMergeCandidateIDs() -> Set<UUID> {
        let plan: EncounterMergePlan?
        if let drag = activeDrag {
            plan = mergePlan(for: drag)
        } else if let editor = inlineEditor {
            plan = mergePlan(for: editor, now: max(editor.referenceNow, Date()))
        } else if let pending = pendingDragAdjustment {
            plan = mergePlan(for: pending, now: Date())
        } else {
            plan = nil
        }

        guard let plan, plan.didMerge else { return [] }
        return Set(plan.absorbed.map(\.id))
    }

    private func liveActiveStartPreview(
        for encounter: ResolvedEncounter,
        proposedStart: Date,
        now: Date
    ) -> (plan: EncounterMergePlan, current: ResolvedEncounter)? {
        guard let current = model.currentResolvedEncounter(for: encounter) else { return nil }
        switch current.status {
        case .active:
            guard proposedStart <= max(current.startedAt, now) else { return nil }
            return (model.previewMerge(editing: current, startedAt: proposedStart, endedAt: nil, now: now), current)
        case .completed:
            guard let end = current.endedAt, end > proposedStart else { return nil }
            return (model.previewMerge(editing: current, startedAt: proposedStart, endedAt: end, now: now), current)
        case .unknownEnd:
            guard proposedStart <= max(current.startedAt, now) else { return nil }
            return (EncounterMergePlan(target: current, absorbed: [], mergedStart: proposedStart, mergedEnd: nil), current)
        }
    }

    private func mergePlan(for drag: ActiveKnobDrag, minute: Int? = nil) -> EncounterMergePlan? {
        guard let encounter = drag.target.encounter else { return nil }
        let adjustedDate = drag.dayStart.addingTimeInterval(Double((minute ?? drag.currentMinute) * 60))
        let start = drag.edge == .start ? adjustedDate : drag.originalStartDate
        if drag.edge == .start && encounter.status == .active {
            return liveActiveStartPreview(for: encounter, proposedStart: start, now: drag.referenceNow)?.plan
        }

        guard let current = model.currentResolvedEncounter(for: encounter) else { return nil }
        let end = drag.edge == .end ? adjustedDate : (drag.originalEndDate ?? drag.fixedOtherDate)
        guard end > start else { return nil }
        return model.previewMerge(editing: current, startedAt: start, endedAt: end, now: drag.referenceNow)
    }

    private func mergePlan(for editor: InlineTimeEditorState, now: Date) -> EncounterMergePlan? {
        guard editor.hasPendingMutation else { return nil }
        if editor.isActiveTarget {
            guard let enc = editor.target.encounter else { return nil }
            return liveActiveStartPreview(for: enc, proposedStart: editor.effectiveStart, now: now)?.plan
        }
        guard editor.effectiveEnd > editor.effectiveStart else { return nil }
        if let enc = editor.target.encounter {
            guard let current = model.currentResolvedEncounter(for: enc) else { return nil }
            return model.previewMerge(
                editing: current,
                startedAt: editor.effectiveStart,
                endedAt: editor.effectiveEnd,
                now: now
            )
        }
        return model.previewMerge(
            editing: nil,
            startedAt: editor.effectiveStart,
            endedAt: editor.effectiveEnd,
            now: now
        )
    }

    private func mergePlan(for pending: PendingKnobAdjustment, now: Date) -> EncounterMergePlan? {
        guard let enc = pending.target.encounter else { return nil }
        if pending.originalStatus == .active {
            return liveActiveStartPreview(for: enc, proposedStart: pending.proposedStart, now: now)?.plan
        }
        guard let current = model.currentResolvedEncounter(for: enc),
              let end = pending.proposedEnd,
              end > pending.proposedStart else { return nil }
        return model.previewMerge(
            editing: current,
            startedAt: pending.proposedStart,
            endedAt: end,
            now: now
        )
    }

    private func dragStatusInfo(for drag: ActiveKnobDrag?) -> (text: String, isMerging: Bool)? {
        guard let drag else { return nil }
        if let plan = mergePlan(for: drag), plan.didMerge {
            if plan.keepsActiveSession && plan.target?.status != .active {
                return ("記録中の時間と重なっています（\(formatMinute(drag.currentMinute))）", true)
            }
            return ("隣の記録と重なっています（\(formatMinute(drag.currentMinute))）", true)
        }
        return ("\(formatMinute(drag.currentMinute))（1分単位で拡大調整中）", false)
    }

    @ViewBuilder
    private func pendingAdjustmentBar(pending: PendingKnobAdjustment) -> some View {
        let now = Date()
        let startMin = max(0, min(1440, Int(floor(pending.proposedStart.timeIntervalSince(pending.dayStart) / 60.0))))
        let endMin = pending.proposedEnd.map {
            max(startMin, min(1440, Int(ceil($0.timeIntervalSince(pending.dayStart) / 60.0))))
        }
        let current = pending.target.encounter.flatMap { model.currentResolvedEncounter(for: $0) }
        let mergePlan = self.mergePlan(for: pending, now: now)
        let staysActive = (current?.status == .active) || (mergePlan?.keepsActiveSession == true)
        let endLabel = staysActive ? "記録中" : formatMinute(endMin ?? startMin)
        let canCommit = mergePlan != nil

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatMinute(startMin)) 〜 \(endLabel)")
                    .font(FoamFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink)
                if !canCommit {
                    Text(current == nil ? "この記録は削除されました" : "終了時刻より前に調整してください")
                        .font(FoamFont.bold(10.5, relativeTo: .caption2))
                        .foregroundStyle(.red)
                } else if mergePlan?.didMerge == true {
                    Text(mergePlan?.keepsActiveSession == true && current?.status != .active
                        ? "記録中の時間とくっつきます"
                        : "隣の記録とくっつきます")
                        .font(FoamFont.bold(10.5, relativeTo: .caption2))
                        .foregroundStyle(FoamTheme.warmAccent)
                }
            }

            Spacer(minLength: 4)

            Button {
                cancelPendingDragAdjustment()
            } label: {
                Text("取り消し")
                    .font(FoamFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.76))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                commitPendingDragAdjustment()
            } label: {
                Text(mergePlan?.didMerge == true ? "くっつける" : "決定")
                    .font(FoamFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(canCommit ? FoamTheme.ink : FoamTheme.ink.opacity(0.28), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.94), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                mergePlan?.didMerge == true ? FoamTheme.warmAccent.opacity(0.45) : Color.white,
                lineWidth: 1.2
            )
        }
        .shadow(color: FoamTheme.ink.opacity(0.09), radius: 8, y: 3)
    }

    private func commitPendingDragAdjustment() {
        guard let pending = pendingDragAdjustment,
              let enc = pending.target.encounter else { return }
        let now = Date()
        guard let plan = mergePlan(for: pending, now: now) else {
            if model.currentResolvedEncounter(for: enc) == nil {
                pendingDragAdjustment = nil
                selectedItemID = nil
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if pending.originalStatus == .active {
            model.updateActiveEncounterStart(enc, startedAt: pending.proposedStart, now: now)
        } else {
            guard let end = pending.proposedEnd, end > pending.proposedStart else { return }
            if pending.originalStatus == .unknownEnd {
                model.completeUnknownEnd(enc, startedAt: pending.proposedStart, endedAt: end, now: now)
            } else {
                model.updateResolvedEncounter(enc, startedAt: pending.proposedStart, endedAt: end, now: now)
            }
        }
        if model.journalError == nil {
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84)) {
                pendingDragAdjustment = nil
                let dayKey = EncounterCalendarAggregator.dayKey(for: pending.dayStart)
                if let surviving = plan.survivingActiveEncounter,
                   let postCommit = model.currentResolvedEncounter(for: surviving) {
                    selectedItemID = "\(postCommit.id.uuidString)_\(dayKey)"
                } else if let postCommit = model.currentResolvedEncounter(for: enc) {
                    selectedItemID = "\(postCommit.id.uuidString)_\(dayKey)"
                }
            }
        }
    }

    private func cancelPendingDragAdjustment() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84)) {
            pendingDragAdjustment = nil
        }
    }

    // MARK: - 4x Zoom Knob Drag (Long-Press + Drag)

    private func startKnobDrag(
        target: TimelineTarget,
        edge: TimelineKnobEdge,
        dayStart: Date,
        initialMinute: Int,
        frozenScale: DayTimelineScale,
        fingerY: CGFloat?
    ) {
        guard let enc = target.encounter, !(enc.status == .active && edge == .end) else { return }
        let dragNow = Date()
        let isActive = enc.status == .active
        inlineEditor = nil
        isMemoFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let currentStart: Date
        let currentEnd: Date?
        if let pending = pendingDragAdjustment, pending.target == target {
            currentStart = pending.proposedStart
            currentEnd = pending.proposedEnd ?? enc.endedAt
        } else {
            pendingDragAdjustment = nil
            currentStart = enc.startedAt
            currentEnd = enc.endedAt
        }

        let fixedOtherDate: Date
        if isActive {
            fixedOtherDate = max(currentStart, dragNow)
        } else if edge == .start {
            fixedOtherDate = currentEnd ?? currentStart.addingTimeInterval(1800)
        } else {
            fixedOtherDate = currentStart
        }

        let initialClamped = max(0, min(isActive ? 1439 : 1440, initialMinute))
        activeDrag = ActiveKnobDrag(
            target: target,
            edge: edge,
            dayStart: dayStart,
            referenceNow: dragNow,
            fixedOtherDate: fixedOtherDate,
            originalStartDate: currentStart,
            originalEndDate: isActive ? nil : currentEnd,
            frozenScale: frozenScale,
            initialMinute: initialClamped,
            currentMinute: initialClamped,
            anchorZoomMinute: Double(initialClamped),
            startFingerY: fingerY
        )

        zoomFocusMinute = Double(initialClamped)
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84)) {
            zoomFactor = 4.0
        }
    }

    private func updateKnobDrag(fingerY: CGFloat, axisHeight: CGFloat) {
        guard var drag = activeDrag else { return }
        if drag.startFingerY == nil {
            drag.startFingerY = fingerY
            activeDrag = drag
            return
        }
        let startY = drag.startFingerY!
        let ptsPerMin = drag.frozenScale.ptsPerMinute(viewportHeight: Double(axisHeight), zoomFactor: 4.0)
        guard ptsPerMin > 0 else { return }
        let deltaMinutes = Int(round(Double(fingerY - startY) / ptsPerMin))
        var nextMinute = max(0, min(1440, drag.initialMinute + deltaMinutes))

        if drag.target.encounter?.status == .active {
            let limit = max(drag.originalStartDate, drag.referenceNow)
            let limitMinute = Int(floor(limit.timeIntervalSince(drag.dayStart) / 60.0))
            nextMinute = min(nextMinute, max(0, min(1439, limitMinute)))
        } else if drag.edge == .start {
            let maxAllowedStartDate = drag.fixedOtherDate.addingTimeInterval(-60)
            let maxStartMin = Int(floor(maxAllowedStartDate.timeIntervalSince(drag.dayStart) / 60.0))
            nextMinute = min(nextMinute, max(0, maxStartMin))
        } else {
            let minAllowedEndDate = drag.fixedOtherDate.addingTimeInterval(60)
            let minEndMin = Int(ceil(minAllowedEndDate.timeIntervalSince(drag.dayStart) / 60.0))
            nextMinute = max(nextMinute, min(1440, minEndMin))
        }

        if nextMinute != drag.currentMinute {
            let willMerge = mergePlan(for: drag, minute: nextMinute)?.didMerge == true
            if willMerge && !drag.didTriggerMergeHaptic {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            drag.currentMinute = nextMinute
            drag.didTriggerMergeHaptic = willMerge
            activeDrag = drag
        }
    }

    private func finishKnobDrag() {
        guard let drag = activeDrag else { return }
        defer {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.84)) {
                zoomFactor = 1.0
                activeDrag = nil
            }
        }

        guard let enc = drag.target.encounter else { return }
        let matchingPending = pendingDragAdjustment?.target == drag.target ? pendingDragAdjustment : nil
        if drag.currentMinute == drag.initialMinute && matchingPending == nil && enc.status != .unknownEnd {
            return
        }

        let adjustedDate = drag.dayStart.addingTimeInterval(Double(drag.currentMinute * 60))
        let finalStart = drag.edge == .start ? adjustedDate : drag.originalStartDate
        let finalEnd: Date?
        if enc.status == .active {
            guard adjustedDate <= max(enc.startedAt, drag.referenceNow) else { return }
            finalEnd = nil
        } else {
            let end = drag.edge == .end ? adjustedDate : (drag.originalEndDate ?? drag.fixedOtherDate)
            guard end > finalStart else { return }
            finalEnd = end
        }

        let itemID = "\(enc.id.uuidString)_\(EncounterCalendarAggregator.dayKey(for: drag.dayStart))"
        var pending = matchingPending.flatMap { $0.originalStatus == enc.status ? $0 : nil } ?? PendingKnobAdjustment(
            target: drag.target,
            itemID: itemID,
            dayStart: drag.dayStart,
            originalStart: enc.startedAt,
            originalEnd: enc.endedAt,
            originalStatus: enc.status,
            proposedStart: finalStart,
            proposedEnd: finalEnd
        )
        pending.proposedStart = finalStart
        pending.proposedEnd = finalEnd
        if pending.originalStatus != .unknownEnd,
           pending.proposedStart == pending.originalStart,
           pending.proposedEnd == pending.originalEnd {
            pendingDragAdjustment = nil
        } else {
            pendingDragAdjustment = pending
            selectedItemID = itemID
        }
    }

    // MARK: - Inline Speech-Bubble Wheel Helpers

    private func openInlineEditor(for item: TimelineRenderItem, focus: TimelineKnobEdge, dayStart: Date) {
        guard focus == .start ? item.canEditStart : item.canEditEnd else { return }
        isMemoFocused = false
        selectedItemID = item.id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openInlineEditor(target: item.target, focus: focus, dayStart: dayStart, item: item)
    }

    private func openInlineEditorForKnob(target: TimelineTarget, edge: TimelineKnobEdge, dayStart: Date) {
        guard !(target.encounter?.status == .active && edge == .end) else { return }
        openInlineEditor(target: target, focus: edge, dayStart: dayStart)
    }

    private func openInlineEditor(
        target: TimelineTarget,
        focus: TimelineKnobEdge,
        dayStart: Date,
        item: TimelineRenderItem? = nil
    ) {
        if target == .draft {
            inlineEditor?.setFocus(focus)
            return
        }
        guard let enc = target.encounter else { return }
        let isActive = enc.status == .active
        let matchingPending = pendingDragAdjustment?.target == target ? pendingDragAdjustment : nil
        pendingDragAdjustment = nil

        let baseStart = matchingPending?.proposedStart ?? enc.startedAt
        let baseEnd = isActive ? nil : (matchingPending?.proposedEnd ?? enc.endedAt)
        let originalStartMinute = Int(floor(baseStart.timeIntervalSince(dayStart) / 60.0))
        let shownStartMinute = matchingPending == nil ? (item?.sliceStartMinute ?? originalStartMinute) : originalStartMinute
        let sMin = max(0, min(isActive ? 1439 : 1440, shownStartMinute))
        let eMin: Int
        if isActive {
            eMin = sMin
        } else if matchingPending == nil, let item, enc.status != .unknownEnd {
            eMin = item.sliceEndMinute
        } else {
            eMin = baseEnd.map { max(sMin, min(1440, Int(ceil($0.timeIntervalSince(dayStart) / 60.0)))) }
                ?? min(1440, sMin + 60)
        }
        let hasUnknownOriginalEnd = enc.status == .unknownEnd && matchingPending == nil
        let resolvedFocus: TimelineKnobEdge = isActive ? .start : (hasUnknownOriginalEnd ? .end : focus)

        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            inlineEditor = InlineTimeEditorState(
                target: .existing(enc),
                focus: resolvedFocus,
                dayStart: dayStart,
                originalStart: baseStart,
                originalEnd: baseEnd,
                hasUnknownOriginalEnd: hasUnknownOriginalEnd,
                isActiveTarget: isActive,
                referenceNow: Date(),
                startHour: min(23, sMin / 60),
                startMinute: sMin % 60,
                endHour: min(24, eMin / 60),
                endMinute: eMin >= 1440 ? 0 : (eMin % 60),
                didTouchStart: matchingPending.map { $0.proposedStart != $0.originalStart } ?? false,
                didTouchEnd: !isActive && (enc.status == .unknownEnd
                    || (matchingPending.map { $0.proposedEnd != $0.originalEnd } ?? false))
            )
        }
    }

    private func openDraftEditor(day: DaySummary, dayStart: Date) {
        pendingDragAdjustment = nil
        var defaultStartMin = 13 * 60
        if let lastEnd = day.slices.compactMap(\.sliceEnd).max() {
            let candidateMin = Int(ceil(lastEnd.timeIntervalSince(dayStart) / 60.0)) + 60
            if candidateMin >= 0 && candidateMin <= 22 * 60 {
                let occupiedDefault = day.slices.contains { slice in
                    guard let se = slice.sliceEnd else { return false }
                    let sM = Int(floor(slice.sliceStart.timeIntervalSince(dayStart) / 60.0))
                    let eM = Int(ceil(se.timeIntervalSince(dayStart) / 60.0))
                    return sM <= (defaultStartMin + 60) && eM >= defaultStartMin
                }
                if occupiedDefault {
                    defaultStartMin = candidateMin
                }
            }
        }
        let defaultEndMin = min(1440, defaultStartMin + 60)
        selectedItemID = "draft"
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82)) {
            inlineEditor = InlineTimeEditorState(
                target: .draft,
                focus: .start,
                dayStart: dayStart,
                originalStart: dayStart.addingTimeInterval(Double(defaultStartMin * 60)),
                originalEnd: dayStart.addingTimeInterval(Double(defaultEndMin * 60)),
                hasUnknownOriginalEnd: false,
                isActiveTarget: false,
                referenceNow: Date(),
                startHour: defaultStartMin / 60,
                startMinute: defaultStartMin % 60,
                endHour: defaultEndMin / 60,
                endMinute: defaultEndMin >= 1440 ? 0 : (defaultEndMin % 60),
                didTouchStart: true,
                didTouchEnd: true
            )
        }
    }

    private func commitInlineEditorOnBackdropTap() {
        guard let editor = inlineEditor else { return }
        if editor.target == .draft {
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85)) {
                inlineEditor = nil
                selectedItemID = nil
            }
            return
        }
        let now = Date()
        let previewNow = editor.isActiveTarget ? max(editor.referenceNow, now) : now
        let plan = mergePlan(for: editor, now: previewNow)
        let shouldCommit = !editor.hasUnknownOriginalEnd
            && (editor.didTouchStart || editor.didTouchEnd)
            && plan != nil
            && plan?.didMerge != true
        if shouldCommit {
            commitInlineEditor()
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85)) {
                inlineEditor = nil
            }
        }
    }

    private func commitInlineEditor() {
        guard let editor = inlineEditor else { return }
        guard editor.hasPendingMutation else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85)) {
                inlineEditor = nil
            }
            return
        }
        let now = Date()
        let previewNow = editor.isActiveTarget ? max(editor.referenceNow, now) : now
        guard let plan = mergePlan(for: editor, now: previewNow) else {
            if let enc = editor.target.encounter, model.currentResolvedEncounter(for: enc) == nil {
                withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85)) {
                    inlineEditor = nil
                    selectedItemID = nil
                }
            }
            return
        }

        let finalStart = editor.effectiveStart
        if editor.isActiveTarget {
            guard case let .existing(enc) = editor.target else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.updateActiveEncounterStart(enc, startedAt: finalStart, now: previewNow)
        } else {
            let finalEnd = editor.effectiveEnd
            guard finalEnd > finalStart else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switch editor.target {
            case .draft:
                model.addManualEncounter(startedAt: finalStart, endedAt: finalEnd, now: now)
            case let .existing(enc):
                if enc.status == .unknownEnd {
                    model.completeUnknownEnd(enc, startedAt: finalStart, endedAt: finalEnd, now: now)
                } else {
                    model.updateResolvedEncounter(enc, startedAt: finalStart, endedAt: finalEnd, now: now)
                }
            }
        }

        if model.journalError == nil {
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85)) {
                inlineEditor = nil
                let dayKey = EncounterCalendarAggregator.dayKey(for: editor.dayStart)
                if let surviving = plan.survivingActiveEncounter,
                   let postCommit = model.currentResolvedEncounter(for: surviving) {
                    selectedItemID = "\(postCommit.id.uuidString)_\(dayKey)"
                } else if let enc = editor.target.encounter,
                          let postCommit = model.currentResolvedEncounter(for: enc) {
                    selectedItemID = "\(postCommit.id.uuidString)_\(dayKey)"
                } else if editor.target == .draft {
                    selectedItemID = nil
                }
            }
        }
    }

    // MARK: - Formatting & Day Switching

    private func formatMinute(_ totalMinute: Int) -> String {
        let clamped = max(0, min(1440, totalMinute))
        let h = clamped / 60
        let m = clamped % 60
        return String(format: "%d:%02d", h, m)
    }

    private func formattedDayTitle(_ date: Date) -> String {
        let md = date.formatted(.dateTime.month().day().locale(Locale(identifier: "ja_JP")))
        let wd = date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ja_JP")))
        return "\(md) (\(wd))"
    }

    private func moveDay(by offset: Int, from currentDayKey: String) {
        commitMemoIfNeeded(dayKey: currentDayKey)
        isMemoFocused = false
        inlineEditor = nil
        pendingDragAdjustment = nil
        selectedItemID = nil
        activeDrag = nil
        zoomFactor = 1.0
        guard let nextDate = Calendar.current.date(byAdding: .day, value: offset, to: currentDate) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            currentDate = nextDate
        }
        let nextMemo = model.daySummary(for: nextDate).memo ?? ""
        memo = nextMemo
        lastSyncedMemo = nextMemo
    }

    private func commitMemoIfNeeded(dayKey: String) {
        guard normalizedMemo != lastSyncedMemo else { return }
        model.saveMemo(dayKey: dayKey, text: memo)
        if model.journalError == nil {
            let saved = model.journal.dailyMemos[dayKey]?.text ?? ""
            memo = saved
            lastSyncedMemo = saved
        }
    }
}

/// Speech bubble container shape with a crisp left pointer tail `<` aiming at the focused timestamp.
private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat
    var tailWidth: CGFloat
    var tailHeight: CGFloat
    var tailY: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min((rect.width - tailWidth) * 0.5, rect.height * 0.5))
        let halfTail = tailHeight * 0.5
        let clampedTailY = min(rect.maxY - r - halfTail, max(rect.minY + r + halfTail, tailY))
        let bodyLeft = rect.minX + tailWidth

        var p = Path()
        p.move(to: CGPoint(x: bodyLeft + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: bodyLeft + r, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: bodyLeft, y: rect.maxY - r),
            control: CGPoint(x: bodyLeft, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: bodyLeft, y: clampedTailY + halfTail))
        p.addLine(to: CGPoint(x: rect.minX, y: clampedTailY))
        p.addLine(to: CGPoint(x: bodyLeft, y: clampedTailY - halfTail))
        p.addLine(to: CGPoint(x: bodyLeft, y: rect.minY + r))
        p.addQuadCurve(
            to: CGPoint(x: bodyLeft + r, y: rect.minY),
            control: CGPoint(x: bodyLeft, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// Vertical white glossy soap bar centered on the unified timeline spine.
private struct TimelineSoapStem: View {
    let status: SessionStatus
    let height: CGFloat
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || status != .active)) { timeline in
            let pulse: CGFloat = status == .active
                ? 1.0 + CGFloat(sin(timeline.date.timeIntervalSinceReferenceDate * 3.0)) * 0.055
                : 1.0
            let barWidth: CGFloat = isSelected ? 16 : 14

            if status == .unknownEnd {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.68),
                                Color(red: 1.0, green: 0.94, blue: 0.82).opacity(0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Color.orange.opacity(0.65),
                                style: StrokeStyle(lineWidth: 1.4, dash: [4, 4])
                            )
                    }
                    .scaleEffect(x: pulse, y: 1.0)
            } else {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.68),
                                Color(red: 1.0, green: 0.93, blue: 0.97).opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: barWidth, height: height)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isSelected
                                    ? AnyShapeStyle(FoamTheme.ink.opacity(0.32))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.94),
                                                Color(red: 0.72, green: 0.92, blue: 1.0, opacity: 0.72),
                                                Color(red: 1.0, green: 0.82, blue: 0.92, opacity: 0.72)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    ),
                                lineWidth: isSelected ? 1.5 : 1.2
                            )
                    }
                    .shadow(color: FoamTheme.ink.opacity(isSelected ? 0.14 : 0.08), radius: isSelected ? 6 : 4, y: 2)
                    .scaleEffect(x: pulse, y: 1.0)
            }
        }
    }
}

private struct TimelineTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.68 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
