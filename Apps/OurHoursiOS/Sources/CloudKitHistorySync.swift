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

enum SyncStorageBackend: Sendable, Equatable {
    case privateZone
    case sharedZone
    case publicFallback
}

struct HistorySyncOutcome: Sendable {
    let state: HistorySyncState
    let journal: JournalSnapshot?
    let peerSessions: [SyncedPeerSession]?
    let peerRecordDetected: Bool
    let backend: SyncStorageBackend
    let recoveredOwnSessions: [EncounterSession]
    let didApplyRemoteChanges: Bool
    let invalidateContext: Bool

    init(
        state: HistorySyncState,
        journal: JournalSnapshot? = nil,
        peerSessions: [SyncedPeerSession]? = nil,
        peerRecordDetected: Bool = false,
        backend: SyncStorageBackend = .publicFallback,
        recoveredOwnSessions: [EncounterSession] = [],
        didApplyRemoteChanges: Bool = false,
        invalidateContext: Bool = false
    ) {
        self.state = state
        self.journal = journal
        self.peerSessions = peerSessions
        self.peerRecordDetected = peerRecordDetected
        self.backend = backend
        self.recoveredOwnSessions = recoveredOwnSessions
        self.didApplyRemoteChanges = didApplyRemoteChanges
        self.invalidateContext = invalidateContext
    }
}

actor CloudKitHistorySync {
    private static let recordType = "PairSharedJournal"
    private static let signInMessage = "iCloud にサインインすると相手と記録・メモを同期できます"

    private var container: CKContainer { CKContainer(identifier: CloudKitLocationSync.containerIdentifier) }

    func sync(
        config: PairConfiguration,
        localSessions: [EncounterSession],
        journalStore: JournalStore,
        peerSyncStore: PartnerSyncStore,
        context: PairSpaceContext?,
        pairSpace: CloudKitPairSpace,
        isPairActive: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async -> HistorySyncOutcome {
        let backend: SyncStorageBackend = switch context?.scope {
        case .privateDB: .privateZone
        case .sharedDB: .sharedZone
        case nil: .publicFallback
        }
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            return HistorySyncOutcome(state: .failed("ペア設定が不正です"), backend: backend)
        }

        var appliedJournal: JournalSnapshot?
        var appliedPeerSessions: [SyncedPeerSession]?
        var peerRecordDetected = false
        var recoveredOwnSessions: [EncounterSession] = []
        var didApplyRemoteChanges = false
        let state: HistorySyncState
        var invalidateContext = false
        do {
            guard try await container.accountStatus() == .available else {
                return HistorySyncOutcome(state: .unavailable(Self.signInMessage), backend: backend)
            }

            let publicDatabase = container.publicCloudDatabase
            let targetDatabase = context.map { pairSpace.database(for: $0.scope) } ?? publicDatabase
            let peerName = PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole.opposite)
            let ownName = PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole)
            let peerID = CKRecord.ID(recordName: peerName, zoneID: context?.zoneID ?? .default)
            let ownID = CKRecord.ID(recordName: ownName, zoneID: context?.zoneID ?? .default)
            let legacyOwnID = CKRecord.ID(recordName: ownName)
            let observationKey = "ourhours.historyPeerInZone.\(PairSpaceCrypto.zoneName(for: config))"
            var canRetry = true

            while true {
                guard await isPairActive() else { return HistorySyncOutcome(state: .idle, backend: backend) }
                let fetched = try await targetDatabase.records(for: [peerID, ownID])
                let ownRecord = try CloudKitPairSpace.record(from: fetched[ownID])
                var peerRecord = try CloudKitPairSpace.record(from: fetched[peerID])
                let peerInZone = context != nil && peerRecord != nil
                if peerInZone {
                    UserDefaults.standard.set(true, forKey: observationKey)
                } else if context != nil, !UserDefaults.standard.bool(forKey: observationKey) {
                    peerRecord = try await CloudKitPairSpace.record(
                        in: publicDatabase, withID: CKRecord.ID(recordName: peerName)
                    )
                }
                let peerEnvelope = Self.envelope(from: peerRecord, config: config, role: config.localRole.opposite)

                var legacyOwnEnvelope: PartnerSyncEnvelope?
                if context != nil, ownRecord == nil {
                    let legacyOwn = try await CloudKitPairSpace.record(in: publicDatabase, withID: legacyOwnID)
                    legacyOwnEnvelope = Self.envelope(from: legacyOwn, config: config, role: config.localRole)
                }

                let previous = Self.envelope(from: ownRecord, config: config, role: config.localRole)
                let remoteOwnEnvelope = previous ?? legacyOwnEnvelope
                let prep = try await MainActor.run { () -> (JournalSnapshot, [SyncedPeerSession]?, Bool)? in
                    guard isPairActive() else { return nil }
                    _ = try journalStore.claimUnscopedEntries(for: config.pairID)
                    var changed = false
                    if let ownJournal = remoteOwnEnvelope?.journal.stampingUnscoped(with: config.pairID) {
                        changed = try journalStore.mergeRemote(ownJournal).didChange
                    }
                    var peerSessions: [SyncedPeerSession]?
                    if let peerEnvelope {
                        let previousCache = try peerSyncStore.load()
                        let cache = try peerSyncStore.savePeerSessions(
                            pairID: config.pairID,
                            peerRole: config.localRole.opposite,
                            sessions: peerEnvelope.bleSessions,
                            now: .now
                        )
                        let previousSessions = previousCache?.pairID == config.pairID
                            && previousCache?.peerRole == cache.peerRole ? previousCache?.sessions ?? [] : []
                        peerSessions = cache.sessions
                        var remoteJournal = peerEnvelope.journal.stampingUnscoped(with: config.pairID)
                        remoteJournal.roleProfiles.removeValue(forKey: config.localRole.shortCode)
                        let merged = try journalStore.mergeRemote(remoteJournal)
                        changed = changed || previousSessions != cache.sessions || merged.didChange
                    }
                    return (try journalStore.load(), peerSessions, changed)
                }
                guard let (journal, peerSessions, changed) = prep else {
                    return HistorySyncOutcome(state: .idle, backend: backend)
                }
                appliedJournal = journal
                appliedPeerSessions = peerSessions ?? appliedPeerSessions
                peerRecordDetected = peerRecordDetected || peerEnvelope != nil
                didApplyRemoteChanges = didApplyRemoteChanges || changed

                let bleMerge = PartnerSyncMerger.mergeOwnBLESessions(
                    local: localSessions + recoveredOwnSessions,
                    remote: remoteOwnEnvelope?.bleSessions ?? [],
                    pairID: config.pairID
                )
                recoveredOwnSessions += bleMerge.missingLocal
                let scopedJournal = journal.scoped(to: config.pairID)
                let localEnvelope = PartnerSyncEnvelope(
                    pairID: config.pairID, senderRole: config.localRole,
                    bleSessions: bleMerge.outbound, journal: scopedJournal
                )

                // A sync triggered by a silent push publishes only when the content changes.
                if try !Self.hasSameContent(previous, as: localEnvelope) {
                    let record = ownRecord ?? CKRecord(recordType: Self.recordType, recordID: ownID)
                    record["payload"] = try PartnerPayloadCipher.encrypt(localEnvelope, using: config) as CKRecordValue
                    record["updatedAt"] = localEnvelope.updatedAt as CKRecordValue
                    record["schemaVersion"] = NSNumber(value: PartnerSyncEnvelope.currentSchemaVersion)
                    guard await isPairActive() else { return HistorySyncOutcome(state: .idle, backend: backend) }
                    do {
                        try await CloudKitPairSpace.saveRecords(
                            [record], savePolicy: .ifServerRecordUnchanged, in: targetDatabase
                        )
                    } catch where canRetry && CloudKitPairSpace.isServerRecordChanged(error) {
                        canRetry = false
                        continue
                    }
                }
                guard await isPairActive() else { return HistorySyncOutcome(state: .idle, backend: backend) }
                if peerInZone {
                    try? await CloudKitPairSpace.deleteRecords([legacyOwnID], in: publicDatabase)
                }
                break
            }

            let peerCount = appliedPeerSessions?.count
                ?? (try? peerSyncStore.load())?.sessions.count(where: { $0.pairID == config.pairID })
                ?? 0
            state = .synced(.now, peerSessions: peerCount)
        } catch {
            invalidateContext = CloudKitPairSpace.isZoneOrAuthInvalidation(error)
            switch (error as? CKError)?.code {
            case .notAuthenticated:
                state = .unavailable(Self.signInMessage)
            case .networkUnavailable, .networkFailure:
                state = .failed("オフラインのため次回自動リトライします")
            default:
                state = .failed(error.localizedDescription)
            }
        }
        return HistorySyncOutcome(
            state: state, journal: appliedJournal, peerSessions: appliedPeerSessions,
            peerRecordDetected: peerRecordDetected, backend: backend, recoveredOwnSessions: recoveredOwnSessions,
            didApplyRemoteChanges: didApplyRemoteChanges || !recoveredOwnSessions.isEmpty,
            invalidateContext: invalidateContext
        )
    }

    private static func envelope(from record: CKRecord?, config: PairConfiguration, role: PeerRole) -> PartnerSyncEnvelope? {
        guard let payload = record?["payload"] as? Data,
              let envelope = try? PartnerPayloadCipher.decrypt(payload, using: config),
              envelope.pairID == config.pairID, envelope.senderRole == role else { return nil }
        return envelope
    }

    private static func hasSameContent(_ previous: PartnerSyncEnvelope?, as local: PartnerSyncEnvelope) throws -> Bool {
        guard let previous, previous.schemaVersion == local.schemaVersion else { return false }
        if previous.journal == local.journal, previous.bleSessions == local.bleSessions { return true }
        // Cloud payloads round dates to the precision of seconds-since-1970 encoding.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let normalized = try decoder.decode(PartnerSyncEnvelope.self, from: encoder.encode(local))
        return previous.journal == normalized.journal && previous.bleSessions == normalized.bleSessions
    }

    func purgeOwnRecord(
        config: PairConfiguration, context: PairSpaceContext?, pairSpace: CloudKitPairSpace
    ) async -> Bool {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else { return false }
        do {
            guard try await container.accountStatus() == .available else { return false }
            let name = PartnerPayloadCipher.journalRecordName(for: config, role: config.localRole)
            let zones = try await pairSpace.resolvePurgeZones(for: config, cachedContext: context)
            for (scope, zoneID) in zones {
                let id = CKRecord.ID(recordName: name, zoneID: zoneID)
                try await CloudKitPairSpace.deleteRecords([id], in: pairSpace.database(for: scope))
            }
            try await CloudKitPairSpace.deleteRecords([CKRecord.ID(recordName: name)], in: container.publicCloudDatabase)
            return true
        } catch {
            return false
        }
    }
}
