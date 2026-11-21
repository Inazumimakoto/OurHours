import Foundation

public struct SyncedPeerSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let connectionPath: ConnectionPath

    public init(
        id: UUID,
        pairID: UUID,
        startedAt: Date,
        endedAt: Date?,
        status: SessionStatus,
        connectionPath: ConnectionPath
    ) {
        self.id = id
        self.pairID = pairID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.connectionPath = connectionPath
    }

    public init(from session: EncounterSession) {
        self.id = session.id
        self.pairID = session.pairID
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.status = session.status
        self.connectionPath = session.connectionPath
    }
}

public struct PartnerSyncEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let pairID: UUID
    public let senderRole: PeerRole
    public let updatedAt: Date
    public let bleSessions: [SyncedPeerSession]
    public let journal: JournalSnapshot

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        pairID: UUID,
        senderRole: PeerRole,
        updatedAt: Date = Date(),
        bleSessions: [SyncedPeerSession],
        journal: JournalSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.pairID = pairID
        self.senderRole = senderRole
        self.updatedAt = updatedAt
        self.bleSessions = bleSessions
        self.journal = journal
    }
}

public struct PeerSessionCache: Codable, Sendable, Equatable {
    public let pairID: UUID
    public let peerRole: PeerRole
    public let updatedAt: Date
    public let sessions: [SyncedPeerSession]

    public init(
        pairID: UUID,
        peerRole: PeerRole,
        updatedAt: Date = Date(),
        sessions: [SyncedPeerSession]
    ) {
        self.pairID = pairID
        self.peerRole = peerRole
        self.updatedAt = updatedAt
        self.sessions = sessions
    }
}
