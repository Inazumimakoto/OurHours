import CryptoKit
import Foundation

public enum PairSpaceCryptoError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidShareURL
    case encryptionFailed
    case decryptionFailed
}

public enum PairAssetKind: String, Codable, Sendable, Equatable, CaseIterable {
    case avatar
    case dayPhoto
    case dayVideo
    case letterPhoto
}

public struct PairSpaceBootstrapPayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let pairID: UUID
    public let keyEpoch: UInt32
    public let shareURL: String
    public let zoneName: String
    public let updatedAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion, pairID: UUID, keyEpoch: UInt32,
        shareURL: String, zoneName: String, updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.pairID = pairID
        self.keyEpoch = keyEpoch
        self.shareURL = shareURL
        self.zoneName = zoneName
        self.updatedAt = updatedAt
    }

    fileprivate func matches(_ config: PairConfiguration) -> Bool {
        schemaVersion == Self.currentSchemaVersion && pairID == config.pairID
            && keyEpoch == config.keyEpoch && !zoneName.isEmpty
    }
}

public enum PairSpaceCrypto {
    private static let bootstrapPurpose = "OurHoursPairSpaceBootstrapV1"
    private static let assetPurpose = "OurHoursPairAssetV1"
    private static let formatVersion: UInt8 = 0x01

    public static func isValidCloudKitShareURL(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.utf8.count <= 512, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.rangeOfCharacter(from: CharacterSet.controlCharacters.union(.newlines)) == nil,
              let url = URLComponents(string: raw), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil,
              let host = url.host?.lowercased(), host == "icloud.com" || host.hasSuffix(".icloud.com") else {
            return false
        }
        let path = url.percentEncodedPath
        guard path.hasPrefix("/"), !path.hasSuffix("/") else { return false }
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2, segments[0].lowercased() == "share" else { return false }
        return segments[1].utf8.allSatisfy { byte in
            switch byte {
            case 65...90, 97...122, 48...57, 45, 95: true
            default: false
            }
        }
    }

    public static func zoneName(for config: PairConfiguration) -> String {
        "PairSpace_\(LocationPayloadCipher.channelToken(for: config).prefix(24))"
    }

    public static func bootstrapRecordName(for config: PairConfiguration) -> String {
        "ohs1_\(LocationPayloadCipher.channelToken(for: config).prefix(32))"
    }

    public static func assetRecordName(for config: PairConfiguration, kind: PairAssetKind, assetID: UUID) -> String {
        "oha1_\(kind.rawValue)_\(assetID.uuidString)"
    }

    public static func subscriptionID(forScope scope: String) -> String {
        "ourhours.pairspace.\(scope)"
    }

    public static func encryptBootstrap(_ payload: PairSpaceBootstrapPayload, using config: PairConfiguration) throws -> Data {
        guard config.isValid else { throw PairSpaceCryptoError.invalidConfiguration }
        guard isValidCloudKitShareURL(payload.shareURL) else { throw PairSpaceCryptoError.invalidShareURL }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard payload.matches(config), let plaintext = try? encoder.encode(payload) else {
            throw PairSpaceCryptoError.encryptionFailed
        }
        return try seal(plaintext, using: key(for: config, purpose: bootstrapPurpose))
    }

    public static func decryptBootstrap(_ ciphertext: Data, using config: PairConfiguration) throws -> PairSpaceBootstrapPayload {
        guard config.isValid else { throw PairSpaceCryptoError.invalidConfiguration }
        let plaintext = try open(ciphertext, using: key(for: config, purpose: bootstrapPurpose))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let payload = try? decoder.decode(PairSpaceBootstrapPayload.self, from: plaintext),
              payload.matches(config), isValidCloudKitShareURL(payload.shareURL) else {
            throw PairSpaceCryptoError.decryptionFailed
        }
        return payload
    }

    public static func encryptAssetData(
        _ plaintext: Data, kind: PairAssetKind, assetID: UUID, using config: PairConfiguration
    ) throws -> Data {
        guard config.isValid else { throw PairSpaceCryptoError.invalidConfiguration }
        return try seal(plaintext, using: key(for: config, purpose: assetPurpose), aad: assetAAD(kind, assetID))
    }

    public static func decryptAssetData(
        _ ciphertext: Data, kind: PairAssetKind, assetID: UUID, using config: PairConfiguration
    ) throws -> Data {
        guard config.isValid else { throw PairSpaceCryptoError.invalidConfiguration }
        return try open(ciphertext, using: key(for: config, purpose: assetPurpose), aad: assetAAD(kind, assetID))
    }

    private static func assetAAD(_ kind: PairAssetKind, _ assetID: UUID) -> Data {
        Data("\(kind.rawValue):\(assetID.uuidString)".utf8)
    }

    private static func seal(_ plaintext: Data, using key: SymmetricKey, aad: Data = Data()) throws -> Data {
        let framed = Data([formatVersion]) + plaintext
        guard let sealed = try? AES.GCM.seal(framed, using: key, authenticating: aad), let combined = sealed.combined else {
            throw PairSpaceCryptoError.encryptionFailed
        }
        return combined
    }

    private static func open(_ ciphertext: Data, using key: SymmetricKey, aad: Data = Data()) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
              let framed = try? AES.GCM.open(box, using: key, authenticating: aad), framed.first == formatVersion else {
            throw PairSpaceCryptoError.decryptionFailed
        }
        return Data(framed.dropFirst())
    }

    private static func key(for config: PairConfiguration, purpose: String) -> SymmetricKey {
        let pairBytes = withUnsafeBytes(of: config.pairID.uuid) { Data($0) }
        let epochBytes = withUnsafeBytes(of: config.keyEpoch.bigEndian) { Data($0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: config.sharedSecret), salt: pairBytes + epochBytes,
            info: Data(purpose.utf8), outputByteCount: 32
        )
    }
}
