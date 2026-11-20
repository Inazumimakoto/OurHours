import Foundation

public enum SessionStatus: String, Codable, Sendable, Equatable {
    case active, completed, unknownEnd
}

public enum ConnectionPath: String, Codable, Sendable, Equatable {
    case autoReconnect, scanDiscovery, restoredConnection, incomingPeripheral
}

public enum BLELinkRole: String, Codable, Sendable, Equatable {
    case central, peripheral
}

public enum SessionEndReason: String, Codable, Sendable, Equatable {
    case disconnected, peerUnsubscribed, terminatedWhileActive, autoRecordingDisabled
    case unpaired, bluetoothUnavailable, manualDisconnect
}

public struct EncounterSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public let connectionPath: ConnectionPath
    public let startRole: BLELinkRole
    public var endReason: SessionEndReason?
    public var disconnectErrorDescription: String?
    public var isAutoReconnectPending: Bool?
    public let gapFromPreviousSessionSeconds: TimeInterval?
    public let batteryLevelAtStart: Float?
    public var batteryLevelAtEnd: Float?

    public init(
        id: UUID = UUID(), pairID: UUID, startedAt: Date, endedAt: Date? = nil,
        status: SessionStatus = .active, connectionPath: ConnectionPath, startRole: BLELinkRole,
        endReason: SessionEndReason? = nil, disconnectErrorDescription: String? = nil,
        isAutoReconnectPending: Bool? = nil, gapFromPreviousSessionSeconds: TimeInterval? = nil,
        batteryLevelAtStart: Float? = nil, batteryLevelAtEnd: Float? = nil
    ) {
        self.id = id
        self.pairID = pairID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.connectionPath = connectionPath
        self.startRole = startRole
        self.endReason = endReason
        self.disconnectErrorDescription = disconnectErrorDescription
        self.isAutoReconnectPending = isAutoReconnectPending
        self.gapFromPreviousSessionSeconds = gapFromPreviousSessionSeconds
        self.batteryLevelAtStart = batteryLevelAtStart
        self.batteryLevelAtEnd = batteryLevelAtEnd
    }

    public var durationSeconds: TimeInterval? {
        guard status == .completed, let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    public static func mergedReferenceIntervals(
        from sessions: [Self], maxGapSeconds: TimeInterval = 300
    ) -> [MergedReferenceInterval] {
        let ordered = sessions.sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt < $1.startedAt
        }
        var intervals: [MergedReferenceInterval] = []
        var lastIndexByPair: [UUID: Int] = [:]
        for session in ordered {
            guard session.status == .completed, let end = session.endedAt, end >= session.startedAt else {
                lastIndexByPair[session.pairID] = nil
                continue
            }
            if let index = lastIndexByPair[session.pairID],
               session.startedAt.timeIntervalSince(intervals[index].endedAt) <= max(0, maxGapSeconds) {
                intervals[index].endedAt = max(end, intervals[index].endedAt)
                intervals[index].sessionIDs.append(session.id)
            } else {
                lastIndexByPair[session.pairID] = intervals.count
                intervals.append(MergedReferenceInterval(
                    pairID: session.pairID, startedAt: session.startedAt, endedAt: end,
                    sessionIDs: [session.id]
                ))
            }
        }
        return intervals
    }
}

public struct MergedReferenceInterval: Identifiable, Sendable, Equatable {
    public let pairID: UUID
    public let startedAt: Date
    public internal(set) var endedAt: Date
    public internal(set) var sessionIDs: [UUID]
    public var id: UUID { sessionIDs[0] }
    public var durationSeconds: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}
