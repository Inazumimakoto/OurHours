import Foundation
import Testing
import OurHoursCore

struct JournalStoreTests {
    private let store = JournalStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    )
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var end: Date { start.addingTimeInterval(1_800.5) }

    @Test func profileAndAnniversaryMutationsPersistWithMonotonicTimestamps() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let day = CalendarDateValue(year: 2000, month: 2, day: 29)
        let created = try store.setRoleProfile(role: .partnerA, bubbleColor: .mint, birthday: day)
        let original = try #require(created.profile(for: .partnerA))
        #expect(original.birthday == day)
        #expect(original.bubbleColor == .mint)
        try store.setRoleProfile(role: .partnerB, bubbleColor: .lavender, birthday: nil)
        let edited = try store.setRoleProfile(role: .partnerA, bubbleColor: .clear, birthday: nil)
        let profile = try #require(edited.profile(for: .partnerA))
        #expect(profile.updatedAt > original.updatedAt)
        #expect(profile.bubbleColor == .clear && profile.bubbleColor.displayName == "透明" && profile.birthday == nil)
        #expect(edited.profile(for: .partnerB)?.bubbleColor == .lavender)

        let saved = try #require(try store.setAnniversary(day).anniversary)
        #expect(saved.date == day)
        let cleared = try #require(try store.setAnniversary(nil).anniversary)
        #expect(cleared.date == nil && cleared.updatedAt > saved.updatedAt)
        let result = try store.clearRoleProfiles()
        #expect(result.roleProfiles.isEmpty && result.anniversary == nil)
        #expect(try store.load() == result)
    }

    @Test func manualRecordsPersistEditsAndDeletion() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(try store.load() == JournalSnapshot())
        let pairID = UUID()
        let added = try store.addManualRecord(pairID: pairID, startedAt: start, endedAt: end)
        let original = try #require(added.manualRecords.first)
        #expect(original.pairID == pairID)
        #expect(original.startedAt == start && original.endedAt == end)
        #expect(original.createdAt == original.updatedAt)
        let otherStore = JournalStore(directory: store.directory)
        #expect(try otherStore.load() == added)

        let updatedEnd = end.addingTimeInterval(20)
        let updated = try otherStore.updateManualRecord(id: original.id, startedAt: start, endedAt: updatedEnd)
        let record = try #require(updated.manualRecords.first)
        #expect(record.id == original.id && record.pairID == original.pairID)
        #expect(record.createdAt == original.createdAt && record.updatedAt >= original.updatedAt)
        #expect(record.endedAt == updatedEnd)
        #expect(try store.load() == updated)
        let deleted = try store.deleteManualRecord(id: original.id)
        #expect(deleted.manualRecords.isEmpty)
        #expect(deleted.deletedManualRecords[original.id] != nil)
        #expect(try otherStore.load() == deleted)
    }

    @Test func overridesAndMemosRoundTripAndCanBeCleared() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let sessionID = UUID()
        let action = SessionOverrideAction.edited(startedAt: start, endedAt: end)
        try store.setSessionOverride(sessionID: sessionID, action: action)
        let dayKey = "2026-11-01"
        let saved = try store.setMemo(dayKey: dayKey, text: "  Dinner\nTogether\n ")
        #expect(saved.sessionOverrides[sessionID]?.action == action)
        #expect(saved.dailyMemos[dayKey]?.text == "Dinner\nTogether")
        #expect(try JournalStore(directory: store.directory).load() == saved)
        #expect(try store.setMemo(dayKey: dayKey, text: "\n\t ").dailyMemos.isEmpty)
        #expect(try store.setSessionOverride(sessionID: sessionID, action: .deleted)
            .sessionOverrides[sessionID]?.action == .deleted)
        let cleared = try store.clearSessionOverride(sessionID: sessionID)
        #expect(cleared.manualRecords.isEmpty)
        #expect(cleared.sessionOverrides.isEmpty)
        #expect(cleared.dailyMemos.isEmpty)
        #expect(cleared.deletedMemoDays[dayKey] != nil)

        try store.addManualRecord(pairID: nil, startedAt: start, endedAt: end)
        try store.setSessionOverride(sessionID: sessionID, action: .deleted)
        try store.setMemo(dayKey: dayKey, text: "Dinner")
        #expect(try store.clearAll() == JournalSnapshot())
        #expect(try store.clearAll() == JournalSnapshot())
        #expect(try store.load() == JournalSnapshot())
    }

    @Test func activeMergePersistsAdjustmentAndTombstonesAtomically() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let pairID = UUID()
        let initial = try store.addManualRecord(pairID: pairID, startedAt: start, endedAt: end)
        let manual = try #require(initial.manualRecords.first)
        let completed = EncounterSession(pairID: pairID, startedAt: start, endedAt: end, status: .completed,
                                         connectionPath: .autoReconnect, startRole: .central)
        let active = EncounterSession(pairID: pairID, startedAt: end, connectionPath: .autoReconnect, startRole: .central)
        for (keep, create) in [(manual.id as UUID?, false), (nil, true)] {
            #expect(throws: JournalStoreError.invalidTimeRange) {
                try store.applyMergedMutation(
                    pairID: pairID, keepManualID: keep, createManual: create, mergedStart: start, mergedEnd: nil,
                    deleteManualIDs: [manual.id], sessionOverrideUpdates: [completed.id: .deleted]
                )
            }
        }
        #expect(try store.load() == initial)
        let saved = try store.applyMergedMutation(
            pairID: pairID, keepManualID: nil, createManual: false, mergedStart: start, mergedEnd: nil,
            deleteManualIDs: [manual.id], sessionOverrideUpdates: [completed.id: .deleted, active.id: .adjustedStart(startedAt: start)]
        )
        let persisted = try JournalStore(directory: store.directory).load()
        #expect(persisted == saved)
        #expect(persisted.manualRecords.isEmpty && persisted.deletedManualRecords[manual.id] != nil)
        #expect(persisted.sessionOverrides[completed.id]?.action == .deleted)
        let resolved = EncounterCalendarAggregator.resolveEncounters(autoSessions: [completed, active], journal: persisted)
        #expect(resolved.map(\.id) == [active.id])
        let survivor = try #require(resolved.first)
        #expect(survivor.status == .active && survivor.startedAt == start && survivor.endedAt == nil)
    }

    @Test func rejectedMutationsPreserveStoredSnapshot() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let saved = try store.addManualRecord(pairID: nil, startedAt: start, endedAt: end)
        let record = try #require(saved.manualRecords.first)
        #expect(throws: JournalStoreError.invalidTimeRange) {
            try store.addManualRecord(pairID: nil, startedAt: start, endedAt: start)
        }
        #expect(throws: JournalStoreError.invalidTimeRange) {
            try store.updateManualRecord(id: record.id, startedAt: end, endedAt: start)
        }
        #expect(throws: JournalStoreError.invalidTimeRange) {
            try store.setSessionOverride(sessionID: UUID(), action: .edited(startedAt: end, endedAt: end))
        }
        #expect(throws: JournalStoreError.recordNotFound) {
            try store.updateManualRecord(id: UUID(), startedAt: start, endedAt: end)
        }
        #expect(throws: JournalStoreError.recordNotFound) {
            try store.deleteManualRecord(id: UUID())
        }
        #expect(try store.load() == saved)
    }

    @Test func corruptJournalThrowsAndPreservesData() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let journalURL = store.directory.appendingPathComponent("journal.json")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: journalURL)

        #expect(throws: DecodingError.self) { try store.load() }
        #expect(throws: DecodingError.self) { try store.setMemo(dayKey: "2026-11-01", text: "Dinner") }
        #expect(try Data(contentsOf: journalURL) == corrupt)
    }

    @Test func concurrentStoreInstancesPreserveAllWrites() async throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try JournalStore(directory: store.directory).addManualRecord(
                        pairID: nil, startedAt: start, endedAt: end
                    )
                }
            }
            try await group.waitForAll()
        }
        let records = try store.load().manualRecords
        #expect(records.count == 16)
        #expect(Set(records.map(\.id)).count == 16)
    }

    @Test func calendarDateValueAlwaysStoresGregorianDates() throws {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = CalendarDateValue.gregorianCurrent.timeZone
        let reiwa8 = try #require(japanese.date(from: DateComponents(year: 8, month: 11, day: 21, hour: 12)))
        let gregorianDate = CalendarDateValue(date: reiwa8)
        #expect(gregorianDate == CalendarDateValue(year: 2026, month: 11, day: 21))
        #expect(gregorianDate.formattedJapanese == "2026年11月21日")

        let leapDay = CalendarDateValue(year: 2000, month: 2, day: 29)
        let roundTrip = CalendarDateValue(date: leapDay.toDate())
        #expect(roundTrip == leapDay)
    }

    @Test func clearedSessionOverrideProducesTombstoneAndBlocksStaleResurrection() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let id = UUID()
        let stale = try store.setSessionOverride(sessionID: id, action: .deleted)
        let cleared = try store.clearSessionOverride(sessionID: id)
        let deletion = try #require(cleared.deletedSessionOverrides[id])
        let original = try #require(stale.sessionOverrides[id])
        #expect(deletion > original.updatedAt)
        #expect(try !store.mergeRemote(stale).didChange)
        #expect(JournalMerger.merge(local: stale, remote: cleared) == cleared)
        let future = deletion.addingTimeInterval(3600)
        try store.mergeRemote(JournalSnapshot(deletedSessionOverrides: [id: future]))
        let new = try store.setSessionOverride(sessionID: id, action: .adjustedStart(startedAt: start))
        #expect(try #require(new.sessionOverrides[id]).updatedAt > future)
        #expect(new.deletedSessionOverrides.isEmpty)
        #expect(JournalMerger.merge(local: cleared, remote: new) == new)
    }

    @Test func journalScopingIsolatesMemosOverridesAndManualRecordsAcrossRePairing() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let oldPair = UUID(), newPair = UUID(), session = UUID(), cleared = UUID()
        try store.addManualRecord(pairID: nil, startedAt: start, endedAt: end)
        try store.setMemo(dayKey: "day1", text: "old")
        let solo = try store.setSessionOverride(sessionID: session, action: .deleted)
        #expect(solo.scoped(to: oldPair, allowedSessionIDs: []).sessionOverrides.isEmpty)
        try store.clearSessionOverride(sessionID: cleared)
        try store.setRoleProfile(role: .partnerA, bubbleColor: .mint, birthday: nil)
        try store.setAnniversary(CalendarDateValue(year: 2020, month: 1, day: 1))
        try store.setMemo(dayKey: "deleted", text: "")
        let retained = try store.prepareForPairTransition(from: oldPair, to: nil)
        #expect(retained.manualRecords.first?.pairID == oldPair)
        #expect(retained.dailyMemos["day1"]?.pairID == oldPair)
        #expect(retained.sessionOverrides[session]?.pairID == oldPair)
        #expect(retained.deletedSessionOverrides[cleared] != nil)
        #expect(retained.roleProfiles.isEmpty && retained.anniversary == nil && retained.deletedMemoDays.isEmpty)
        try store.setMemo(dayKey: "day2", text: "solo")
        let paired = try store.prepareForPairTransition(from: nil, to: newPair)
        #expect(try store.load() == paired)
        let scoped = paired.scoped(to: newPair, allowedSessionIDs: [])
        #expect(scoped.manualRecords.isEmpty && scoped.sessionOverrides.isEmpty && scoped.deletedSessionOverrides.isEmpty)
        #expect(scoped.dailyMemos.count == 1 && scoped.dailyMemos["day2"]?.pairID == newPair)
        #expect(try store.claimUnscopedEntries(for: newPair) == paired)
    }

    @Test func newerUnscopedMemoAndOverrideRetainPairOwnership() throws {
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let pair = UUID(), session = UUID()
        try store.setSessionOverride(sessionID: session, action: .deleted, pairID: pair)
        try store.setMemo(dayKey: "day", text: "before", pairID: pair)
        try store.setSessionOverrides([session: .adjustedStart(startedAt: start)])
        let local = try store.setMemo(dayKey: "day", text: "after")
        #expect(local.sessionOverrides[session]?.pairID == pair && local.dailyMemos["day"]?.pairID == pair)
        let future = Date().addingTimeInterval(3600)
        let remote = JournalSnapshot(
            sessionOverrides: [session: SessionOverride(sessionID: session, action: .deleted, updatedAt: future)],
            dailyMemos: ["day": DailyMemo(dayKey: "day", text: "remote", updatedAt: future)]
        )
        let merged = JournalMerger.merge(local: local, remote: remote)
        #expect(merged.dailyMemos["day"]?.text == "remote" && merged.dailyMemos["day"]?.pairID == pair)
        #expect(merged.sessionOverrides[session]?.action == .deleted && merged.sessionOverrides[session]?.pairID == pair)
        #expect(JournalMerger.merge(local: remote, remote: local) == merged)
    }
}
