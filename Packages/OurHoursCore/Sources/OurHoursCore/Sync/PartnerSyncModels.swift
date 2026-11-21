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

public enum PartnerSyncMerger {
    public static func mergeOwnBLESessions(
        local: [EncounterSession],
        remote: [SyncedPeerSession],
        pairID: UUID
    ) -> (outbound: [SyncedPeerSession], missingLocal: [EncounterSession]) {
        let own = local.filter { $0.pairID == pairID }
        let activeIDs = Set(own.filter { $0.status == .active }.map(\.id))
        let localByID = Dictionary(
            own.filter { $0.status != .active }.map { ($0.id, SyncedPeerSession(from: $0)) },
            uniquingKeysWith: preferredSession
        )
        var combined = localByID
        for item in remote where item.pairID == pairID && item.status != .active {
            combined[item.id] = combined[item.id].map { preferredSession($0, item) } ?? item
        }
        let outbound = combined.values.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        let missingLocal = outbound.compactMap { item -> EncounterSession? in
            guard !activeIDs.contains(item.id) else { return nil }
            if let existing = localByID[item.id] {
                guard existing.status == .unknownEnd, item.status == .completed, item.endedAt != nil else { return nil }
            }
            return EncounterSession(id: item.id, pairID: item.pairID, startedAt: item.startedAt, endedAt: item.endedAt,
                                    status: item.status, connectionPath: item.connectionPath, startRole: .central,
                                    endReason: item.status == .completed ? .disconnected : .terminatedWhileActive)
        }
        return (outbound, missingLocal)
    }

    private static func preferredSession(_ lhs: SyncedPeerSession, _ rhs: SyncedPeerSession) -> SyncedPeerSession {
        guard rhs.status == .completed, let rightEnd = rhs.endedAt else { return lhs }
        guard lhs.status == .completed, let leftEnd = lhs.endedAt else { return rhs }
        return rightEnd > leftEnd ? rhs : lhs
    }
}
