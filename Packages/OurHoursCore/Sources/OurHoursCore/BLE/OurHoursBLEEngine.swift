import CoreBluetooth
import Foundation

/// CoreBluetooth objects and mutable engine state are confined to `queue`.
public final class OurHoursBLEEngine: NSObject, @unchecked Sendable {
    private final class CentralPeer {
        enum Phase: Equatable {
            case connecting, reconnecting, authenticating, authenticated, cancelling
        }

        let peripheral: CBPeripheral
        var path: ConnectionPath
        var phase = Phase.connecting
        var handshake: CentralAuthSession?
        var timeoutID: UUID?
        var legacyDisconnectID: UUID?
        var characteristic: CBCharacteristic?
        var wasRestored = false
        var restoredCleanupID: UUID?
        var awaitingServerAuth = false

        init(_ peripheral: CBPeripheral, path: ConnectionPath) {
            self.peripheral = peripheral
            self.path = path
        }
    }

    private struct PeripheralPeer {
        let central: CBCentral
        var handshake: PeripheralAuthSession?
        var timeoutID: UUID?
        var pending: Data?
        var pendingCompletesAuth = false
        var path: ConnectionPath
    }

    private let queue = DispatchQueue(label: "io.github.inazumimakoto.OurHours.ble")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let configStore: PairConfigStore
    private let logStore: EncounterLogStore
    private let metrics = DeviceMetricsProvider()
    private let enableStateRestoration: Bool

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var pairConfiguration: PairConfiguration?
    private var isAutoRecordingEnabled = true
    private var scanningOverrideEnabled = true
    private var advertisingOverrideEnabled = true
    private var coordinator = SessionCoordinator()
    private var events: [DiagnosticEvent] = []
    private var continuations: [UUID: AsyncStream<EngineSnapshot>.Continuation] = [:]
    private var lastConnectionPath: ConnectionPath?
    private var lastAuthenticatedPeripheralID: UUID?
    private var lastAuthDate: Date?
    private var lastErrorMessage: String?
    private var centralPeers: [UUID: CentralPeer] = [:]
    private var cooldowns: [UUID: DispatchTime] = [:]
    private var peripheralPeers: [UUID: PeripheralPeer] = [:]
    private var service: CBMutableService?
    private var authCharacteristic: CBMutableCharacteristic?
    private var servicePublished = false
    private var advertisingStarting = false
    private var restoredCentrals: [CBCentral] = []
    private var centralStateReceived = false
    private var peripheralStateReceived = false
    private var launchReconciled = false
    private static let eventLimit = 200

    public init(
        configStore: PairConfigStore = PairConfigStore(), logStore: EncounterLogStore = EncounterLogStore(),
        enableStateRestoration: Bool
    ) {
        self.configStore = configStore
        self.logStore = logStore
        self.enableStateRestoration = enableStateRestoration
        super.init()
        queue.setSpecific(key: queueKey, value: true)
        onQueue {
            loadStores()
        }
    }

    deinit {
        onQueue {
            for continuation in continuations.values { continuation.finish() }
        }
    }

    public func start() {
        onQueue {
            guard centralManager == nil else { return }
            record(.lifecycle, "started", "Started BLE engine.")
            let centralOptions: [String: Any]? = enableStateRestoration
                ? [CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralRestoreIdentifier] : nil
            let peripheralOptions: [String: Any]? = enableStateRestoration
                ? [CBPeripheralManagerOptionRestoreIdentifierKey: BLEConstants.peripheralRestoreIdentifier] : nil
            centralManager = CBCentralManager(delegate: self, queue: queue, options: centralOptions)
            peripheralManager = CBPeripheralManager(delegate: self, queue: queue, options: peripheralOptions)
            queue.asyncAfter(deadline: .now() + 2 * BLEConstants.authTimeoutSeconds) { [weak self] in
                self?.finishLaunch()
                self?.publish()
            }
            publish()
        }
    }

    public func currentSnapshot() -> EngineSnapshot {
        onQueue { makeSnapshot() }
    }

    public func snapshotStream() -> AsyncStream<EngineSnapshot> {
        onQueue {
            let id = UUID()
            let (stream, continuation) = AsyncStream.makeStream(
                of: EngineSnapshot.self, bufferingPolicy: .bufferingNewest(1)
            )
            continuation.onTermination = { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
            continuations[id] = continuation
            continuation.yield(makeSnapshot())
            return stream
        }
    }

    public func configurePair(_ config: PairConfiguration) {
        onQueue {
            defer { publish() }
            do {
                try configStore.savePairConfiguration(config)
            } catch {
                recordError(.storage, "pairSaveFailed", error)
                return
            }
            cooldowns.removeAll()
            let credentialsChanged = pairConfiguration.map {
                $0.pairID != config.pairID || $0.keyEpoch != config.keyEpoch
                    || $0.localRole != config.localRole || $0.sharedSecret != config.sharedSecret
            } ?? true
            if credentialsChanged {
                stopRecording(reason: .unpaired)
                resetPeerHistory()
            }
            pairConfiguration = config
            record(.settings, "pairConfigured", "Saved pair configuration.")
            refreshRadios()
        }
    }

    public func unpair() {
        onQueue {
            defer { publish() }
            stopRecording(reason: .unpaired)
            cooldowns.removeAll()
            do {
                try configStore.deletePairConfiguration()
                pairConfiguration = nil
                resetPeerHistory()
                record(.settings, "unpaired", "Removed pair configuration.")
            } catch {
                // Keep pairConfiguration non-nil so the UI stays retryable, while disabling recording.
                configStore.isAutoRecordingEnabled = false
                isAutoRecordingEnabled = false
                recordError(.storage, "pairDeleteFailed", error)
            }
        }
    }

    public func setAutoRecordingEnabled(_ enabled: Bool) {
        onQueue {
            guard enabled != isAutoRecordingEnabled else { return }
            configStore.isAutoRecordingEnabled = enabled
            isAutoRecordingEnabled = enabled
            if enabled {
                refreshRadios()
            } else {
                stopRecording(reason: .autoRecordingDisabled)
            }
            record(.settings, "autoRecordingChanged", "Automatic recording changed.", metadata: ["enabled": String(enabled)])
            publish()
        }
    }

    public func setAdvertisingOverride(_ enabled: Bool) {
        onQueue {
            guard enabled != advertisingOverrideEnabled else { return }
            advertisingOverrideEnabled = enabled
            refreshPeripheral()
            record(.settings, "advertisingOverrideChanged", "Advertising override changed.", metadata: ["enabled": String(enabled)])
            publish()
        }
    }

    public func setScanningOverride(_ enabled: Bool) {
        onQueue {
            guard enabled != scanningOverrideEnabled else { return }
            scanningOverrideEnabled = enabled
            refreshCentral(lookup: enabled)
            record(.settings, "scanningOverrideChanged", "Scanning override changed.", metadata: ["enabled": String(enabled)])
            publish()
        }
    }

    public func simulateDisconnect() {
        onQueue {
            stopRecording(reason: .manualDisconnect)
            record(.lifecycle, "simulatedDisconnect", "Simulated a BLE disconnect.")
            refreshRadios()
            publish()
        }
    }

    public func simulateEngineRestart() {
        onQueue {
            defer { publish() }
            let savedSessions: [EncounterSession]
            do {
                savedSessions = try logStore.loadSessions()
            } catch {
                recordError(.storage, "sessionsLoadFailed", error)
                return
            }
            tearDownLinks()
            cooldowns.removeAll()
            coordinator = SessionCoordinator(sessions: savedSessions)
            launchReconciled = false
            finishLaunch()
            lastConnectionPath = nil
            lastAuthDate = nil
            record(.lifecycle, "simulatedRestart", "Simulated a restart without restored links.")
            refreshRadios()
        }
    }

    public func clearLogs() {
        onQueue {
            defer { publish() }
            do {
                try logStore.clearLogs()
                tearDownLinks()
                coordinator = SessionCoordinator()
                events.removeAll()
                lastErrorMessage = nil
                lastConnectionPath = nil
                lastAuthDate = nil
                refreshRadios()
            } catch {
                recordError(.storage, "clearLogsFailed", error)
            }
        }
    }

    public func exportJSONData() -> Data {
        onQueue { logStore.exportJSONData(pairConfiguration: pairConfiguration) }
    }

    public func exportSessionsCSVData() -> Data {
        onQueue { logStore.exportSessionsCSVData() }
    }

    public func exportEventsCSVData() -> Data {
        onQueue { logStore.exportEventsCSVData() }
    }

    private func onQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return operation() }
        return queue.sync(execute: operation)
    }

    private var canRecord: Bool {
        pairConfiguration != nil && isAutoRecordingEnabled
    }

    private func loadStores() {
        isAutoRecordingEnabled = configStore.isAutoRecordingEnabled
        lastAuthenticatedPeripheralID = configStore.lastAuthenticatedPeripheralID
        var failures: [(String, any Error)] = []
        do {
            events = try logStore.recentEvents(limit: Self.eventLimit)
        } catch {
            failures.append(("eventsLoadFailed", error))
        }
        do {
            coordinator = SessionCoordinator(sessions: try logStore.loadSessions())
        } catch {
            failures.append(("sessionsLoadFailed", error))
        }
        do {
            pairConfiguration = try configStore.loadPairConfiguration()
        } catch {
            failures.append(("pairLoadFailed", error))
        }
        for (kind, error) in failures { recordError(.storage, kind, error) }
    }

    private func makeSnapshot() -> EngineSnapshot {
        EngineSnapshot(
            isPaired: pairConfiguration != nil, pairConfiguration: pairConfiguration,
            isAutoRecordingEnabled: isAutoRecordingEnabled,
            centralState: centralManager?.state.description ?? "unknown",
            peripheralState: peripheralManager?.state.description ?? "unknown",
            isScanning: centralManager?.isScanning ?? false, isAdvertising: peripheralManager?.isAdvertising ?? false,
            activeLinkCount: coordinator.activeLinks.count,
            activeLinksSummary: coordinator.activeLinks.map { "\($0.role.rawValue): \($0.peerID.uuidString)" }.sorted(),
            activeSession: coordinator.activeSession, sessions: coordinator.sessions, recentEvents: events,
            lastConnectionPath: lastConnectionPath, lastAuthenticatedPeripheralID: lastAuthenticatedPeripheralID,
            lastAuthDate: lastAuthDate, lastErrorMessage: lastErrorMessage,
            advertisingOverrideEnabled: advertisingOverrideEnabled, scanningOverrideEnabled: scanningOverrideEnabled
        )
    }

    private func publish() {
        guard !continuations.isEmpty else { return }
        let snapshot = makeSnapshot()
        for continuation in continuations.values { continuation.yield(snapshot) }
    }

    private func record(_ category: EventCategory, _ kind: String, _ message: String,
                        at: Date = Date(), metadata: [String: String] = [:]) {
        let event = DiagnosticEvent(
            timestamp: at, category: category, kind: kind, message: message, metadata: metadata,
            batteryLevel: metrics.batteryLevel(), appState: metrics.appStateDescription()
        )
        events.append(event)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
        do {
            try logStore.appendEvent(event)
        } catch {
            lastErrorMessage = "Could not save diagnostic event: \(error.localizedDescription)"
        }
    }

    private func recordError(_ category: EventCategory, _ kind: String, _ error: any Error,
                             metadata: [String: String] = [:]) {
        let message = error is AuthError ? String(describing: error) : error.localizedDescription
        lastErrorMessage = message
        record(category, kind, message, metadata: metadata)
    }

    private func persistSessions() {
        do {
            try logStore.saveSessions(coordinator.sessions)
        } catch {
            recordError(.storage, "sessionsSaveFailed", error)
        }
    }

    private func reconcileLaunchIfReady() {
        guard centralStateReceived, peripheralStateReceived,
              !centralPeers.values.contains(where: { $0.path == .restoredConnection && $0.phase == .authenticating }),
              !centralPeers.values.contains(where: { $0.restoredCleanupID != nil }),
              restoredCentrals.isEmpty,
              !peripheralPeers.values.contains(where: { $0.path == .restoredConnection && $0.timeoutID != nil }) else {
            return
        }
        finishLaunch()
    }

    private func finishLaunch(restoredLink: ActiveLinkKey? = nil) {
        guard !launchReconciled else { return }
        launchReconciled = true
        guard let session = coordinator.activeSession else { return }
        let links: Set<ActiveLinkKey>
        if let restoredLink, session.pairID == pairConfiguration?.pairID {
            links = [restoredLink]
        } else {
            links = []
        }
        coordinator.reconcileActiveSessionsOnLaunch(now: Date(), restoredActiveLinks: links)
        persistSessions()
        record(.session, "launchReconciled", "Reconciled the previous active session.",
               metadata: ["restored": String(!links.isEmpty)])
    }

    private func authenticated(_ link: ActiveLinkKey, path: ConnectionPath) {
        guard let pairID = pairConfiguration?.pairID, canRecord else { return }
        if path == .restoredConnection {
            finishLaunch(restoredLink: link)
        } else {
            reconcileLaunchIfReady()
        }
        let now = Date()
        lastAuthDate = now
        lastConnectionPath = path
        if link.role == .central {
            lastAuthenticatedPeripheralID = link.peerID
            configStore.lastAuthenticatedPeripheralID = link.peerID
        }
        record(.auth, "authenticated", "Authenticated BLE peer.",
               metadata: ["peerID": link.peerID.uuidString, "role": link.role.rawValue, "path": path.rawValue])
        if let session = coordinator.linkAuthenticated(
            link, pairID: pairID, at: now, connectionPath: path, batteryLevel: metrics.batteryLevel()
        ) {
            persistSessions()
            record(.session, "sessionStarted", "Started an encounter.", at: now, metadata: ["id": session.id.uuidString])
        }
    }

    private func disconnected(
        _ link: ActiveLinkKey, at: Date = Date(), reason: SessionEndReason,
        errorDescription: String? = nil, isReconnecting: Bool? = nil
    ) {
        if let session = coordinator.linkDisconnected(
            link, at: at, endReason: reason, disconnectErrorDescription: errorDescription,
            isAutoReconnectPending: isReconnecting, batteryLevel: metrics.batteryLevel()
        ) {
            didComplete(session)
        }
    }

    private func didComplete(_ session: EncounterSession) {
        persistSessions()
        record(.session, "sessionCompleted", "Completed an encounter.", at: session.endedAt ?? Date(),
               metadata: ["id": session.id.uuidString, "reason": session.endReason?.rawValue ?? "unknown"])
    }

    private func stopRecording(reason: SessionEndReason) {
        finishLaunch()
        if let session = coordinator.endActiveSessionForControlChange(
            at: Date(), endReason: reason, batteryLevel: metrics.batteryLevel()
        ) {
            didComplete(session)
        }
        tearDownLinks()
    }

    private func tearDownLinks() {
        if centralManager?.state == .poweredOn {
            centralManager?.stopScan()
            for peer in centralPeers.values { cancel(peer) }
        } else {
            centralPeers.removeAll()
        }
        discardPeripheralService()
    }

    private func resetPeerHistory() {
        configStore.lastAuthenticatedPeripheralID = nil
        lastAuthenticatedPeripheralID = nil
        lastAuthDate = nil
        lastConnectionPath = nil
    }

    private func refreshRadios() {
        refreshCentral(lookup: true)
        refreshPeripheral()
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "unknown"
        }
    }
}

extension OurHoursBLEEngine: CBCentralManagerDelegate, CBPeripheralDelegate {
    private var hasAuthenticatedCentral: Bool {
        coordinator.activeLinks.contains { $0.role == .central }
    }

    private func refreshCentral(lookup: Bool) {
        guard let manager = centralManager, manager.state == .poweredOn else { return }
        guard canRecord, scanningOverrideEnabled, coordinator.activeLinks.isEmpty else {
            if manager.isScanning { manager.stopScan() }
            return
        }
        if lookup {
            if let id = lastAuthenticatedPeripheralID {
                for peripheral in manager.retrievePeripherals(withIdentifiers: [id]) {
                    connect(peripheral, path: .autoReconnect)
                }
            }
            for peripheral in manager.retrieveConnectedPeripherals(withServices: [BLEConstants.serviceUUID]) {
                connect(peripheral, path: .autoReconnect)
            }
        }
        if !manager.isScanning {
            manager.scanForPeripherals(
                withServices: [BLEConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    private func connect(_ peripheral: CBPeripheral, path: ConnectionPath) {
        let id = peripheral.identifier
        guard let manager = centralManager, !hasAuthenticatedCentral, cooldowns[id] == nil else { return }
        if centralPeers[id] != nil { return }
        let peer = CentralPeer(peripheral, path: path)
        centralPeers[id] = peer
        manager.connect(peripheral, options: [CBConnectPeripheralOptionEnableAutoReconnect: true])
        record(.central, "connectionRequested", "Requested a BLE connection.", metadata: ["peerID": id.uuidString])
    }

    private func cancel(_ peer: CentralPeer) {
        peer.restoredCleanupID = nil
        guard peer.phase != .cancelling else { return }
        let shouldRemoveImmediately = peer.peripheral.state == .disconnected
        peer.phase = .cancelling
        peer.timeoutID = nil
        peer.handshake = nil
        peer.characteristic = nil
        centralManager?.cancelPeripheralConnection(peer.peripheral)
        if shouldRemoveImmediately {
            centralPeers[peer.peripheral.identifier] = nil
        }
    }

    private func enterCooldown(_ id: UUID) {
        let deadline = DispatchTime.now() + BLEConstants.failedPeerCooldownSeconds
        cooldowns[id] = deadline
        queue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self, cooldowns[id] == deadline else { return }
            cooldowns[id] = nil
            // Discovery with duplicate filtering may already have seen this peer.
            if centralManager?.isScanning == true { centralManager?.stopScan() }
            refreshCentral(lookup: true)
            publish()
        }
    }

    private func failCentralAuth(_ peer: CentralPeer, error: any Error) {
        let id = peer.peripheral.identifier
        enterCooldown(id)
        cancel(peer)
        recordError(.auth, "centralAuthFailed", error, metadata: ["peerID": id.uuidString])
        reconcileLaunchIfReady()
        refreshCentral(lookup: false)
    }

    private func startCentralAuth(_ peer: CentralPeer) {
        guard canRecord, let pairConfiguration, !hasAuthenticatedCentral else {
            cancel(peer)
            reconcileLaunchIfReady()
            return
        }
        peer.characteristic = nil
        armCentralHandshake(peer, configuration: pairConfiguration)
        peer.peripheral.delegate = self
        peer.peripheral.discoverServices([BLEConstants.serviceUUID])
    }

    private func armCentralHandshake(_ peer: CentralPeer, configuration: PairConfiguration) {
        let id = peer.peripheral.identifier
        let token = UUID()
        peer.phase = .authenticating
        peer.timeoutID = token
        peer.awaitingServerAuth = false
        peer.handshake = CentralAuthSession(configuration: configuration)
        queue.asyncAfter(deadline: .now() + BLEConstants.authTimeoutSeconds) { [weak self] in
            guard let self, let peer = centralPeers[id], peer.timeoutID == token else { return }
            failCentralAuth(peer, error: AuthError.expired)
            publish()
        }
    }

    private func authenticatingPeer(_ peripheral: CBPeripheral) -> CentralPeer? {
        guard let peer = centralPeers[peripheral.identifier], peer.peripheral === peripheral,
              peer.phase == .authenticating else { return nil }
        return peer
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard central === centralManager else { return }
        defer { publish() }
        record(.central, "stateChanged", central.state.description)
        if central.state == .poweredOn {
            centralStateReceived = true
            for peer in Array(centralPeers.values) where peer.wasRestored && peer.phase == .connecting {
                if peer.peripheral.state == .connected && canRecord {
                    startCentralAuth(peer)
                } else if !canRecord {
                    cancel(peer)
                } else if peer.peripheral.state == .disconnected, peer.restoredCleanupID == nil {
                    let id = peer.peripheral.identifier
                    let token = UUID()
                    peer.restoredCleanupID = token
                    queue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                        guard let self, let current = centralPeers[id],
                              current.restoredCleanupID == token else { return }
                        current.restoredCleanupID = nil
                        centralPeers[id] = nil
                        reconcileLaunchIfReady()
                        refreshCentral(lookup: true)
                        publish()
                    }
                }
            }
            refreshCentral(lookup: true)
        } else if central.state != .unknown {
            centralStateReceived = central.state != .resetting
            centralPeers.removeAll()
            let now = Date()
            for link in coordinator.activeLinks where link.role == .central {
                disconnected(link, at: now, reason: .bluetoothUnavailable)
            }
        }
        reconcileLaunchIfReady()
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard central === centralManager else { return }
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals {
            peripheral.delegate = self
            let path: ConnectionPath = peripheral.state == .connected ? .restoredConnection : .autoReconnect
            let peer = CentralPeer(peripheral, path: path)
            peer.wasRestored = true
            centralPeers[peripheral.identifier] = peer
        }
        record(.lifecycle, "centralRestored", "Restored central state.", metadata: ["peers": String(peripherals.count)])
        publish()
    }

    public func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard central === centralManager, canRecord, scanningOverrideEnabled else { return }
        connect(peripheral, path: .scanDiscovery)
        publish()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === centralManager else { return }
        defer { publish() }
        guard let peer = centralPeers[peripheral.identifier], peer.peripheral === peripheral else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peer.restoredCleanupID = nil
        switch peer.phase {
        case .cancelling:
            central.cancelPeripheralConnection(peripheral)
        case .connecting, .reconnecting:
            record(.central, "connected", "Connected to BLE peripheral.",
                   metadata: ["peerID": peripheral.identifier.uuidString, "path": peer.path.rawValue])
            startCentralAuth(peer)
        case .authenticating, .authenticated:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?
    ) {
        guard central === centralManager, let peer = centralPeers[peripheral.identifier],
              peer.peripheral === peripheral else { return }
        centralPeers[peripheral.identifier] = nil
        if peer.phase != .cancelling {
            enterCooldown(peripheral.identifier)
            recordError(.central, "connectionFailed", error ?? TransportError.connectionFailed,
                        metadata: ["peerID": peripheral.identifier.uuidString])
        }
        reconcileLaunchIfReady()
        refreshCentral(lookup: true)
        publish()
    }

    public func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?
    ) {
        guard central === centralManager else { return }
        handleCentralDisconnect(
            peripheral, at: Date(timeIntervalSinceReferenceDate: timestamp), isReconnecting: isReconnecting, error: error
        )
    }

    public func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?
    ) {
        let id = peripheral.identifier
        guard central === centralManager, let peer = centralPeers[id], peer.peripheral === peripheral,
              peer.phase != .reconnecting, peer.phase != .connecting else { return }
        let token = UUID()
        let at = Date()
        peer.legacyDisconnectID = token
        // Prefer the newer callback's timestamp and reconnect flag if CoreBluetooth delivers both.
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self, let peer = centralPeers[id], peer.legacyDisconnectID == token else { return }
            handleCentralDisconnect(peer.peripheral, at: at, isReconnecting: nil, error: error)
        }
    }

    private func handleCentralDisconnect(
        _ peripheral: CBPeripheral, at: Date, isReconnecting: Bool?, error: (any Error)?
    ) {
        let id = peripheral.identifier
        guard let peer = centralPeers[id], peer.peripheral === peripheral else { return }
        if peer.phase == .reconnecting, isReconnecting != false { return }
        peer.restoredCleanupID = nil
        peer.legacyDisconnectID = nil
        if !launchReconciled, peer.wasRestored, id == lastAuthenticatedPeripheralID, coordinator.activeSession != nil {
            finishLaunch(restoredLink: .central(id))
        }
        let errorDescription = error?.localizedDescription
        disconnected(.central(id), at: at, reason: .disconnected,
                     errorDescription: errorDescription, isReconnecting: isReconnecting)
        if isReconnecting == true, peer.phase != .cancelling, canRecord {
            peer.phase = .reconnecting
            peer.path = .autoReconnect
            peer.handshake = nil
            peer.timeoutID = nil
            peer.characteristic = nil
        } else {
            if isReconnecting == true {
                // A reconnect notification may precede the callback from our cancellation.
                centralManager?.cancelPeripheralConnection(peripheral)
            }
            centralPeers[id] = nil
        }
        var metadata = ["peerID": id.uuidString]
        metadata["error"] = errorDescription
        metadata["isReconnecting"] = isReconnecting.map { String($0) }
        record(.central, "disconnected", "Disconnected from BLE peripheral.", at: at, metadata: metadata)
        reconcileLaunchIfReady()
        refreshCentral(lookup: true)
        publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let peer = authenticatingPeer(peripheral) else { return }
        defer { publish() }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
            failCentralAuth(peer, error: error ?? TransportError.serviceMissing)
            return
        }
        peripheral.discoverCharacteristics([BLEConstants.authCharacteristicUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?
    ) {
        guard let peer = authenticatingPeer(peripheral), service.uuid == BLEConstants.serviceUUID else { return }
        defer { publish() }
        guard error == nil, let characteristic = service.characteristics?.first(where: {
            $0.uuid == BLEConstants.authCharacteristicUUID && $0.properties.contains([.notify, .write])
        }) else {
            failCentralAuth(peer, error: error ?? TransportError.characteristicMissing)
            return
        }
        peer.characteristic = characteristic
        if characteristic.isNotifying {
            // Request a fresh challenge without unsubscribing a live restored partner link.
            peripheral.writeValue(Data([0x00]), for: characteristic, type: .withResponse)
        } else {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        guard let peer = authenticatingPeer(peripheral), peer.characteristic === characteristic else { return }
        defer { publish() }
        if let error {
            failCentralAuth(peer, error: error)
        } else if !characteristic.isNotifying {
            failCentralAuth(peer, error: TransportError.subscriptionFailed)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        guard let peer = centralPeers[peripheral.identifier], peer.peripheral === peripheral,
              peer.characteristic === characteristic else { return }
        if let pairConfiguration,
           (peer.phase == .authenticated || (peer.phase == .authenticating && peer.awaitingServerAuth)),
           error == nil, let value = characteristic.value,
           value.count == MutualAuthProtocol.Message.serverHello.length,
           value.dropFirst().first == MutualAuthProtocol.Message.serverHello.rawValue {
            // The peer may have restored or restarted its challenge while this link stayed up.
            if peer.phase == .authenticated {
                peer.path = .restoredConnection
            }
            armCentralHandshake(peer, configuration: pairConfiguration)
        }
        guard peer.phase == .authenticating, var handshake = peer.handshake else { return }
        defer { publish() }
        do {
            if let error { throw error }
            guard let data = characteristic.value else { throw AuthError.invalidLength }
            if peer.awaitingServerAuth {
                try handshake.receiveServerAuth(data)
                peer.phase = .authenticated
                peer.timeoutID = nil
                peer.handshake = nil
                authenticated(.central(peripheral.identifier), path: peer.path)
                for other in centralPeers.values where other !== peer { cancel(other) }
                refreshCentral(lookup: false)
            } else {
                let response = try handshake.receiveServerHello(data)
                guard response.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
                    throw TransportError.messageTooLarge
                }
                peer.handshake = handshake
                peer.awaitingServerAuth = true
                peripheral.writeValue(response, for: characteristic, type: .withResponse)
            }
        } catch {
            failCentralAuth(peer, error: error)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        guard let error, let peer = authenticatingPeer(peripheral), peer.characteristic === characteristic else { return }
        failCentralAuth(peer, error: error)
        publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let id = peripheral.identifier
        guard let peer = centralPeers[id], peer.peripheral === peripheral, peer.phase != .cancelling,
              invalidatedServices.contains(where: { $0.uuid == BLEConstants.serviceUUID }) else { return }
        disconnected(.central(id), reason: .disconnected)
        cancel(peer)
        record(.central, "serviceInvalidated", "The peer removed its OurHours service.",
               metadata: ["peerID": id.uuidString])
        reconcileLaunchIfReady()
        refreshCentral(lookup: false)
        publish()
    }
}

extension OurHoursBLEEngine: CBPeripheralManagerDelegate {
    private func refreshPeripheral() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }
        if !canRecord {
            discardPeripheralService()
            return
        }
        if service == nil {
            let characteristic = CBMutableCharacteristic(
                type: BLEConstants.authCharacteristicUUID,
                properties: [.write, .writeWithoutResponse, .notify], value: nil, permissions: [.writeable]
            )
            let newService = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
            newService.characteristics = [characteristic]
            authCharacteristic = characteristic
            service = newService
            manager.add(newService)
        }
        if advertisingOverrideEnabled, servicePublished {
            if !manager.isAdvertising, !advertisingStarting {
                advertisingStarting = true
                manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID]])
            }
        } else if manager.isAdvertising {
            manager.stopAdvertising()
        }
    }

    private func discardPeripheralService() {
        peripheralPeers.removeAll()
        restoredCentrals.removeAll()
        servicePublished = false
        authCharacteristic = nil
        if let manager = peripheralManager, manager.state == .poweredOn {
            if manager.isAdvertising { manager.stopAdvertising() }
            if let service { manager.remove(service) }
        } else {
            advertisingStarting = false
        }
        service = nil
    }

    private func startPeripheralAuth(_ central: CBCentral, path: ConnectionPath) {
        guard let pairConfiguration, canRecord, peripheralPeers[central.identifier] == nil else { return }
        let id = central.identifier
        let token = UUID()
        var handshake = PeripheralAuthSession(configuration: pairConfiguration)
        do {
            let hello = try handshake.makeServerHello()
            peripheralPeers[id] = PeripheralPeer(central: central, handshake: handshake, timeoutID: token, path: path)
            try sendNotification(hello, to: id, completesAuth: false)
        } catch {
            failPeripheralAuth(id, error: error)
            return
        }
        queue.asyncAfter(deadline: .now() + BLEConstants.authTimeoutSeconds) { [weak self] in
            guard let self, peripheralPeers[id]?.timeoutID == token else { return }
            failPeripheralAuth(id, error: AuthError.expired)
            reconcileLaunchIfReady()
            publish()
        }
    }

    private func sendNotification(_ data: Data, to id: UUID, completesAuth: Bool) throws {
        guard var peer = peripheralPeers[id], let manager = peripheralManager,
              let authCharacteristic else { throw TransportError.characteristicMissing }
        guard data.count <= peer.central.maximumUpdateValueLength else { throw TransportError.messageTooLarge }
        let sent = manager.updateValue(data, for: authCharacteristic, onSubscribedCentrals: [peer.central])
        peer.pending = sent ? nil : data
        peer.pendingCompletesAuth = !sent && completesAuth
        if sent && completesAuth { peer.timeoutID = nil }
        peripheralPeers[id] = peer
        if sent && completesAuth {
            authenticated(.peripheral(id), path: peer.path)
            refreshCentral(lookup: false)
        }
    }

    private func failPeripheralAuth(_ id: UUID, error: any Error) {
        peripheralPeers[id] = nil
        recordError(.auth, "peripheralAuthFailed", error, metadata: ["peerID": id.uuidString])
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard peripheral === peripheralManager else { return }
        defer { publish() }
        record(.peripheral, "stateChanged", peripheral.state.description)
        if peripheral.state == .poweredOn {
            peripheralStateReceived = true
            refreshPeripheral()
            let subscribed = restoredCentrals
            restoredCentrals.removeAll()
            for central in subscribed { startPeripheralAuth(central, path: .restoredConnection) }
        } else if peripheral.state != .unknown {
            peripheralStateReceived = peripheral.state != .resetting
            discardPeripheralService()
            let now = Date()
            for link in coordinator.activeLinks where link.role == .peripheral {
                disconnected(link, at: now, reason: .bluetoothUnavailable)
            }
        }
        reconcileLaunchIfReady()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        guard peripheral === peripheralManager else { return }
        let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
        if let restored = services.first(where: { $0.uuid == BLEConstants.serviceUUID }),
           let characteristic = restored.characteristics?.first(where: {
               $0.uuid == BLEConstants.authCharacteristicUUID
           }) as? CBMutableCharacteristic {
            service = restored
            authCharacteristic = characteristic
            servicePublished = true
            restoredCentrals = characteristic.subscribedCentrals ?? []
        }
        record(.lifecycle, "peripheralRestored", "Restored peripheral state.",
               metadata: ["subscribers": String(restoredCentrals.count)])
        publish()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        guard peripheral === peripheralManager, service === self.service else { return }
        if let error {
            recordError(.peripheral, "servicePublicationFailed", error)
            self.service = nil
            authCharacteristic = nil
        } else {
            servicePublished = true
            refreshPeripheral()
        }
        publish()
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: (any Error)?) {
        guard peripheral === peripheralManager else { return }
        advertisingStarting = false
        if let error {
            recordError(.peripheral, "advertisingFailed", error)
        } else if !canRecord || !advertisingOverrideEnabled {
            if peripheral.state == .poweredOn { peripheral.stopAdvertising() }
        } else {
            record(.peripheral, "advertising", "Started BLE advertising.")
        }
        publish()
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard peripheral === peripheralManager, characteristic === authCharacteristic else { return }
        startPeripheralAuth(central, path: .incomingPeripheral)
        publish()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // CoreBluetooth expects one response to the first request of a write batch.
        guard peripheral === peripheralManager, let request = requests.first else { return }
        let id = request.central.identifier
        defer {
            reconcileLaunchIfReady()
            publish()
        }
        guard requests.allSatisfy({
            $0.characteristic.uuid == BLEConstants.authCharacteristicUUID
                && $0.characteristic === authCharacteristic && $0.central.identifier == id
        }) else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        if requests.count == 1, request.offset == 0, request.value == Data([0x00]) {
            guard canRecord else {
                peripheral.respond(to: request, withResult: .insufficientAuthentication)
                return
            }
            peripheral.respond(to: request, withResult: .success)
            peripheralPeers[id] = nil
            startPeripheralAuth(request.central, path: .restoredConnection)
            return
        }
        guard canRecord, var peer = peripheralPeers[id], var handshake = peer.handshake, peer.pending == nil else {
            peripheral.respond(to: request, withResult: .insufficientAuthentication)
            return
        }
        var payload = Data()
        for part in requests.sorted(by: { $0.offset < $1.offset }) {
            guard part.offset == payload.count else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            guard let value = part.value, !value.isEmpty,
                  value.count <= MutualAuthProtocol.Message.clientAuth.length - payload.count else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                failPeripheralAuth(id, error: AuthError.invalidLength)
                return
            }
            payload.append(value)
        }
        do {
            let response = try handshake.receiveClientAuth(payload)
            guard response.count <= peer.central.maximumUpdateValueLength else { throw TransportError.messageTooLarge }
            peer.handshake = nil
            peripheralPeers[id] = peer
            peripheral.respond(to: request, withResult: .success)
            do {
                try sendNotification(response, to: id, completesAuth: true)
            } catch {
                failPeripheralAuth(id, error: error)
            }
        } catch {
            peripheral.respond(to: request, withResult: .insufficientAuthentication)
            failPeripheralAuth(id, error: error)
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard peripheral === peripheralManager, canRecord else { return }
        for id in Array(peripheralPeers.keys) {
            guard let peer = peripheralPeers[id], let data = peer.pending else { continue }
            do {
                try sendNotification(data, to: id, completesAuth: peer.pendingCompletesAuth)
                if peripheralPeers[id]?.pending != nil { break }
            } catch {
                failPeripheralAuth(id, error: error)
            }
        }
        reconcileLaunchIfReady()
        publish()
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard peripheral === peripheralManager, characteristic === authCharacteristic else { return }
        let id = central.identifier
        peripheralPeers[id] = nil
        restoredCentrals.removeAll { $0.identifier == id }
        record(.peripheral, "unsubscribed", "BLE central unsubscribed.", metadata: ["peerID": id.uuidString])
        disconnected(.peripheral(id), reason: .peerUnsubscribed)
        refreshCentral(lookup: true)
        reconcileLaunchIfReady()
        publish()
    }
}

private enum TransportError: LocalizedError {
    case connectionFailed, serviceMissing, characteristicMissing, subscriptionFailed, messageTooLarge

    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Could not connect to the BLE peripheral."
        case .serviceMissing: "The peer did not publish the OurHours service."
        case .characteristicMissing: "The peer did not publish the OurHours authentication characteristic."
        case .subscriptionFailed: "Could not subscribe to authentication notifications."
        case .messageTooLarge: "The BLE link cannot carry the authentication message."
        }
    }
}
