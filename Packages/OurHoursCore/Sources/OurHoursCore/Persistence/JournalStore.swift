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
            snapshot.manualRecords[index] = ManualEncounterRecord(
                id: record.id, pairID: record.pairID, startedAt: startedAt, endedAt: endedAt,
                createdAt: record.createdAt, updatedAt: Date()
            )
        }
    }

    @discardableResult
    public func deleteManualRecord(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.manualRecords.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            snapshot.manualRecords.remove(at: index)
        }
    }

    @discardableResult
    public func setSessionOverride(sessionID: UUID, action: SessionOverrideAction) throws -> JournalSnapshot {
        if case let .edited(startedAt, endedAt) = action, !(endedAt > startedAt) {
            throw JournalStoreError.invalidTimeRange
        }
        return try modify { snapshot in
            snapshot.sessionOverrides[sessionID] = SessionOverride(
                sessionID: sessionID, action: action, updatedAt: Date()
            )
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
            snapshot.dailyMemos[dayKey] = trimmed.isEmpty
                ? nil
                : DailyMemo(dayKey: dayKey, text: trimmed, updatedAt: Date())
        }
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
