import CryptoKit
import Foundation

public enum LocationPayloadCipherError: Error, Sendable, Equatable {
    case invalidConfiguration
    case encryptionFailed
    case decryptionFailed
}

public enum LocationPayloadCipher {
    public static func channelToken(for config: PairConfiguration) -> String {
        let pairBytes = withUnsafeBytes(of: config.pairID.uuid) { Data($0) }
        let epochBytes = withUnsafeBytes(of: config.keyEpoch.bigEndian) { Data($0) }
        let input = Data("OurHoursCloudChannelV1|".utf8) + pairBytes + epochBytes
        let key = SymmetricKey(data: config.sharedSecret)
        let mac = HMAC<SHA256>.authenticationCode(for: input, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public static func dayRecordName(for config: PairConfiguration, role: PeerRole, utcDayKey: String) -> String {
        let prefix = String(channelToken(for: config).prefix(32))
        return "oh1_\(prefix)_\(role.shortCode)_\(utcDayKey)"
    }

    public static func encrypt(_ bucket: DayLocationBucket, using config: PairConfiguration) throws -> Data {
        guard config.isValid else { throw LocationPayloadCipherError.invalidConfiguration }
        let key = payloadKey(for: config)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let plaintext = try? encoder.encode(bucket),
              let sealed = try? AES.GCM.seal(plaintext, using: key),
              let combined = sealed.combined else {
            throw LocationPayloadCipherError.encryptionFailed
        }
        return combined
    }

    public static func decrypt(_ ciphertext: Data, using config: PairConfiguration) throws -> DayLocationBucket {
        guard config.isValid else { throw LocationPayloadCipherError.invalidConfiguration }
        let key = payloadKey(for: config)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
              let plaintext = try? AES.GCM.open(box, using: key),
              let bucket = try? decoder.decode(DayLocationBucket.self, from: plaintext) else {
            throw LocationPayloadCipherError.decryptionFailed
        }
        return bucket
    }

    public static func deterministicMatchID(pairID: UUID, startedAt: Date) -> UUID {
        let pairBytes = withUnsafeBytes(of: pairID.uuid) { Data($0) }
        let bucketIndex = Int64(floor(startedAt.timeIntervalSince1970 / 600.0))
        let bucketBytes = withUnsafeBytes(of: bucketIndex.bigEndian) { Data($0) }
        let digest = SHA256.hash(data: Data("OurHoursLocMatchV1|".utf8) + pairBytes + bucketBytes)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func payloadKey(for config: PairConfiguration) -> SymmetricKey {
        let pairBytes = withUnsafeBytes(of: config.pairID.uuid) { Data($0) }
        let epochBytes = withUnsafeBytes(of: config.keyEpoch.bigEndian) { Data($0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: config.sharedSecret),
            salt: pairBytes + epochBytes,
            info: Data("OurHoursLocationPayloadV1".utf8),
            outputByteCount: 32
        )
    }
}
