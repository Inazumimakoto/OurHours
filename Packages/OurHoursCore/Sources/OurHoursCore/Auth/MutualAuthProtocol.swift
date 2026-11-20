import CryptoKit
import Foundation

public enum AuthError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidLength
    case unsupportedVersion
    case unexpectedMessage
    case wrongRole
    case wrongKeyEpoch
    case invalidTag
    case invalidState
    case expired
}

public enum MutualAuthProtocol {
    enum Message: UInt8 {
        case serverHello = 1
        case clientAuth = 2
        case serverAuth = 3

        var length: Int {
            switch self {
            case .serverHello: 23
            case .clientAuth: 55
            case .serverAuth: 39
            }
        }
    }

    static let nonceLength = 16

    static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func epochBytes(_ epoch: UInt32) -> Data {
        withUnsafeBytes(of: epoch.bigEndian) { Data($0) }
    }

    static func encode(_ message: Message, config: PairConfiguration, body: Data) -> Data {
        Data([1, message.rawValue, config.localRole.rawValue]) + epochBytes(config.keyEpoch) + body
    }

    static func decode(_ data: Data, as message: Message, config: PairConfiguration) throws -> Data {
        guard data.count == message.length else { throw AuthError.invalidLength }
        let header = Array(data.prefix(7))
        guard header[0] == 1 else { throw AuthError.unsupportedVersion }
        guard header[1] == message.rawValue else { throw AuthError.unexpectedMessage }
        guard header[2] == config.localRole.opposite.rawValue else { throw AuthError.wrongRole }
        guard Data(header[3..<7]) == epochBytes(config.keyEpoch) else { throw AuthError.wrongKeyEpoch }
        return Data(data.dropFirst(7))
    }

    static func transcript(
        _ message: Message, config: PairConfiguration, clientRole: PeerRole,
        clientNonce: Data, serverNonce: Data
    ) -> Data {
        let domain = message == .clientAuth ? "OurHoursAuthV1|C2P" : "OurHoursAuthV1|P2C"
        let pairID = withUnsafeBytes(of: config.pairID.uuid) { Data($0) }
        return Data(domain.utf8) + pairID + epochBytes(config.keyEpoch)
            + Data([clientRole.rawValue, clientRole.opposite.rawValue]) + clientNonce + serverNonce
    }

    static func checkDeadline(_ now: Date, startedAt: Date, timeout: TimeInterval) throws {
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed >= 0, elapsed < timeout else { throw AuthError.expired }
    }
}

public struct PeripheralAuthSession: Sendable {
    private enum State: Sendable {
        case ready
        case awaitingClient(serverNonce: Data)
        case consumed
    }

    private var state = State.ready
    private let config: PairConfiguration
    private let startedAt: Date
    private let timeout: TimeInterval

    public init(configuration: PairConfiguration, now: Date = Date(),
                timeout: TimeInterval = BLEConstants.authTimeoutSeconds) {
        config = configuration
        startedAt = now
        self.timeout = timeout
    }

    public mutating func makeServerHello(now: Date = Date()) throws -> Data {
        guard case .ready = state else { throw AuthError.invalidState }
        state = .consumed
        guard config.isValid else { throw AuthError.invalidConfiguration }
        try MutualAuthProtocol.checkDeadline(now, startedAt: startedAt, timeout: timeout)
        let nonce = MutualAuthProtocol.randomBytes(count: MutualAuthProtocol.nonceLength)
        state = .awaitingClient(serverNonce: nonce)
        return MutualAuthProtocol.encode(.serverHello, config: config, body: nonce)
    }

    public mutating func receiveClientAuth(_ data: Data, now: Date = Date()) throws -> Data {
        guard case let .awaitingClient(serverNonce) = state else { throw AuthError.invalidState }
        state = .consumed
        try MutualAuthProtocol.checkDeadline(now, startedAt: startedAt, timeout: timeout)
        let body = try MutualAuthProtocol.decode(data, as: .clientAuth, config: config)
        let clientNonce = Data(body.prefix(MutualAuthProtocol.nonceLength))
        let tag = Data(body.dropFirst(MutualAuthProtocol.nonceLength))
        let clientTranscript = MutualAuthProtocol.transcript(
            .clientAuth, config: config, clientRole: config.localRole.opposite,
            clientNonce: clientNonce, serverNonce: serverNonce
        )
        let key = SymmetricKey(data: config.sharedSecret)
        guard HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: clientTranscript, using: key) else {
            throw AuthError.invalidTag
        }
        let serverTranscript = MutualAuthProtocol.transcript(
            .serverAuth, config: config, clientRole: config.localRole.opposite,
            clientNonce: clientNonce, serverNonce: serverNonce
        )
        let response = Data(HMAC<SHA256>.authenticationCode(for: serverTranscript, using: key))
        return MutualAuthProtocol.encode(.serverAuth, config: config, body: response)
    }
}

public struct CentralAuthSession: Sendable {
    private enum State: Sendable {
        case awaitingHello
        case awaitingServer(clientNonce: Data, serverNonce: Data)
        case consumed
    }

    private var state = State.awaitingHello
    private let config: PairConfiguration
    private let startedAt: Date
    private let timeout: TimeInterval

    public init(configuration: PairConfiguration, now: Date = Date(),
                timeout: TimeInterval = BLEConstants.authTimeoutSeconds) {
        config = configuration
        startedAt = now
        self.timeout = timeout
    }

    public mutating func receiveServerHello(_ data: Data, now: Date = Date()) throws -> Data {
        guard case .awaitingHello = state else { throw AuthError.invalidState }
        state = .consumed
        guard config.isValid else { throw AuthError.invalidConfiguration }
        try MutualAuthProtocol.checkDeadline(now, startedAt: startedAt, timeout: timeout)
        let serverNonce = try MutualAuthProtocol.decode(data, as: .serverHello, config: config)
        let clientNonce = MutualAuthProtocol.randomBytes(count: MutualAuthProtocol.nonceLength)
        let transcript = MutualAuthProtocol.transcript(
            .clientAuth, config: config, clientRole: config.localRole,
            clientNonce: clientNonce, serverNonce: serverNonce
        )
        let key = SymmetricKey(data: config.sharedSecret)
        let tag = Data(HMAC<SHA256>.authenticationCode(for: transcript, using: key))
        state = .awaitingServer(clientNonce: clientNonce, serverNonce: serverNonce)
        return MutualAuthProtocol.encode(.clientAuth, config: config, body: clientNonce + tag)
    }

    public mutating func receiveServerAuth(_ data: Data, now: Date = Date()) throws {
        guard case let .awaitingServer(clientNonce, serverNonce) = state else { throw AuthError.invalidState }
        state = .consumed
        try MutualAuthProtocol.checkDeadline(now, startedAt: startedAt, timeout: timeout)
        let tag = try MutualAuthProtocol.decode(data, as: .serverAuth, config: config)
        let transcript = MutualAuthProtocol.transcript(
            .serverAuth, config: config, clientRole: config.localRole,
            clientNonce: clientNonce, serverNonce: serverNonce
        )
        guard HMAC<SHA256>.isValidAuthenticationCode(
            tag, authenticating: transcript, using: SymmetricKey(data: config.sharedSecret)
        ) else {
            throw AuthError.invalidTag
        }
    }
}
