import Foundation
import Synchronization

public final class LocationTimelineStore: Sendable {
    private static let lock = Mutex(())
    public static let retentionDays = 14
    public let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("location_timeline.json") }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    public func load() throws -> LocationTimelineSnapshot {
        try Self.lock.withLock { _ in try read() }
    }

    @discardableResult
    public func recordVisit(
        _ visit: LocationVisitRecord,
        role: PeerRole,
        arrivalUnknown: Bool = false,
        now: Date = Date()
    ) throws -> LocationTimelineSnapshot {
        try modify { snapshot in
            let resolvedArrivedAt: Date
            if arrivalUnknown, let departedAt = visit.departedAt {
                resolvedArrivedAt = Self.inferArrivalDate(
                    forLatitude: visit.latitude,
                    longitude: visit.longitude,
                    departedAt: departedAt,
                    in: snapshot
                )
            } else if let departedAt = visit.departedAt, visit.arrivedAt >= departedAt {
                resolvedArrivedAt = departedAt.addingTimeInterval(-300)
            } else {
                resolvedArrivedAt = visit.arrivedAt
            }

            let normalizedVisit = LocationVisitRecord(
                id: visit.id,
                latitude: visit.latitude,
                longitude: visit.longitude,
                horizontalAccuracy: visit.horizontalAccuracy,
                arrivedAt: resolvedArrivedAt,
                departedAt: visit.departedAt,
                recordedAt: visit.recordedAt
            )

            let dayKey = LocationDayKey.utcDayKey(for: normalizedVisit.arrivedAt)
            var bucket = snapshot.localBuckets[dayKey] ?? DayLocationBucket(dayKeyUTC: dayKey, role: role, updatedAt: now)

            if let matchIndex = Self.findMatchingVisitIndex(in: bucket.visits, for: normalizedVisit) {
                var existing = bucket.visits[matchIndex]
                let mergedDepartedAt = normalizedVisit.departedAt ?? existing.departedAt
                let useNewCoords = normalizedVisit.horizontalAccuracy <= existing.horizontalAccuracy
                var mergedArrivedAt = min(existing.arrivedAt, normalizedVisit.arrivedAt)
                if let mergedDepartedAt, mergedArrivedAt >= mergedDepartedAt {
                    mergedArrivedAt = mergedDepartedAt.addingTimeInterval(-300)
                }
                existing = LocationVisitRecord(
                    id: existing.id,
                    latitude: useNewCoords ? normalizedVisit.latitude : existing.latitude,
                    longitude: useNewCoords ? normalizedVisit.longitude : existing.longitude,
                    horizontalAccuracy: min(existing.horizontalAccuracy, normalizedVisit.horizontalAccuracy),
                    arrivedAt: mergedArrivedAt,
                    departedAt: mergedDepartedAt,
                    recordedAt: now
                )
                bucket.visits[matchIndex] = existing
            } else {
                bucket.visits.append(normalizedVisit)
            }

            bucket.updatedAt = now
            snapshot.localBuckets[dayKey] = bucket
            Self.pruneOldBuckets(&snapshot, now: now)
        }
    }

    @discardableResult
    public func recordPoint(
        _ point: LocationPointSample,
        role: PeerRole,
        now: Date = Date()
    ) throws -> LocationTimelineSnapshot {
        try modify { snapshot in
            let dayKey = LocationDayKey.utcDayKey(for: point.timestamp)
            var bucket = snapshot.localBuckets[dayKey] ?? DayLocationBucket(dayKeyUTC: dayKey, role: role, updatedAt: now)

            if let last = bucket.points.last {
                let dt = abs(point.timestamp.timeIntervalSince(last.timestamp))
                let dist = LocationProximityMatcher.haversineMeters(
                    lat1: last.latitude, lon1: last.longitude,
                    lat2: point.latitude, lon2: point.longitude
                )
                if dt < 180 && dist <= 20 {
                    if point.horizontalAccuracy < last.horizontalAccuracy {
                        bucket.points[bucket.points.count - 1] = point
                    }
                    bucket.updatedAt = now
                    snapshot.localBuckets[dayKey] = bucket
                    Self.pruneOldBuckets(&snapshot, now: now)
                    return
                }
            }

            bucket.points.append(point)
            bucket.updatedAt = now
            snapshot.localBuckets[dayKey] = bucket
            Self.pruneOldBuckets(&snapshot, now: now)
        }
    }

    @discardableResult
    public func mergeRemoteOwnBuckets(
        _ buckets: [String: DayLocationBucket], role: PeerRole, now: Date = Date()
    ) throws -> (snapshot: LocationTimelineSnapshot, didChange: Bool) {
        try Self.lock.withLock { _ in
            let current = try read()
            var snapshot = current
            let valid = Set(LocationDayKey.recentUTCDayKeys(endingAt: now, days: Self.retentionDays))
            for (key, bucket) in buckets {
                guard bucket.role == role, key == bucket.dayKeyUTC, valid.contains(key), !bucket.isEmpty else { continue }
                let existing = snapshot.localBuckets[key] ?? DayLocationBucket(dayKeyUTC: key, role: role, updatedAt: bucket.updatedAt)
                snapshot.localBuckets[key] = existing.merged(with: bucket)
            }
            Self.pruneOldBuckets(&snapshot, now: now)
            guard snapshot != current else { return (current, false) }
            try write(snapshot)
            return (snapshot, true)
        }
    }

    @discardableResult
    public func replacePeerBuckets(
        _ buckets: [String: DayLocationBucket],
        now: Date = Date()
    ) throws -> LocationTimelineSnapshot {
        try modify { snapshot in
            for (key, bucket) in buckets {
                snapshot.peerBuckets[key] = bucket
            }
            Self.pruneOldBuckets(&snapshot, now: now)
        }
    }

    @discardableResult
    public func recomputeMatches(
        pairID: UUID,
        now: Date = Date()
    ) throws -> LocationTimelineSnapshot {
        try modify { snapshot in
            Self.pruneOldBuckets(&snapshot, now: now)

            let recentKeys = LocationDayKey.recentUTCDayKeys(endingAt: now, days: Self.retentionDays)
            let oldestKeyDate: Date
            if let oldestDay = Self.dateFromUTCDayKey(recentKeys.first ?? LocationDayKey.utcDayKey(for: now)) {
                oldestKeyDate = oldestDay
            } else {
                oldestKeyDate = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
            }

            // Preserve already-derived matches whose end predates the raw coordinate window.
            let preservedOlder = snapshot.matchedSessions.filter {
                $0.pairID == pairID && $0.endedAt < oldestKeyDate
            }

            let fresh = LocationProximityMatcher.match(
                pairID: pairID,
                localBuckets: Array(snapshot.localBuckets.values),
                peerBuckets: Array(snapshot.peerBuckets.values),
                now: now
            )

            var combined = (preservedOlder + fresh).sorted { $0.startedAt < $1.startedAt }
            var merged: [LocationMatchedSession] = []
            for item in combined {
                if let last = merged.last,
                   item.startedAt.timeIntervalSince(last.endedAt) <= LocationProximityMatcher.mergeGapSeconds {
                    let prevDur = max(1.0, last.durationSeconds)
                    let curDur = max(1.0, item.durationSeconds)
                    let avg = (last.averageDistanceMeters * prevDur + item.averageDistanceMeters * curDur) / (prevDur + curDur)
                    merged[merged.count - 1] = LocationMatchedSession(
                        id: last.id,
                        pairID: pairID,
                        startedAt: last.startedAt,
                        endedAt: max(last.endedAt, item.endedAt),
                        averageDistanceMeters: avg
                    )
                } else {
                    merged.append(item)
                }
            }
            combined = merged
            snapshot.matchedSessions = combined
            snapshot.lastSyncedAt = now
        }
    }

    @discardableResult
    public func clearAll() throws -> LocationTimelineSnapshot {
        try Self.lock.withLock { _ in
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return LocationTimelineSnapshot()
            }
            return LocationTimelineSnapshot()
        }
    }

    private static func inferArrivalDate(
        forLatitude latitude: Double,
        longitude: Double,
        departedAt: Date,
        in snapshot: LocationTimelineSnapshot
    ) -> Date {
        struct Candidate {
            let time: Date
            let latitude: Double
            let longitude: Double
        }

        var candidates: [Candidate] = []
        for bucket in snapshot.localBuckets.values {
            for point in bucket.points
            where point.horizontalAccuracy >= 0 && point.horizontalAccuracy <= LocationProximityMatcher.maxAcceptedAccuracyMeters {
                if point.timestamp < departedAt {
                    candidates.append(Candidate(time: point.timestamp, latitude: point.latitude, longitude: point.longitude))
                }
            }
            for existingVisit in bucket.visits
            where existingVisit.horizontalAccuracy >= 0 && existingVisit.horizontalAccuracy <= LocationProximityMatcher.maxAcceptedAccuracyMeters {
                if existingVisit.arrivedAt < departedAt {
                    candidates.append(Candidate(
                        time: existingVisit.arrivedAt,
                        latitude: existingVisit.latitude,
                        longitude: existingVisit.longitude
                    ))
                }
            }
        }

        candidates.sort { $0.time > $1.time }
        var earliestContiguous: Date?
        for item in candidates {
            let dist = LocationProximityMatcher.haversineMeters(
                lat1: latitude, lon1: longitude,
                lat2: item.latitude, lon2: item.longitude
            )
            if dist > LocationProximityMatcher.maxProximityMeters {
                break
            }
            if dist <= 100 {
                earliestContiguous = item.time
            }
        }

        return earliestContiguous ?? departedAt.addingTimeInterval(-300)
    }

    private static func findMatchingVisitIndex(in existingVisits: [LocationVisitRecord], for visit: LocationVisitRecord) -> Int? {
        existingVisits.firstIndex { existing in
            let dt = abs(existing.arrivedAt.timeIntervalSince(visit.arrivedAt))
            guard dt <= 90 else { return false }
            let dist = LocationProximityMatcher.haversineMeters(
                lat1: existing.latitude, lon1: existing.longitude,
                lat2: visit.latitude, lon2: visit.longitude
            )
            return dist <= 60
        }
    }

    private static func pruneOldBuckets(_ snapshot: inout LocationTimelineSnapshot, now: Date) {
        let validKeys = Set(LocationDayKey.recentUTCDayKeys(endingAt: now, days: retentionDays))
        snapshot.localBuckets = snapshot.localBuckets.filter { validKeys.contains($0.key) }
        snapshot.peerBuckets = snapshot.peerBuckets.filter { validKeys.contains($0.key) }
    }

    private static func dateFromUTCDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func read() throws -> LocationTimelineSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return LocationTimelineSnapshot()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LocationTimelineSnapshot.self, from: data)
    }

    private func modify(_ update: (inout LocationTimelineSnapshot) throws -> Void) throws -> LocationTimelineSnapshot {
        try Self.lock.withLock { _ in
            var snapshot = try read()
            try update(&snapshot)
            try write(snapshot)
            return snapshot
        }
    }

    private func write(_ snapshot: LocationTimelineSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
