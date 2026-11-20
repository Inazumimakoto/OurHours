import Observation
import OurHoursCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    private let engine: OurHoursBLEEngine
    private(set) var snapshot: EngineSnapshot
    @ObservationIgnored private var subscription: Task<Void, Never>?

    private let journalStore: JournalStore
    private(set) var journal = JournalSnapshot()
    var journalError: String?

    init(engine: OurHoursBLEEngine, journalStore: JournalStore = JournalStore()) {
        self.journalStore = journalStore
        self.engine = engine
        snapshot = engine.currentSnapshot()
        do { journal = try journalStore.load() }
        catch { journalError = error.localizedDescription }
        let snapshots = engine.snapshotStream()
        subscription = Task { [weak self] in
            for await value in snapshots {
                self?.snapshot = value
            }
        }
    }

    deinit { subscription?.cancel() }

    var isAutoRecordingEnabled: Bool { snapshot.isAutoRecordingEnabled }

    var isTogetherNow: Bool { snapshot.activeSession != nil }
    var activeSessionStartDate: Date? { snapshot.activeSession?.startedAt }
    var resolvedEncounters: [ResolvedEncounter] {
        EncounterCalendarAggregator.resolveEncounters(autoSessions: snapshot.sessions, journal: journal)
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
        case let .auto(id), let .autoEdited(id):
            write { try $0.setSessionOverride(sessionID: id, action: .edited(startedAt: startedAt, endedAt: endedAt)) }
        }
    }

    func deleteResolvedEncounter(_ encounter: ResolvedEncounter) {
        switch encounter.source {
        case let .manual(id): write { try $0.deleteManualRecord(id: id) }
        case let .auto(id), let .autoEdited(id): write { try $0.setSessionOverride(sessionID: id, action: .deleted) }
        }
    }

    func completeUnknownEnd(sessionID: UUID, startedAt: Date, endedAt: Date) {
        write { try $0.setSessionOverride(sessionID: sessionID, action: .edited(startedAt: startedAt, endedAt: endedAt)) }
    }

    func saveMemo(dayKey: String, text: String) {
        write { try $0.setMemo(dayKey: dayKey, text: text) }
    }

    func daySummaries(forMonth monthDate: Date) -> [String: DaySummary] {
        EncounterCalendarAggregator.daySummaries(forMonth: monthDate, autoSessions: snapshot.sessions, journal: journal)
    }

    func daySummary(for date: Date) -> DaySummary {
        EncounterCalendarAggregator.daySummary(for: date, autoSessions: snapshot.sessions, journal: journal)
    }

    func monthlyRecordedSeconds(forMonth monthDate: Date) -> TimeInterval {
        EncounterCalendarAggregator.monthlyRecordedSeconds(forMonth: monthDate, autoSessions: snapshot.sessions, journal: journal)
    }

    func metDayCount(forMonth monthDate: Date) -> Int {
        EncounterCalendarAggregator.metDayCount(forMonth: monthDate, autoSessions: snapshot.sessions, journal: journal)
    }

    func lifetimeRecordedSeconds() -> TimeInterval {
        EncounterCalendarAggregator.lifetimeRecordedSeconds(autoSessions: snapshot.sessions, journal: journal)
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
    }

    func unpair() { engine.unpair() }
    func setAutoRecordingEnabled(_ enabled: Bool) { engine.setAutoRecordingEnabled(enabled) }
    func clearLogs() { engine.clearLogs() }

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
