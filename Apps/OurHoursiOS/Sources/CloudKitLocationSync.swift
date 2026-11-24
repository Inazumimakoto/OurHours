import CloudKit
import Foundation
import OurHoursCore

enum LocationSyncState: Sendable, Equatable {
    case idle
    case syncing
    case synced(Date, peerDays: Int)
    case unavailable(String)
    case failed(String)
}

struct LocationSyncOutcome: Sendable {
    let state: LocationSyncState
    let didApplyRemoteChanges: Bool
    let invalidateContext: Bool

    init(state: LocationSyncState, didApplyRemoteChanges: Bool = false, invalidateContext: Bool = false) {
        self.state = state
        self.didApplyRemoteChanges = didApplyRemoteChanges
        self.invalidateContext = invalidateContext
    }
}

actor CloudKitLocationSync {
    static let containerIdentifier = "iCloud.io.github.inazumimakoto.OurHours"
    private static let recordType = "PairDayPresence"

    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    func sync(
        config: PairConfiguration,
        store: LocationTimelineStore,
        context: PairSpaceContext?,
        pairSpace: CloudKitPairSpace,
        isPairActive: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async -> LocationSyncOutcome {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            return LocationSyncOutcome(state: .failed("ペア設定が不正です"))
        }

        let signInMessage = "iCloud にサインインすると相手と位置補完を同期できます"
        var didApplyRemoteChanges = false
        do {
            guard try await container.accountStatus() == .available else {
                return LocationSyncOutcome(state: .unavailable(signInMessage))
            }

            let publicDatabase = container.publicCloudDatabase
            let database = context.map { pairSpace.database(for: $0.scope) } ?? publicDatabase
            let zoneID = context?.zoneID ?? .default
            let uploadKeys = LocationDayKey.recentUTCDayKeys(endingAt: .now, days: LocationTimelineStore.retentionDays)
            let ownIDs = uploadKeys.map { Self.recordID(for: config, role: config.localRole, day: $0, zoneID: zoneID) }
            let peerRole = config.localRole.opposite
            let peerIDs = uploadKeys.map { Self.recordID(for: config, role: peerRole, day: $0, zoneID: zoneID) }
            let observationKey = "ourhours.locationPeerInZone.\(PairSpaceCrypto.zoneName(for: config))"
            var canRetry = true

            while true {
                guard await isPairActive() else { return LocationSyncOutcome(state: .idle) }
                let fetched = try await database.records(for: ownIDs + peerIDs)
                let ownRecords = try Self.records(for: ownIDs, from: fetched)
                let peerRecords = try Self.records(for: peerIDs, from: fetched)
                let existingOwnBuckets = Self.buckets(
                    from: ownRecords, ids: ownIDs, days: uploadKeys, role: config.localRole, config: config
                )
                var remoteOwnBuckets = existingOwnBuckets
                var remotePeerBuckets = Self.buckets(
                    from: peerRecords, ids: peerIDs, days: uploadKeys, role: peerRole, config: config
                )

                if context != nil {
                    if !remotePeerBuckets.isEmpty {
                        UserDefaults.standard.set(true, forKey: observationKey)
                    }
                    if remotePeerBuckets.count < uploadKeys.count,
                       !UserDefaults.standard.bool(forKey: observationKey) {
                        let legacyPeer = try await fetchLegacyBuckets(
                            days: uploadKeys, role: peerRole, config: config, in: publicDatabase
                        )
                        for (day, bucket) in legacyPeer where remotePeerBuckets[day] == nil {
                            remotePeerBuckets[day] = bucket
                        }
                    }
                    if remoteOwnBuckets.count < uploadKeys.count {
                        let legacyOwn = try await fetchLegacyBuckets(
                            days: uploadKeys, role: config.localRole, config: config, in: publicDatabase
                        )
                        for (day, bucket) in legacyOwn where remoteOwnBuckets[day] == nil {
                            remoteOwnBuckets[day] = bucket
                        }
                    }
                }

                let ownBuckets = remoteOwnBuckets
                let peerBuckets = remotePeerBuckets
                let prep = try await MainActor.run { () -> (LocationTimelineSnapshot, Bool)? in
                    guard isPairActive() else { return nil }
                    let now = Date.now
                    let ownMerge = try store.mergeRemoteOwnBuckets(ownBuckets, role: config.localRole, now: now)
                    let priorPeers = try store.load().peerBuckets
                    let updated = try store.replacePeerBuckets(peerBuckets, now: now)
                    try store.recomputeMatches(pairID: config.pairID, now: now)
                    return (try store.load(), ownMerge.didChange || priorPeers != updated.peerBuckets)
                }
                guard let (snapshot, changed) = prep else { return LocationSyncOutcome(state: .idle) }
                didApplyRemoteChanges = didApplyRemoteChanges || changed

                var recordsToSave: [CKRecord] = []
                for (day, id) in zip(uploadKeys, ownIDs) {
                    guard let bucket = snapshot.localBuckets[day], !bucket.isEmpty, bucket.role == config.localRole,
                          try !Self.hasSameContent(existingOwnBuckets[day], as: bucket) else { continue }
                    let record = ownRecords[id] ?? CKRecord(recordType: Self.recordType, recordID: id)
                    record["payload"] = try LocationPayloadCipher.encrypt(bucket, using: config) as CKRecordValue
                    record["updatedAt"] = bucket.updatedAt as CKRecordValue
                    record["schemaVersion"] = NSNumber(value: 1)
                    recordsToSave.append(record)
                }
                guard await isPairActive() else { return LocationSyncOutcome(state: .idle) }
                do {
                    try await CloudKitPairSpace.saveRecords(recordsToSave, savePolicy: .ifServerRecordUnchanged, in: database)
                } catch where canRetry && CloudKitPairSpace.isServerRecordChanged(error) {
                    canRetry = false
                    continue
                }

                return LocationSyncOutcome(
                    state: .synced(.now, peerDays: peerBuckets.count), didApplyRemoteChanges: didApplyRemoteChanges
                )
            }
        } catch {
            let state: LocationSyncState
            switch (error as? CKError)?.code {
            case .notAuthenticated:
                state = .unavailable(signInMessage)
            case .networkUnavailable, .networkFailure:
                state = .failed("オフラインのため次回自動リトライします")
            default:
                state = .failed(error.localizedDescription)
            }
            return LocationSyncOutcome(
                state: state, didApplyRemoteChanges: didApplyRemoteChanges,
                invalidateContext: CloudKitPairSpace.isZoneOrAuthInvalidation(error)
            )
        }
    }

    private func fetchLegacyBuckets(
        days: [String], role: PeerRole, config: PairConfiguration, in database: CKDatabase
    ) async throws -> [String: DayLocationBucket] {
        let ids = days.map { Self.recordID(for: config, role: role, day: $0, zoneID: .default) }
        let fetched = try await database.records(for: ids)
        return Self.buckets(from: try Self.records(for: ids, from: fetched), ids: ids, days: days, role: role, config: config)
    }

    private static func records(
        for ids: [CKRecord.ID], from fetched: [CKRecord.ID: Result<CKRecord, any Error>]
    ) throws -> [CKRecord.ID: CKRecord] {
        var records: [CKRecord.ID: CKRecord] = [:]
        for id in ids {
            records[id] = try CloudKitPairSpace.record(from: fetched[id])
        }
        return records
    }

    private static func buckets(
        from records: [CKRecord.ID: CKRecord], ids: [CKRecord.ID], days: [String], role: PeerRole, config: PairConfiguration
    ) -> [String: DayLocationBucket] {
        var buckets: [String: DayLocationBucket] = [:]
        for (day, id) in zip(days, ids) {
            guard let payload = records[id]?["payload"] as? Data,
                  let bucket = try? LocationPayloadCipher.decrypt(payload, using: config),
                  bucket.dayKeyUTC == day, bucket.role == role else { continue }
            buckets[day] = bucket
        }
        return buckets
    }

    private static func hasSameContent(_ previous: DayLocationBucket?, as local: DayLocationBucket) throws -> Bool {
        guard let previous else { return false }
        if previous == local { return true }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try previous == decoder.decode(DayLocationBucket.self, from: encoder.encode(local))
    }

    func purgeOwnRecords(config: PairConfiguration, context: PairSpaceContext?, pairSpace: CloudKitPairSpace) async -> Bool {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else { return false }
        do {
            guard try await container.accountStatus() == .available else { return false }
            let days = LocationDayKey.recentUTCDayKeys(endingAt: .now, days: LocationTimelineStore.retentionDays)
            let zones = try await pairSpace.resolvePurgeZones(for: config, cachedContext: context)
            for (scope, zoneID) in zones {
                let ids = days.map { Self.recordID(for: config, role: config.localRole, day: $0, zoneID: zoneID) }
                try await CloudKitPairSpace.deleteRecords(ids, in: pairSpace.database(for: scope))
            }
            let publicIDs = days.map { Self.recordID(for: config, role: config.localRole, day: $0, zoneID: .default) }
            try await CloudKitPairSpace.deleteRecords(publicIDs, in: container.publicCloudDatabase)
            return true
        } catch {
            return false
        }
    }

    private static func recordID(
        for config: PairConfiguration, role: PeerRole, day: String, zoneID: CKRecordZone.ID
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: LocationPayloadCipher.dayRecordName(for: config, role: role, utcDayKey: day),
            zoneID: zoneID
        )
    }
}
