import Foundation
import Testing
@testable import OurHoursCore

struct PairingPayloadCodecTests {
    @Test func bundleCreatesComplementaryRolesAndRandomCredentials() throws {
        let (local, payload) = PairingPayloadCodec.makePairingBundle(displayLabel: "Together", keyEpoch: 12)
        let (second, _) = PairingPayloadCodec.makePairingBundle()
        let peer = try PairingPayloadCodec.decode(payload)
        #expect(local.localRole == .partnerA)
        #expect(peer.localRole == .partnerB)
        #expect(local.displayLabel == "Together")
        #expect(peer.displayLabel == nil)
        #expect(local.pairID == peer.pairID)
        #expect(local.sharedSecret == peer.sharedSecret)
        #expect(local.sharedSecret.count == 32)
        #expect(local.keyEpoch == peer.keyEpoch)
        #expect(second.keyEpoch == 1)
        #expect(local.pairID != second.pairID)
        #expect(local.sharedSecret != second.sharedSecret)
    }

    @Test(arguments: PeerRole.allCases)
    func roundTripWithWhitespace(role: PeerRole) throws {
        let config = PairConfiguration(
            pairID: UUID(), sharedSecret: Data(repeating: 255, count: 32), localRole: role.opposite, keyEpoch: .max
        )
        let payload = PairingPayloadCodec.encode(config, for: role)
        let decoded = try PairingPayloadCodec.decode(" \n" + payload + "\r\n\t")
        #expect(decoded.pairID == config.pairID)
        #expect(decoded.sharedSecret == config.sharedSecret)
        #expect(decoded.keyEpoch == UInt32.max)
        #expect(decoded.localRole == role)
        #expect(payload.contains("&k=___"))
    }

    @Test(arguments: [
        "badID", "shortKey", "paddedKey", "nonCanonicalKey", "wrongRole", "zeroEpoch", "overflowEpoch",
        "signedEpoch", "wrongScheme", "wrongHost", "wrongPath", "duplicateEpoch", "missingEpoch",
        "extraParameter", "credentials", "port", "fragment"
    ])
    func rejectsMalformedPayload(variant: String) {
        let (_, valid) = PairingPayloadCodec.makePairingBundle()
        let url = URLComponents(string: valid)!
        let query = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
        let key = query["k"]!
        let invalid: String
        switch variant {
        case "badID": invalid = valid.replacingOccurrences(of: query["p"]!, with: "broken")
        case "shortKey": invalid = valid.replacingOccurrences(of: key, with: "abc")
        case "paddedKey": invalid = valid.replacingOccurrences(of: key, with: key + "=")
        case "nonCanonicalKey": invalid = valid.replacingOccurrences(of: key, with: String(key.dropLast()) + "+")
        case "wrongRole": invalid = valid.replacingOccurrences(of: "&r=B", with: "&r=b")
        case "zeroEpoch": invalid = valid.replacingOccurrences(of: "&e=1", with: "&e=0")
        case "overflowEpoch": invalid = valid.replacingOccurrences(of: "&e=1", with: "&e=4294967296")
        case "signedEpoch": invalid = valid.replacingOccurrences(of: "&e=1", with: "&e=+1")
        case "wrongScheme": invalid = valid.replacingOccurrences(of: "ourhours:", with: "https:")
        case "wrongHost": invalid = valid.replacingOccurrences(of: "pair/v1", with: "other/v1")
        case "wrongPath": invalid = valid.replacingOccurrences(of: "/v1", with: "/v2")
        case "duplicateEpoch": invalid = valid + "&e=2"
        case "missingEpoch": invalid = valid.replacingOccurrences(of: "&e=1", with: "")
        case "extraParameter": invalid = valid + "&x=1"
        case "credentials": invalid = valid.replacingOccurrences(of: "//pair", with: "//user@pair")
        case "port": invalid = valid.replacingOccurrences(of: "pair/v1", with: "pair:9/v1")
        default: invalid = valid + "#fragment"
        }
        #expect(throws: PairingPayloadError.self) { try PairingPayloadCodec.decode(invalid) }
    }

    @Test func generatesQRCodeAtRequestedIntegerScale() throws {
        let (_, payload) = PairingPayloadCodec.makePairingBundle()
        let original = try #require(PairingPayloadCodec.generateQRCodeCGImage(from: payload, scale: 1))
        let scaled = try #require(PairingPayloadCodec.generateQRCodeCGImage(from: payload, scale: 3))
        #expect(original.width > 0)
        #expect(scaled.width == original.width * 3)
        #expect(scaled.height == original.height * 3)
        #expect(PairingPayloadCodec.generateQRCodeCGImage(from: payload, scale: 0) == nil)
    }
}
