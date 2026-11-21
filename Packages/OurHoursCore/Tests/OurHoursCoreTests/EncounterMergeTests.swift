import Foundation
import Testing
@testable import OurHoursCore

struct EncounterMergeTests {
    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func resolved(
        id: UUID = UUID(),
        source: EncounterSource? = nil,
        linked: [UUID]? = nil,
        start: Date,
        end: Date?,
        status: SessionStatus = .completed
    ) -> ResolvedEncounter {
        let resolvedSource = source ?? .auto(sessionID: id)
        return ResolvedEncounter(
            id: id,
            source: resolvedSource,
            linkedSessionIDs: linked,
            startedAt: start,
            endedAt: end,
            status: status,
            connectionPath: nil
        )
    }

    @Test func forwardTouchChainBackwardUnknownEndAndGuards() throws {
        let t13 = try date("2026-11-21T13:00:00+09:00")
        let t16 = try date("2026-11-21T16:00:00+09:00")
        let t17 = try date("2026-11-21T17:00:00+09:00")
        let t19 = try date("2026-11-21T19:00:00+09:00")
        let t1930 = try date("2026-11-21T19:30:00+09:00")
        let t21 = try date("2026-11-21T21:00:00+09:00")

        let e1 = resolved(start: t13, end: t16)
        let e2 = resolved(start: t17, end: t19)
        let e3 = resolved(start: t1930, end: t21)

        // 1. Extending 13:00-16:00 to exact touch 17:00 merges with 17:00-19:00
        let touchPlan = EncounterMergePlanner.plan(editing: e1, proposedStart: t13, proposedEnd: t17, among: [e1, e2, e3])
        #expect(touchPlan.didMerge)
        #expect(touchPlan.absorbed.map(\.id) == [e2.id])
        #expect(touchPlan.mergedStart == t13 && touchPlan.mergedEnd == t19)

        // 2. Extending to 16:59 does NOT merge 17:00-19:00
        let gapPlan = EncounterMergePlanner.plan(editing: e1, proposedStart: t13, proposedEnd: t17.addingTimeInterval(-60), among: [e1, e2])
        #expect(!gapPlan.didMerge)
        #expect(gapPlan.mergedEnd == t17.addingTimeInterval(-60))

        // 3. Fixed-point chaining across two neighbors (proposed end 20:00 absorbs e2 AND e3 -> ends 21:00)
        let chainPlan = EncounterMergePlanner.plan(editing: e1, proposedStart: t13, proposedEnd: t1930.addingTimeInterval(1800), among: [e1, e2, e3])
        #expect(chainPlan.absorbed.map(\.id) == [e2.id, e3.id])
        #expect(chainPlan.mergedStart == t13 && chainPlan.mergedEnd == t21)

        // 4. Pulling e2 start backward to 16:00 merges backward with e1 -> 13:00-19:00
        let backPlan = EncounterMergePlanner.plan(editing: e2, proposedStart: t16, proposedEnd: t19, among: [e1, e2])
        #expect(backPlan.absorbed.map(\.id) == [e1.id])
        #expect(backPlan.mergedStart == t13 && backPlan.mergedEnd == t19)

        // 5. Completing unknownEnd 13:00 -> 17:00 absorbs 17:00-19:00; and extending over a following unknownEnd absorbs it too
        let u1 = resolved(start: t13, end: nil, status: .unknownEnd)
        let completePlan = EncounterMergePlanner.plan(editing: u1, proposedStart: t13, proposedEnd: t17, among: [u1, e2])
        #expect(completePlan.absorbed.map(\.id) == [e2.id])
        #expect(completePlan.mergedStart == t13 && completePlan.mergedEnd == t19)

        let uFollowing = resolved(start: t17, end: nil, status: .unknownEnd)
        let activeLive = resolved(start: t17, end: nil, status: .active)
        let swallowUnknown = EncounterMergePlanner.plan(
            editing: e1,
            proposedStart: t13,
            proposedEnd: t19,
            among: [e1, uFollowing, activeLive], now: t19
        )
        #expect(Set(swallowUnknown.absorbed.map(\.id)) == [uFollowing.id, activeLive.id])
        #expect(swallowUnknown.survivingActiveEncounter == activeLive)
        #expect(swallowUnknown.mergedStart == t13 && swallowUnknown.mergedEnd == nil)
    }

    @Test func activeStartMovesAcrossTouchingChainWithoutExpandingPastNow() {
        func t(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }
        let early = resolved(start: t(1), end: t(3))
        let bridge = resolved(start: t(3), end: t(5))
        let unknown = resolved(start: t(2), end: nil, status: .unknownEnd)
        let active = resolved(start: t(8), end: nil, status: .active)
        let straddlesNow = resolved(start: t(10), end: t(15))
        let manualID = UUID()
        let future = resolved(id: manualID, source: .manual(recordID: manualID), start: t(11), end: t(14))
        let plan = EncounterMergePlanner.plan(
            editing: active, proposedStart: t(5), proposedEnd: nil,
            among: [unknown, early, bridge, active, straddlesNow, future], now: t(10)
        )
        #expect(plan.survivingActiveEncounter == active)
        #expect(plan.mergedStart == t(1) && plan.mergedEnd == nil)
        #expect(plan.absorbed == [early, unknown, bridge, straddlesNow])

        let forward = EncounterMergePlanner.plan(editing: active, proposedStart: t(10), proposedEnd: nil, among: [active], now: t(10))
        #expect(forward.keepsActiveSession && forward.mergedStart == t(10) && forward.mergedEnd == nil)
        let invalid = EncounterMergePlanner.plan(editing: active, proposedStart: t(11), proposedEnd: nil, among: [active], now: t(10))
        #expect(!invalid.keepsActiveSession && !invalid.didMerge && invalid.mergedEnd == nil)
    }

    @Test func earlierTargetsAndManualDraftsCanTouchActiveSession() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let contact = start.addingTimeInterval(120)
        let active = resolved(start: contact, end: nil, status: .active)
        let targets: [ResolvedEncounter?] = [
            nil, resolved(start: start, end: start.addingTimeInterval(30)),
            resolved(start: start, end: nil, status: .unknownEnd)
        ]
        for target in targets {
            let records = [active] + [target].compactMap { $0 }
            let touch = EncounterMergePlanner.plan(
                editing: target, proposedStart: start, proposedEnd: contact, among: records, now: contact
            )
            #expect(touch.absorbed == [active] && touch.survivingActiveEncounter == active)
            #expect(touch.mergedStart == start && touch.mergedEnd == nil)
            let gap = EncounterMergePlanner.plan(
                editing: target, proposedStart: start, proposedEnd: contact.addingTimeInterval(-1), among: records, now: contact
            )
            #expect(!gap.didMerge && !gap.keepsActiveSession)
        }
    }

    @Test func atomicMergedMutationsResolveCleanlyAcrossBLEAndManualAndSync() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OurHoursMergeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let pairID = UUID()
        let t13 = try date("2026-11-21T13:00:00+09:00")
        let t16 = try date("2026-11-21T16:00:00+09:00")
        let t17 = try date("2026-11-21T17:00:00+09:00")
        let t19 = try date("2026-11-21T19:00:00+09:00")

        // Case A: Merging BLE component (with peer linked ID) + BLE session
        let storeA = JournalStore(directory: dir.appendingPathComponent("caseA"))
        let localS1 = EncounterSession(id: UUID(), pairID: pairID, startedAt: t13, endedAt: t16, status: .completed, connectionPath: .autoReconnect, startRole: .central)
        let peerS1 = SyncedPeerSession(id: UUID(), pairID: pairID, startedAt: t13.addingTimeInterval(30), endedAt: t16, status: .completed, connectionPath: .scanDiscovery)
        let localS2 = EncounterSession(id: UUID(), pairID: pairID, startedAt: t17, endedAt: t19, status: .completed, connectionPath: .autoReconnect, startRole: .peripheral)

        let preResolvedA = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localS1, localS2], peerSessions: [peerS1], journal: try storeA.load()
        )
        #expect(preResolvedA.count == 2)
        let targetA = preResolvedA[0]
        let planA = EncounterMergePlanner.plan(editing: targetA, proposedStart: t13, proposedEnd: t17, among: preResolvedA)
        #expect(planA.didMerge)

        var overridesA: [UUID: SessionOverrideAction] = [targetA.id: .edited(startedAt: planA.mergedStart, endedAt: try #require(planA.mergedEnd))]
        for sid in targetA.linkedSessionIDs where sid != targetA.id { overridesA[sid] = .deleted }
        for absEnc in planA.absorbed {
            for sid in (absEnc.linkedSessionIDs.isEmpty ? [absEnc.id] : absEnc.linkedSessionIDs) where sid != targetA.id {
                overridesA[sid] = .deleted
            }
        }
        let jA = try storeA.applyMergedMutation(
            pairID: pairID, keepManualID: nil, createManual: false,
            mergedStart: planA.mergedStart, mergedEnd: planA.mergedEnd,
            deleteManualIDs: [], sessionOverrideUpdates: overridesA
        )
        let afterA = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localS1, localS2], peerSessions: [peerS1], journal: jA
        )
        #expect(afterA.count == 1)
        #expect(afterA[0].durationSeconds == 21_600.0)

        // Verify surviving JournalMerger sync with stale remote snapshot
        let mergedRemoteA = JournalMerger.merge(local: JournalSnapshot(), remote: jA)
        #expect(EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localS1, localS2], peerSessions: [peerS1], journal: mergedRemoteA
        ).count == 1)

        // Case B: Manual record absorbing a BLE session
        let storeB = JournalStore(directory: dir.appendingPathComponent("caseB"))
        let snapWithManual = try storeB.addManualRecord(pairID: pairID, startedAt: t13, endedAt: t16)
        let manualID = try #require(snapWithManual.manualRecords.first?.id)
        let preResolvedB = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localS2], peerSessions: [], journal: snapWithManual
        )
        let manualTarget = try #require(preResolvedB.first { $0.id == manualID })
        let planB = EncounterMergePlanner.plan(editing: manualTarget, proposedStart: t13, proposedEnd: t17, among: preResolvedB)
        #expect(planB.absorbed.map(\.id) == [localS2.id])

        let jB = try storeB.applyMergedMutation(
            pairID: pairID, keepManualID: manualID, createManual: false,
            mergedStart: planB.mergedStart, mergedEnd: planB.mergedEnd,
            deleteManualIDs: [], sessionOverrideUpdates: [localS2.id: .deleted]
        )
        let afterB = EncounterCalendarAggregator.resolveEncounters(autoSessions: [localS2], journal: jB)
        #expect(afterB.count == 1)
        #expect(afterB[0].id == manualID && afterB[0].durationSeconds == 21_600.0)

        // Case C: BLE session absorbing a manual record -> manual is tombstoned so peer copy never resurrects it
        let storeC = JournalStore(directory: dir.appendingPathComponent("caseC"))
        let staleManualSnap = try storeC.addManualRecord(pairID: pairID, startedAt: t17, endedAt: t19)
        let absorbedManual = try #require(staleManualSnap.manualRecords.first)
        let preResolvedC = EncounterCalendarAggregator.resolveEncounters(autoSessions: [localS1], journal: staleManualSnap)
        let bleTarget = try #require(preResolvedC.first { $0.id == localS1.id })
        let planC = EncounterMergePlanner.plan(editing: bleTarget, proposedStart: t13, proposedEnd: t17, among: preResolvedC)
        #expect(planC.absorbed.map(\.id) == [absorbedManual.id])

        let jC = try storeC.applyMergedMutation(
            pairID: pairID, keepManualID: nil, createManual: false,
            mergedStart: planC.mergedStart, mergedEnd: planC.mergedEnd,
            deleteManualIDs: [absorbedManual.id],
            sessionOverrideUpdates: [localS1.id: .edited(startedAt: planC.mergedStart, endedAt: try #require(planC.mergedEnd))]
        )
        #expect(jC.deletedManualRecords[absorbedManual.id] != nil)
        let syncedWithStaleManual = JournalMerger.merge(local: jC, remote: staleManualSnap)
        #expect(syncedWithStaleManual.manualRecords.isEmpty)
        let afterC = EncounterCalendarAggregator.resolveEncounters(autoSessions: [localS1], journal: syncedWithStaleManual)
        #expect(afterC.count == 1 && afterC[0].durationSeconds == 21_600.0)
    }
}
