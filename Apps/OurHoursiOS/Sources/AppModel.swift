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

    private let journalStore: JournalStore
    private(set) var journal = JournalSnapshot()
    var journalError: String?

    private let locationStore: LocationTimelineStore
    private let locationSync: CloudKitLocationSync
    let locationMonitor: LocationPresenceMonitor
    private(set) var locationMatchedSessions: [LocationMatchedSession] = []
    private(set) var locationSyncState: LocationSyncState = .idle

    init(
        engine: OurHoursBLEEngine,
        journalStore: JournalStore = JournalStore(),
        locationStore: LocationTimelineStore = LocationTimelineStore(),
        locationSync: CloudKitLocationSync = CloudKitLocationSync()
    ) {
        self.engine = engine
        self.journalStore = journalStore
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
                self?.snapshot = value
            }
        }
    }

    deinit {
        subscription?.cancel()
        scheduledSyncTask?.cancel()
    }

    var isAutoRecordingEnabled: Bool { snapshot.isAutoRecordingEnabled }

    var isTogetherNow: Bool { snapshot.activeSession != nil }
    var activeSessionStartDate: Date? { snapshot.activeSession?.startedAt }
    var resolvedEncounters: [ResolvedEncounter] {
        EncounterCalendarAggregator.resolveEncounters(
            autoSessions: snapshot.sessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
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

    func addManualEncounter(startedAt: Date, endedAt: Date) {
        write { try $0.addManualRecord(pairID: snapshot.pairConfiguration?.pairID, startedAt: startedAt, endedAt: endedAt) }
    }

    func updateResolvedEncounter(_ encounter: ResolvedEncounter, startedAt: Date, endedAt: Date) {
        switch encounter.source {
        case let .manual(id):
            write { try $0.updateManualRecord(id: id, startedAt: startedAt, endedAt: endedAt) }
        case let .auto(id), let .autoEdited(id), let .locationMatched(id):
            write { try $0.setSessionOverride(sessionID: id, action: .edited(startedAt: startedAt, endedAt: endedAt)) }
        }
    }

    func deleteResolvedEncounter(_ encounter: ResolvedEncounter) {
        switch encounter.source {
        case let .manual(id):
            write { try $0.deleteManualRecord(id: id) }
        case let .auto(id), let .autoEdited(id), let .locationMatched(id):
            write { try $0.setSessionOverride(sessionID: id, action: .deleted) }
        }
    }

    func completeUnknownEnd(sessionID: UUID, startedAt: Date, endedAt: Date) {
        write { try $0.setSessionOverride(sessionID: sessionID, action: .edited(startedAt: startedAt, endedAt: endedAt)) }
    }

    func saveMemo(dayKey: String, text: String) {
        write { try $0.setMemo(dayKey: dayKey, text: text) }
    }

    func daySummaries(forMonth monthDate: Date) -> [String: DaySummary] {
        EncounterCalendarAggregator.daySummaries(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func daySummary(for date: Date) -> DaySummary {
        EncounterCalendarAggregator.daySummary(
            for: date,
            autoSessions: snapshot.sessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func monthlyRecordedSeconds(forMonth monthDate: Date) -> TimeInterval {
        EncounterCalendarAggregator.monthlyRecordedSeconds(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func metDayCount(forMonth monthDate: Date) -> Int {
        EncounterCalendarAggregator.metDayCount(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            locationSessions: locationMatchedSessions,
            journal: journal
        )
    }

    func lifetimeRecordedSeconds() -> TimeInterval {
        EncounterCalendarAggregator.lifetimeRecordedSeconds(
            autoSessions: snapshot.sessions,
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
        engine.start()
        if locationMonitor.isEnabled {
            locationMonitor.startIfAuthorized()
            scheduleLocationSync(delay: .seconds(1))
        }
    }

    func unpair() {
        let previousConfig = snapshot.pairConfiguration
        engine.unpair()
        scheduledSyncTask?.cancel()
        _ = try? locationStore.clearAll()
        locationMatchedSessions = []
        locationSyncState = .idle
        if let previousConfig {
            Task { await locationSync.purgeOwnRecords(config: previousConfig) }
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
        locationMatchedSessions = []
        locationSyncState = .idle
    }

    func handleForegroundActivation() {
        engine.handleForegroundActivation()
        locationMonitor.startIfAuthorized()
        if locationMonitor.isEnabled && snapshot.isPaired && isAutoRecordingEnabled {
            Task { await syncLocationNow(requestFreshFix: true) }
        }
    }

    func handleBackgroundLocationLaunch() {
        engine.handleBackgroundWake(source: "launchLocation")
        locationMonitor.startIfAuthorized()
        if locationMonitor.isEnabled && snapshot.isPaired && isAutoRecordingEnabled {
            Task { await syncLocationNow(requestFreshFix: false) }
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
