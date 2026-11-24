import Foundation

public enum ActiveLinkKey: Hashable, Sendable {
    case central(UUID)
    case peripheral(UUID)

    public var peerID: UUID {
        switch self {
        case .central(let id), .peripheral(let id): id
        }
    }

    public var role: BLELinkRole {
        switch self {
        case .central: .central
        case .peripheral: .peripheral
        }
    }
}

public struct SessionCoordinator: Sendable {
    public private(set) var activeLinks: Set<ActiveLinkKey> = []
    public private(set) var sessions: [EncounterSession]

    public init(sessions: [EncounterSession] = []) {
        self.sessions = sessions
    }

    @discardableResult
    public mutating func mergeRecoveredSessions(_ recovered: [EncounterSession]) -> Bool {
        var changed = false
        var indices = Dictionary(sessions.indices.map { (sessions[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in recovered where item.status != .active {
            if let index = indices[item.id] {
                guard sessions[index].pairID == item.pairID, sessions[index].status == .unknownEnd,
                      item.status == .completed, let end = item.endedAt else { continue }
                sessions[index].status = .completed
                sessions[index].endedAt = end
                sessions[index].endReason = item.endReason
            } else {
                indices[item.id] = sessions.count
                sessions.append(item)
            }
            changed = true
        }
        if changed {
            sessions.sort { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        }
        return changed
    }

    public var activeSession: EncounterSession? {
        sessions.last { $0.status == .active }
    }

    public mutating func reconcileActiveSessionsOnLaunch(now _: Date, restoredActiveLinks: Set<ActiveLinkKey>) {
        activeLinks = restoredActiveLinks
        let retainedID = restoredActiveLinks.isEmpty ? nil : activeSession?.id
        for index in sessions.indices where sessions[index].status == .active && sessions[index].id != retainedID {
            sessions[index].status = .unknownEnd
            sessions[index].endedAt = nil
            sessions[index].endReason = .terminatedWhileActive
            sessions[index].batteryLevelAtEnd = nil
        }
    }

    @discardableResult
    public mutating func recordActiveHeartbeat(
        at: Date,
        minimumInterval: TimeInterval = BLEConstants.activeSessionHeartbeatSeconds
    ) -> EncounterSession? {
        guard !activeLinks.isEmpty,
              let index = sessions.lastIndex(where: { $0.status == .active }) else {
            return nil
        }
        let currentMark = sessions[index].effectiveLastSeenAt
        guard at > currentMark, at.timeIntervalSince(currentMark) >= minimumInterval else {
            return nil
        }
        sessions[index].lastSeenAt = at
        return sessions[index]
    }

    @discardableResult
    public mutating func linkAuthenticated(
        _ link: ActiveLinkKey,
        pairID: UUID,
        at: Date,
        connectionPath: ConnectionPath,
        batteryLevel: Float? = nil,
        maxResumeGapSeconds: TimeInterval = BLEConstants.terminatedSessionResumeWindowSeconds
    ) -> EncounterSession? {
        guard activeLinks.insert(link).inserted, activeSession == nil else { return nil }

        if maxResumeGapSeconds > 0,
           let lastIndex = sessions.indices.last,
           sessions[lastIndex].pairID == pairID,
           sessions[lastIndex].status == .unknownEnd,
           sessions[lastIndex].endReason == .terminatedWhileActive {
            let lastKnown = sessions[lastIndex].effectiveLastSeenAt
            if at >= lastKnown, at.timeIntervalSince(lastKnown) <= maxResumeGapSeconds {
                sessions[lastIndex].status = .active
                sessions[lastIndex].endedAt = nil
                sessions[lastIndex].endReason = nil
                sessions[lastIndex].disconnectErrorDescription = nil
                sessions[lastIndex].isAutoReconnectPending = nil
                sessions[lastIndex].batteryLevelAtEnd = nil
                if at > sessions[lastIndex].startedAt {
                    sessions[lastIndex].lastSeenAt = at
                }
                return sessions[lastIndex]
            }
        }

        let priorEnd = sessions.lazy.filter { $0.pairID == pairID && $0.status == .completed }
            .compactMap(\.endedAt).filter { $0 <= at }.max()
        let session = EncounterSession(
            pairID: pairID, startedAt: at, connectionPath: connectionPath, startRole: link.role,
            gapFromPreviousSessionSeconds: priorEnd.map { at.timeIntervalSince($0) },
            batteryLevelAtStart: batteryLevel
        )
        sessions.append(session)
        return session
    }

    @discardableResult
    public mutating func linkDisconnected(
        _ link: ActiveLinkKey, at: Date, endReason: SessionEndReason,
        disconnectErrorDescription: String? = nil, isAutoReconnectPending: Bool? = nil, batteryLevel: Float? = nil
    ) -> EncounterSession? {
        guard activeLinks.remove(link) != nil, activeLinks.isEmpty else { return nil }
        return complete(
            at: at, endReason: endReason, disconnectErrorDescription: disconnectErrorDescription,
            isAutoReconnectPending: isAutoReconnectPending, batteryLevel: batteryLevel
        )
    }

    @discardableResult
    public mutating func endActiveSessionForControlChange(
        at: Date, endReason: SessionEndReason, batteryLevel: Float? = nil
    ) -> EncounterSession? {
        activeLinks.removeAll()
        return complete(at: at, endReason: endReason, batteryLevel: batteryLevel)
    }

    private mutating func complete(
        at: Date, endReason: SessionEndReason, disconnectErrorDescription: String? = nil,
        isAutoReconnectPending: Bool? = nil, batteryLevel: Float?
    ) -> EncounterSession? {
        guard let index = sessions.lastIndex(where: { $0.status == .active }) else { return nil }
        sessions[index].status = .completed
        sessions[index].endedAt = at
        sessions[index].endReason = endReason
        sessions[index].disconnectErrorDescription = disconnectErrorDescription
        sessions[index].isAutoReconnectPending = isAutoReconnectPending
        sessions[index].batteryLevelAtEnd = batteryLevel
        return sessions[index]
    }
}
