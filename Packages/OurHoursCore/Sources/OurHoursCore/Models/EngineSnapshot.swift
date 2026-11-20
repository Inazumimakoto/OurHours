import Foundation

public struct EngineSnapshot: Sendable, Equatable {
    public var isPaired: Bool
    public var pairConfiguration: PairConfiguration?
    public var isAutoRecordingEnabled: Bool
    public var centralState: String
    public var peripheralState: String
    public var isScanning: Bool
    public var isAdvertising: Bool
    public var activeLinkCount: Int
    public var activeLinksSummary: [String]
    public var activeSession: EncounterSession?
    public var sessions: [EncounterSession]
    public var recentEvents: [DiagnosticEvent]
    public var lastConnectionPath: ConnectionPath?
    public var lastAuthenticatedPeripheralID: UUID?
    public var lastAuthDate: Date?
    public var lastErrorMessage: String?
    public var advertisingOverrideEnabled: Bool
    public var scanningOverrideEnabled: Bool

    public init(
        isPaired: Bool = false, pairConfiguration: PairConfiguration? = nil,
        isAutoRecordingEnabled: Bool = true, centralState: String = "unknown",
        peripheralState: String = "unknown", isScanning: Bool = false, isAdvertising: Bool = false,
        activeLinkCount: Int = 0, activeLinksSummary: [String] = [], activeSession: EncounterSession? = nil,
        sessions: [EncounterSession] = [], recentEvents: [DiagnosticEvent] = [],
        lastConnectionPath: ConnectionPath? = nil, lastAuthenticatedPeripheralID: UUID? = nil,
        lastAuthDate: Date? = nil, lastErrorMessage: String? = nil,
        advertisingOverrideEnabled: Bool = true, scanningOverrideEnabled: Bool = true
    ) {
        self.isPaired = isPaired
        self.pairConfiguration = pairConfiguration
        self.isAutoRecordingEnabled = isAutoRecordingEnabled
        self.centralState = centralState
        self.peripheralState = peripheralState
        self.isScanning = isScanning
        self.isAdvertising = isAdvertising
        self.activeLinkCount = activeLinkCount
        self.activeLinksSummary = activeLinksSummary
        self.activeSession = activeSession
        self.sessions = sessions
        self.recentEvents = recentEvents
        self.lastConnectionPath = lastConnectionPath
        self.lastAuthenticatedPeripheralID = lastAuthenticatedPeripheralID
        self.lastAuthDate = lastAuthDate
        self.lastErrorMessage = lastErrorMessage
        self.advertisingOverrideEnabled = advertisingOverrideEnabled
        self.scanningOverrideEnabled = scanningOverrideEnabled
    }
}
