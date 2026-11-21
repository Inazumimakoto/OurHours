import CloudKit
import Foundation
import OSLog
import OurHoursCore

enum PairSpaceDatabaseScope: Sendable, Equatable {
    case privateDB
    case sharedDB
}

struct PairSpaceContext: Sendable, Equatable {
    let scope: PairSpaceDatabaseScope
    let zoneID: CKRecordZone.ID
    let shareURL: String?
    let isSameAppleIDFallback: Bool
    let needsMaintenance: Bool

    init(
        scope: PairSpaceDatabaseScope, zoneID: CKRecordZone.ID, shareURL: String?,
        isSameAppleIDFallback: Bool, needsMaintenance: Bool = false
    ) {
        self.scope = scope
        self.zoneID = zoneID
        self.shareURL = shareURL
        self.isSameAppleIDFallback = isSameAppleIDFallback
        self.needsMaintenance = needsMaintenance
    }
}

enum PairSpaceStatus: Sendable, Equatable {
    case idle
    case settingUp
    case connected(scope: PairSpaceDatabaseScope, shareURL: String?, sameAppleID: Bool)
    case unavailable(String)
    case failed(String)
}

struct PairSpaceResolutionResult: Sendable {
    let status: PairSpaceStatus
    let context: PairSpaceContext?
    let discoveredShareURL: String?
}

enum CloudKitPairSpaceError: LocalizedError {
    case missingResult
    case unexpectedShare
    case missingAsset

    var errorDescription: String? {
        switch self {
        case .missingResult: "CloudKit の処理結果を取得できませんでした"
        case .unexpectedShare: "このペアに対応する共有スペースを確認できませんでした"
        case .missingAsset: "共有スペースのファイルを読み込めませんでした"
        }
    }
}

actor CloudKitPairSpace {
    private struct CacheKey: Hashable {
        let pairID: UUID
        let keyEpoch: UInt32
        let role: PeerRole

        init(_ config: PairConfiguration) {
            pairID = config.pairID
            keyEpoch = config.keyEpoch
            role = config.localRole
        }
    }

    private struct CacheEntry {
        var config: PairConfiguration
        var context: PairSpaceContext
        var result: PairSpaceResolutionResult
        var bootstrapPublished: Bool
        var subscriptionVerified: Bool
    }

    private static let logger = Logger(subsystem: "io.github.inazumimakoto.OurHours", category: "PairSpace")
    private static let signInMessage = "iCloud にサインインすると共有スペースを利用できます"
    private var cache: [CacheKey: CacheEntry] = [:]
    private var cacheGeneration = 0

    private var container: CKContainer { CKContainer(identifier: CloudKitLocationSync.containerIdentifier) }

    nonisolated func database(for scope: PairSpaceDatabaseScope) -> CKDatabase {
        let container = CKContainer(identifier: CloudKitLocationSync.containerIdentifier)
        switch scope {
        case .privateDB: return container.privateCloudDatabase
        case .sharedDB: return container.sharedCloudDatabase
        }
    }

    func invalidate() {
        cache.removeAll()
        cacheGeneration += 1
    }

    func resolveContext(for config: PairConfiguration) async -> PairSpaceResolutionResult {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            return Self.unresolved(.failed("ペア設定が不正です"))
        }

        let key = CacheKey(config)
        let generation = cacheGeneration
        do {
            guard try await container.accountStatus() == .available else {
                return Self.unresolved(.unavailable(Self.signInMessage))
            }
            if var entry = cache[key], entry.config.matchesCredentials(of: config) {
                guard entry.context.needsMaintenance else { return entry.result }
                entry.config = config
                if config.localRole == .partnerA, entry.context.shareURL == nil {
                    do {
                        entry.context = try await resolveOwnerContext(config: config, zoneName: entry.context.zoneID.zoneName)
                    } catch {
                        Self.logger.debug("CloudKit share refresh failed: \(error as NSError, privacy: .private)")
                    }
                }
                return await maintain(entry, generation: generation)
            }

            let zoneName = PairSpaceCrypto.zoneName(for: config)
            let context: PairSpaceContext
            if config.localRole == .partnerA {
                context = try await resolveOwnerContext(config: config, zoneName: zoneName)
            } else if let participantContext = try await resolveParticipantContext(config: config, zoneName: zoneName) {
                context = participantContext
            } else {
                return Self.unresolved(.unavailable("パートナーの共有準備を待っています"))
            }
            return await connect(context, config: config, generation: generation)
        } catch let error as CKError where error.code == .notAuthenticated {
            return Self.unresolved(.unavailable(Self.signInMessage))
        } catch {
            return Self.unresolved(.failed(error.localizedDescription))
        }
    }

    func acceptExternalShareMetadata(
        _ metadata: CKShare.Metadata,
        expectedConfig: PairConfiguration
    ) async -> PairSpaceResolutionResult {
        let generation = cacheGeneration
        do {
            let shareURL = Self.validatedShareURL(metadata.share.url?.absoluteString)
                ?? Self.validatedShareURL(expectedConfig.cloudShareURL)
            let context = try await acceptShare(metadata, expectedConfig: expectedConfig, shareURL: shareURL)
            return await connect(context, config: expectedConfig, generation: generation)
        } catch {
            return Self.unresolved(.failed(error.localizedDescription))
        }
    }

    private func resolveOwnerContext(config: PairConfiguration, zoneName: String) async throws -> PairSpaceContext {
        let database = database(for: .privateDB)
        let zoneID = try await ensurePrivateZone(named: zoneName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let share: CKShare
        if let existing = try await Self.record(in: database, withID: shareID) {
            guard let existingShare = existing as? CKShare else {
                throw CloudKitPairSpaceError.unexpectedShare
            }
            share = existingShare
        } else {
            share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "OurHours ふたりの記録" as CKRecordValue
        }

        let savedShare: CKShare
        let canEnablePublicAccess = share.publicPermission != .readWrite
            && !share.participants.contains(where: { $0.role != .owner })
        if share.url == nil || canEnablePublicAccess {
            share.publicPermission = .readWrite
            guard let saved = try await database.save(share) as? CKShare else {
                throw CloudKitPairSpaceError.unexpectedShare
            }
            savedShare = saved
        } else {
            savedShare = share
        }

        let shareURL = Self.validatedShareURL(savedShare.url?.absoluteString)
        return PairSpaceContext(scope: .privateDB, zoneID: zoneID, shareURL: shareURL, isSameAppleIDFallback: false)
    }

    private func resolveParticipantContext(config: PairConfiguration, zoneName: String) async throws -> PairSpaceContext? {
        var resolutionError: Error?
        let embeddedURL = Self.validatedShareURL(config.cloudShareURL)
        do {
            if let zoneID = try await findZone(named: zoneName, in: .sharedDB) {
                return PairSpaceContext(
                    scope: .sharedDB, zoneID: zoneID, shareURL: embeddedURL, isSameAppleIDFallback: false
                )
            }
        } catch {
            resolutionError = error
        }

        if let embeddedURL, let url = URL(string: embeddedURL) {
            do {
                let metadata = try await container.shareMetadata(for: url)
                return try await acceptShare(metadata, expectedConfig: config, shareURL: embeddedURL)
            } catch {
                resolutionError = error
            }
        }

        do {
            if let bootstrap = try await fetchBootstrap(config: config),
               bootstrap.shareURL != embeddedURL, let url = URL(string: bootstrap.shareURL) {
                let metadata = try await container.shareMetadata(for: url)
                return try await acceptShare(metadata, expectedConfig: config, shareURL: bootstrap.shareURL)
            }
        } catch {
            resolutionError = error
        }

        if let zoneID = try await findZone(named: zoneName, in: .privateDB) {
            return PairSpaceContext(scope: .privateDB, zoneID: zoneID, shareURL: nil, isSameAppleIDFallback: true)
        }
        if let resolutionError { throw resolutionError }
        return nil
    }

    private func acceptShare(
        _ metadata: CKShare.Metadata,
        expectedConfig: PairConfiguration,
        shareURL: String?
    ) async throws -> PairSpaceContext {
        let shareID = metadata.share.recordID
        let zoneName = shareID.zoneID.zoneName
        guard expectedConfig.sharedSecret.count == 32, expectedConfig.keyEpoch >= 1,
              metadata.containerIdentifier == CloudKitLocationSync.containerIdentifier,
              shareID.recordName == CKRecordNameZoneWideShare,
              zoneName == PairSpaceCrypto.zoneName(for: expectedConfig) else {
            throw CloudKitPairSpaceError.unexpectedShare
        }

        if metadata.participantRole == .owner {
            let zoneID: CKRecordZone.ID
            if let existing = try await findZone(named: zoneName, ownerName: shareID.zoneID.ownerName, in: .privateDB) {
                zoneID = existing
            } else {
                zoneID = try await ensurePrivateZone(named: zoneName)
            }
            return PairSpaceContext(
                scope: .privateDB, zoneID: zoneID, shareURL: shareURL,
                isSameAppleIDFallback: expectedConfig.localRole != .partnerA
            )
        }

        if metadata.participantStatus != .accepted {
            _ = try await container.accept(metadata)
        }
        let zoneID = try await findZone(named: zoneName, ownerName: shareID.zoneID.ownerName, in: .sharedDB)
            ?? shareID.zoneID
        return PairSpaceContext(scope: .sharedDB, zoneID: zoneID, shareURL: shareURL, isSameAppleIDFallback: false)
    }

    private func ensurePrivateZone(named zoneName: String) async throws -> CKRecordZone.ID {
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let results = try await database(for: .privateDB).modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)], deleting: []
        )
        guard let saved = results.saveResults[zoneID] else { throw CloudKitPairSpaceError.missingResult }
        return try saved.get().zoneID
    }

    private func findZone(
        named zoneName: String, ownerName: String? = nil, in scope: PairSpaceDatabaseScope
    ) async throws -> CKRecordZone.ID? {
        let zones = try await database(for: scope).allRecordZones()
        if let ownerName, let exact = zones.first(where: {
            $0.zoneID.zoneName == zoneName && $0.zoneID.ownerName == ownerName
        }) {
            return exact.zoneID
        }
        return zones.first { $0.zoneID.zoneName == zoneName }?.zoneID
    }

    private func ensureSubscription(for scope: PairSpaceDatabaseScope) async -> Bool {
        let database = database(for: scope)
        let scopeName = scope == .privateDB ? "private" : "shared"
        let id = PairSpaceCrypto.subscriptionID(forScope: scopeName)
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            let results = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            guard let saved = results.saveResults[id] else { throw CloudKitPairSpaceError.missingResult }
            _ = try saved.get()
            return true
        } catch {
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest,
               let existing = try? await database.subscription(for: id),
               existing is CKDatabaseSubscription,
               existing.notificationInfo?.shouldSendContentAvailable == true {
                return true
            }
            Self.logger.debug("CloudKit subscription verification failed: \(error as NSError, privacy: .private)")
            return false
        }
    }

    private func publishBootstrap(config: PairConfiguration, shareURL: String, zoneName: String) async -> Bool {
        do {
            let database = container.publicCloudDatabase
            let recordID = CKRecord.ID(recordName: PairSpaceCrypto.bootstrapRecordName(for: config))
            let existing = try await Self.record(in: database, withID: recordID)
            if let data = existing?["payload"] as? Data,
               let payload = try? PairSpaceCrypto.decryptBootstrap(data, using: config),
               payload.shareURL == shareURL, payload.zoneName == zoneName {
                return true
            }

            let payload = PairSpaceBootstrapPayload(
                pairID: config.pairID, keyEpoch: config.keyEpoch, shareURL: shareURL, zoneName: zoneName
            )
            let record = existing ?? CKRecord(recordType: "PairSpaceBootstrap", recordID: recordID)
            record["payload"] = try PairSpaceCrypto.encryptBootstrap(payload, using: config) as CKRecordValue
            record["updatedAt"] = payload.updatedAt as CKRecordValue
            record["schemaVersion"] = NSNumber(value: payload.schemaVersion)
            try await Self.saveRecords([record], in: database)
            return true
        } catch {
            Self.logger.debug("CloudKit bootstrap upload failed: \(error as NSError, privacy: .private)")
            return false
        }
    }

    private func fetchBootstrap(config: PairConfiguration) async throws -> PairSpaceBootstrapPayload? {
        let recordID = CKRecord.ID(recordName: PairSpaceCrypto.bootstrapRecordName(for: config))
        guard let record = try await Self.record(in: container.publicCloudDatabase, withID: recordID),
              let payload = record["payload"] as? Data else { return nil }
        let bootstrap = try PairSpaceCrypto.decryptBootstrap(payload, using: config)
        guard bootstrap.zoneName == PairSpaceCrypto.zoneName(for: config),
              Self.validatedShareURL(bootstrap.shareURL) != nil else {
            throw CloudKitPairSpaceError.unexpectedShare
        }
        return bootstrap
    }

    private func connect(
        _ context: PairSpaceContext, config: PairConfiguration, generation: Int
    ) async -> PairSpaceResolutionResult {
        await maintain(
            CacheEntry(
                config: config, context: context, result: Self.connected(context),
                bootstrapPublished: false, subscriptionVerified: false
            ),
            generation: generation
        )
    }

    private func maintain(_ cachedEntry: CacheEntry, generation: Int) async -> PairSpaceResolutionResult {
        var entry = cachedEntry
        let config = entry.config
        let context = entry.context
        let needsBootstrap = config.localRole == .partnerA
        if needsBootstrap, !entry.bootstrapPublished, let shareURL = context.shareURL {
            entry.bootstrapPublished = await publishBootstrap(
                config: config, shareURL: shareURL, zoneName: context.zoneID.zoneName
            )
        }
        if !entry.subscriptionVerified {
            entry.subscriptionVerified = await ensureSubscription(for: context.scope)
        }
        entry.context = PairSpaceContext(
            scope: context.scope, zoneID: context.zoneID, shareURL: context.shareURL,
            isSameAppleIDFallback: context.isSameAppleIDFallback,
            needsMaintenance: (needsBootstrap && !entry.bootstrapPublished) || !entry.subscriptionVerified
        )
        entry.result = Self.connected(entry.context)
        guard generation == cacheGeneration else { return Self.unresolved(.settingUp) }
        cache[CacheKey(config)] = entry
        return entry.result
    }

    private static func connected(_ context: PairSpaceContext) -> PairSpaceResolutionResult {
        PairSpaceResolutionResult(
            status: .connected(
                scope: context.scope, shareURL: context.shareURL, sameAppleID: context.isSameAppleIDFallback
            ),
            context: context,
            discoveredShareURL: context.shareURL
        )
    }

    private static func unresolved(_ status: PairSpaceStatus) -> PairSpaceResolutionResult {
        PairSpaceResolutionResult(status: status, context: nil, discoveredShareURL: nil)
    }

    private static func validatedShareURL(_ raw: String?) -> String? {
        guard let raw, PairSpaceCrypto.isValidCloudKitShareURL(raw) else { return nil }
        return raw
    }

    static func record(in database: CKDatabase, withID id: CKRecord.ID) async throws -> CKRecord? {
        let records = try await database.records(for: [id])
        return try record(from: records[id])
    }

    static func record(from result: Result<CKRecord, any Error>?) throws -> CKRecord? {
        guard let result else { throw CloudKitPairSpaceError.missingResult }
        do {
            return try result.get()
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static func saveRecords(
        _ records: [CKRecord],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
        in database: CKDatabase
    ) async throws {
        guard !records.isEmpty else { return }
        let results = try await database.modifyRecords(
            saving: records, deleting: [], savePolicy: savePolicy, atomically: false
        )
        var failure: Error?
        for record in records {
            guard let result = results.saveResults[record.recordID] else { throw CloudKitPairSpaceError.missingResult }
            if case let .failure(error) = result {
                if isZoneOrAuthInvalidation(error) { throw error }
                if failure == nil || isServerRecordChanged(error) {
                    failure = error
                }
            }
        }
        if let failure { throw failure }
    }

    static func deleteRecords(_ ids: [CKRecord.ID], in database: CKDatabase) async throws {
        guard !ids.isEmpty else { return }
        let results: (saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>])
        do {
            results = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        } catch where isAlreadyDeleted(error) {
            return
        }
        for id in ids {
            guard let result = results.deleteResults[id] else { throw CloudKitPairSpaceError.missingResult }
            if case let .failure(error) = result, !isAlreadyDeleted(error) { throw error }
        }
    }

    private static func isAlreadyDeleted(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return true
        case .partialFailure:
            guard let errors = error.partialErrorsByItemID?.values, !errors.isEmpty else { return false }
            return errors.allSatisfy(isAlreadyDeleted)
        default:
            return false
        }
    }

    static func isZoneOrAuthInvalidation(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .zoneNotFound, .userDeletedZone, .permissionFailure, .notAuthenticated:
            return true
        case .partialFailure:
            return error.partialErrorsByItemID?.values.contains(where: isZoneOrAuthInvalidation) == true
        default:
            return false
        }
    }

    static func isServerRecordChanged(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .serverRecordChanged:
            return true
        case .partialFailure, .batchRequestFailed:
            return error.partialErrorsByItemID?.values.contains(where: isServerRecordChanged) == true
        default:
            return false
        }
    }

    func saveEncryptedAsset(
        _ plaintext: Data,
        kind: PairAssetKind,
        assetID: UUID,
        config: PairConfiguration,
        context: PairSpaceContext
    ) async throws {
        let id = try assetRecordID(kind, assetID, config: config, context: context)
        let encrypted = try PairSpaceCrypto.encryptAssetData(plaintext, kind: kind, assetID: assetID, using: config)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("oha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try encrypted.write(to: tempURL, options: .atomic)

        let record = CKRecord(recordType: "PairEncryptedAsset", recordID: id)
        record["asset"] = CKAsset(fileURL: tempURL)
        record["kind"] = kind.rawValue as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        record["schemaVersion"] = NSNumber(value: 1)
        try await Self.saveRecords([record], savePolicy: .allKeys, in: database(for: context.scope))
    }

    func fetchEncryptedAsset(
        kind: PairAssetKind, assetID: UUID, config: PairConfiguration, context: PairSpaceContext
    ) async throws -> Data? {
        let id = try assetRecordID(kind, assetID, config: config, context: context)
        guard let record = try await Self.record(in: database(for: context.scope), withID: id) else { return nil }
        guard let asset = record["asset"] as? CKAsset, let fileURL = asset.fileURL else {
            throw CloudKitPairSpaceError.missingAsset
        }
        let encrypted = try Data(contentsOf: fileURL)
        return try PairSpaceCrypto.decryptAssetData(encrypted, kind: kind, assetID: assetID, using: config)
    }

    func deleteEncryptedAsset(
        kind: PairAssetKind, assetID: UUID, config: PairConfiguration, context: PairSpaceContext
    ) async throws {
        let id = try assetRecordID(kind, assetID, config: config, context: context)
        do {
            _ = try await database(for: context.scope).deleteRecord(withID: id)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func assetRecordID(
        _ kind: PairAssetKind, _ assetID: UUID, config: PairConfiguration, context: PairSpaceContext
    ) throws -> CKRecord.ID {
        guard config.sharedSecret.count == 32, config.keyEpoch >= 1 else {
            throw PairSpaceCryptoError.invalidConfiguration
        }
        guard context.zoneID.zoneName == PairSpaceCrypto.zoneName(for: config) else {
            throw CloudKitPairSpaceError.unexpectedShare
        }
        return CKRecord.ID(
            recordName: PairSpaceCrypto.assetRecordName(for: config, kind: kind, assetID: assetID), zoneID: context.zoneID
        )
    }

    func resolvePurgeZones(
        for config: PairConfiguration, cachedContext: PairSpaceContext?
    ) async throws -> [(PairSpaceDatabaseScope, CKRecordZone.ID)] {
        if let cachedContext { return [(cachedContext.scope, cachedContext.zoneID)] }
        guard try await container.accountStatus() == .available else {
            throw CloudKitPairSpaceError.missingResult
        }
        let zoneName = PairSpaceCrypto.zoneName(for: config)
        var zones: [(PairSpaceDatabaseScope, CKRecordZone.ID)] = []
        for scope: PairSpaceDatabaseScope in [.sharedDB, .privateDB] {
            do {
                if let zoneID = try await findZone(named: zoneName, in: scope) {
                    zones.append((scope, zoneID))
                }
            } catch where Self.isAlreadyDeleted(error) {
                continue
            }
        }
        return zones
    }

    func purgePairSpace(config: PairConfiguration) async -> Bool {
        cache = cache.filter { $0.key.pairID != config.pairID }
        cacheGeneration += 1
        do {
            guard try await container.accountStatus() == .available else { return false }
            let zoneName = PairSpaceCrypto.zoneName(for: config)
            if config.localRole == .partnerA {
                let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
                do {
                    _ = try await database(for: .privateDB).deleteRecordZone(withID: zoneID)
                } catch where Self.isAlreadyDeleted(error) {
                    // An earlier attempt may have deleted the zone before removing the bootstrap.
                }
                let bootstrapID = CKRecord.ID(recordName: PairSpaceCrypto.bootstrapRecordName(for: config))
                try await Self.deleteRecords([bootstrapID], in: container.publicCloudDatabase)
            } else {
                let zoneID: CKRecordZone.ID?
                do {
                    zoneID = try await findZone(named: zoneName, in: .sharedDB)
                } catch where Self.isAlreadyDeleted(error) {
                    return true
                }
                if let zoneID {
                    let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                    try await Self.deleteRecords([shareID], in: database(for: .sharedDB))
                }
            }
            return true
        } catch {
            Self.logger.debug("CloudKit pair space purge failed: \(error as NSError, privacy: .private)")
            return false
        }
    }
}
