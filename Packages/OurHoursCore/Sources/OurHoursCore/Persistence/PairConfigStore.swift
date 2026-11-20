import Foundation
import Security
import Synchronization

public protocol SecretStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

public struct KeychainSecretStorage: SecretStorage {
    public struct StorageError: Error, Sendable, Equatable {
        public let status: OSStatus
    }

    private let service: String
    private let account: String

    public init(service: String = "io.github.inazumimakoto.OurHours", account: String = "pairConfiguration") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if !os(macOS)
        result[kSecUseDataProtectionKeychain as String] = true
        #endif
        return result
    }

    public func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError(status: status) }
        guard let data = item as? Data else { throw StorageError(status: errSecDecode) }
        return data
    }

    public func save(_ data: Data) throws {
        var attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        #if !os(macOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        let item = query.merging(attributes) { _, value in value }
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw StorageError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError(status: status)
        }
    }
}

public final class InMemorySecretStorage: SecretStorage {
    private let data = Mutex<Data?>(nil)

    public init() {}
    public func load() -> Data? { data.withLock { $0 } }
    public func save(_ value: Data) { data.withLock { $0 = value } }
    public func delete() { data.withLock { $0 = nil } }
}

// UserDefaults synchronizes its own reads and writes. SecretStorage must be Sendable.
public final class PairConfigStore: @unchecked Sendable {
    private let secretStorage: any SecretStorage
    private let defaults: UserDefaults
    private let recordingKey = "OurHours.isAutoRecordingEnabled"
    private let peripheralKey = "OurHours.lastAuthenticatedPeripheralID"

    public init(secretStorage: any SecretStorage = KeychainSecretStorage(), userDefaults: UserDefaults = .standard) {
        self.secretStorage = secretStorage
        defaults = userDefaults
    }

    public func loadPairConfiguration() throws -> PairConfiguration? {
        guard let data = try secretStorage.load() else { return nil }
        let config = try JSONDecoder().decode(PairConfiguration.self, from: data)
        guard config.isValid else { throw AuthError.invalidConfiguration }
        return config
    }

    public func savePairConfiguration(_ configuration: PairConfiguration) throws {
        guard configuration.isValid else { throw AuthError.invalidConfiguration }
        try secretStorage.save(JSONEncoder().encode(configuration))
    }

    public func deletePairConfiguration() throws {
        try secretStorage.delete()
    }

    public var isAutoRecordingEnabled: Bool {
        get { defaults.object(forKey: recordingKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: recordingKey) }
    }

    public var lastAuthenticatedPeripheralID: UUID? {
        get { defaults.string(forKey: peripheralKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: peripheralKey) }
    }
}
