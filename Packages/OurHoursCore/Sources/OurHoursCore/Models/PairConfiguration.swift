import Foundation

public enum PeerRole: UInt8, Codable, Sendable, Equatable, CaseIterable {
    case partnerA = 1
    case partnerB = 2

    public var opposite: Self { self == .partnerA ? .partnerB : .partnerA }
    public var shortCode: String { self == .partnerA ? "A" : "B" }
}

public struct PairConfiguration: Codable, Sendable, Equatable {
    public let pairID: UUID
    public let sharedSecret: Data
    public let localRole: PeerRole
    public let keyEpoch: UInt32
    public let createdAt: Date
    public let displayLabel: String?

    public init(
        pairID: UUID, sharedSecret: Data, localRole: PeerRole, keyEpoch: UInt32,
        createdAt: Date = Date(), displayLabel: String? = nil
    ) {
        self.pairID = pairID
        self.sharedSecret = sharedSecret
        self.localRole = localRole
        self.keyEpoch = keyEpoch
        self.createdAt = createdAt
        self.displayLabel = displayLabel
    }

    var isValid: Bool { sharedSecret.count == 32 && keyEpoch >= 1 }
}
