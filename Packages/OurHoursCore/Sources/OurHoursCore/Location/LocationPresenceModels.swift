import Foundation

public enum LocationSampleSource: String, Codable, Sendable, Equatable {
    case visitArrival
    case visitDeparture
    case significantChange
    case geofenceExit
    case foregroundFix
    case manualSyncFix
}

public struct LocationVisitRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let arrivedAt: Date
    public var departedAt: Date?
    public var recordedAt: Date

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        arrivedAt: Date,
        departedAt: Date? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.recordedAt = recordedAt
    }
}

public struct LocationPointSample: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let source: LocationSampleSource

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        source: LocationSampleSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }
}

public struct DayLocationBucket: Codable, Sendable, Equatable {
    public let dayKeyUTC: String
    public let role: PeerRole
    public var updatedAt: Date
    public var visits: [LocationVisitRecord]
    public var points: [LocationPointSample]

    public init(
        dayKeyUTC: String,
        role: PeerRole,
        updatedAt: Date = Date(),
        visits: [LocationVisitRecord] = [],
        points: [LocationPointSample] = []
    ) {
        self.dayKeyUTC = dayKeyUTC
        self.role = role
        self.updatedAt = updatedAt
        self.visits = visits
        self.points = points
    }

    public var isEmpty: Bool {
        visits.isEmpty && points.isEmpty
    }
}

public struct LocationMatchedSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let averageDistanceMeters: Double

    public init(
        id: UUID,
        pairID: UUID,
        startedAt: Date,
        endedAt: Date,
        averageDistanceMeters: Double
    ) {
        self.id = id
        self.pairID = pairID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.averageDistanceMeters = averageDistanceMeters
    }

    public var durationSeconds: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

public struct LocationTimelineSnapshot: Codable, Sendable, Equatable {
    public var localBuckets: [String: DayLocationBucket]
    public var peerBuckets: [String: DayLocationBucket]
    public var matchedSessions: [LocationMatchedSession]
    public var lastSyncedAt: Date?

    public init(
        localBuckets: [String: DayLocationBucket] = [:],
        peerBuckets: [String: DayLocationBucket] = [:],
        matchedSessions: [LocationMatchedSession] = [],
        lastSyncedAt: Date? = nil
    ) {
        self.localBuckets = localBuckets
        self.peerBuckets = peerBuckets
        self.matchedSessions = matchedSessions
        self.lastSyncedAt = lastSyncedAt
    }
}

public enum LocationDayKey {
    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    public static func utcDayKey(for date: Date) -> String {
        let comp = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)
    }

    public static func utcDayStart(for date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    public static func recentUTCDayKeys(endingAt date: Date = Date(), days: Int = 14) -> [String] {
        guard days > 0 else { return [] }
        let cal = utcCalendar
        let endDayStart = cal.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: endDayStart).map { utcDayKey(for: $0) }
        }
    }
}
