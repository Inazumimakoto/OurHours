import Foundation
import Testing
@testable import OurHoursCore

struct PartnerSyncTests {
    private let tokyo: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }()

    private func makeConfig(role: PeerRole = .partnerA, epoch: UInt32 = 1) -> PairConfiguration {
        PairConfiguration(
            pairID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sharedSecret: Data(repeating: 0x5A, count: 32),
            localRole: role,
            keyEpoch: epoch
        )
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func payloadCipherRoundTripAndKeyIsolation() throws {
        let configA = makeConfig(role: .partnerA, epoch: 1)
        let configB = makeConfig(role: .partnerB, epoch: 1)
        let wrongEpoch = makeConfig(role: .partnerA, epoch: 2)
        let wrongSecret = PairConfiguration(
            pairID: configA.pairID,
            sharedSecret: Data(repeating: 0x12, count: 32),
            localRole: .partnerB,
            keyEpoch: 1
        )

        let recordA = PartnerPayloadCipher.journalRecordName(for: configA, role: .partnerA)
        let recordB = PartnerPayloadCipher.journalRecordName(for: configB, role: .partnerB)
        #expect(recordA != recordB)
        #expect(recordA != LocationPayloadCipher.dayRecordName(for: configA, role: .partnerA, utcDayKey: "2026-11-21"))

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let adjustment = SessionOverride(sessionID: sessionID, action: .adjustedStart(startedAt: base), updatedAt: base)
        let envelope = PartnerSyncEnvelope(
            pairID: configA.pairID,
            senderRole: .partnerA,
            updatedAt: base,
            bleSessions: [
                SyncedPeerSession(
                    id: UUID(),
                    pairID: configA.pairID,
                    startedAt: base,
                    endedAt: base.addingTimeInterval(5400),
                    status: .completed,
                    connectionPath: .autoReconnect
                )
            ],
            journal: JournalSnapshot(
                manualRecords: [
                    ManualEncounterRecord(
                        id: UUID(),
                        pairID: configA.pairID,
                        startedAt: base.addingTimeInterval(7200),
                        endedAt: base.addingTimeInterval(10800),
                        createdAt: base,
                        updatedAt: base
                    )
                ],
                sessionOverrides: [sessionID: adjustment],
                dailyMemos: ["2026-11-21": DailyMemo(dayKey: "2026-11-21", text: String(repeating: "あわ", count: 40), updatedAt: base)],
                deletedManualRecords: [UUID(): base],
                deletedMemoDays: ["2026-11-20": base],
                roleProfiles: ["A": SyncedRoleProfile(bubbleColor: .mint, birthday: nil, updatedAt: base)],
                anniversary: SyncedAnniversary(date: CalendarDateValue(year: 2020, month: 5, day: 1), updatedAt: base)
            )
        )

        let journalData = try JSONEncoder().encode(envelope.journal)
        let object = try #require(JSONSerialization.jsonObject(with: journalData) as? [String: Any])
        let profiles = try #require(object["roleProfiles"] as? [String: Any])
        #expect(profiles["A"] != nil)
        let ciphertext = try PartnerPayloadCipher.encrypt(envelope, using: configA)
        let decrypted = try PartnerPayloadCipher.decrypt(ciphertext, using: configB)
        #expect(decrypted == envelope)

        #expect(throws: PartnerPayloadCipherError.decryptionFailed) {
            try PartnerPayloadCipher.decrypt(ciphertext, using: wrongEpoch)
        }
        #expect(throws: PartnerPayloadCipherError.decryptionFailed) {
            try PartnerPayloadCipher.decrypt(ciphertext, using: wrongSecret)
        }
    }

    @Test func legacyJournalSnapshotDecodesWithoutTombstoneKeys() throws {
        let sessionID = UUID()
        let full = JournalSnapshot(
            manualRecords: [],
            sessionOverrides: [sessionID: SessionOverride(sessionID: sessionID, action: .deleted, updatedAt: Date(timeIntervalSinceReferenceDate: 100))],
            dailyMemos: ["2026-11-21": DailyMemo(dayKey: "2026-11-21", text: "Legacy", updatedAt: Date(timeIntervalSinceReferenceDate: 100))]
        )
        let encoded = try JSONEncoder().encode(full)
        var jsonObj = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        jsonObj.removeValue(forKey: "deletedManualRecords")
        jsonObj.removeValue(forKey: "deletedMemoDays")
        jsonObj.removeValue(forKey: "roleProfiles")
        jsonObj.removeValue(forKey: "anniversary")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObj)

        let decoded = try JSONDecoder().decode(JournalSnapshot.self, from: legacyData)
        #expect(decoded.roleProfiles.isEmpty)
        #expect(decoded.anniversary == nil)
        #expect(decoded.manualRecords.isEmpty)
        #expect(decoded.sessionOverrides.count == 1)
        #expect(decoded.dailyMemos["2026-11-21"]?.text == "Legacy")
        #expect(decoded.deletedManualRecords.isEmpty)
        #expect(decoded.deletedMemoDays.isEmpty)
    }

    @Test func profilesMergePerRoleWithDeterministicTies() {
        let base = Date(timeIntervalSinceReferenceDate: 100)
        let earlier = CalendarDateValue(year: 1999, month: 2, day: 1)
        let later = CalendarDateValue(year: 2000, month: 5, day: 10)
        let original = SyncedRoleProfile(bubbleColor: .mint, birthday: earlier, updatedAt: base)
        let near = base.addingTimeInterval(0.0004)
        let others = [
            SyncedRoleProfile(bubbleColor: .coral, birthday: nil, updatedAt: near),
            SyncedRoleProfile(bubbleColor: .skyBlue, birthday: earlier, updatedAt: near),
            SyncedRoleProfile(bubbleColor: .mint, birthday: later, updatedAt: near)
        ]
        let local = JournalSnapshot(roleProfiles: ["A": original])
        let peer = JournalSnapshot(roleProfiles: ["B": others[0]])
        #expect(JournalMerger.merge(local: local, remote: peer).roleProfiles == ["A": original, "B": others[0]])
        let newer = SyncedRoleProfile(bubbleColor: .skyBlue, birthday: nil, updatedAt: base.addingTimeInterval(0.001))
        for candidate in others + [newer] {
            let remote = JournalSnapshot(roleProfiles: ["A": candidate])
            let expected = candidate == newer ? newer : original
            #expect(JournalMerger.merge(local: local, remote: remote).profile(for: .partnerA) == expected)
            #expect(JournalMerger.merge(local: remote, remote: local).profile(for: .partnerA) == expected)
        }
    }

    @Test func anniversaryClearsAndTiesMergeInBothDirections() {
        let base = Date(timeIntervalSinceReferenceDate: 100)
        let day = CalendarDateValue(year: 2024, month: 10, day: 1)
        let original = SyncedAnniversary(date: day, updatedAt: base)
        let near = base.addingTimeInterval(0.0004)
        let clear = SyncedAnniversary(date: nil, updatedAt: base.addingTimeInterval(0.001))
        let candidates = [
            SyncedAnniversary(date: nil, updatedAt: near),
            SyncedAnniversary(date: CalendarDateValue(year: 2025, month: 1, day: 1), updatedAt: near),
            clear
        ]
        let local = JournalSnapshot(anniversary: original)
        for candidate in candidates {
            let remote = JournalSnapshot(anniversary: candidate)
            let expected = candidate == clear ? clear : original
            #expect(JournalMerger.merge(local: local, remote: remote).anniversary == expected)
            #expect(JournalMerger.merge(local: remote, remote: local).anniversary == expected)
        }
        let restored = SyncedAnniversary(date: day, updatedAt: base.addingTimeInterval(0.002))
        #expect(JournalMerger.merge(local: JournalSnapshot(anniversary: clear),
                                    remote: JournalSnapshot(anniversary: restored)).anniversary == restored)
    }

    @Test func journalMergerHandlesManualAdditionsTombstonesAndReEdits() {
        let pairID = UUID()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let t1 = t0.addingTimeInterval(60)
        let t2 = t0.addingTimeInterval(120)

        let idA = UUID()
        let idB = UUID()
        let idDeleted = UUID()
        let idRevived = UUID()

        let recA = ManualEncounterRecord(id: idA, pairID: pairID, startedAt: t0, endedAt: t0.addingTimeInterval(1800), createdAt: t0, updatedAt: t0)
        let recB = ManualEncounterRecord(id: idB, pairID: pairID, startedAt: t1, endedAt: t1.addingTimeInterval(1800), createdAt: t1, updatedAt: t1)
        let recStaleCopy = ManualEncounterRecord(id: idDeleted, pairID: pairID, startedAt: t0, endedAt: t0.addingTimeInterval(900), createdAt: t0, updatedAt: t0)
        let recRevivedNew = ManualEncounterRecord(id: idRevived, pairID: pairID, startedAt: t2, endedAt: t2.addingTimeInterval(3600), createdAt: t0, updatedAt: t2)

        let local = JournalSnapshot(
            manualRecords: [recA],
            deletedManualRecords: [idDeleted: t1, idRevived: t1]
        )
        let remote = JournalSnapshot(
            manualRecords: [recB, recStaleCopy, recRevivedNew]
        )

        let merged = JournalMerger.merge(local: local, remote: remote)
        let mergedIDs = Set(merged.manualRecords.map(\.id))
        #expect(mergedIDs == [idA, idB, idRevived])
        #expect(merged.deletedManualRecords[idDeleted] == t1)
        #expect(merged.deletedManualRecords[idRevived] == nil)
    }

    @Test func journalMergerHandlesMemosTombstonesAndOverrideTieBreak() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let t1 = t0.addingTimeInterval(30)
        let t2 = t0.addingTimeInterval(60)

        let sid1 = UUID()
        let sid2 = UUID()

        let local = JournalSnapshot(
            sessionOverrides: [
                sid1: SessionOverride(sessionID: sid1, action: .deleted, updatedAt: t0),
                sid2: SessionOverride(sessionID: sid2, action: .deleted, updatedAt: t1)
            ],
            dailyMemos: [
                "2026-11-20": DailyMemo(dayKey: "2026-11-20", text: "Newer local", updatedAt: t1),
                "2026-11-22": DailyMemo(dayKey: "2026-11-22", text: "Revived memo", updatedAt: t2)
            ],
            deletedMemoDays: ["2026-11-21": t1]
        )

        let remote = JournalSnapshot(
            sessionOverrides: [
                sid1: SessionOverride(sessionID: sid1, action: .edited(startedAt: t0, endedAt: t1), updatedAt: t1),
                sid2: SessionOverride(sessionID: sid2, action: .edited(startedAt: t0, endedAt: t1), updatedAt: t1)
            ],
            dailyMemos: [
                "2026-11-20": DailyMemo(dayKey: "2026-11-20", text: "Older remote", updatedAt: t0),
                "2026-11-21": DailyMemo(dayKey: "2026-11-21", text: "Deleted remotely", updatedAt: t0)
            ],
            deletedMemoDays: ["2026-11-22": t1]
        )

        let merged = JournalMerger.merge(local: local, remote: remote)
        #expect(merged.dailyMemos["2026-11-20"]?.text == "Newer local")
        #expect(merged.dailyMemos["2026-11-21"] == nil)
        #expect(merged.deletedMemoDays["2026-11-21"] == t1)
        #expect(merged.dailyMemos["2026-11-22"]?.text == "Revived memo")
        #expect(merged.deletedMemoDays["2026-11-22"] == nil)

        // Newer override wins; equal timestamp prefers .edited over .deleted
        if case let .edited(s, e) = merged.sessionOverrides[sid1]?.action {
            #expect(s == t0 && e == t1)
        } else {
            Issue.record("Expected sid1 override to be .edited")
        }
        if case let .edited(s, e) = merged.sessionOverrides[sid2]?.action {
            #expect(s == t0 && e == t1)
        } else {
            Issue.record("Expected sid2 tie-break override to prefer .edited over .deleted")
        }
    }

    @Test func simultaneousSessionOverridesConvergeInEitherOrder() {
        let id = UUID()
        let time = Date(timeIntervalSinceReferenceDate: 1)
        let later = time.addingTimeInterval(60)
        let ranked: [SessionOverrideAction] = [.deleted, .adjustedStart(startedAt: later),
                                               .adjustedStart(startedAt: time), .edited(startedAt: time, endedAt: later)]
        func journal(_ action: SessionOverrideAction, _ timestamp: Date) -> JournalSnapshot {
            JournalSnapshot(sessionOverrides: [id: SessionOverride(sessionID: id, action: action, updatedAt: timestamp)])
        }
        for (index, winner) in ranked.enumerated() {
            let preferred = journal(winner, time)
            for other in ranked.prefix(index) {
                let competing = journal(other, time.addingTimeInterval(0.0001))
                #expect(JournalMerger.merge(local: preferred, remote: competing) == preferred)
                #expect(JournalMerger.merge(local: competing, remote: preferred) == preferred)
            }
        }
        let older = journal(.adjustedStart(startedAt: time), time)
        let newer = journal(.adjustedStart(startedAt: time), time.addingTimeInterval(0.0001))
        #expect(JournalMerger.merge(local: older, remote: newer) == newer)
        #expect(JournalMerger.merge(local: newer, remote: older) == newer)
    }

    @Test func deduplicatesOverlappingAndSplitCrossDeviceBLESessions() throws {
        let pairID = UUID()
        let start = try date("2026-11-21T14:00:00+09:00")
        let end = start.addingTimeInterval(7200) // 16:00

        let localContinuous = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: start, endedAt: end,
            status: .completed, connectionPath: .autoReconnect, startRole: .central
        )
        let peerSplit1 = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: start.addingTimeInterval(15), endedAt: start.addingTimeInterval(2700),
            status: .completed, connectionPath: .scanDiscovery
        )
        let peerSplit2 = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: start.addingTimeInterval(2820), endedAt: end.addingTimeInterval(-10),
            status: .completed, connectionPath: .autoReconnect
        )

        let resolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localContinuous],
            peerSessions: [peerSplit1, peerSplit2],
            journal: JournalSnapshot()
        )
        #expect(resolved.count == 1)
        let item = try #require(resolved.first)
        #expect(Set(item.linkedSessionIDs) == [localContinuous.id, peerSplit1.id, peerSplit2.id])
        #expect(item.durationSeconds == 7200)
        #expect(EncounterCalendarAggregator.lifetimeRecordedSeconds(
            autoSessions: [localContinuous], peerSessions: [peerSplit1, peerSplit2], journal: JournalSnapshot(), calendar: tokyo
        ) == 7200)
    }

    @Test func includesPeerOnlySessionAndCompletesLocalUnknownEnd() throws {
        let pairID = UUID()
        let morningStart = try date("2026-11-21T09:00:00+09:00")
        let lunchStart = try date("2026-11-21T12:00:00+09:00")
        let lunchEnd = try date("2026-11-21T13:30:00+09:00")
        let eveningStart = try date("2026-11-21T18:00:00+09:00")
        let eveningEnd = try date("2026-11-21T20:00:00+09:00")

        // Unrelated morning unknownEnd (should remain .unknownEnd, not touched by afternoon peer sessions)
        let localUnrelatedUnknown = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: morningStart, endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        // Evening unknownEnd that peer observed cleanly from 18:02 -> 20:00
        let localEveningUnknown = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: eveningStart, endedAt: nil,
            status: .unknownEnd, connectionPath: .autoReconnect, startRole: .peripheral
        )
        // Lunch missed completely by local
        let peerLunch = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: lunchStart, endedAt: lunchEnd,
            status: .completed, connectionPath: .scanDiscovery
        )
        let peerEvening = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: eveningStart.addingTimeInterval(120), endedAt: eveningEnd,
            status: .completed, connectionPath: .scanDiscovery
        )

        let resolved = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localUnrelatedUnknown, localEveningUnknown],
            peerSessions: [peerLunch, peerEvening],
            journal: JournalSnapshot()
        )
        #expect(resolved.count == 3)

        #expect(resolved[0].status == .unknownEnd)
        #expect(resolved[0].id == localUnrelatedUnknown.id)

        if case let .peerAuto(sessionID) = resolved[1].source {
            #expect(sessionID == peerLunch.id)
        } else {
            Issue.record("Expected peerLunch to resolve as .peerAuto")
        }
        #expect(resolved[1].durationSeconds == 5400)

        let expectedPrimaryEvening = [localEveningUnknown.id, peerEvening.id].sorted { $0.uuidString < $1.uuidString }[0]
        if case let .peerCompleted(sessionID) = resolved[2].source {
            #expect(sessionID == expectedPrimaryEvening)
        } else {
            Issue.record("Expected localEveningUnknown + peerEvening to resolve as .peerCompleted")
        }
        #expect(resolved[2].status == .completed)
        #expect(resolved[2].startedAt == eveningStart)
        #expect(resolved[2].endedAt == eveningEnd)
        #expect(resolved[2].durationSeconds == 7200)
        #expect(Set(resolved[2].linkedSessionIDs) == [localEveningUnknown.id, peerEvening.id])
    }

    @Test func linksDualUnknownEndSuppressesCoveredLocationAndRespectsOfflineManualOverrides() throws {
        let pairID = UUID()
        let start = try date("2026-11-21T15:00:00+09:00")
        let end = try date("2026-11-21T17:00:00+09:00")

        // 1. Both devices unknownEnd within 3 minutes -> single encounter linking both IDs
        let localUnknown = EncounterSession(
            id: UUID(), pairID: pairID, startedAt: start, endedAt: nil,
            status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central
        )
        let peerUnknown = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: start.addingTimeInterval(180), endedAt: nil,
            status: .unknownEnd, connectionPath: .incomingPeripheral
        )
        let dualUnknown = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localUnknown], peerSessions: [peerUnknown], journal: JournalSnapshot()
        )
        #expect(dualUnknown.count == 1)
        #expect(dualUnknown[0].status == .unknownEnd)
        #expect(Set(dualUnknown[0].linkedSessionIDs) == [localUnknown.id, peerUnknown.id])

        // 2. Manual deletion performed offline on localUnknown BEFORE peerUnknown completed/arrived wins!
        let localDelete = JournalSnapshot(
            sessionOverrides: [
                localUnknown.id: SessionOverride(sessionID: localUnknown.id, action: .deleted, updatedAt: start)
            ]
        )
        let peerCompletedLater = SyncedPeerSession(
            id: peerUnknown.id, pairID: pairID, startedAt: start, endedAt: end,
            status: .completed, connectionPath: .incomingPeripheral
        )
        let afterOfflineDelete = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [localUnknown], peerSessions: [peerCompletedLater], journal: localDelete
        )
        #expect(afterOfflineDelete.isEmpty)

        // 3. Peer-only BLE session suppresses >=95% covered LocationMatchedSession
        let peerOnly = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: start, endedAt: end,
            status: .completed, connectionPath: .autoReconnect
        )
        let locCovered = LocationMatchedSession(
            id: UUID(), pairID: pairID, startedAt: start.addingTimeInterval(60), endedAt: end.addingTimeInterval(-60),
            averageDistanceMeters: 25
        )
        let resolvedWithLoc = EncounterCalendarAggregator.resolveEncounters(
            autoSessions: [], peerSessions: [peerOnly], locationSessions: [locCovered], journal: JournalSnapshot()
        )
        #expect(resolvedWithLoc.count == 1)
        if case .peerAuto = resolvedWithLoc[0].source {} else {
            Issue.record("Expected covered LocationMatchedSession to be suppressed by peer BLE session")
        }
    }

    @Test func storesPersistJournalMergeAtomicOverridesAndPeerSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OurHoursPartnerSyncTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let journalStore = JournalStore(directory: dir)
        let syncStore = PartnerSyncStore(directory: dir)
        let pairID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let id1 = UUID()
        let id2 = UUID()
        _ = try journalStore.setSessionOverrides([
            id1: .edited(startedAt: base, endedAt: base.addingTimeInterval(3600)),
            id2: .deleted
        ])
        _ = try journalStore.setMemo(dayKey: "2026-11-21", text: "Local memo")

        let remoteMemoID = UUID()
        let remoteJournal = JournalSnapshot(
            manualRecords: [
                ManualEncounterRecord(
                    id: remoteMemoID, pairID: pairID, startedAt: base, endedAt: base.addingTimeInterval(1800),
                    createdAt: base, updatedAt: base
                )
            ],
            dailyMemos: [
                "2026-11-20": DailyMemo(dayKey: "2026-11-20", text: "Remote memo", updatedAt: base)
            ]
        )
        let mergeFirst = try journalStore.mergeRemote(remoteJournal)
        #expect(mergeFirst.didChange)
        #expect(mergeFirst.snapshot.manualRecords.map(\.id) == [remoteMemoID])
        #expect(mergeFirst.snapshot.dailyMemos["2026-11-20"]?.text == "Remote memo")
        #expect(mergeFirst.snapshot.dailyMemos["2026-11-21"]?.text == "Local memo")

        let mergeSecond = try journalStore.mergeRemote(remoteJournal)
        #expect(!mergeSecond.didChange)

        let peerSession = SyncedPeerSession(
            id: UUID(), pairID: pairID, startedAt: base, endedAt: base.addingTimeInterval(1200),
            status: .completed, connectionPath: .autoReconnect
        )
        let foreignSession = SyncedPeerSession(
            id: UUID(), pairID: UUID(), startedAt: base, endedAt: base.addingTimeInterval(1200),
            status: .completed, connectionPath: .autoReconnect
        )
        _ = try syncStore.savePeerSessions(pairID: pairID, peerRole: .partnerB, sessions: [peerSession, foreignSession], now: base)
        let loaded = try syncStore.load()
        #expect(loaded?.sessions == [peerSession])

        try syncStore.clearAll()
        #expect(try syncStore.load() == nil)
    }
}
