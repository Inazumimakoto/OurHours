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

    @Test func adjustedStartSurvivesActiveCompletedAndUnknownEndStates() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let adjusted = start.addingTimeInterval(10)
        let previous = session(start.addingTimeInterval(-100), start)
        var live = session(start, nil, status: .active)
        let action = SessionOverride(sessionID: live.id, action: .adjustedStart(startedAt: adjusted), updatedAt: start)
        let journal = JournalSnapshot(sessionOverrides: [live.id: action])

        func resolve() throws -> ResolvedEncounter {
            let entries = EncounterCalendarAggregator.resolveEncounters(autoSessions: [previous, live], journal: journal)
            #expect(entries.count == 2)
            return try #require(entries.first { $0.id == live.id })
        }
        let active = try resolve()
        #expect(active.source == .autoEdited(sessionID: live.id) && active.status == .active)
        #expect(active.startedAt == adjusted && active.endedAt == nil)
        #expect(EncounterCalendarAggregator.coalescedActiveSessionStart(autoSessions: [previous, live], journal: journal) == adjusted)

        live.status = .unknownEnd
        let unknown = try resolve()
        #expect(unknown.status == .unknownEnd && unknown.startedAt == adjusted && unknown.endedAt == nil)
        live.status = .completed
        live.endedAt = start.addingTimeInterval(500)
        let completed = try resolve()
        #expect(completed.status == .completed && completed.startedAt == adjusted && completed.endedAt == live.endedAt)
    }

    @Test func linkedPeerCompletionAndNewerOverridesResolveAfterStartAdjustment() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let adjusted = start.addingTimeInterval(-10)
        let end = start.addingTimeInterval(3600)
        let local = session(start, end, status: .completed)
        let peer = SyncedPeerSession(id: UUID(), pairID: pairID, startedAt: start, endedAt: end.addingTimeInterval(60),
                                     status: .completed, connectionPath: .autoReconnect)
        var journal = JournalSnapshot(sessionOverrides: [
            local.id: SessionOverride(sessionID: local.id, action: .adjustedStart(startedAt: adjusted), updatedAt: start)
        ])
        func resolve() -> [ResolvedEncounter] {
            EncounterCalendarAggregator.resolveEncounters(autoSessions: [local], peerSessions: [peer], journal: journal)
        }
        let linked = try #require(resolve().first)
        #expect(Set(linked.linkedSessionIDs) == [local.id, peer.id])
        #expect(linked.status == .completed && linked.startedAt == adjusted && linked.endedAt == peer.endedAt)
        journal.sessionOverrides[peer.id] = SessionOverride(sessionID: peer.id, action: .edited(startedAt: start, endedAt: end), updatedAt: end)
        let edited = try #require(resolve().first)
        #expect(edited.startedAt == start && edited.endedAt == end)
        journal.sessionOverrides[peer.id] = SessionOverride(sessionID: peer.id, action: .deleted, updatedAt: end)
        #expect(resolve().isEmpty)
    }

    @Test func coalescedActiveSessionStartChainsShortGapsAndIsolatesPairs() throws {
        let base = try date("2026-11-21T10:00:00+09:00")
        let sFar = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(-3_600), // 09:00-09:44 (16m before s1 -> stays unmerged)
            endedAt: base.addingTimeInterval(-960),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )
        let s1 = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base, // 10:00-10:30
            endedAt: base.addingTimeInterval(1_800),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )
        let s2 = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(2_280), // +8m -> 10:38-11:00
            endedAt: base.addingTimeInterval(3_600),
            status: .completed, connectionPath: .autoReconnect, startRole: .peripheral
        )
        let active = EncounterSession(
            id: UUID(), pairID: pairID,
            startedAt: base.addingTimeInterval(4_080), // +8m -> 11:08 active
            endedAt: nil,
            status: .active, connectionPath: .autoReconnect, startRole: .central
        )

        let otherPairID = UUID()
        let otherPairSession = EncounterSession(
            id: UUID(), pairID: otherPairID,
            startedAt: base.addingTimeInterval(-1_800), // 09:30-10:55, different pair
            endedAt: base.addingTimeInterval(3_300),
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )

        let mergedStart = EncounterCalendarAggregator.coalescedActiveSessionStart(
            autoSessions: [sFar, s1, s2, active, otherPairSession],
            journal: JournalSnapshot()
        )
        #expect(mergedStart == s1.startedAt)

        // Deleted override on s2 breaks the bridge back to s1
        let deletedBridge = JournalSnapshot(
            sessionOverrides: [
                s2.id: SessionOverride(sessionID: s2.id, action: .deleted, updatedAt: base)
            ]
        )
        let afterDelete = EncounterCalendarAggregator.coalescedActiveSessionStart(
            autoSessions: [sFar, s1, s2, active],
            journal: deletedBridge
        )
        #expect(afterDelete == active.startedAt)

        // No active session -> nil
        #expect(
            EncounterCalendarAggregator.coalescedActiveSessionStart(
                autoSessions: [sFar, s1, s2],
                journal: JournalSnapshot()
            ) == nil
        )
    }

    @Test func adjustedStartGuardsZeroDurationAndPreservesEarliestSiblingEditAndUntouchedCoalesce() throws {
        let base = try date("2026-11-21T09:00:00+09:00")
        let t0955 = base.addingTimeInterval(55 * 60)
        let t1000 = base.addingTimeInterval(60 * 60)
        let t1030 = base.addingTimeInterval(90 * 60)
        let t1100 = base.addingTimeInterval(120 * 60)

        // 1. F-06: Linked peer ending before adjustedStart keeps local unknownEnd instead of 0-duration completion
        let localUnknown = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        let peerShort = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: t1000,
            status: .completed, connectionPath: .autoReconnect
        )
        let locationShort = LocationMatchedSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: t1000, averageDistanceMeters: 5.0
        )
        let f06Journal = JournalSnapshot(
            sessionOverrides: [
                localUnknown.id: SessionOverride(sessionID: localUnknown.id, action: .adjustedStart(startedAt: t1030), updatedAt: t1030),
                locationShort.id: SessionOverride(sessionID: locationShort.id, action: .adjustedStart(startedAt: t1030), updatedAt: t1030)
            ]
        )
        let resolvedF06 = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localUnknown],
            peerSessions: [peerShort],
            locationSessions: [locationShort],
            journal: f06Journal
        )
        let bleF06 = try #require(resolvedF06.first { $0.linkedSessionIDs.contains(localUnknown.id) })
        #expect(bleF06.startedAt == t1030)
        #expect(bleF06.endedAt == nil)
        #expect(bleF06.status == .unknownEnd)

        let locF06 = try #require(resolvedF06.first { $0.id == locationShort.id })
        #expect(locF06.startedAt == t1030)
        #expect(locF06.endedAt == nil)
        #expect(locF06.status == .unknownEnd)

        // 2. F-11: Concurrent unlinked sibling .adjustedStart edits keep earliest start once linked; newer .deleted supersedes both
        let localSibling = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: t1000, endedAt: t1100,
            status: .completed, connectionPath: .autoReconnect, startRole: .central
        )
        let peerSibling = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: t1000, endedAt: t1100,
            status: .completed, connectionPath: .scanDiscovery
        )
        let mergedEarliestJournal = JournalSnapshot(
            sessionOverrides: [
                localSibling.id: SessionOverride(sessionID: localSibling.id, action: .adjustedStart(startedAt: base), updatedAt: t1000),
                peerSibling.id: SessionOverride(sessionID: peerSibling.id, action: .adjustedStart(startedAt: t0955), updatedAt: t1030)
            ]
        )
        let resolvedSibling = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localSibling],
            peerSessions: [peerSibling],
            journal: mergedEarliestJournal
        )
        #expect(resolvedSibling.count == 1)
        #expect(resolvedSibling[0].startedAt == base)
        #expect(resolvedSibling[0].endedAt == t1100)
        #expect(resolvedSibling[0].status == .completed)

        var deletedSupersedes = mergedEarliestJournal
        deletedSupersedes.sessionOverrides[peerSibling.id] = SessionOverride(
            sessionID: peerSibling.id,
            action: .deleted,
            updatedAt: t1100
        )
        #expect(
            EncounterCalendarAggregator.resolveEncounters(
                autoSessions: [localSibling],
                peerSessions: [peerSibling],
                journal: deletedSupersedes
            ).isEmpty
        )

        // 3. F-02: Untouched active session with non-zero seconds still coalesces across short gap
        let completedMorning = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: t0955,
            status: .completed, connectionPath: .scanDiscovery, startRole: .central
        )
        let activeWithSeconds = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: t1000.addingTimeInterval(45), endedAt: nil,
            status: .active, connectionPath: .autoReconnect, startRole: .central
        )
        #expect(
            EncounterCalendarAggregator.coalescedActiveSessionStart(
                autoSessions: [completedMorning, activeWithSeconds],
                journal: JournalSnapshot()
            ) == base
        )
    }

    @Test func activeSessionSpansMultipleDaysThroughActiveReferenceDate() throws {
        let nov18 = try date("2026-11-18T23:00:00+09:00")
        let nov19Start = try date("2026-11-19T00:00:00+09:00")
        let nov20Start = try date("2026-11-20T00:00:00+09:00")
        let nov21Start = try date("2026-11-21T00:00:00+09:00")
        let nov22Start = try date("2026-11-22T00:00:00+09:00")
        let now = try date("2026-11-21T20:36:00+09:00")

        let active = session(nov18, nil, status: .active)
        let unknown = session(nov18, nil, status: .unknownEnd)

        let summaries = EncounterCalendarAggregator.daySummaries(
            forMonth: nov18,
            autoSessions: [active, unknown],
            journal: JournalSnapshot(),
            calendar: tokyo,
            activeReferenceDate: now
        )

        let d18 = try #require(summaries["2026-11-18"])
        #expect(d18.slices.count == 2)
        let d18Active = try #require(d18.slices.first { $0.status == .active })
        #expect(d18Active.sliceStart == nov18 && d18Active.sliceEnd == nov19Start)
        #expect(!d18Active.continuesFromPreviousDay && d18Active.continuesToNextDay)
        #expect(d18.continuesToNextDay)

        let d19 = try #require(summaries["2026-11-19"])
        #expect(d19.slices.count == 1)
        #expect(d19.hasActiveSession && !d19.hasUnknownEnd)
        #expect(d19.slices[0].sliceStart == nov19Start && d19.slices[0].sliceEnd == nov20Start)
        #expect(d19.continuesFromPreviousDay && d19.continuesToNextDay)

        let d20 = try #require(summaries["2026-11-20"])
        #expect(d20.slices.count == 1)
        #expect(d20.hasActiveSession)
        #expect(d20.slices[0].sliceStart == nov20Start && d20.slices[0].sliceEnd == nov21Start)
        #expect(d20.continuesFromPreviousDay && d20.continuesToNextDay)

        let d21 = try #require(summaries["2026-11-21"])
        #expect(d21.slices.count == 1)
        #expect(d21.hasActiveSession)
        #expect(d21.slices[0].sliceStart == nov21Start && d21.slices[0].sliceEnd == nil)
        #expect(d21.continuesFromPreviousDay && !d21.continuesToNextDay)

        #expect(summaries["2026-11-22"] == nil)
        #expect(EncounterCalendarAggregator.daySummary(
            for: nov20Start, autoSessions: [active, unknown], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: now
        ) == d20)
        #expect(EncounterCalendarAggregator.daySummary(
            for: nov22Start, autoSessions: [active, unknown], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: now
        ).slices.isEmpty)
        #expect(EncounterCalendarAggregator.metDayCount(
            forMonth: nov18, autoSessions: [active, unknown], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: now
        ) == 4)
        #expect(EncounterCalendarAggregator.monthlyRecordedSeconds(
            forMonth: nov18, autoSessions: [active, unknown], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: now
        ) == 0)

        // Month boundary crossing
        let oct31 = try date("2026-10-31T23:00:00+09:00")
        let nov2 = try date("2026-11-02T10:00:00+09:00")
        let octActive = session(oct31, nil, status: .active)
        let octSummaries = EncounterCalendarAggregator.daySummaries(
            forMonth: oct31, autoSessions: [octActive], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: nov2
        )
        let novSummaries = EncounterCalendarAggregator.daySummaries(
            forMonth: nov2, autoSessions: [octActive], journal: JournalSnapshot(), calendar: tokyo, activeReferenceDate: nov2
        )
        #expect(octSummaries.keys.sorted() == ["2026-10-31"])
        #expect(octSummaries["2026-10-31"]?.continuesToNextDay == true)
        #expect(novSummaries.keys.sorted() == ["2026-11-01", "2026-11-02"])
        #expect(novSummaries["2026-11-01"]?.continuesFromPreviousDay == true && novSummaries["2026-11-01"]?.continuesToNextDay == true)
        #expect(novSummaries["2026-11-02"]?.continuesFromPreviousDay == true && novSummaries["2026-11-02"]?.continuesToNextDay == false)
    }

    @Test func absorbsUneditedUnknownEndCoveredByLocationEditedOrManualAndPreservesEditedUnknown() throws {
        let base = try date("2026-11-23T00:00:00+09:00")
        let t0100 = base.addingTimeInterval(3_600)
        let t0200 = base.addingTimeInterval(7_200)
        let t020430 = base.addingTimeInterval(7_470) // 02:04:30
        let t0205 = base.addingTimeInterval(7_500)   // 02:05:00
        let t0220 = base.addingTimeInterval(8_400)   // 02:20:00
        let t0400 = base.addingTimeInterval(14_400)

        // 1. Emitted locationMatched covers BLE unknownEnd -> absorbed into locationMatched (same pair only)
        let uLoc = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: t020430, endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        let otherPairUnknown = EncounterSession(
            id: UUID(), pairID: UUID(), startedAt: t020430, endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        let locCovering = LocationMatchedSession(
            id: LocationPayloadCipher.deterministicMatchID(pairID: pairID, startedAt: base),
            pairID: pairID,
            startedAt: base,
            endedAt: t0205,
            averageDistanceMeters: 15
        )
        let absorbedByLoc = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [uLoc, otherPairUnknown],
            locationSessions: [locCovering],
            journal: JournalSnapshot()
        )
        #expect(absorbedByLoc.count == 2)
        let locResolved = try #require(absorbedByLoc.first { $0.id == locCovering.id })
        #expect(locResolved.status == .completed && locResolved.startedAt == base && locResolved.endedAt == t0205)
        #expect(Set(locResolved.linkedSessionIDs) == [locCovering.id, uLoc.id])
        #expect(absorbedByLoc.contains { $0.id == otherPairUnknown.id && $0.status == .unknownEnd })

        // Deleted locationMatched must NOT absorb unknownEnd
        let deletedLocJournal = JournalSnapshot(
            sessionOverrides: [locCovering.id: SessionOverride(sessionID: locCovering.id, action: .deleted, updatedAt: t0205)]
        )
        let notAbsorbedByDeleted = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [uLoc],
            locationSessions: [locCovering],
            journal: deletedLocJournal
        )
        #expect(notAbsorbedByDeleted.count == 1 && notAbsorbedByDeleted[0].status == .unknownEnd)

        // 2. Suppressed locationMatched (>=95% covered by completed BLE) + trailing unknownEnd -> merges & extends BLE end
        let bleMain = session(base, t020430.addingTimeInterval(-15)) // 00:00:00 -> 02:04:15
        let trailingUnknown = session(t020430, nil, status: .unknownEnd) // 02:04:30 -> ?
        let suppressedLocMerged = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [bleMain, trailingUnknown],
            locationSessions: [locCovering], // 00:00:00 -> 02:05:00
            journal: JournalSnapshot()
        )
        #expect(suppressedLocMerged.count == 1)
        #expect(suppressedLocMerged[0].status == .completed)
        #expect(suppressedLocMerged[0].startedAt == base && suppressedLocMerged[0].endedAt == t0205)
        #expect(Set(suppressedLocMerged[0].linkedSessionIDs) == [bleMain.id, trailingUnknown.id])

        // 3. AutoEdited completed session covering unknownEnd -> absorbed into linkedSessionIDs without moving edited bounds
        let autoTarget = session(t0100, t0200)
        let editedJournal = JournalSnapshot(
            sessionOverrides: [
                autoTarget.id: SessionOverride(
                    sessionID: autoTarget.id,
                    action: .edited(startedAt: t0100, endedAt: t0220),
                    updatedAt: t0220
                )
            ]
        )
        let resolvedEdited = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [autoTarget, trailingUnknown],
            journal: editedJournal
        )
        #expect(resolvedEdited.count == 1)
        #expect(resolvedEdited[0].startedAt == t0100 && resolvedEdited[0].endedAt == t0220)
        #expect(Set(resolvedEdited[0].linkedSessionIDs) == [autoTarget.id, trailingUnknown.id])

        // 4. Manual record covers unknownEnd inside [start, end), leaves unknownEnd outside untouched
        let manual = ManualEncounterRecord(
            id: UUID(), pairID: pairID, startedAt: t0100, endedAt: t0220, createdAt: t0220, updatedAt: t0220
        )
        let outsideUnknown = session(t0400, nil, status: .unknownEnd)
        let manualResolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [trailingUnknown, outsideUnknown],
            journal: JournalSnapshot(manualRecords: [manual])
        )
        #expect(manualResolved.count == 2)
        #expect(manualResolved[0].id == manual.id)
        #expect(manualResolved[1].id == outsideUnknown.id && manualResolved[1].status == .unknownEnd)

        // 5. Explicitly adjustedStart unknownEnd (.autoEdited) is NEVER swallowed by covering completed manual/location
        let adjustedUnknownJournal = JournalSnapshot(
            manualRecords: [manual],
            sessionOverrides: [
                trailingUnknown.id: SessionOverride(
                    sessionID: trailingUnknown.id,
                    action: .adjustedStart(startedAt: t0200),
                    updatedAt: t0220
                )
            ]
        )
        let preservedEditedUnknown = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [trailingUnknown],
            locationSessions: [locCovering],
            journal: adjustedUnknownJournal
        )
        #expect(preservedEditedUnknown.contains { $0.id == trailingUnknown.id && $0.status == .unknownEnd })
    }

    @Test func locationSuppressionRespectsPairScopeAndUncoveredGapLimit() throws {
        let base = try date("2026-11-01T00:00:00+09:00")
        let locPairA = LocationMatchedSession(
            id: UUID(),
            pairID: pairID,
            startedAt: base,
            endedAt: base.addingTimeInterval(7_200),
            averageDistanceMeters: 15
        )
        let otherPairBLE = EncounterSession(
            pairID: UUID(),
            startedAt: base,
            endedAt: base.addingTimeInterval(7_200),
            status: .completed,
            connectionPath: .scanDiscovery,
            startRole: .central
        )
        let crossPairResolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [otherPairBLE],
            locationSessions: [locPairA],
            journal: JournalSnapshot()
        )
        #expect(crossPairResolved.count == 2)
        #expect(crossPairResolved.contains { $0.id == locPairA.id })
        #expect(crossPairResolved.contains { $0.id == otherPairBLE.id })

        // 20h location vs 19h15m BLE -> 96.25% covered, but 45m (2,700s > 300s) uncovered must not be suppressed.
        let loc20h = LocationMatchedSession(
            id: UUID(),
            pairID: pairID,
            startedAt: base,
            endedAt: base.addingTimeInterval(72_000),
            averageDistanceMeters: 20
        )
        let ble19h15m = session(base, base.addingTimeInterval(69_300))
        let longUncoveredResolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [ble19h15m],
            locationSessions: [loc20h],
            journal: JournalSnapshot()
        )
        #expect(longUncoveredResolved.contains {
            $0.id == loc20h.id && $0.endedAt == base.addingTimeInterval(72_000)
        })
    }
}
