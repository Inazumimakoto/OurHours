import Observation
import OurHoursCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    private let engine: OurHoursBLEEngine
    private(set) var snapshot: EngineSnapshot
    @ObservationIgnored private var subscription: Task<Void, Never>?
    @ObservationIgnored private var scheduledSyncTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledHistorySyncTask: Task<Void, Never>?

    private let journalStore: JournalStore
    private(set) var journal = JournalSnapshot()
    var journalError: String?

    private let peerSyncStore: PartnerSyncStore
    private let historySync: CloudKitHistorySync
    private(set) var peerSessions: [SyncedPeerSession] = []
    private(set) var historySyncState: HistorySyncState = .idle

    private let locationStore: LocationTimelineStore
    private let locationSync: CloudKitLocationSync
    let locationMonitor: LocationPresenceMonitor
    private(set) var locationMatchedSessions: [LocationMatchedSession] = []
    private(set) var locationSyncState: LocationSyncState = .idle

    init(
        engine: OurHoursBLEEngine,
        journalStore: JournalStore = JournalStore(),
        peerSyncStore: PartnerSyncStore = PartnerSyncStore(),
        historySync: CloudKitHistorySync = CloudKitHistorySync(),
        locationStore: LocationTimelineStore = LocationTimelineStore(),
        locationSync: CloudKitLocationSync = CloudKitLocationSync()
    ) {
        self.engine = engine
        self.journalStore = journalStore
        self.peerSyncStore = peerSyncStore
        self.historySync = historySync
        self.locationStore = locationStore
        self.locationSync = locationSync

        var sink: (@MainActor (LocationVisitRecord, Bool) -> Void)?
        var pointSink: (@MainActor (LocationPointSample) -> Void)?

        self.locationMonitor = LocationPresenceMonitor(
            onVisit: { visit, arrivalUnknown in sink?(visit, arrivalUnknown) },
            onPoint: { point in pointSink?(point) },
            onWake: { [weak engine] source in
                engine?.handleBackgroundWake(source: source)
            }
        )

        snapshot = engine.currentSnapshot()
        do { journal = try journalStore.load() }
        catch { journalError = error.localizedDescription }

        if let pairID = snapshot.pairConfiguration?.pairID,
           let cachedPeer = try? peerSyncStore.load(),
           cachedPeer.pairID == pairID {
            peerSessions = cachedPeer.sessions
        }

        if let initialLocation = try? locationStore.load() {
            locationMatchedSessions = initialLocation.matchedSessions
        }

        sink = { [weak self] visit, arrivalUnknown in
            self?.handleCapturedVisit(visit, arrivalUnknown: arrivalUnknown)
        }
        pointSink = { [weak self] point in
            self?.handleCapturedPoint(point)
        }

        let snapshots = engine.snapshotStream()
        subscription = Task { [weak self] in
            for await value in snapshots {
                guard let self else { break }
                let previousNonActive = self.snapshot.sessions.filter { $0.status != .active }
                let nextNonActive = value.sessions.filter { $0.status != .active }
                self.snapshot = value
                if value.isPaired && nextNonActive != previousNonActive {
                    self.scheduleHistorySync(delay: .seconds(1.5))
                }
            }
        }
    }

    deinit {
        subscription?.cancel()
        scheduledSyncTask?.cancel()
        scheduledHistorySyncTask?.cancel()
    }

    var isAutoRecordingEnabled: Bool { snapshot.isAutoRecordingEnabled }

    var isTogetherNow: Bool { activeSessionStartDate != nil }
    var activeSessionStartDate: Date? {
        EncounterCalendarAggregator.coalescedActiveSessionStart(
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    private var activePairPeerSessions: [SyncedPeerSession] {
        guard let pairID = snapshot.pairConfiguration?.pairID else { return [] }
        return peerSessions.filter { $0.pairID == pairID }
    }

    var syncedPeerSessionCount: Int { activePairPeerSessions.count }

    var resolvedEncounters: [ResolvedEncounter] {
        EncounterCalendarAggregator.resolveEncounters(
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    var historySyncStatusText: String {
        switch historySyncState {
        case .idle:
            return snapshot.isPaired ? "未同期" : "ペア設定後に同期します"
        case .syncing:
            return "CloudKit 同期中…"
        case let .synced(date, peerCount):
            return "\(date.formatted(date: .omitted, time: .shortened)) 同期済み（相手 \(peerCount) 件）"
        case let .unavailable(reason), let .failed(reason):
            return reason
        }
    }

    var isHistorySyncing: Bool {
        if case .syncing = historySyncState { return true }
        return false
    }

    var locationSyncStatusText: String {
        switch locationSyncState {
        case .idle:
            return snapshot.isPaired ? "未同期" : "ペア設定後に同期します"
        case .syncing:
            return "CloudKit 同期中…"
        case let .synced(date, peerDays):
            return "\(date.formatted(date: .omitted, time: .shortened)) 同期済み（相手 \(peerDays) 日分）"
        case let .unavailable(reason), let .failed(reason):
            return reason
        }
    }

    var isLocationSyncing: Bool {
        if case .syncing = locationSyncState { return true }
        return false
    }

    private func write(_ operation: (JournalStore) throws -> JournalSnapshot) {
        do {
            journal = try operation(journalStore)
            journalError = nil
        } catch { journalError = error.localizedDescription }
    }

    func previewMerge(editing target: ResolvedEncounter?, startedAt: Date, endedAt: Date) -> EncounterMergePlan {
        EncounterMergePlanner.plan(
            editing: target,
            proposedStart: startedAt,
            proposedEnd: endedAt,
            among: resolvedEncounters
        )
    }

    func addManualEncounter(startedAt: Date, endedAt: Date) {
        let plan = previewMerge(editing: nil, startedAt: startedAt, endedAt: endedAt)
        applyMergePlan(plan)
    }

    func updateResolvedEncounter(_ encounter: ResolvedEncounter, startedAt: Date, endedAt: Date) {
        let plan = previewMerge(editing: encounter, startedAt: startedAt, endedAt: endedAt)
        applyMergePlan(plan)
    }

    func deleteResolvedEncounter(_ encounter: ResolvedEncounter) {
        switch encounter.source {
        case let .manual(id):
            write { try $0.deleteManualRecord(id: id) }
        case .auto, .peerAuto, .peerCompleted, .autoEdited, .locationMatched:
            let ids = encounter.linkedSessionIDs.isEmpty ? [encounter.id] : encounter.linkedSessionIDs
            let updates = Dictionary(uniqueKeysWithValues: ids.map { ($0, SessionOverrideAction.deleted) })
            write { try $0.setSessionOverrides(updates) }
        }
        scheduleHistorySyncIfPaired()
    }

    func completeUnknownEnd(_ encounter: ResolvedEncounter, startedAt: Date? = nil, endedAt: Date) {
        let plan = previewMerge(editing: encounter, startedAt: startedAt ?? encounter.startedAt, endedAt: endedAt)
        applyMergePlan(plan)
    }

    func saveMemo(dayKey: String, text: String) {
        write { try $0.setMemo(dayKey: dayKey, text: text) }
        scheduleHistorySyncIfPaired()
    }

    private func applyMergePlan(_ plan: EncounterMergePlan) {
        var deleteManualIDs: [UUID] = []
        var absorbedSessionIDs: [UUID] = []
        for enc in plan.absorbed {
            switch enc.source {
            case let .manual(id):
                deleteManualIDs.append(id)
            case .auto, .peerAuto, .peerCompleted, .autoEdited, .locationMatched:
                let ids = enc.linkedSessionIDs.isEmpty ? [enc.id] : enc.linkedSessionIDs
                absorbedSessionIDs.append(contentsOf: ids)
            }
        }

        let keepManualID: UUID?
        let createManual: Bool
        var sessionOverrideUpdates: [UUID: SessionOverrideAction] = [:]

        if let target = plan.target {
            switch target.source {
            case let .manual(id):
                keepManualID = id
                createManual = false
                for sid in absorbedSessionIDs {
                    sessionOverrideUpdates[sid] = .deleted
                }
            case .auto, .peerAuto, .peerCompleted, .autoEdited, .locationMatched:
                keepManualID = nil
                createManual = false
                let targetIDs = target.linkedSessionIDs.isEmpty ? [target.id] : target.linkedSessionIDs
                sessionOverrideUpdates[target.id] = .edited(startedAt: plan.mergedStart, endedAt: plan.mergedEnd)
                for sid in targetIDs where sid != target.id {
                    sessionOverrideUpdates[sid] = .deleted
                }
                for sid in absorbedSessionIDs where sid != target.id {
                    sessionOverrideUpdates[sid] = .deleted
                }
            }
        } else {
            keepManualID = nil
            createManual = true
            for sid in absorbedSessionIDs {
                sessionOverrideUpdates[sid] = .deleted
            }
        }

        write { store in
            try store.applyMergedMutation(
                pairID: snapshot.pairConfiguration?.pairID,
                keepManualID: keepManualID,
                createManual: createManual,
                mergedStart: plan.mergedStart,
                mergedEnd: plan.mergedEnd,
                deleteManualIDs: deleteManualIDs,
                sessionOverrideUpdates: sessionOverrideUpdates
            )
        }
        scheduleHistorySyncIfPaired()
    }

    private func scheduleHistorySyncIfPaired() {
        guard journalError == nil, snapshot.isPaired else { return }
        scheduleHistorySync(delay: .seconds(1))
    }

    func daySummaries(forMonth monthDate: Date) -> [String: DaySummary] {
        EncounterCalendarAggregator.daySummaries(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func daySummary(for date: Date) -> DaySummary {
        EncounterCalendarAggregator.daySummary(
            for: date,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func monthlyRecordedSeconds(forMonth monthDate: Date) -> TimeInterval {
        EncounterCalendarAggregator.monthlyRecordedSeconds(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func metDayCount(forMonth monthDate: Date) -> Int {
        EncounterCalendarAggregator.metDayCount(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func lifetimeRecordedSeconds() -> TimeInterval {
        EncounterCalendarAggregator.lifetimeRecordedSeconds(
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func startInvitePairing() throws -> String {
        let bundle = PairingPayloadCodec.makePairingBundle()
        try configure(bundle.localConfiguration)
        return bundle.peerQRPayload
    }

    func completePairing(fromURLString value: String) throws {
        let configuration = try PairingPayloadCodec.decode(value)
        guard configuration.localRole == .partnerB else { throw PairingPayloadError.invalidRole }
        try configure(configuration)
    }

    private func configure(_ configuration: PairConfiguration) throws {
        engine.configurePair(configuration)
        snapshot = engine.currentSnapshot()
        guard snapshot.pairConfiguration == configuration else {
            throw PairSetupError.saveFailed
        }
        if let cachedPeer = try? peerSyncStore.load(), cachedPeer.pairID == configuration.pairID {
            peerSessions = cachedPeer.sessions
        } else {
            peerSessions = []
        }
        engine.start()
        scheduleHistorySync(delay: .seconds(1))
        if locationMonitor.isEnabled {
            locationMonitor.startIfAuthorized()
            scheduleLocationSync(delay: .seconds(1))
        }
    }

    func unpair() {
        let previousConfig = snapshot.pairConfiguration
        engine.unpair()
        scheduledSyncTask?.cancel()
        scheduledHistorySyncTask?.cancel()
        _ = try? locationStore.clearAll()
        try? peerSyncStore.clearAll()
        peerSessions = []
        historySyncState = .idle
        locationMatchedSessions = []
        locationSyncState = .idle
        if let previousConfig {
            Task {
                await historySync.purgeOwnRecord(config: previousConfig)
                await locationSync.purgeOwnRecords(config: previousConfig)
            }
        }
    }

    func setAutoRecordingEnabled(_ enabled: Bool) {
        engine.setAutoRecordingEnabled(enabled)
        if enabled && locationMonitor.isEnabled {
            scheduleLocationSync(delay: .seconds(1))
        }
    }

    func clearLogs() {
        engine.clearLogs()
        _ = try? locationStore.clearAll()
        try? peerSyncStore.clearAll()
        peerSessions = []
        historySyncState = .idle
        locationMatchedSessions = []
        locationSyncState = .idle
    }

    func handleForegroundActivation() {
        engine.handleForegroundActivation()
        locationMonitor.startIfAuthorized()
        if snapshot.isPaired {
            Task { await syncSharedHistoryNow() }
        }
        if locationMonitor.isEnabled && snapshot.isPaired && isAutoRecordingEnabled {
            Task { await syncLocationNow(requestFreshFix: true) }
        }
    }

    func handleBackgroundLocationLaunch() {
        engine.handleBackgroundWake(source: "launchLocation")
        locationMonitor.startIfAuthorized()
        if snapshot.isPaired {
            Task { await syncSharedHistoryNow() }
        }
        if locationMonitor.isEnabled && snapshot.isPaired && isAutoRecordingEnabled {
            Task { await syncLocationNow(requestFreshFix: false) }
        }
    }

    func syncSharedHistoryNow() async {
        guard let config = snapshot.pairConfiguration else { return }
        guard !isHistorySyncing else { return }

        historySyncState = .syncing
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "OurHoursHistorySync") {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        let outcome = await historySync.sync(
            config: config,
            localSessions: snapshot.sessions,
            journalStore: journalStore,
            peerSyncStore: peerSyncStore
        )
        historySyncState = outcome.state
        if let updatedJournal = outcome.journal {
            journal = updatedJournal
        }
        if let updatedPeer = outcome.peerSessions {
            peerSessions = updatedPeer
        }
    }

    func syncLocationNow(requestFreshFix: Bool) async {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled, locationMonitor.isEnabled else {
            return
        }
        if requestFreshFix {
            locationMonitor.requestFreshFix(source: .manualSyncFix)
        }
        guard !isLocationSyncing else { return }

        locationSyncState = .syncing
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "OurHoursLocationSync") {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        let state = await locationSync.sync(config: config, store: locationStore)
        locationSyncState = state
        if let updated = try? locationStore.load() {
            locationMatchedSessions = updated.matchedSessions
        }
    }

    private func handleCapturedVisit(_ visit: LocationVisitRecord, arrivalUnknown: Bool) {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled else { return }
        _ = try? locationStore.recordVisit(visit, role: config.localRole, arrivalUnknown: arrivalUnknown, now: .now)
        if let matched = try? locationStore.recomputeMatches(pairID: config.pairID, now: .now) {
            locationMatchedSessions = matched.matchedSessions
        }
        scheduleLocationSync(delay: .seconds(1))
    }

    private func handleCapturedPoint(_ point: LocationPointSample) {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled else { return }
        _ = try? locationStore.recordPoint(point, role: config.localRole, now: .now)
        if let matched = try? locationStore.recomputeMatches(pairID: config.pairID, now: .now) {
            locationMatchedSessions = matched.matchedSessions
        }
        scheduleLocationSync(delay: .seconds(1))
    }

    private func scheduleLocationSync(delay: Duration) {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncLocationNow(requestFreshFix: false)
        }
    }

    private func scheduleHistorySync(delay: Duration) {
        scheduledHistorySyncTask?.cancel()
        scheduledHistorySyncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncSharedHistoryNow()
        }
    }

    func export(_ format: LogExport.Format) -> LogExport {
        LogExport(engine: engine, format: format)
    }
}

enum PairSetupError: LocalizedError {
    case saveFailed
    var errorDescription: String? { "ペア情報を保存できませんでした。再度お試しください。" }
}

struct LogExport: Transferable {
    enum Format: String, Sendable {
        case json = "OurHours.json"
        case sessions = "Sessions.csv"
        case events = "Events.csv"
    }

    let engine: OurHoursBLEEngine
    let format: Format

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            try item.writeFile()
        }
        .exportingCondition { $0.format == .json }
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            try item.writeFile()
        }
        .exportingCondition { $0.format != .json }
    }

    private func writeFile() throws -> SentTransferredFile {
        let data = switch format {
        case .json: engine.exportJSONData()
        case .sessions: engine.exportSessionsCSVData()
        case .events: engine.exportEventsCSVData()
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: format.rawValue)
        try data.write(to: file, options: .atomic)
        return SentTransferredFile(file)
    }
}
