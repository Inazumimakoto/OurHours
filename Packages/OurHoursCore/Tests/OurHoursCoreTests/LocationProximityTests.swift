import Foundation
import Testing
@testable import OurHoursCore

struct LocationProximityTests {
    private func makeConfig(role: PeerRole = .partnerA, epoch: UInt32 = 1) -> PairConfiguration {
        PairConfiguration(
            pairID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sharedSecret: Data(repeating: 0xAB, count: 32),
            localRole: role,
            keyEpoch: epoch
        )
    }

    @Test func payloadCipherRoundTripAndKeyIsolation() throws {
        let configA = makeConfig(role: .partnerA, epoch: 1)
        let configB = makeConfig(role: .partnerB, epoch: 1)
        let wrongEpoch = makeConfig(role: .partnerA, epoch: 2)
        let wrongSecret = PairConfiguration(
            pairID: configA.pairID,
            sharedSecret: Data(repeating: 0xCD, count: 32),
            localRole: .partnerB,
            keyEpoch: 1
        )

        #expect(LocationPayloadCipher.channelToken(for: configA) == LocationPayloadCipher.channelToken(for: configB))
        #expect(LocationPayloadCipher.channelToken(for: configA) != LocationPayloadCipher.channelToken(for: wrongEpoch))
        #expect(
            LocationPayloadCipher.dayRecordName(for: configA, role: .partnerA, utcDayKey: "2026-11-21")
                != LocationPayloadCipher.dayRecordName(for: configA, role: .partnerB, utcDayKey: "2026-11-21")
        )
        #expect(
            LocationPayloadCipher.dayRecordName(for: configA, role: .partnerA, utcDayKey: "2026-11-21")
                != LocationPayloadCipher.dayRecordName(for: configA, role: .partnerA, utcDayKey: "2026-11-22")
        )

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bucket = DayLocationBucket(
            dayKeyUTC: "2026-11-21",
            role: .partnerA,
            updatedAt: now,
            visits: [
                LocationVisitRecord(
                    latitude: 35.681236,
                    longitude: 139.767125,
                    horizontalAccuracy: 18,
                    arrivedAt: now.addingTimeInterval(-3600),
                    departedAt: now,
                    recordedAt: now
                )
            ],
            points: [
                LocationPointSample(
                    timestamp: now,
                    latitude: 35.681250,
                    longitude: 139.767150,
                    horizontalAccuracy: 12,
                    source: .foregroundFix
                )
            ]
        )

        let encrypted = try LocationPayloadCipher.encrypt(bucket, using: configA)
        let decryptedByPartner = try LocationPayloadCipher.decrypt(encrypted, using: configB)
        #expect(decryptedByPartner == bucket)

        #expect(throws: LocationPayloadCipherError.decryptionFailed) {
            try LocationPayloadCipher.decrypt(encrypted, using: wrongEpoch)
        }
        #expect(throws: LocationPayloadCipherError.decryptionFailed) {
            try LocationPayloadCipher.decrypt(encrypted, using: wrongSecret)
        }
    }

    @Test func matcherOverlappingAndSeparateVisitsAndCoarseFilter() {
        let pairID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let day = LocationDayKey.utcDayKey(for: base)

        // ~20 meters apart at Tokyo Station
        let localSame = LocationVisitRecord(
            latitude: 35.681236,
            longitude: 139.767125,
            horizontalAccuracy: 15,
            arrivedAt: base,
            departedAt: base.addingTimeInterval(3600),
            recordedAt: base
        )
        let peerSame = LocationVisitRecord(
            latitude: 35.681400,
            longitude: 139.767180,
            horizontalAccuracy: 20,
            arrivedAt: base.addingTimeInterval(600),
            departedAt: base.addingTimeInterval(3600),
            recordedAt: base
        )
        // ~350 meters apart (too far)
        let peerFar = LocationVisitRecord(
            latitude: 35.684400,
            longitude: 139.767125,
            horizontalAccuracy: 10,
            arrivedAt: base.addingTimeInterval(7200),
            departedAt: base.addingTimeInterval(10800),
            recordedAt: base
        )
        let localAtFarTime = LocationVisitRecord(
            latitude: 35.681236,
            longitude: 139.767125,
            horizontalAccuracy: 10,
            arrivedAt: base.addingTimeInterval(7200),
            departedAt: base.addingTimeInterval(10800),
            recordedAt: base
        )
        // Coarse fix (> 150m accuracy) should be filtered out
        let peerCoarse = LocationVisitRecord(
            latitude: 35.681236,
            longitude: 139.767125,
            horizontalAccuracy: 500,
            arrivedAt: base.addingTimeInterval(12000),
            departedAt: base.addingTimeInterval(15600),
            recordedAt: base
        )
        let localDuringCoarse = LocationVisitRecord(
            latitude: 35.681236,
            longitude: 139.767125,
            horizontalAccuracy: 10,
            arrivedAt: base.addingTimeInterval(12000),
            departedAt: base.addingTimeInterval(15600),
            recordedAt: base
        )

        let matches = LocationProximityMatcher.match(
            pairID: pairID,
            localBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerA, visits: [localSame, localAtFarTime, localDuringCoarse])],
            peerBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerB, visits: [peerSame, peerFar, peerCoarse])],
            now: base.addingTimeInterval(16000)
        )

        #expect(matches.count == 1)
        #expect(matches[0].startedAt == base.addingTimeInterval(600))
        #expect(matches[0].endedAt == base.addingTimeInterval(3600))
        #expect(matches[0].averageDistanceMeters < 30)
    }

    @Test func matcherCapsOpenVisitOnMovementAndSupportsStationaryPointsAndShortGapMerge() {
        let pairID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let day = LocationDayKey.utcDayKey(for: base)

        // Ongoing visit without departure should be capped when a subsequent point moves >150m away
        let openVisit = LocationVisitRecord(
            latitude: 35.681236,
            longitude: 139.767125,
            horizontalAccuracy: 15,
            arrivedAt: base,
            departedAt: nil,
            recordedAt: base
        )
        let movedAwayPoint = LocationPointSample(
            timestamp: base.addingTimeInterval(7200),
            latitude: 35.685000,
            longitude: 139.767125,
            horizontalAccuracy: 15,
            source: .geofenceExit
        )
        // Peer has two stationary points 3 hours apart + a brief 4-min gap at the midpoint
        let peerVisit1 = LocationVisitRecord(
            latitude: 35.681240,
            longitude: 139.767130,
            horizontalAccuracy: 15,
            arrivedAt: base,
            departedAt: base.addingTimeInterval(3600),
            recordedAt: base
        )
        let peerVisit2 = LocationVisitRecord(
            latitude: 35.681240,
            longitude: 139.767130,
            horizontalAccuracy: 15,
            arrivedAt: base.addingTimeInterval(3840), // 4-min gap <= 10m merge threshold
            departedAt: base.addingTimeInterval(10800),
            recordedAt: base
        )

        let matches = LocationProximityMatcher.match(
            pairID: pairID,
            localBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerA, visits: [openVisit], points: [movedAwayPoint])],
            peerBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerB, visits: [peerVisit1, peerVisit2])],
            now: base.addingTimeInterval(12000)
        )

        // Merged into one session ending at movedAwayPoint.timestamp (base + 7200), not continuing to base + 10800!
        #expect(matches.count == 1)
        #expect(matches[0].startedAt == base)
        #expect(matches[0].endedAt == base.addingTimeInterval(7200))

        // Also test stationary points spanning 3h matching peer visit
        let pt1 = LocationPointSample(timestamp: base, latitude: 35.681236, longitude: 139.767125, horizontalAccuracy: 20, source: .foregroundFix)
        let pt2 = LocationPointSample(timestamp: base.addingTimeInterval(10_800), latitude: 35.681250, longitude: 139.767140, horizontalAccuracy: 20, source: .significantChange)
        let pointMatches = LocationProximityMatcher.match(
            pairID: pairID,
            localBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerA, points: [pt1, pt2])],
            peerBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerB, visits: [
                LocationVisitRecord(latitude: 35.681245, longitude: 139.767130, horizontalAccuracy: 15, arrivedAt: base, departedAt: base.addingTimeInterval(10_800), recordedAt: base)
            ])],
            now: base.addingTimeInterval(11_000)
        )
        #expect(pointMatches.count == 1)
        #expect(pointMatches[0].durationSeconds == 10_800)

        // Short < 3m noise should be dropped
        let noise = LocationProximityMatcher.match(
            pairID: pairID,
            localBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerA, visits: [
                LocationVisitRecord(latitude: 35.6812, longitude: 139.7671, horizontalAccuracy: 10, arrivedAt: base, departedAt: base.addingTimeInterval(120), recordedAt: base)
            ])],
            peerBuckets: [DayLocationBucket(dayKeyUTC: day, role: .partnerB, visits: [
                LocationVisitRecord(latitude: 35.6812, longitude: 139.7671, horizontalAccuracy: 10, arrivedAt: base, departedAt: base.addingTimeInterval(120), recordedAt: base)
            ])],
            now: base.addingTimeInterval(200)
        )
        #expect(noise.isEmpty)
    }

    @Test func timelineStoreUpdatesVisitDepartureAndRetainsMatchedHistoryPast14Days() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OurHoursLocTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocationTimelineStore(directory: dir)
        let pairID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let open = LocationVisitRecord(latitude: 35.681236, longitude: 139.767125, horizontalAccuracy: 15, arrivedAt: day1, departedAt: nil, recordedAt: day1)
        try store.recordVisit(open, role: .partnerA, now: day1)
        let closed = LocationVisitRecord(latitude: 35.681240, longitude: 139.767130, horizontalAccuracy: 10, arrivedAt: day1.addingTimeInterval(10), departedAt: day1.addingTimeInterval(3600), recordedAt: day1.addingTimeInterval(3600))
        try store.recordVisit(closed, role: .partnerA, now: day1.addingTimeInterval(3600))

        let peerBucket = DayLocationBucket(
            dayKeyUTC: LocationDayKey.utcDayKey(for: day1),
            role: .partnerB,
            updatedAt: day1.addingTimeInterval(3600),
            visits: [LocationVisitRecord(latitude: 35.681240, longitude: 139.767130, horizontalAccuracy: 12, arrivedAt: day1, departedAt: day1.addingTimeInterval(3600), recordedAt: day1)]
        )
        try store.replacePeerBuckets([peerBucket.dayKeyUTC: peerBucket], now: day1.addingTimeInterval(3600))
        let afterMatch = try store.recomputeMatches(pairID: pairID, now: day1.addingTimeInterval(3600))
        #expect(afterMatch.localBuckets[peerBucket.dayKeyUTC]?.visits.count == 1)
        #expect(afterMatch.localBuckets[peerBucket.dayKeyUTC]?.visits[0].departedAt == day1.addingTimeInterval(3600))
        #expect(afterMatch.matchedSessions.count == 1)

        // 20 days later, raw buckets prune cleanly, while derived matchedSessions persist forever
        let day20 = day1.addingTimeInterval(20 * 86_400)
        let afterPrune = try store.recomputeMatches(pairID: pairID, now: day20)
        #expect(afterPrune.localBuckets.isEmpty)
        #expect(afterPrune.peerBuckets.isEmpty)
        #expect(afterPrune.matchedSessions.count == 1)
    }

    @Test func calendarAggregatorUnionsBleAndLocationAndRespectsOverrides() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 19, minute: 0))!
        let bleEnd = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 19, minute: 40))!
        let locEnd = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 21, minute: 0))!
        let pairID = UUID()

        let ble = EncounterSession(
            pairID: pairID,
            startedAt: start,
            endedAt: bleEnd,
            status: .completed,
            connectionPath: .scanDiscovery,
            startRole: .central
        )
        let loc = LocationMatchedSession(
            id: LocationPayloadCipher.deterministicMatchID(pairID: pairID, startedAt: start),
            pairID: pairID,
            startedAt: start,
            endedAt: locEnd,
            averageDistanceMeters: 18
        )

        // Partial overlap: BLE 19:00-19:40 + Location 19:00-21:00 -> union must equal exact 2 hours (7200s)
        let summary = EncounterCalendarAggregator.daySummary(
            for: start,
            autoSessions: [ble],
            locationSessions: [loc],
            journal: JournalSnapshot(),
            calendar: cal
        )
        #expect(summary.totalRecordedSeconds == 7_200)
        #expect(summary.slices.count == 2)

        // Location completely covered by BLE -> no duplicate slice emitted
        let fullBle = EncounterSession(
            pairID: pairID,
            startedAt: start,
            endedAt: locEnd,
            status: .completed,
            connectionPath: .scanDiscovery,
            startRole: .central
        )
        let deduped = EncounterCalendarAggregator.daySummary(
            for: start,
            autoSessions: [fullBle],
            locationSessions: [loc],
            journal: JournalSnapshot(),
            calendar: cal
        )
        #expect(deduped.totalRecordedSeconds == 7_200)
        #expect(deduped.slices.count == 1)

        // Deleting a locationMatched session via JournalSnapshot override hides it
        var journal = JournalSnapshot()
        journal.sessionOverrides[loc.id] = SessionOverride(sessionID: loc.id, action: .deleted, updatedAt: .now)
        let deletedSummary = EncounterCalendarAggregator.daySummary(
            for: start,
            autoSessions: [],
            locationSessions: [loc],
            journal: journal,
            calendar: cal
        )
        #expect(deletedSummary.totalRecordedSeconds == 0)
        #expect(deletedSummary.slices.isEmpty)
    }

    @Test func distantPastDepartureVisitBackfillsFromNearbyPointAndInvertedVisitNeverBecomesOpen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OurHoursDistantPast-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocationTimelineStore(directory: dir)
        let pairID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        // Exact timeline observed in today's outing logs:
        // 13:21:46 nearby foregroundFix (acc 8.2m), then 13:35:10 departure CLVisit (departed 13:29:27, arrivalDate == .distantPast)
        let t1321 = Date(timeIntervalSince1970: 1_800_000_000)
        let t1329 = t1321.addingTimeInterval(461) // 13:29:27
        let t1335 = t1321.addingTimeInterval(804) // 13:35:10

        try store.recordPoint(
            LocationPointSample(
                timestamp: t1321,
                latitude: 35.71022,
                longitude: 139.57188,
                horizontalAccuracy: 8.2,
                source: .foregroundFix
            ),
            role: .partnerB,
            now: t1321
        )
        let snapshot = try store.recordVisit(
            LocationVisitRecord(
                latitude: 35.71022,
                longitude: 139.57186,
                horizontalAccuracy: 9.8,
                arrivedAt: t1329,
                departedAt: t1329,
                recordedAt: t1335
            ),
            role: .partnerB,
            arrivalUnknown: true,
            now: t1335
        )
        let dayKey = LocationDayKey.utcDayKey(for: t1321)
        let storedVisit = try #require(snapshot.localBuckets[dayKey]?.visits.first)
        #expect(storedVisit.arrivedAt == t1321)
        #expect(storedVisit.departedAt == t1329)

        // Direct inverted closed visit in LocationProximityMatcher must be ignored (0 matches), NOT treated as open
        let invertedClosed = LocationVisitRecord(
            latitude: 35.71022,
            longitude: 139.57186,
            horizontalAccuracy: 9.8,
            arrivedAt: t1335,
            departedAt: t1329,
            recordedAt: t1335
        )
        let peerLaterStay = LocationVisitRecord(
            latitude: 35.71022,
            longitude: 139.57186,
            horizontalAccuracy: 10,
            arrivedAt: t1335.addingTimeInterval(60),
            departedAt: t1335.addingTimeInterval(3600),
            recordedAt: t1335.addingTimeInterval(3600)
        )
        let matcherResult = LocationProximityMatcher.match(
            pairID: pairID,
            localBuckets: [DayLocationBucket(dayKeyUTC: dayKey, role: .partnerB, visits: [invertedClosed])],
            peerBuckets: [DayLocationBucket(dayKeyUTC: dayKey, role: .partnerA, visits: [peerLaterStay])],
            now: t1335.addingTimeInterval(4000)
        )
        #expect(matcherResult.isEmpty)
    }
}
