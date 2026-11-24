import CoreBluetooth
import Foundation
import Synchronization
import Testing
@testable import OurHoursCore

private final class FailableSecretStorage: SecretStorage {
    private struct State {
        var data: Data?
        var shouldFailDelete = false
    }

    private struct MockDeleteError: Error {}
    private let state = Mutex(State())

    func setShouldFailDelete(_ fail: Bool) {
        state.withLock { $0.shouldFailDelete = fail }
    }

    func load() -> Data? {
        state.withLock { $0.data }
    }

    func save(_ value: Data) {
        state.withLock { $0.data = value }
    }

    func delete() throws {
        try state.withLock {
            if $0.shouldFailDelete { throw MockDeleteError() }
            $0.data = nil
        }
    }
}

private final class LoadFailableSecretStorage: SecretStorage {
    private struct State {
        var data: Data?
        var shouldFailLoad = false
    }

    private struct MockLoadError: Error {}
    private let state = Mutex(State())

    func setShouldFailLoad(_ fail: Bool) {
        state.withLock { $0.shouldFailLoad = fail }
    }

    func load() throws -> Data? {
        try state.withLock {
            if $0.shouldFailLoad { throw MockLoadError() }
            return $0.data
        }
    }

    func save(_ value: Data) {
        state.withLock { $0.data = value }
    }

    func delete() {
        state.withLock { $0.data = nil }
    }
}

struct OurHoursBLEEngineTests {
    @Test func controlsPersistAndBroadcastSnapshots() async throws {
        let suite = "OurHoursCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStorage = InMemorySecretStorage()
        let configStore = PairConfigStore(secretStorage: secretStorage, userDefaults: defaults)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logStore = EncounterLogStore(directory: directory)
        let engine = OurHoursBLEEngine(configStore: configStore, logStore: logStore, enableStateRestoration: false)

        var firstObserver = engine.snapshotStream().makeAsyncIterator()
        var secondObserver = engine.snapshotStream().makeAsyncIterator()
        let initial = await firstObserver.next()
        #expect(initial?.isPaired == false)
        #expect(initial?.isAutoRecordingEnabled == true)

        let (configuration, _) = PairingPayloadCodec.makePairingBundle()
        engine.configurePair(configuration)
        let firstUpdate = await firstObserver.next()
        let secondUpdate = await secondObserver.next()
        #expect(firstUpdate?.pairConfiguration == configuration)
        #expect(secondUpdate == firstUpdate)
        #expect(try configStore.loadPairConfiguration() == configuration)

        engine.setAutoRecordingEnabled(false)
        let updated = await firstObserver.next()
        #expect(updated?.isAutoRecordingEnabled == false)
        #expect(!PairConfigStore(secretStorage: secretStorage, userDefaults: defaults).isAutoRecordingEnabled)
        engine.unpair()
        #expect(!engine.currentSnapshot().isPaired)
        #expect(try configStore.loadPairConfiguration() == nil)
    }

    @Test func simulatedRestartReconcilesPersistedSession() throws {
        let suite = "OurHoursCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configStore = PairConfigStore(secretStorage: InMemorySecretStorage(), userDefaults: defaults)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logStore = EncounterLogStore(directory: directory)
        let (configuration, _) = PairingPayloadCodec.makePairingBundle()
        try configStore.savePairConfiguration(configuration)
        let active = EncounterSession(
            pairID: configuration.pairID, startedAt: Date(), connectionPath: .scanDiscovery, startRole: .central
        )
        try logStore.saveSessions([active])
        let engine = OurHoursBLEEngine(configStore: configStore, logStore: logStore, enableStateRestoration: false)

        engine.simulateEngineRestart()
        let saved = try #require(try logStore.loadSessions().first)
        #expect(saved.id == active.id)
        #expect(saved.status == .unknownEnd)
        #expect(saved.endedAt == nil)
        #expect(saved.endReason == .terminatedWhileActive)
        #expect(engine.currentSnapshot().activeSession == nil)

        engine.clearLogs()
        #expect(engine.currentSnapshot().recentEvents.isEmpty)
        #expect(engine.currentSnapshot().sessions.isEmpty)
        #expect(try logStore.loadSessions().isEmpty)
        #expect(try logStore.recentEvents().isEmpty)
    }

    @Test func failedUnpairKeepsPairRetryableAndDisablesRecordingUntilRetrySucceeds() throws {
        let suite = "OurHoursCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStorage = FailableSecretStorage()
        let configStore = PairConfigStore(secretStorage: secretStorage, userDefaults: defaults)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logStore = EncounterLogStore(directory: directory)
        let engine = OurHoursBLEEngine(configStore: configStore, logStore: logStore, enableStateRestoration: false)

        let (configuration, _) = PairingPayloadCodec.makePairingBundle()
        engine.configurePair(configuration)
        #expect(engine.currentSnapshot().isPaired)
        #expect(engine.currentSnapshot().isAutoRecordingEnabled)

        secretStorage.setShouldFailDelete(true)
        engine.unpair()
        let failedSnapshot = engine.currentSnapshot()
        #expect(failedSnapshot.isPaired)
        #expect(failedSnapshot.pairConfiguration == configuration)
        #expect(!failedSnapshot.isAutoRecordingEnabled)
        #expect(failedSnapshot.lastErrorMessage != nil)
        #expect(try configStore.loadPairConfiguration() == configuration)

        secretStorage.setShouldFailDelete(false)
        engine.unpair()
        let retriedSnapshot = engine.currentSnapshot()
        #expect(!retriedSnapshot.isPaired)
        #expect(retriedSnapshot.pairConfiguration == nil)
        #expect(try configStore.loadPairConfiguration() == nil)
    }

    @Test func bleTimingAndAuthCooldownClassification() throws {
        #expect(BLEConstants.authTimeoutSeconds < 10)
        #expect(BLEConstants.authTimeoutSeconds == 6)
        #expect(BLEConstants.launchReconnectGraceSeconds == 25)
        #expect(BLEConstants.activeSessionHeartbeatSeconds == 180)
        #expect(BLEConstants.terminatedSessionResumeWindowSeconds == 600)
        #expect(BLEConstants.knownPeerConnectionFailureCooldownSeconds == 10)
        #expect(BLEConstants.knownPeerAuthFailureCooldownSeconds == 10)
        #expect(
            BLEConstants.authTimeoutSeconds
                + BLEConstants.knownPeerAuthFailureCooldownSeconds
                + BLEConstants.authTimeoutSeconds < BLEConstants.launchReconnectGraceSeconds
        )

        #if DEBUG
        #expect(BLEConstants.isDebugChannel)
        #expect(BLEConstants.serviceUUID == CBUUID(string: BLEConstants.devServiceUUIDString))
        #expect(BLEConstants.serviceUUID != CBUUID(string: BLEConstants.productionServiceUUIDString))
        #expect(BLEConstants.authCharacteristicUUID == CBUUID(string: BLEConstants.devAuthCharacteristicUUIDString))
        #expect(BLEConstants.authCharacteristicUUID != CBUUID(string: BLEConstants.productionAuthCharacteristicUUIDString))
        #expect(BLEConstants.centralRestoreIdentifier.contains(".dev."))
        #expect(BLEConstants.peripheralRestoreIdentifier.contains(".dev."))
        #else
        #expect(!BLEConstants.isDebugChannel)
        #expect(BLEConstants.serviceUUID == CBUUID(string: BLEConstants.productionServiceUUIDString))
        #expect(BLEConstants.authCharacteristicUUID == CBUUID(string: BLEConstants.productionAuthCharacteristicUUIDString))
        #expect(!BLEConstants.centralRestoreIdentifier.contains(".dev."))
        #expect(!BLEConstants.peripheralRestoreIdentifier.contains(".dev."))
        #endif

        let invalidHandle = NSError(domain: CBATTErrorDomain, code: CBATTError.invalidHandle.rawValue)
        let otherATT = NSError(domain: CBATTErrorDomain, code: CBATTError.readNotPermitted.rawValue)
        let genericError = NSError(domain: "OurHoursTest", code: 1)
        #expect(OurHoursBLEEngine.isInvalidHandleError(invalidHandle))
        #expect(!OurHoursBLEEngine.isInvalidHandleError(otherATT))
        #expect(!OurHoursBLEEngine.isInvalidHandleError(genericError))

        let knownID = UUID()
        let unknownID = UUID()
        #expect(OurHoursBLEEngine.authFailureCooldown(for: knownID, lastAuthenticatedPeripheralID: knownID, error: AuthError.expired) == 10)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: knownID, lastAuthenticatedPeripheralID: knownID, error: invalidHandle) == 10)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: knownID, lastAuthenticatedPeripheralID: knownID, error: genericError) == 10)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: knownID, lastAuthenticatedPeripheralID: knownID, error: AuthError.invalidTag) == 300)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: knownID, lastAuthenticatedPeripheralID: knownID, error: AuthError.wrongKeyEpoch) == 300)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: unknownID, lastAuthenticatedPeripheralID: knownID, error: AuthError.expired) == 300)
        #expect(OurHoursBLEEngine.authFailureCooldown(for: unknownID, lastAuthenticatedPeripheralID: nil, error: invalidHandle) == 300)
    }

    @Test func foregroundActivationRunsSafelyForUnpairedAndPairedEngines() throws {
        let suite = "OurHoursCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configStore = PairConfigStore(secretStorage: InMemorySecretStorage(), userDefaults: defaults)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logStore = EncounterLogStore(directory: directory)
        let engine = OurHoursBLEEngine(configStore: configStore, logStore: logStore, enableStateRestoration: false)

        engine.handleForegroundActivation()
        #expect(!engine.currentSnapshot().isPaired)

        let (configuration, _) = PairingPayloadCodec.makePairingBundle()
        engine.configurePair(configuration)
        engine.handleForegroundActivation()
        #expect(engine.currentSnapshot().isPaired)
        #expect(engine.currentSnapshot().recentEvents.contains { $0.kind == "foregroundRefresh" })

        engine.handleBackgroundWake(source: "locationVisit")
        #expect(engine.currentSnapshot().recentEvents.contains {
            $0.kind == "backgroundWake" && $0.metadata["source"] == "locationVisit"
        })
    }

    @Test func pendingPurgeQueuePersistsUntilExplicitRemoval() throws {
        let pending = InMemorySecretStorage(), credentials = InMemorySecretStorage()
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = PairingPayloadCodec.makePairingBundle().localConfiguration
        let updated = config.withCloudShareURL("https://icloud.com/share/test")
        let second = try PairingPayloadCodec.decode(PairingPayloadCodec.encode(config, for: config.localRole.opposite))
        func engine() -> OurHoursBLEEngine {
            OurHoursBLEEngine(configStore: PairConfigStore(secretStorage: credentials, pendingPurgeStorage: pending),
                              logStore: EncounterLogStore(directory: directory), enableStateRestoration: false)
        }
        let original = engine()
        original.enqueuePendingPurge(config)
        original.enqueuePendingPurge(second)
        original.enqueuePendingPurge(updated)
        let restarted = engine()
        #expect(restarted.loadPendingPurges() == [updated, second])
        restarted.removePendingPurge(config)
        #expect(original.loadPendingPurges() == [second])
        restarted.removePendingPurge(second)
        #expect(original.loadPendingPurges().isEmpty && pending.load() == nil)
    }

    @Test func engineImportsRecoveredOwnSessionsWithoutDisturbingActiveSession() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = EncounterLogStore(directory: directory)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let active = EncounterSession(pairID: UUID(), startedAt: time, connectionPath: .scanDiscovery, startRole: .central)
        var collision = active
        collision.status = .completed
        collision.endedAt = time.addingTimeInterval(60)
        let historical = EncounterSession(pairID: active.pairID, startedAt: time.addingTimeInterval(-3600),
                                          endedAt: time, status: .completed, connectionPath: .incomingPeripheral,
                                          startRole: .central, endReason: .disconnected)
        var unknown = historical
        unknown.endedAt = nil
        unknown.status = .unknownEnd
        unknown.endReason = .terminatedWhileActive
        let other = EncounterSession(pairID: active.pairID, startedAt: time.addingTimeInterval(-7200),
                                     status: .unknownEnd, connectionPath: .scanDiscovery, startRole: .central)
        try log.saveSessions([unknown, active])
        let engine = OurHoursBLEEngine(configStore: PairConfigStore(secretStorage: InMemorySecretStorage()),
                                       logStore: log, enableStateRestoration: false)
        engine.importRecoveredSessions([collision, historical, other])
        engine.importRecoveredSessions([historical])
        #expect(engine.currentSnapshot().activeSession == active)
        #expect(engine.currentSnapshot().sessions == [other, historical, active])
        #expect(try log.loadSessions() == [other, historical, active])
    }

    @Test func reloadConfigurationIfNeededRecoversProtectedDataAfterInitialLoadFailure() async throws {
        let suite = "OurHoursCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = LoadFailableSecretStorage()
        let configStore = PairConfigStore(secretStorage: storage, userDefaults: defaults)
        let (configuration, _) = PairingPayloadCodec.makePairingBundle()
        try configStore.savePairConfiguration(configuration)

        storage.setShouldFailLoad(true)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logStore = EncounterLogStore(directory: directory)
        let engine = OurHoursBLEEngine(configStore: configStore, logStore: logStore, enableStateRestoration: false)

        var observer = engine.snapshotStream().makeAsyncIterator()
        let initial = try #require(await observer.next())
        #expect(initial.pairConfiguration == nil)
        #expect(!initial.isPaired)

        storage.setShouldFailLoad(false)
        engine.reloadConfigurationIfNeeded()

        var recovered: EngineSnapshot?
        for _ in 0..<5 {
            guard let next = await observer.next() else { break }
            recovered = next
            if next.pairConfiguration != nil && next.recentEvents.contains(where: { $0.kind == "protectedDataReloaded" }) {
                break
            }
        }
        let finalSnapshot = try #require(recovered)
        #expect(finalSnapshot.pairConfiguration == configuration)
        #expect(finalSnapshot.isPaired)
        #expect(finalSnapshot.recentEvents.contains { $0.kind == "protectedDataReloaded" })
    }
}
