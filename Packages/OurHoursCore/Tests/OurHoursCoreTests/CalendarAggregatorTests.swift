import Foundation
import Testing
import OurHoursCore

struct CalendarAggregatorTests {
    private let tokyo = calendar("Asia/Tokyo")
    private let pairID = UUID()

    private static func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func session(_ start: Date, _ end: Date?, status: SessionStatus = .completed) -> EncounterSession {
        EncounterSession(
            pairID: pairID, startedAt: start, endedAt: end, status: status,
            connectionPath: .scanDiscovery, startRole: .central
        )
    }

    @Test func manualOverridesTakePrecedenceAndCompleteUnfinishedSessions() throws {
        let start = try date("2026-11-01T10:00:00+09:00")
        let end = start.addingTimeInterval(1_801.5)
        var unknown = session(start, nil, status: .unknownEnd)
        let active = session(start, nil, status: .active)
        let deleted = session(start, end)
        let manual = ManualEncounterRecord(
            id: UUID(), pairID: nil, startedAt: start, endedAt: end, createdAt: start, updatedAt: start
        )
        let invalid = ManualEncounterRecord(
            id: UUID(), pairID: nil, startedAt: end, endedAt: start, createdAt: start, updatedAt: start
        )
        let edit = SessionOverrideAction.edited(startedAt: start, endedAt: end)
        let journal = JournalSnapshot(
            manualRecords: [manual, invalid],
            sessionOverrides: [
                unknown.id: SessionOverride(sessionID: unknown.id, action: edit, updatedAt: start),
                active.id: SessionOverride(sessionID: active.id, action: edit, updatedAt: start),
                deleted.id: SessionOverride(sessionID: deleted.id, action: .deleted, updatedAt: start)
            ]
        )
        let resolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [unknown, active, deleted], journal: journal
        )
        #expect(resolved.map(\.id) == [unknown.id, active.id, manual.id].sorted { $0.uuidString < $1.uuidString })
        #expect(Set(resolved.map(\.source)) == [
            .autoEdited(sessionID: unknown.id), .autoEdited(sessionID: active.id), .manual(recordID: manual.id)
        ])
        #expect(resolved.allSatisfy { $0.status == .completed && $0.durationSeconds == 1_801.5 })
        #expect(resolved.first { $0.id == unknown.id }?.connectionPath == .scanDiscovery)
        #expect(resolved.first { $0.id == manual.id }?.connectionPath == nil)

        unknown.endedAt = end.addingTimeInterval(3_600)
        unknown.status = .completed
        #expect(EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [unknown, active, deleted], journal: journal
        ) == resolved)
    }

    @Test func splitsAtLocalMonthBoundaryAndUnionsOverlappingIntervals() throws {
        let start = try date("2026-10-31T23:40:00+09:00")
        let midnight = start.addingTimeInterval(1_200)
        let end = midnight.addingTimeInterval(1_200)
        let autoSessions = [
            session(start, end),
            session(start.addingTimeInterval(600), end.addingTimeInterval(60.5)),
            session(start, midnight)
        ]
        let journal = JournalSnapshot()
        let october = EncounterCalendarAggregator.daySummaries(
            forMonth: start, autoSessions: autoSessions, journal: journal, calendar: tokyo
        )
        let november = EncounterCalendarAggregator.daySummaries(
            forMonth: end, autoSessions: autoSessions, journal: journal, calendar: tokyo
        )
        let lastDay = try #require(october["2026-10-31"])
        let firstDay = try #require(november["2026-11-01"])
        #expect(lastDay.slices.count == 1)
        #expect(lastDay.totalRecordedSeconds == 1_200)
        #expect(firstDay.slices.count == 1)
        #expect(firstDay.totalRecordedSeconds == 1_260.5)
        #expect(firstDay.slices.allSatisfy { $0.sliceStart == midnight })
        #expect(firstDay.slices.first?.fullStart == start)
        #expect(firstDay.slices.first?.durationSeconds == 1_260.5)
        #expect(EncounterCalendarAggregator.daySummary(
            for: end, autoSessions: autoSessions, journal: journal, calendar: tokyo
        ) == firstDay)
        #expect(EncounterCalendarAggregator.monthlyRecordedSeconds(
            forMonth: end, autoSessions: autoSessions, journal: journal, calendar: tokyo
        ) == 1_260.5)
        #expect(EncounterCalendarAggregator.lifetimeRecordedSeconds(
            autoSessions: autoSessions, journal: journal, calendar: tokyo
        ) == 2_460.5)
        #expect(EncounterCalendarAggregator.dayKey(for: midnight, calendar: Self.calendar("UTC")) == "2026-10-31")
    }

    @Test(arguments: [
        ("2026-03-08T00:00:00-05:00", "2026-03-09T00:00:00-04:00", 23.0),
        ("2026-11-01T00:00:00-04:00", "2026-11-02T00:00:00-05:00", 25.0)
    ])
    func daylightSavingUsesElapsedSeconds(start: String, end: String, hours: Double) throws {
        let start = try date(start)
        let end = try date(end)
        let summaries = EncounterCalendarAggregator.daySummaries(
            forMonth: start, autoSessions: [session(start, end)], journal: JournalSnapshot(),
            calendar: Self.calendar("America/New_York")
        )
        #expect(summaries.count == 1)
        #expect(summaries.values.first?.totalRecordedSeconds == hours * 3_600)
    }

    @Test func unfinishedSessionsStayOnTheirStartDayAndMemosAppearOnTheirOwn() throws {
        let start = try date("2026-11-05T23:00:00+09:00")
        let nextDay = start.addingTimeInterval(3_600)
        let sessions = [session(start, nil, status: .active), session(start, nil, status: .unknownEnd)]
        let memo = DailyMemo(dayKey: "2026-11-06", text: "Dinner", updatedAt: nextDay)
        let journal = JournalSnapshot(dailyMemos: [memo.dayKey: memo])
        let summaries = EncounterCalendarAggregator.daySummaries(
            forMonth: start, autoSessions: sessions, journal: journal, calendar: tokyo
        )
        let first = try #require(summaries["2026-11-05"])
        #expect(first.slices.count == 2)
        #expect(first.slices.allSatisfy { $0.sliceEnd == nil && $0.durationSeconds == nil })
        #expect(first.hasActiveSession && first.hasUnknownEnd)
        #expect(first.totalRecordedSeconds == 0)
        #expect(first.bubbleIntensity == .small)
        let second = try #require(summaries[memo.dayKey])
        #expect(second.memo == memo.text)
        #expect(second.slices.isEmpty)
        #expect(second.bubbleIntensity == BubbleIntensity.none)
        #expect(EncounterCalendarAggregator.metDayCount(
            forMonth: start, autoSessions: sessions, journal: journal, calendar: tokyo
        ) == 1)
        let empty = EncounterCalendarAggregator.daySummary(
            for: nextDay.addingTimeInterval(86_400), autoSessions: sessions, journal: journal, calendar: tokyo
        )
        #expect(empty.dayKey == "2026-11-07")
        #expect(empty.slices.isEmpty && empty.memo == nil && empty.bubbleIntensity == BubbleIntensity.none)
    }

    @Test(arguments: [
        (0.0, BubbleIntensity.none), (7_200.0, .small), (7_200.5, .medium),
        (18_000.0, .medium), (18_000.5, .large)
    ])
    func bubbleIntensityUsesExactThresholds(seconds: TimeInterval, intensity: BubbleIntensity) throws {
        let start = try date("2026-11-01T10:00:00+09:00")
        let summary = EncounterCalendarAggregator.daySummary(
            for: start, autoSessions: [session(start, start.addingTimeInterval(seconds))],
            journal: JournalSnapshot(), calendar: tokyo
        )
        #expect(summary.bubbleIntensity == intensity)
    }

    @Test func multiDayContinuityFlagsTrackOvernightAndMultiDayEncounters() throws {
        // 1. Same-day session: neither flag set
        let sameStart = try date("2026-11-02T14:00:00+09:00")
        let sameEnd = try date("2026-11-02T18:00:00+09:00")
        let sameDay = EncounterCalendarAggregator.daySummary(
            for: sameStart, autoSessions: [session(sameStart, sameEnd)], journal: JournalSnapshot(), calendar: tokyo
        )
        #expect(!sameDay.continuesFromPreviousDay)
        #expect(!sameDay.continuesToNextDay)

        // 2. Overnight 2-day session
        let overStart = try date("2026-11-05T22:00:00+09:00")
        let overEnd = try date("2026-11-06T09:00:00+09:00")
        let twoDaySummaries = EncounterCalendarAggregator.daySummaries(
            forMonth: overStart, autoSessions: [session(overStart, overEnd)], journal: JournalSnapshot(), calendar: tokyo
        )
        let d5 = try #require(twoDaySummaries["2026-11-05"])
        let d6 = try #require(twoDaySummaries["2026-11-06"])
        #expect(!d5.continuesFromPreviousDay)
        #expect(d5.continuesToNextDay)
        #expect(d6.continuesFromPreviousDay)
        #expect(!d6.continuesToNextDay)

        // 3. 3-day session: middle day has both flags set
        let threeStart = try date("2026-11-10T20:00:00+09:00")
        let threeEnd = try date("2026-11-12T10:00:00+09:00")
        let threeSummaries = EncounterCalendarAggregator.daySummaries(
            forMonth: threeStart, autoSessions: [session(threeStart, threeEnd)], journal: JournalSnapshot(), calendar: tokyo
        )
        let d10 = try #require(threeSummaries["2026-11-10"])
        let d11 = try #require(threeSummaries["2026-11-11"])
        let d12 = try #require(threeSummaries["2026-11-12"])
        #expect(!d10.continuesFromPreviousDay && d10.continuesToNextDay)
        #expect(d11.continuesFromPreviousDay && d11.continuesToNextDay)
        #expect(d12.continuesFromPreviousDay && !d12.continuesToNextDay)

        // 4. Exact midnight end: 22:00 -> 00:00 stays strictly on day 1
        let midStart = try date("2026-11-15T22:00:00+09:00")
        let midEnd = try date("2026-11-16T00:00:00+09:00")
        let midSummaries = EncounterCalendarAggregator.daySummaries(
            forMonth: midStart, autoSessions: [session(midStart, midEnd)], journal: JournalSnapshot(), calendar: tokyo
        )
        let d15 = try #require(midSummaries["2026-11-15"])
        #expect(!d15.continuesFromPreviousDay && !d15.continuesToNextDay)
        #expect(midSummaries["2026-11-16"] == nil)
    }

    @Test func coalescesShortGapBLESessionsAndRespectsOverridesAndPairs() throws {
        let base = try date("2026-11-21T10:00:00+09:00")
        let s1 = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: base.addingTimeInterval(1_800),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        ) // 10:00-10:30
        let s2 = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(2_160), // +6m -> 10:36-11:00
            endedAt: base.addingTimeInterval(3_600),
            status: .completed, connectionPath: .autoReconnect, startRole: .peripheral
        )
        let s3 = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(4_200), // exact 10m (600s) -> 11:10-11:40
            endedAt: base.addingTimeInterval(6_000),
            status: .completed, connectionPath: .autoReconnect, startRole: .central
        )
        let sFar = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(6_601), // 10m01s gap -> stays separate
            endedAt: base.addingTimeInterval(7_800),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )
        let otherPairID = UUID()
        let otherPairNear = EncounterSession(
            id: UUID(), pairID: otherPairID,
            startedAt: base.addingTimeInterval(1_860), // 1m after s1, different pair
            endedAt: base.addingTimeInterval(2_100),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )

        let coalesced = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [s1, s2, s3, sFar, otherPairNear],
            journal: JournalSnapshot()
        )
        #expect(coalesced.count == 3)

        let mergedFirst = try #require(coalesced.first { Set($0.linkedSessionIDs) == [s1.id, s2.id, s3.id] })
        #expect(mergedFirst.startedAt == s1.startedAt)
        #expect(mergedFirst.endedAt == s3.endedAt)
        #expect(coalesced.contains { $0.id == sFar.id })
        #expect(coalesced.contains { $0.id == otherPairNear.id && $0.linkedSessionIDs == [otherPairNear.id] })

        // Deleted session does not break or suppress neighbor; autoEdited stays exact without auto-merging
        let jEdited = JournalSnapshot(
            sessionOverrides: [
                s2.id: SessionOverride(sessionID: s2.id, action: .deleted, updatedAt: base),
                s1.id: SessionOverride(
                    sessionID: s1.id,
                    action: .edited(startedAt: base, endedAt: base.addingTimeInterval(1_920)),
                    updatedAt: base
                )
            ]
        )
        let sNearEdited = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(2_220), // 5m after edited end 10:32
            endedAt: base.addingTimeInterval(3_000),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )
        let afterOverride = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [s1, s2, sNearEdited],
            journal: jEdited
        )
        #expect(afterOverride.count == 2)
        #expect(afterOverride[0].source == .autoEdited(sessionID: s1.id))
        #expect(afterOverride[0].endedAt == base.addingTimeInterval(1_920))
        #expect(afterOverride[1].id == sNearEdited.id)

        // UnknownEnd: duplicates within 10m collapse; unknown 4m before completed absorbs into it; 30m earlier remains unknownEnd
        let uEarly = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base.addingTimeInterval(-1_800), endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        ) // 09:30 (30m before s1)
        let uDup1 = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base.addingTimeInterval(-1_500), endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        ) // 09:35 (5m after uEarly -> collapses into uEarly)
        let uBeforeS1 = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base.addingTimeInterval(-240), endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        ) // 09:56 (4m before s1 -> absorbed into s1)
        let unknownResolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [uEarly, uDup1, uBeforeS1, s1],
            journal: JournalSnapshot()
        )
        #expect(unknownResolved.count == 2)
        #expect(unknownResolved[0].status == .unknownEnd)
        #expect(unknownResolved[0].startedAt == uEarly.startedAt)
        #expect(Set(unknownResolved[0].linkedSessionIDs) == [uEarly.id, uDup1.id])

        #expect(unknownResolved[1].status == .completed)
        #expect(unknownResolved[1].startedAt == uBeforeS1.startedAt)
        #expect(unknownResolved[1].endedAt == s1.endedAt)
        #expect(Set(unknownResolved[1].linkedSessionIDs) == [uBeforeS1.id, s1.id])
    }
}
