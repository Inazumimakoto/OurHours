import Foundation
import Synchronization

public enum JournalStoreError: Error, Sendable, Equatable {
    case invalidTimeRange
    case recordNotFound
}

public final class JournalStore: Sendable {
    // Serialize read-modify-write operations even when stores share a directory.
    private static let lock = Mutex(())
    public let directory: URL
    private var journalURL: URL { directory.appendingPathComponent("journal.json") }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    public func load() throws -> JournalSnapshot {
        try Self.lock.withLock { _ in try read() }
    }

    @discardableResult
    public func setRoleProfile(
        role: PeerRole, bubbleColor: BubbleColorTheme, birthday: CalendarDateValue?
    ) throws -> JournalSnapshot {
        try modify { snapshot in
            let ts = Self.monotonicNow(after: snapshot.roleProfiles[role.shortCode]?.updatedAt ?? .distantPast)
            snapshot.roleProfiles[role.shortCode] = SyncedRoleProfile(
                bubbleColor: bubbleColor, birthday: birthday, updatedAt: ts
            )
        }
    }

    @discardableResult
    public func clearRoleProfiles() throws -> JournalSnapshot {
        try modify {
            $0.roleProfiles = [:]
            $0.anniversary = nil
        }
    }

    @discardableResult
    public func setAnniversary(_ date: CalendarDateValue?) throws -> JournalSnapshot {
        try modify { snapshot in
            let ts = Self.monotonicNow(after: snapshot.anniversary?.updatedAt ?? .distantPast)
            snapshot.anniversary = SyncedAnniversary(date: date, updatedAt: ts)
        }
    }

    @discardableResult
    public func addManualRecord(pairID: UUID?, startedAt: Date, endedAt: Date) throws -> JournalSnapshot {
        guard endedAt > startedAt else { throw JournalStoreError.invalidTimeRange }
        return try modify { snapshot in
            let now = Date()
            snapshot.manualRecords.append(ManualEncounterRecord(
                id: UUID(), pairID: pairID, startedAt: startedAt, endedAt: endedAt,
                createdAt: now, updatedAt: now
            ))
        }
    }

    @discardableResult
    public func updateManualRecord(id: UUID, startedAt: Date, endedAt: Date) throws -> JournalSnapshot {
        guard endedAt > startedAt else { throw JournalStoreError.invalidTimeRange }
        return try modify { snapshot in
            guard let index = snapshot.manualRecords.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let record = snapshot.manualRecords[index]
            let ts = Self.monotonicNow(after: record.updatedAt)
            snapshot.manualRecords[index] = ManualEncounterRecord(
                id: record.id, pairID: record.pairID, startedAt: startedAt, endedAt: endedAt,
                createdAt: record.createdAt, updatedAt: ts
            )
            snapshot.deletedManualRecords[id] = nil
        }
    }

    @discardableResult
    public func deleteManualRecord(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.manualRecords.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let record = snapshot.manualRecords.remove(at: index)
            snapshot.deletedManualRecords[id] = Self.monotonicNow(
                after: record.updatedAt,
                snapshot.deletedManualRecords[id] ?? .distantPast
            )
        }
    }

    @discardableResult
    public func setSessionOverride(sessionID: UUID, action: SessionOverrideAction) throws -> JournalSnapshot {
        try setSessionOverrides([sessionID: action])
    }

    @discardableResult
    public func setSessionOverrides(_ updates: [UUID: SessionOverrideAction]) throws -> JournalSnapshot {
        for action in updates.values {
            if case let .edited(startedAt, endedAt) = action, !(endedAt > startedAt) {
                throw JournalStoreError.invalidTimeRange
            }
        }
        guard !updates.isEmpty else { return try load() }
        return try modify { snapshot in
            let floor = updates.keys.compactMap { snapshot.sessionOverrides[$0]?.updatedAt }.max() ?? .distantPast
            let ts = Self.monotonicNow(after: floor)
            for (sessionID, action) in updates {
                snapshot.sessionOverrides[sessionID] = SessionOverride(
                    sessionID: sessionID,
                    action: action,
                    updatedAt: ts
                )
            }
        }
    }

    @discardableResult
    public func clearSessionOverride(sessionID: UUID) throws -> JournalSnapshot {
        try modify { $0.sessionOverrides[sessionID] = nil }
    }

    @discardableResult
    public func setMemo(dayKey: String, text: String) throws -> JournalSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return try modify { snapshot in
            let existingMemoAt = snapshot.dailyMemos[dayKey]?.updatedAt ?? .distantPast
            let existingDeletedAt = snapshot.deletedMemoDays[dayKey] ?? .distantPast
            let ts = Self.monotonicNow(after: existingMemoAt, existingDeletedAt)
            if trimmed.isEmpty {
                snapshot.dailyMemos[dayKey] = nil
                snapshot.deletedMemoDays[dayKey] = ts
            } else {
                snapshot.dailyMemos[dayKey] = DailyMemo(dayKey: dayKey, text: trimmed, updatedAt: ts)
                snapshot.deletedMemoDays[dayKey] = nil
            }
        }
    }

    @discardableResult
    public func applyMergedMutation(
        pairID: UUID?,
        keepManualID: UUID?,
        createManual: Bool,
        mergedStart: Date,
        mergedEnd: Date,
        deleteManualIDs: [UUID],
        sessionOverrideUpdates: [UUID: SessionOverrideAction]
    ) throws -> JournalSnapshot {
        guard mergedEnd > mergedStart else { throw JournalStoreError.invalidTimeRange }
        for action in sessionOverrideUpdates.values {
            if case let .edited(startedAt, endedAt) = action, !(endedAt > startedAt) {
                throw JournalStoreError.invalidTimeRange
            }
        }
        return try modify { snapshot in
            var floors: [Date] = []
            if let keepManualID {
                guard let keep = snapshot.manualRecords.first(where: { $0.id == keepManualID }) else {
                    throw JournalStoreError.recordNotFound
                }
                floors.append(keep.updatedAt)
                if let prevDel = snapshot.deletedManualRecords[keepManualID] {
                    floors.append(prevDel)
                }
            }
            for delID in deleteManualIDs where delID != keepManualID {
                if let rec = snapshot.manualRecords.first(where: { $0.id == delID }) {
                    floors.append(rec.updatedAt)
                }
                if let prevDel = snapshot.deletedManualRecords[delID] {
                    floors.append(prevDel)
                }
            }
            for sid in sessionOverrideUpdates.keys {
                if let prevOv = snapshot.sessionOverrides[sid] {
                    floors.append(prevOv.updatedAt)
                }
            }
            let ts = Self.monotonicNow(after: floors)

            if let keepManualID,
               let idx = snapshot.manualRecords.firstIndex(where: { $0.id == keepManualID }) {
                let existing = snapshot.manualRecords[idx]
                snapshot.manualRecords[idx] = ManualEncounterRecord(
                    id: existing.id,
                    pairID: existing.pairID,
                    startedAt: mergedStart,
                    endedAt: mergedEnd,
                    createdAt: existing.createdAt,
                    updatedAt: ts
                )
                snapshot.deletedManualRecords[keepManualID] = nil
            } else if createManual {
                snapshot.manualRecords.append(ManualEncounterRecord(
                    id: UUID(),
                    pairID: pairID,
                    startedAt: mergedStart,
                    endedAt: mergedEnd,
                    createdAt: ts,
                    updatedAt: ts
                ))
            }

            let deleteSet = Set(deleteManualIDs.filter { $0 != keepManualID })
            if !deleteSet.isEmpty {
                snapshot.manualRecords.removeAll { deleteSet.contains($0.id) }
                for delID in deleteSet {
                    snapshot.deletedManualRecords[delID] = ts
                }
            }

            for (sid, action) in sessionOverrideUpdates {
                snapshot.sessionOverrides[sid] = SessionOverride(
                    sessionID: sid,
                    action: action,
                    updatedAt: ts
                )
            }
        }
    }

    @discardableResult
    public func mergeRemote(_ remote: JournalSnapshot) throws -> (snapshot: JournalSnapshot, didChange: Bool) {
        try Self.lock.withLock { _ in
            let current = try read()
            let merged = JournalMerger.merge(local: current, remote: remote)
            guard merged != current else {
                return (current, false)
            }
            let data = try JSONEncoder().encode(merged)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: journalURL, options: .atomic)
            return (merged, true)
        }
    }

    private static func monotonicNow(after dates: Date...) -> Date {
        monotonicNow(after: dates)
    }

    private static func monotonicNow(after dates: [Date]) -> Date {
        let floor = dates.max() ?? .distantPast
        return max(Date(), floor.addingTimeInterval(0.001))
    }

    @discardableResult
    public func clearAll() throws -> JournalSnapshot {
        try Self.lock.withLock { _ in
            do {
                try FileManager.default.removeItem(at: journalURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return JournalSnapshot()
            }
            return JournalSnapshot()
        }
    }

    private func read() throws -> JournalSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: journalURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return JournalSnapshot()
        }
        return try JSONDecoder().decode(JournalSnapshot.self, from: data)
    }

    private func modify(_ update: (inout JournalSnapshot) throws -> Void) throws -> JournalSnapshot {
        try Self.lock.withLock { _ in
            var snapshot = try read()
            try update(&snapshot)
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: journalURL, options: .atomic)
            return snapshot
        }
    }
}
