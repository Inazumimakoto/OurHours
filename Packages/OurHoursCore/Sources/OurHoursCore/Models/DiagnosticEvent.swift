import Foundation

public enum EventCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case lifecycle, central, peripheral, auth, session, storage, settings
}

public struct DiagnosticEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: EventCategory
    public let kind: String
    public let message: String
    public let metadata: [String: String]
    public let batteryLevel: Float?
    public let appState: String?

    public init(
        id: UUID = UUID(), timestamp: Date = Date(), category: EventCategory,
        kind: String, message: String, metadata: [String: String] = [:],
        batteryLevel: Float? = nil, appState: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.kind = kind
        self.message = message
        self.metadata = metadata
        self.batteryLevel = batteryLevel
        self.appState = appState
    }
}
