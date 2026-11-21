import CloudKit
import Foundation
import OurHoursCore

enum HistorySyncState: Sendable, Equatable {
    case idle
    case syncing
    case synced(Date, peerSessions: Int)
    case unavailable(String)
    case failed(String)
}

struct HistorySyncOutcome: Sendable {
    let state: HistorySyncState
    let journal: JournalSnapshot?
    let peerSessions: [SyncedPeerSession]?
}

actor CloudKitHistorySync {
    private static let recordType = "PairSharedJournal"

    private var container: CKContainer { CKContainer(identifier: CloudKitLocationSync.containerIdentifier) }
    private var database: CKDatabase { container.publicCloudDatabase }

    func sync(
        config: PairConfiguration,
        localSessions: [EncounterSession],
        journalStore: JournalStore,
        peerSyncStore: PartnerSyncStore
    ) async -> HistorySyncOutcome {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            return HistorySyncOutcome(state: .failed("ペア設定が不正です"), journal: nil, peerSessions: nil)
        }

        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                return HistorySyncOutcome(
                    state: .unavailable("iCloud にサインインすると相手と記録・メモを同期できます"),
                    journal: nil,
                    peerSessions: nil
                )
            }

            let peerRecordID = CKRecord.ID(
                recordName: PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole.opposite)
            )
            let fetchResults = try await database.records(for: [peerRecordID])

            var loadedPeerSessions: [SyncedPeerSession]?
            if case let .success(peerRecord) = fetchResults[peerRecordID],
               let payload = peerRecord["payload"] as? Data,
               let envelope = try? PartnerPayloadCipher.decrypt(payload, using: config),
               envelope.pairID == config.pairID,
               envelope.senderRole == config.localRole.opposite {
                let cache = try peerSyncStore.savePeerSessions(
                    pairID: config.pairID,
                    peerRole: config.localRole.opposite,
                    sessions: envelope.bleSessions,
                    now: .now
                )
                loadedPeerSessions = cache.sessions
                _ = try journalStore.mergeRemote(envelope.journal)
            }

            let mergedJournal = try journalStore.load()
            let scopedJournal = JournalSnapshot(
                manualRecords: mergedJournal.manualRecords.filter { $0.pairID == nil || $0.pairID == config.pairID },
                sessionOverrides: mergedJournal.sessionOverrides,
                dailyMemos: mergedJournal.dailyMemos,
                deletedManualRecords: mergedJournal.deletedManualRecords,
                deletedMemoDays: mergedJournal.deletedMemoDays
            )
            let scopedBLE = localSessions
                .filter { $0.pairID == config.pairID && $0.status != .active }
                .map(SyncedPeerSession.init(from:))

            let localEnvelope = PartnerSyncEnvelope(
                pairID: config.pairID,
                senderRole: config.localRole,
                updatedAt: .now,
                bleSessions: scopedBLE,
                journal: scopedJournal
            )
            let encrypted = try PartnerPayloadCipher.encrypt(localEnvelope, using: config)
            let ownRecordID = CKRecord.ID(
                recordName: PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole)
            )
            let ownRecord = CKRecord(recordType: Self.recordType, recordID: ownRecordID)
            ownRecord["payload"] = encrypted as CKRecordValue
            ownRecord["updatedAt"] = localEnvelope.updatedAt as CKRecordValue
            ownRecord["schemaVersion"] = NSNumber(value: PartnerSyncEnvelope.currentSchemaVersion)

            _ = try await database.modifyRecords(
                saving: [ownRecord],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )

            let fallbackPeerCount = loadedPeerSessions?.count
                ?? (try? peerSyncStore.load())?.sessions.count(where: { $0.pairID == config.pairID })
                ?? 0
            return HistorySyncOutcome(
                state: .synced(.now, peerSessions: fallbackPeerCount),
                journal: mergedJournal,
                peerSessions: loadedPeerSessions
            )
        } catch let error as CKError {
            switch error.code {
            case .notAuthenticated:
                return HistorySyncOutcome(
                    state: .unavailable("iCloud にサインインすると相手と記録・メモを同期できます"),
                    journal: nil,
                    peerSessions: nil
                )
            case .networkUnavailable, .networkFailure:
                return HistorySyncOutcome(
                    state: .failed("オフラインのため次回自動リトライします"),
                    journal: nil,
                    peerSessions: nil
                )
            default:
                return HistorySyncOutcome(state: .failed(error.localizedDescription), journal: nil, peerSessions: nil)
            }
        } catch {
            return HistorySyncOutcome(state: .failed(error.localizedDescription), journal: nil, peerSessions: nil)
        }
    }

    func purgeOwnRecord(config: PairConfiguration) async {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else { return }
        let ownRecordID = CKRecord.ID(
            recordName: PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole)
        )
        _ = try? await database.modifyRecords(
            saving: [],
            deleting: [ownRecordID],
            savePolicy: .allKeys,
            atomically: false
        )
    }
}
