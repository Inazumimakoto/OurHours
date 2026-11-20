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

    public init(
        manualRecords: [ManualEncounterRecord] = [],
        sessionOverrides: [UUID: SessionOverride] = [:],
        dailyMemos: [String: DailyMemo] = [:]
    ) {
        self.manualRecords = manualRecords
        self.sessionOverrides = sessionOverrides
        self.dailyMemos = dailyMemos
    }
}
