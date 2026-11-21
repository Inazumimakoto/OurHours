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

actor CloudKitLocationSync {
    static let containerIdentifier = "iCloud.io.github.inazumimakoto.OurHours"
    private static let recordType = "PairDayPresence"

    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }
    private var database: CKDatabase { container.publicCloudDatabase }

    func sync(config: PairConfiguration, store: LocationTimelineStore) async -> LocationSyncState {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            return .failed("ペア設定が不正です")
        }

        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                return .unavailable("iCloud にサインインすると相手と位置補完を同期できます")
            }

            let snapshot = try store.load()
            let uploadKeys = LocationDayKey.recentUTCDayKeys(endingAt: .now, days: 7)
            var recordsToSave: [CKRecord] = []
            for key in uploadKeys {
                guard let bucket = snapshot.localBuckets[key], !bucket.isEmpty else { continue }
                let encrypted = try LocationPayloadCipher.encrypt(bucket, using: config)
                let recordID = CKRecord.ID(
                    recordName: LocationPayloadCipher.dayRecordName(
                        for: config,
                        role: config.localRole,
                        utcDayKey: key
                    )
                )
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)
                record["payload"] = encrypted as CKRecordValue
                record["updatedAt"] = bucket.updatedAt as CKRecordValue
                record["schemaVersion"] = NSNumber(value: 1)
                recordsToSave.append(record)
            }

            if !recordsToSave.isEmpty {
                _ = try await database.modifyRecords(
                    saving: recordsToSave,
                    deleting: [],
                    savePolicy: .allKeys,
                    atomically: false
                )
            }

            let fetchKeys = LocationDayKey.recentUTCDayKeys(endingAt: .now, days: LocationTimelineStore.retentionDays)
            let mappedIDs: [(key: String, recordID: CKRecord.ID)] = fetchKeys.map { key in
                (
                    key,
                    CKRecord.ID(
                        recordName: LocationPayloadCipher.dayRecordName(
                            for: config,
                            role: config.localRole.opposite,
                            utcDayKey: key
                        )
                    )
                )
            }

            let fetchResults = try await database.records(for: mappedIDs.map(\.recordID))
            var decryptedPeerBuckets: [String: DayLocationBucket] = [:]
            for (key, recordID) in mappedIDs {
                guard case let .success(record) = fetchResults[recordID],
                      let payload = record["payload"] as? Data,
                      let bucket = try? LocationPayloadCipher.decrypt(payload, using: config) else {
                    continue
                }
                decryptedPeerBuckets[key] = bucket
            }

            try store.replacePeerBuckets(decryptedPeerBuckets, now: .now)
            try store.recomputeMatches(pairID: config.pairID, now: .now)
            return .synced(.now, peerDays: decryptedPeerBuckets.count)
        } catch let error as CKError {
            switch error.code {
            case .notAuthenticated:
                return .unavailable("iCloud にサインインすると相手と位置補完を同期できます")
            case .networkUnavailable, .networkFailure:
                return .failed("オフラインのため次回自動リトライします")
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func purgeOwnRecords(config: PairConfiguration) async {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else { return }
        let keys = LocationDayKey.recentUTCDayKeys(endingAt: .now, days: LocationTimelineStore.retentionDays)
        let ids = keys.map { key in
            CKRecord.ID(
                recordName: LocationPayloadCipher.dayRecordName(
                    for: config,
                    role: config.localRole,
                    utcDayKey: key
                )
            )
        }
        guard !ids.isEmpty else { return }
        _ = try? await database.modifyRecords(
            saving: [],
            deleting: ids,
            savePolicy: .allKeys,
            atomically: false
        )
    }
}
