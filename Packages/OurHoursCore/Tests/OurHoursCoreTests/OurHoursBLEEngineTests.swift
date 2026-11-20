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
}
