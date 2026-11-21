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

    @Test(arguments: ["https://www.icloud.com/share/0abc123", "https://icloud.com/share/Ab_c-1#OurHours",
                      "HTTPS://ICLOUD.COM/SHARE/Ab_c-1"])
    func shareURLRoundTripsInPeerQR(url: String) throws {
        let (local, payload) = PairingPayloadCodec.makePairingBundle(cloudShareURL: url)
        #expect(local.cloudShareURL == url)
        #expect(payload == PairingPayloadCodec.encode(local, for: .partnerB))
        let peer = try PairingPayloadCodec.decode("\n " + payload + "\t")
        #expect(peer.cloudShareURL == url)
        #expect(peer.localRole == .partnerB)

        let invalidURL = "https://example.com/share/abc"
        let (withoutURL, withoutParameter) = PairingPayloadCodec.makePairingBundle(cloudShareURL: invalidURL)
        #expect(withoutURL.cloudShareURL == nil)
        #expect(!withoutParameter.contains("&s="))
        #expect(PairingPayloadCodec.encode(local.withCloudShareURL(invalidURL)) == PairingPayloadCodec.encode(local.withCloudShareURL(nil)))
    }

    @Test func rejectsInvalidShareParameter() {
        let (_, base) = PairingPayloadCodec.makePairingBundle()
        let urls = ["http://icloud.com/a", "https://icloud.com.example.org/a", "https://icloud.com/" + String(repeating: "a", count: 500)]
        let invalidPaths = ["/mail", "/settings#profile", "/share", "/share/", "/share/abc/def", "/share/abc%2Fdef", "/share/abc?foo=1"]
        let invalidValues = (urls + invalidPaths.map { "https://icloud.com" + $0 }).map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
        // This valid URL needs two padding characters in standard base64.
        let encoded = Data("https://icloud.com/share/abc".utf8).base64EncodedString()
        let canonical = encoded.replacingOccurrences(of: "=", with: "")
        for invalid in invalidValues + ["", "!", "_w", encoded, String(canonical.dropLast()) + "h"] {
            #expect(throws: PairingPayloadError.invalidShareURL) { try PairingPayloadCodec.decode(base + "&s=" + invalid) }
        }
        #expect(throws: PairingPayloadError.invalidParameters) { try PairingPayloadCodec.decode(base + "&s=" + canonical + "&s=" + canonical) }
        #expect(throws: PairingPayloadError.invalidParameters) { try PairingPayloadCodec.decode(base + "&x=1") }
    }

    @Test func legacyConfigurationKeepsCredentialsWhenMetadataChanges() throws {
        let json = """
        {"pairID":"F71EAD9A-BE02-48B2-BE01-7213BCC07F02","sharedSecret":"\(Data(repeating: 1, count: 32).base64EncodedString())","localRole":1,"keyEpoch":1,"createdAt":42,"displayLabel":"Together"}
        """
        let legacy = try JSONDecoder().decode(PairConfiguration.self, from: Data(json.utf8))
        #expect(legacy.cloudShareURL == nil)
        let updated = legacy.withCloudShareURL("https://icloud.com/share/pair")
        #expect(updated.cloudShareURL == "https://icloud.com/share/pair")
        #expect(updated.withCloudShareURL(nil) == legacy)
        let other = PairConfiguration(
            pairID: legacy.pairID, sharedSecret: legacy.sharedSecret, localRole: legacy.localRole,
            keyEpoch: legacy.keyEpoch, createdAt: legacy.createdAt.addingTimeInterval(10), displayLabel: "Us"
        )
        #expect(updated.matchesCredentials(of: other))
    }
}
