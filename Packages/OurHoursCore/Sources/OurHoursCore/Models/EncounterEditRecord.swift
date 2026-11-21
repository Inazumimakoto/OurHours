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
    case deleted
}

public struct SessionOverride: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let action: SessionOverrideAction
    public let updatedAt: Date

    public init(sessionID: UUID, action: SessionOverrideAction, updatedAt: Date) {
        self.sessionID = sessionID
        self.action = action
        self.updatedAt = updatedAt
    }
}

public struct DailyMemo: Codable, Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let text: String
    public let updatedAt: Date
    public var id: String { dayKey }

    public init(dayKey: String, text: String, updatedAt: Date) {
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
        case deletedMemoDays
    }

    public init(
        manualRecords: [ManualEncounterRecord] = [],
        sessionOverrides: [UUID: SessionOverride] = [:],
        dailyMemos: [String: DailyMemo] = [:],
        deletedManualRecords: [UUID: Date] = [:],
        deletedMemoDays: [String: Date] = [:],
        roleProfiles: [String: SyncedRoleProfile] = [:],
        anniversary: SyncedAnniversary? = nil
    ) {
        self.roleProfiles = roleProfiles
        self.anniversary = anniversary
        self.manualRecords = manualRecords
        self.sessionOverrides = sessionOverrides
        self.dailyMemos = dailyMemos
        self.deletedManualRecords = deletedManualRecords
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
        self.deletedMemoDays = try container.decodeIfPresent([String: Date].self, forKey: .deletedMemoDays) ?? [:]
    }
}
