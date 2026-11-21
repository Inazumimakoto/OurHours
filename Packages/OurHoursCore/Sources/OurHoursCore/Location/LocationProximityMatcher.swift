import Foundation

public enum LocationProximityMatcher {
    public static let maxAcceptedAccuracyMeters = 150.0
    public static let baseProximityMeters = 50.0
    public static let minProximityMeters = 65.0
    public static let maxProximityMeters = 150.0
    public static let stationaryPointPairMaxMeters = 120.0
    public static let stationaryPointMaxGapSeconds: TimeInterval = 14_400
    public static let singlePointWindowHalfSeconds: TimeInterval = 300
    public static let mergeGapSeconds: TimeInterval = 600
    public static let minCompletedDurationSeconds: TimeInterval = 180
    private static let openVisitSafetyCapSeconds: TimeInterval = 18 * 3_600

    private struct LocationSpan {
        let start: Date
        let end: Date
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }

    private struct RawOverlap {
        var start: Date
        var end: Date
        var weightedDistanceSum: Double
        var weightSum: Double
    }

    public static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let rLat1 = lat1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0
        let sinHalfLat = sin(dLat * 0.5)
        let sinHalfLon = sin(dLon * 0.5)
        let a = sinHalfLat * sinHalfLat + cos(rLat1) * cos(rLat2) * sinHalfLon * sinHalfLon
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return r * c
    }

    public static func match(
        pairID: UUID,
        localBuckets: [DayLocationBucket],
        peerBuckets: [DayLocationBucket],
        now: Date = Date()
    ) -> [LocationMatchedSession] {
        let localSpans = normalizeSpans(from: localBuckets, now: now)
        let peerSpans = normalizeSpans(from: peerBuckets, now: now)
        guard !localSpans.isEmpty, !peerSpans.isEmpty else { return [] }

        var overlaps: [RawOverlap] = []
        for local in localSpans {
            for peer in peerSpans {
                let start = max(local.start, peer.start)
                let end = min(local.end, peer.end)
                guard end > start else { continue }

                let dist = haversineMeters(
                    lat1: local.latitude, lon1: local.longitude,
                    lat2: peer.latitude, lon2: peer.longitude
                )
                let allowed = max(
                    minProximityMeters,
                    min(maxProximityMeters, baseProximityMeters + 0.5 * (local.accuracy + peer.accuracy))
                )
                if dist <= allowed {
                    let duration = max(1.0, end.timeIntervalSince(start))
                    overlaps.append(RawOverlap(
                        start: start,
                        end: end,
                        weightedDistanceSum: dist * duration,
                        weightSum: duration
                    ))
                }
            }
        }

        guard !overlaps.isEmpty else { return [] }
        overlaps.sort {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }

        var merged: [RawOverlap] = [overlaps[0]]
        for item in overlaps.dropFirst() {
            let lastIndex = merged.count - 1
            if item.start.timeIntervalSince(merged[lastIndex].end) <= mergeGapSeconds {
                merged[lastIndex].end = max(merged[lastIndex].end, item.end)
                merged[lastIndex].weightedDistanceSum += item.weightedDistanceSum
                merged[lastIndex].weightSum += item.weightSum
            } else {
                merged.append(item)
            }
        }

        return merged.compactMap { item in
            guard item.end.timeIntervalSince(item.start) >= minCompletedDurationSeconds else { return nil }
            let avgDistance = item.weightSum > 0 ? item.weightedDistanceSum / item.weightSum : 0
            return LocationMatchedSession(
                id: LocationPayloadCipher.deterministicMatchID(pairID: pairID, startedAt: item.start),
                pairID: pairID,
                startedAt: item.start,
                endedAt: item.end,
                averageDistanceMeters: avgDistance
            )
        }
    }

    private static func normalizeSpans(from buckets: [DayLocationBucket], now: Date) -> [LocationSpan] {
        let visits = buckets
            .flatMap(\.visits)
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= maxAcceptedAccuracyMeters && $0.arrivedAt <= now }

        let points = buckets
            .flatMap(\.points)
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= maxAcceptedAccuracyMeters && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        struct MovementMarker {
            let time: Date
            let latitude: Double
            let longitude: Double
        }

        var markers: [MovementMarker] = points.map {
            MovementMarker(time: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude)
        }
        markers.append(contentsOf: visits.map {
            MovementMarker(time: $0.arrivedAt, latitude: $0.latitude, longitude: $0.longitude)
        })
        markers.sort { $0.time < $1.time }

        var spans: [LocationSpan] = []

        for visit in visits {
            let endDate: Date
            if let departedAt = visit.departedAt {
                guard departedAt > visit.arrivedAt else { continue }
                endDate = min(now, departedAt)
            } else {
                let firstFarObservation = markers.first { marker in
                    marker.time > visit.arrivedAt && haversineMeters(
                        lat1: visit.latitude, lon1: visit.longitude,
                        lat2: marker.latitude, lon2: marker.longitude
                    ) > maxProximityMeters
                }?.time
                let safetyCap = min(now, visit.arrivedAt.addingTimeInterval(openVisitSafetyCapSeconds))
                endDate = firstFarObservation.map { min(safetyCap, $0) } ?? safetyCap
            }
            if endDate > visit.arrivedAt {
                spans.append(LocationSpan(
                    start: visit.arrivedAt,
                    end: endDate,
                    latitude: visit.latitude,
                    longitude: visit.longitude,
                    accuracy: visit.horizontalAccuracy
                ))
            }
        }

        if !points.isEmpty {
            for point in points {
                let start = point.timestamp.addingTimeInterval(-singlePointWindowHalfSeconds)
                let end = min(now, point.timestamp.addingTimeInterval(singlePointWindowHalfSeconds))
                if end > start {
                    spans.append(LocationSpan(
                        start: start,
                        end: end,
                        latitude: point.latitude,
                        longitude: point.longitude,
                        accuracy: point.horizontalAccuracy
                    ))
                }
            }

            if points.count >= 2 {
                for index in 0..<(points.count - 1) {
                    let a = points[index]
                    let b = points[index + 1]
                    let gap = b.timestamp.timeIntervalSince(a.timestamp)
                    guard gap > 0, gap <= stationaryPointMaxGapSeconds else { continue }
                    let dist = haversineMeters(
                        lat1: a.latitude, lon1: a.longitude,
                        lat2: b.latitude, lon2: b.longitude
                    )
                    guard dist <= stationaryPointPairMaxMeters else { continue }
                    let wA = 1.0 / pow(max(5.0, a.horizontalAccuracy), 2.0)
                    let wB = 1.0 / pow(max(5.0, b.horizontalAccuracy), 2.0)
                    let totalW = wA + wB
                    spans.append(LocationSpan(
                        start: a.timestamp,
                        end: b.timestamp,
                        latitude: (a.latitude * wA + b.latitude * wB) / totalW,
                        longitude: (a.longitude * wA + b.longitude * wB) / totalW,
                        accuracy: max(a.horizontalAccuracy, b.horizontalAccuracy)
                    ))
                }
            }
        }

        return spans
    }
}
