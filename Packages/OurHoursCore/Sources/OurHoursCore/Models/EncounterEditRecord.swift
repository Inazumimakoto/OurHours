import Foundation

public struct ManualEncounterRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID?
    public let startedAt: Date
    public let endedAt: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, pairID: UUID?, startedAt: Date, endedAt: Date, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.pairID = pairID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SessionOverrideAction: Codable, Sendable, Equatable {
    case edited(startedAt: Date, endedAt: Date)
    case adjustedStart(startedAt: Date)
    case deleted
}

public struct SessionOverride: Codable, Sendable, Equatable {
    public let pairID: UUID?
    public let sessionID: UUID
    public let action: SessionOverrideAction
    public let updatedAt: Date

    public init(sessionID: UUID, action: SessionOverrideAction, updatedAt: Date, pairID: UUID? = nil) {
        self.pairID = pairID
        self.sessionID = sessionID
        self.action = action
        self.updatedAt = updatedAt
    }
}

public struct DailyMemo: Codable, Sendable, Equatable, Identifiable {
    public let pairID: UUID?
    public let dayKey: String
    public let text: String
    public let updatedAt: Date
    public var id: String { dayKey }

    public init(dayKey: String, text: String, updatedAt: Date, pairID: UUID? = nil) {
        self.pairID = pairID
        self.dayKey = dayKey
        self.text = text
        self.updatedAt = updatedAt
    }
}

public struct JournalSnapshot: Codable, Sendable, Equatable {
    public var manualRecords: [ManualEncounterRecord]
    public var sessionOverrides: [UUID: SessionOverride]
    public var dailyMemos: [String: DailyMemo]
    public var deletedManualRecords: [UUID: Date]
    public var deletedSessionOverrides: [UUID: Date]
    public var deletedMemoDays: [String: Date]

    public var roleProfiles: [String: SyncedRoleProfile]
    public var anniversary: SyncedAnniversary?

    public func profile(for role: PeerRole) -> SyncedRoleProfile? {
        roleProfiles[role.shortCode]
    }

    private enum CodingKeys: String, CodingKey {
        case manualRecords
        case sessionOverrides
        case dailyMemos
        case deletedManualRecords
        case roleProfiles
        case anniversary
        case deletedSessionOverrides
        case deletedMemoDays
    }

    public init(
        manualRecords: [ManualEncounterRecord] = [],
        sessionOverrides: [UUID: SessionOverride] = [:],
        dailyMemos: [String: DailyMemo] = [:],
        deletedManualRecords: [UUID: Date] = [:],
        deletedMemoDays: [String: Date] = [:],
        deletedSessionOverrides: [UUID: Date] = [:],
        roleProfiles: [String: SyncedRoleProfile] = [:],
        anniversary: SyncedAnniversary? = nil
    ) {
        self.roleProfiles = roleProfiles
        self.anniversary = anniversary
        self.manualRecords = manualRecords
        self.sessionOverrides = sessionOverrides
        self.dailyMemos = dailyMemos
        self.deletedManualRecords = deletedManualRecords
        self.deletedSessionOverrides = deletedSessionOverrides
        self.deletedMemoDays = deletedMemoDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.roleProfiles = try container.decodeIfPresent([String: SyncedRoleProfile].self, forKey: .roleProfiles) ?? [:]
        self.anniversary = try container.decodeIfPresent(SyncedAnniversary.self, forKey: .anniversary)
        self.manualRecords = try container.decodeIfPresent([ManualEncounterRecord].self, forKey: .manualRecords) ?? []
        self.sessionOverrides = try container.decodeIfPresent([UUID: SessionOverride].self, forKey: .sessionOverrides) ?? [:]
        self.dailyMemos = try container.decodeIfPresent([String: DailyMemo].self, forKey: .dailyMemos) ?? [:]
        self.deletedManualRecords = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedManualRecords) ?? [:]
        self.deletedSessionOverrides = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedSessionOverrides) ?? [:]
        self.deletedMemoDays = try container.decodeIfPresent([String: Date].self, forKey: .deletedMemoDays) ?? [:]
    }
}

extension JournalSnapshot {
    public func scoped(to pairID: UUID, allowedSessionIDs: Set<UUID>? = nil) -> JournalSnapshot {
        var result = self
        result.manualRecords = manualRecords.filter { $0.pairID == nil || $0.pairID == pairID }
        result.dailyMemos = dailyMemos.filter { $0.value.pairID == nil || $0.value.pairID == pairID }
        result.sessionOverrides = sessionOverrides.filter { id, entry in
            entry.pairID == pairID || (entry.pairID == nil && (allowedSessionIDs?.contains(id) ?? true))
        }
        result.deletedSessionOverrides = deletedSessionOverrides.filter { allowedSessionIDs?.contains($0.key) ?? true }
        return result
    }

    public func stampingUnscoped(with pairID: UUID) -> JournalSnapshot {
        var result = self
        result.manualRecords = manualRecords.map { record in
            guard record.pairID == nil else { return record }
            return ManualEncounterRecord(id: record.id, pairID: pairID, startedAt: record.startedAt,
                                         endedAt: record.endedAt, createdAt: record.createdAt, updatedAt: record.updatedAt)
        }
        result.dailyMemos = dailyMemos.mapValues { memo in
            guard memo.pairID == nil else { return memo }
            return DailyMemo(dayKey: memo.dayKey, text: memo.text, updatedAt: memo.updatedAt, pairID: pairID)
        }
        result.sessionOverrides = sessionOverrides.mapValues { entry in
            guard entry.pairID == nil else { return entry }
            return SessionOverride(sessionID: entry.sessionID, action: entry.action, updatedAt: entry.updatedAt, pairID: pairID)
        }
        return result
    }
}
