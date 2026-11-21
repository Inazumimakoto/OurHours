import Foundation
import Testing
@testable import OurHoursCore

struct PairSpaceCryptoTests {
    private let config = PairingPayloadCodec.makePairingBundle().localConfiguration
    private let url = "https://www.icloud.com/share/0abc123"

    private var bootstrap: PairSpaceBootstrapPayload {
        PairSpaceBootstrapPayload(
            pairID: config.pairID, keyEpoch: config.keyEpoch, shareURL: url,
            zoneName: PairSpaceCrypto.zoneName(for: config), updatedAt: Date(timeIntervalSince1970: 123456.5)
        )
    }

    @Test func recordAndSubscriptionNames() {
        let token = LocationPayloadCipher.channelToken(for: config)
        #expect(PairSpaceCrypto.zoneName(for: config) == "PairSpace_\(token.prefix(24))")
        #expect(PairSpaceCrypto.bootstrapRecordName(for: config) == "ohs1_\(token.prefix(32))")
        let id = UUID()
        for kind in PairAssetKind.allCases {
            #expect(PairSpaceCrypto.assetRecordName(for: config, kind: kind, assetID: id) == "oha1_\(kind.rawValue)_\(id.uuidString)")
        }
        #expect(PairSpaceCrypto.subscriptionID(forScope: "shared") == "ourhours.pairspace.shared")
    }

    @Test func bootstrapRoundTripAndTampering() throws {
        let ciphertext = try PairSpaceCrypto.encryptBootstrap(bootstrap, using: config)
        #expect(try PairSpaceCrypto.decryptBootstrap(ciphertext, using: config) == bootstrap)
        var damaged = ciphertext
        damaged[0] ^= 1
        #expect(throws: PairSpaceCryptoError.decryptionFailed) { try PairSpaceCrypto.decryptBootstrap(damaged, using: config) }
    }

    @Test func rejectsInvalidBootstrapMetadata() {
        let variants: [(UUID, UInt32, String, String, PairSpaceCryptoError)] = [
            (UUID(), config.keyEpoch, url, "zone", .encryptionFailed),
            (config.pairID, 2, url, "zone", .encryptionFailed),
            (config.pairID, config.keyEpoch, url, "", .encryptionFailed),
            (config.pairID, config.keyEpoch, "https://example.org/test", "zone", .invalidShareURL)
        ]
        for (id, epoch, link, zone, error) in variants {
            let payload = PairSpaceBootstrapPayload(pairID: id, keyEpoch: epoch, shareURL: link, zoneName: zone)
            #expect(throws: error) { try PairSpaceCrypto.encryptBootstrap(payload, using: config) }
        }
    }

    @Test func keysDependOnPairSecretAndEpoch() throws {
        let id = UUID()
        let asset = try PairSpaceCrypto.encryptAssetData(Data(), kind: .avatar, assetID: id, using: config)
        let discovery = try PairSpaceCrypto.encryptBootstrap(bootstrap, using: config)
        let variants = [
            (UUID(), config.keyEpoch, config.sharedSecret),
            (config.pairID, config.keyEpoch + 1, config.sharedSecret),
            (config.pairID, config.keyEpoch, Data(repeating: 3, count: 32))
        ]
        for (pair, epoch, secret) in variants {
            let other = PairConfiguration(pairID: pair, sharedSecret: secret, localRole: config.localRole, keyEpoch: epoch)
            #expect(throws: PairSpaceCryptoError.decryptionFailed) { try PairSpaceCrypto.decryptBootstrap(discovery, using: other) }
            #expect(throws: PairSpaceCryptoError.decryptionFailed) {
                try PairSpaceCrypto.decryptAssetData(asset, kind: .avatar, assetID: id, using: other)
            }
        }
    }

    @Test(arguments: PairAssetKind.allCases)
    func assetAuthenticatesContentsKindAndID(kind: PairAssetKind) throws {
        let peer = try PairingPayloadCodec.decode(PairingPayloadCodec.encode(config, for: .partnerB))
        let id = UUID()
        let plaintext = Data([0, 1, 2, 0xff])
        let ciphertext = try PairSpaceCrypto.encryptAssetData(plaintext, kind: kind, assetID: id, using: config)
        #expect(try PairSpaceCrypto.decryptAssetData(ciphertext, kind: kind, assetID: id, using: peer) == plaintext)
        var damaged = ciphertext
        damaged[damaged.count - 1] ^= 1
        #expect(throws: PairSpaceCryptoError.decryptionFailed) {
            try PairSpaceCrypto.decryptAssetData(damaged, kind: kind, assetID: id, using: peer)
        }
        #expect(throws: PairSpaceCryptoError.decryptionFailed) {
            try PairSpaceCrypto.decryptAssetData(ciphertext, kind: kind, assetID: UUID(), using: peer)
        }
        for other in PairAssetKind.allCases where other != kind {
            #expect(throws: PairSpaceCryptoError.decryptionFailed) {
                try PairSpaceCrypto.decryptAssetData(ciphertext, kind: other, assetID: id, using: peer)
            }
        }
    }

    @Test func shareURLValidation() {
        for invalid in ["", url + " ", "\t" + url, url + "\u{1}", url + "\u{2028}x",
                        "https://icloud.com", "https://icloud.com/", "https://noticloud.com/s",
                        "https://user:pw@icloud.com/s", "https://icloud.com:443/s"] {
            #expect(!PairSpaceCrypto.isValidCloudKitShareURL(invalid))
        }
        for path in ["/mail", "/settings#profile", "/share", "/share/", "/share/abc/def", "/share/abc%2Fdef", "/share/abc?foo=1", "/share//abc", "/share/abc/"] {
            #expect(!PairSpaceCrypto.isValidCloudKitShareURL("https://icloud.com" + path))
        }
        #expect(PairSpaceCrypto.isValidCloudKitShareURL(url))
        #expect(PairSpaceCrypto.isValidCloudKitShareURL(url + "#OurHours"))
        let prefix = "HTTPS://ICLOUD.COM/SHARE/"
        let atLimit = prefix + String(repeating: "a", count: 512 - prefix.utf8.count)
        #expect(PairSpaceCrypto.isValidCloudKitShareURL(atLimit))
        #expect(!PairSpaceCrypto.isValidCloudKitShareURL(atLimit + "a"))
    }
}
