import CryptoKit
import Foundation
import Testing
@testable import OurHoursCore

struct MutualAuthProtocolTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)
    private let pairID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
    private let key = Data(0..<32)
    private let epoch: UInt32 = 0x01020304

    private func config(_ role: PeerRole, secret: Data? = nil, epoch: UInt32? = nil) -> PairConfiguration {
        PairConfiguration(pairID: pairID, sharedSecret: secret ?? key, localRole: role, keyEpoch: epoch ?? self.epoch)
    }

    @Test(arguments: PeerRole.allCases)
    func validHandshake(role: PeerRole) throws {
        var central = CentralAuthSession(configuration: config(role), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(role.opposite), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        let client = try central.receiveServerHello(hello, now: now)
        let server = try peripheral.receiveClientAuth(client, now: now)
        try central.receiveServerAuth(server, now: now)
        #expect(hello.count == 23)
        #expect(client.count == 55)
        #expect(server.count == 39)
        #expect(Array(hello.prefix(7)) == [1, 1, role.opposite.rawValue, 1, 2, 3, 4])
        #expect(Array(client.prefix(7)) == [1, 2, role.rawValue, 1, 2, 3, 4])
        #expect(Array(server.prefix(7)) == [1, 3, role.opposite.rawValue, 1, 2, 3, 4])
    }

    @Test func matchesWireTranscript() throws {
        var central = CentralAuthSession(configuration: config(.partnerB), now: now)
        let serverNonce = Data(16..<32)
        let hello = Data([1, 1, 1, 1, 2, 3, 4]) + serverNonce
        let response = try central.receiveServerHello(hello, now: now)
        let pairBytes = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                              0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let suffix = pairBytes + Data([1, 2, 3, 4, 2, 1]) + response[7..<23] + serverNonce
        let symmetricKey = SymmetricKey(data: key)
        let clientTag = HMAC<SHA256>.authenticationCode(for: Data("OurHoursAuthV1|C2P".utf8) + suffix, using: symmetricKey)
        #expect(Data(response[23...]) == Data(clientTag))
        let serverTag = HMAC<SHA256>.authenticationCode(for: Data("OurHoursAuthV1|P2C".utf8) + suffix, using: symmetricKey)
        try central.receiveServerAuth(Data([1, 3, 1, 1, 2, 3, 4]) + Data(serverTag), now: now)
    }

    @Test func wrongSecret() throws {
        var central = CentralAuthSession(configuration: config(.partnerA, secret: Data(repeating: 99, count: 32)), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        let client = try central.receiveServerHello(hello, now: now)
        #expect(throws: AuthError.invalidTag) { try peripheral.receiveClientAuth(client, now: now) }
        #expect(throws: AuthError.invalidState) { try peripheral.receiveClientAuth(client, now: now) }
    }

    @Test func tamperedServerTag() throws {
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        let client = try central.receiveServerHello(hello, now: now)
        let server = try peripheral.receiveClientAuth(client, now: now)
        var tampered = server
        tampered[38] ^= 1
        #expect(throws: AuthError.invalidTag) { try central.receiveServerAuth(tampered, now: now) }
        #expect(throws: AuthError.invalidState) { try central.receiveServerAuth(server, now: now) }
    }

    @Test func wrongRole() throws {
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerA), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        #expect(throws: AuthError.wrongRole) { try central.receiveServerHello(hello, now: now) }
    }

    @Test func wrongEpoch() throws {
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB, epoch: 1), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        #expect(throws: AuthError.wrongKeyEpoch) { try central.receiveServerHello(hello, now: now) }
    }

    @Test func replayedClientAuthAndConsumedNonces() throws {
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        #expect(throws: AuthError.invalidState) { try peripheral.makeServerHello(now: now) }
        let client = try central.receiveServerHello(hello, now: now)
        #expect(throws: AuthError.invalidState) { try central.receiveServerHello(hello, now: now) }
        let server = try peripheral.receiveClientAuth(client, now: now)
        try central.receiveServerAuth(server, now: now)
        #expect(throws: AuthError.invalidState) { try central.receiveServerAuth(server, now: now) }
        #expect(throws: AuthError.invalidState) { try peripheral.receiveClientAuth(client, now: now) }

        var freshPeripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let freshHello = try freshPeripheral.makeServerHello(now: now)
        #expect(freshHello != hello)
        #expect(throws: AuthError.invalidTag) { try freshPeripheral.receiveClientAuth(client, now: now) }
    }

    @Test func expiredNonce() throws {
        var central = CentralAuthSession(configuration: config(.partnerA), now: now, timeout: 2)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now, timeout: 2)
        let hello = try peripheral.makeServerHello(now: now)
        let client = try central.receiveServerHello(hello, now: now.addingTimeInterval(1))
        #expect(throws: AuthError.expired) { try peripheral.receiveClientAuth(client, now: now.addingTimeInterval(2)) }

        var freshPeripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        _ = try freshPeripheral.makeServerHello(now: now)
        var secondCentral = CentralAuthSession(configuration: config(.partnerA), now: now, timeout: 2)
        #expect(throws: AuthError.expired) { try secondCentral.receiveServerHello(hello, now: now.addingTimeInterval(2)) }
    }

    @Test(arguments: [-1, 1])
    func rejectsMalformedLengths(delta: Int) throws {
        func malformed(_ data: Data) -> Data {
            delta < 0 ? Data(data.dropLast()) : data + Data([0])
        }
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        var freshCentral = CentralAuthSession(configuration: config(.partnerA), now: now)
        #expect(throws: AuthError.invalidLength) { try freshCentral.receiveServerHello(malformed(hello), now: now) }
        let client = try central.receiveServerHello(hello, now: now)
        var freshPeripheral = peripheral
        #expect(throws: AuthError.invalidLength) { try freshPeripheral.receiveClientAuth(malformed(client), now: now) }
        let server = try peripheral.receiveClientAuth(client, now: now)
        #expect(throws: AuthError.invalidLength) { try central.receiveServerAuth(malformed(server), now: now) }
    }

    @Test func rejectsUnsupportedVersionAndWrongType() throws {
        var peripheral = PeripheralAuthSession(configuration: config(.partnerB), now: now)
        let hello = try peripheral.makeServerHello(now: now)
        var central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var unsupported = hello
        unsupported[0] = 2
        #expect(throws: AuthError.unsupportedVersion) { try central.receiveServerHello(unsupported, now: now) }
        central = CentralAuthSession(configuration: config(.partnerA), now: now)
        var wrongType = hello
        wrongType[1] = 2
        #expect(throws: AuthError.unexpectedMessage) { try central.receiveServerHello(wrongType, now: now) }
    }
}
