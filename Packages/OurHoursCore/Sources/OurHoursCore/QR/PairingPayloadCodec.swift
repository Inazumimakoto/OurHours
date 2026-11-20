import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public enum PairingPayloadError: Error, Sendable, Equatable {
    case invalidURL, invalidParameters, invalidPairID, invalidSecret, invalidRole, invalidEpoch
}

public enum PairingPayloadCodec {
    private static let urlPrefix = "ourhours://pair/v1?"

    /// Creates a new pair with a positive key epoch.
    public static func makePairingBundle(
        displayLabel: String? = nil, keyEpoch: UInt32 = 1
    ) -> (localConfiguration: PairConfiguration, peerQRPayload: String) {
        precondition(keyEpoch >= 1, "The pairing key epoch must be positive.")
        let config = PairConfiguration(
            pairID: UUID(), sharedSecret: MutualAuthProtocol.randomBytes(count: 32),
            localRole: .partnerA, keyEpoch: keyEpoch, displayLabel: displayLabel
        )
        return (config, encode(config, for: .partnerB))
    }

    public static func encode(_ configuration: PairConfiguration, for role: PeerRole? = nil) -> String {
        let secret = base64URL(configuration.sharedSecret)
        let roleCode = (role ?? configuration.localRole).shortCode
        return "\(urlPrefix)p=\(configuration.pairID.uuidString)&k=\(secret)&r=\(roleCode)&e=\(configuration.keyEpoch)"
    }

    public static func decode(_ rawString: String) throws -> PairConfiguration {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(urlPrefix), let url = URLComponents(string: trimmed), url.fragment == nil else {
            throw PairingPayloadError.invalidURL
        }
        var parameters: [String: String] = [:]
        for item in url.percentEncodedQueryItems ?? [] {
            guard let value = item.value, parameters.updateValue(value, forKey: item.name) == nil else {
                throw PairingPayloadError.invalidParameters
            }
        }
        guard parameters.count == 4, let pair = parameters["p"], let key = parameters["k"],
              let role = parameters["r"], let epoch = parameters["e"] else {
            throw PairingPayloadError.invalidParameters
        }
        guard let pairID = UUID(uuidString: pair) else { throw PairingPayloadError.invalidPairID }
        guard key.utf8.count == 43,
              let secret = Data(base64Encoded: key.replacingOccurrences(of: "-", with: "+")
                  .replacingOccurrences(of: "_", with: "/") + "="),
              secret.count == 32, base64URL(secret) == key else {
            throw PairingPayloadError.invalidSecret
        }
        guard let localRole = PeerRole.allCases.first(where: { $0.shortCode == role }) else {
            throw PairingPayloadError.invalidRole
        }
        guard !epoch.isEmpty, epoch.utf8.allSatisfy({ (48...57).contains($0) }),
              let keyEpoch = UInt32(epoch), keyEpoch >= 1 else {
            throw PairingPayloadError.invalidEpoch
        }
        return PairConfiguration(pairID: pairID, sharedSecret: secret, localRole: localRole, keyEpoch: keyEpoch)
    }

    public static func generateQRCodeCGImage(from payload: String, scale: CGFloat = 10) -> CGImage? {
        guard scale.isFinite, scale >= 1 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        guard let output = filter.outputImage else { return nil }
        let factor = scale.rounded(.down)
        let image = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        return CIContext().createCGImage(image, from: image.extent)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
