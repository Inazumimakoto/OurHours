import CryptoKit
import Foundation

public enum PartnerPayloadCipherError: Error, Sendable, Equatable {
    case invalidConfiguration
    case compressionFailed
    case encryptionFailed
    case decryptionFailed
}

public enum PartnerPayloadCipher {
    private static let formatVersionByte: UInt8 = 0x01

    public static func journalRecordName(for config: PairConfiguration, role: PeerRole) -> String {
        let prefix = String(LocationPayloadCipher.channelToken(for: config).prefix(32))
        return "ohj1_\(prefix)_\(role.shortCode)"
    }

    public static func encrypt(_ envelope: PartnerSyncEnvelope, using config: PairConfiguration) throws -> Data {
        guard config.isValid else { throw PartnerPayloadCipherError.invalidConfiguration }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let plaintext = try? encoder.encode(envelope) else {
            throw PartnerPayloadCipherError.encryptionFailed
        }

        let compressed: Data
        do {
            compressed = try (plaintext as NSData).compressed(using: .lzfse) as Data
        } catch {
            throw PartnerPayloadCipherError.compressionFailed
        }

        var framed = Data([formatVersionByte])
        framed.append(compressed)

        let key = payloadKey(for: config)
        guard let sealed = try? AES.GCM.seal(framed, using: key),
              let combined = sealed.combined else {
            throw PartnerPayloadCipherError.encryptionFailed
        }
        return combined
    }

    public static func decrypt(_ ciphertext: Data, using config: PairConfiguration) throws -> PartnerSyncEnvelope {
        guard config.isValid else { throw PartnerPayloadCipherError.invalidConfiguration }

        let key = payloadKey(for: config)
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
              let framed = try? AES.GCM.open(box, using: key),
              let version = framed.first,
              version == formatVersionByte else {
            throw PartnerPayloadCipherError.decryptionFailed
        }

        let compressed = Data(framed.dropFirst())
        let plaintext: Data
        do {
            plaintext = try (compressed as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw PartnerPayloadCipherError.decryptionFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let envelope = try? decoder.decode(PartnerSyncEnvelope.self, from: plaintext) else {
            throw PartnerPayloadCipherError.decryptionFailed
        }
        return envelope
    }

    private static func payloadKey(for config: PairConfiguration) -> SymmetricKey {
        let pairBytes = withUnsafeBytes(of: config.pairID.uuid) { Data($0) }
        let epochBytes = withUnsafeBytes(of: config.keyEpoch.bigEndian) { Data($0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: config.sharedSecret),
            salt: pairBytes + epochBytes,
            info: Data("OurHoursSharedJournalPayloadV1".utf8),
            outputByteCount: 32
        )
    }
}
