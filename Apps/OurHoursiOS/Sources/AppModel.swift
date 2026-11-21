import CoreBluetooth
import Observation
import OurHoursCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    private enum DefaultsKey {
        static let onboarding = "ourhours.hasCompletedOnboarding"
        static let color = "ourhours.localBubbleColor"
        static let birthday = "ourhours.localBirthday"
        static let nickname = "ourhours.partnerNickname"
        static let anniversaryMarkStyle = "ourhours.anniversaryMarkStyle"
        static let myBirthdayMarkStyle = "ourhours.myBirthdayMarkStyle"
        static let partnerBirthdayMarkStyle = "ourhours.partnerBirthdayMarkStyle"
    }

    private let userDefaults: UserDefaults
    private(set) var hasCompletedOnboarding: Bool
    private(set) var localBubbleColor: BubbleColorTheme
    private(set) var localBirthday: CalendarDateValue?
    private(set) var partnerNickname: String
    private(set) var anniversaryMarkStyle: AnniversaryMarkStyle
    private(set) var myBirthdayMarkStyle: BirthdayMarkStyle
    private(set) var partnerBirthdayMarkStyle: BirthdayMarkStyle
    private(set) var bluetoothAuthorization = CBManager.authorization
    private(set) var confirmedPeerPairID: UUID?

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
        locationSync: CloudKitLocationSync = CloudKitLocationSync(),
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        let initialSnapshot = engine.currentSnapshot()
        snapshot = initialSnapshot
        if userDefaults.object(forKey: DefaultsKey.onboarding) != nil {
            hasCompletedOnboarding = userDefaults.bool(forKey: DefaultsKey.onboarding)
        } else {
            let completed = initialSnapshot.isPaired && CBManager.authorization != .notDetermined
            hasCompletedOnboarding = completed
            userDefaults.set(completed, forKey: DefaultsKey.onboarding)
        }
        localBubbleColor = userDefaults.string(forKey: DefaultsKey.color).flatMap(BubbleColorTheme.init(rawValue:)) ?? .skyBlue
        localBirthday = userDefaults.data(forKey: DefaultsKey.birthday).flatMap {
            try? JSONDecoder().decode(CalendarDateValue.self, from: $0)
        }
        partnerNickname = userDefaults.string(forKey: DefaultsKey.nickname) ?? ""
        anniversaryMarkStyle = userDefaults.string(forKey: DefaultsKey.anniversaryMarkStyle)
            .flatMap(AnniversaryMarkStyle.init(rawValue:)) ?? .heart
        myBirthdayMarkStyle = userDefaults.string(forKey: DefaultsKey.myBirthdayMarkStyle)
            .flatMap(BirthdayMarkStyle.init(rawValue:)) ?? .cake
        partnerBirthdayMarkStyle = userDefaults.string(forKey: DefaultsKey.partnerBirthdayMarkStyle)
            .flatMap(BirthdayMarkStyle.init(rawValue:)) ?? .cake
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

        do {
            journal = try journalStore.load()
            if let role = initialSnapshot.pairConfiguration?.localRole, journal.profile(for: role) == nil {
                journal = try journalStore.setRoleProfile(role: role, bubbleColor: localBubbleColor, birthday: localBirthday)
            }
        } catch { journalError = error.localizedDescription }

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
                self.refreshPermissionStates()
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

    private var partnerProfile: SyncedRoleProfile? {
        guard let role = snapshot.pairConfiguration?.localRole else { return nil }
        return journal.profile(for: role.opposite)
    }

    var partnerBubbleColor: BubbleColorTheme? { partnerProfile?.bubbleColor }
    var partnerBirthday: CalendarDateValue? { partnerProfile?.birthday }
    var anniversaryDate: CalendarDateValue? { journal.anniversary?.date }

    var daysTogetherCount: Int? {
        guard let anniversaryDate else { return nil }
        return SpecialDayCalculator.daysTogether(since: anniversaryDate)
    }

    func daysTogetherCount(asOf date: Date) -> Int? {
        guard let anniversaryDate else { return nil }
        return SpecialDayCalculator.daysTogether(since: anniversaryDate, asOf: date)
    }

    var togetherStatusTitle: String {
        let trimmed = partnerNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "いっしょにいるよ" : "\(trimmed)といっしょにいるよ"
    }

    func specialDayEvents(on date: Date) -> [SpecialDayEvent] {
        SpecialDayCalculator.events(
            on: date, anniversary: anniversaryDate, myBirthday: localBirthday, partnerBirthday: partnerBirthday
        )
    }

    func visibleCalendarSpecialDayEvents(on date: Date) -> [SpecialDayEvent] {
        specialDayEvents(on: date).filter { event in
            switch event {
            case .anniversary: anniversaryMarkStyle != .none
            case .myBirthday: myBirthdayMarkStyle != .none
            case .partnerBirthday: partnerBirthdayMarkStyle != .none
            case .seasonal: true
            }
        }
    }

    var displayPartnerName: String {
        let trimmed = partnerNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "パートナー" : trimmed
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: DefaultsKey.onboarding)
    }

    func setLocalBubbleColor(_ color: BubbleColorTheme) {
        localBubbleColor = color
        userDefaults.set(color.rawValue, forKey: DefaultsKey.color)
        publishLocalProfile()
    }

    func setLocalBirthday(_ birthday: CalendarDateValue?) {
        localBirthday = birthday
        let encoded = birthday.flatMap { try? JSONEncoder().encode($0) }
        userDefaults.set(encoded, forKey: DefaultsKey.birthday)
        publishLocalProfile()
    }

    private func publishLocalProfile() {
        guard let role = snapshot.pairConfiguration?.localRole else { return }
        write { try $0.setRoleProfile(role: role, bubbleColor: localBubbleColor, birthday: localBirthday) }
        scheduleHistorySyncIfPaired()
    }

    func setPartnerNickname(_ nickname: String) {
        partnerNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(partnerNickname, forKey: DefaultsKey.nickname)
    }

    func setAnniversaryDate(_ date: CalendarDateValue?) {
        write { try $0.setAnniversary(date) }
        scheduleHistorySyncIfPaired()
    }

    func setAnniversaryMarkStyle(_ style: AnniversaryMarkStyle) {
        anniversaryMarkStyle = style
        userDefaults.set(style.rawValue, forKey: DefaultsKey.anniversaryMarkStyle)
    }

    func setMyBirthdayMarkStyle(_ style: BirthdayMarkStyle) {
        myBirthdayMarkStyle = style
        userDefaults.set(style.rawValue, forKey: DefaultsKey.myBirthdayMarkStyle)
    }

    func setPartnerBirthdayMarkStyle(_ style: BirthdayMarkStyle) {
        partnerBirthdayMarkStyle = style
        userDefaults.set(style.rawValue, forKey: DefaultsKey.partnerBirthdayMarkStyle)
    }

    func requestBluetoothPermission() {
        engine.start()
        refreshPermissionStates()
    }

    func refreshPermissionStates() {
        bluetoothAuthorization = CBManager.authorization
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

    func currentResolvedEncounter(for encounter: ResolvedEncounter) -> ResolvedEncounter? {
        let probeIDs = Set(encounter.linkedSessionIDs.isEmpty ? [encounter.id] : encounter.linkedSessionIDs)
        return resolvedEncounters.first { candidate in
            candidate.id == encounter.id || !probeIDs.isDisjoint(with: candidate.linkedSessionIDs)
        }
    }

    func previewMerge(editing target: ResolvedEncounter?, startedAt: Date, endedAt: Date?, now: Date = .now) -> EncounterMergePlan {
        let resolvedTarget: ResolvedEncounter?
        if let target {
            guard let current = currentResolvedEncounter(for: target) else {
                return EncounterMergePlan(target: target, absorbed: [], mergedStart: startedAt, mergedEnd: endedAt)
            }
            resolvedTarget = current
        } else {
            resolvedTarget = nil
        }
        return EncounterMergePlanner.plan(
            editing: resolvedTarget,
            proposedStart: startedAt,
            proposedEnd: endedAt,
            among: resolvedEncounters,
            now: now
        )
    }

    func addManualEncounter(startedAt: Date, endedAt: Date, now: Date = .now) {
        let plan = previewMerge(editing: nil, startedAt: startedAt, endedAt: endedAt, now: now)
        applyMergePlan(plan)
    }

    func updateResolvedEncounter(_ encounter: ResolvedEncounter, startedAt: Date, endedAt: Date, now: Date = .now) {
        guard let current = currentResolvedEncounter(for: encounter) else { return }
        let plan = previewMerge(editing: current, startedAt: startedAt, endedAt: endedAt, now: now)
        applyMergePlan(plan)
    }

    func deleteResolvedEncounter(_ encounter: ResolvedEncounter) {
        let current = currentResolvedEncounter(for: encounter) ?? encounter
        switch current.source {
        case let .manual(id):
            write { try $0.deleteManualRecord(id: id) }
        case .auto, .peerAuto, .peerCompleted, .autoEdited, .locationMatched:
            let ids = current.linkedSessionIDs.isEmpty ? [current.id] : current.linkedSessionIDs
            let updates = Dictionary(uniqueKeysWithValues: ids.map { ($0, SessionOverrideAction.deleted) })
            write { try $0.setSessionOverrides(updates) }
        }
        scheduleHistorySyncIfPaired()
    }

    func completeUnknownEnd(_ encounter: ResolvedEncounter, startedAt: Date? = nil, endedAt: Date, now: Date = .now) {
        guard let current = currentResolvedEncounter(for: encounter) else { return }
        let plan = previewMerge(editing: current, startedAt: startedAt ?? current.startedAt, endedAt: endedAt, now: now)
        applyMergePlan(plan)
    }

    func updateActiveEncounterStart(_ encounter: ResolvedEncounter, startedAt: Date, now: Date = .now) {
        guard let current = currentResolvedEncounter(for: encounter) else { return }
        switch current.status {
        case .completed:
            guard let end = current.endedAt, end > startedAt else {
                journalError = "記録が終了したため、終了時刻より前に調整してください"
                return
            }
            updateResolvedEncounter(current, startedAt: startedAt, endedAt: end, now: now)
        case .active, .unknownEnd:
            guard startedAt <= max(current.startedAt, now) else {
                journalError = "開始時刻は現在時刻より前に設定してください"
                return
            }
            if current.status == .active {
                applyMergePlan(previewMerge(editing: current, startedAt: startedAt, endedAt: nil, now: now))
            } else {
                var updates: [UUID: SessionOverrideAction] = [current.id: .adjustedStart(startedAt: startedAt)]
                for id in current.linkedSessionIDs where id != current.id { updates[id] = .deleted }
                write { try $0.setSessionOverrides(updates) }
                scheduleHistorySyncIfPaired()
            }
        }
    }

    func saveMemo(dayKey: String, text: String) {
        write { try $0.setMemo(dayKey: dayKey, text: text) }
        scheduleHistorySyncIfPaired()
    }

    private func applyMergePlan(_ plan: EncounterMergePlan) {
        let survivor = plan.survivingActiveEncounter ?? plan.target
        var removed = plan.absorbed.filter { $0.id != survivor?.id }
        if let target = plan.target, target.id != survivor?.id { removed.append(target) }

        var deleteManualIDs: [UUID] = []
        var sessionOverrideUpdates: [UUID: SessionOverrideAction] = [:]
        for encounter in removed {
            if case let .manual(id) = encounter.source {
                deleteManualIDs.append(id)
            } else {
                let ids = encounter.linkedSessionIDs.isEmpty ? [encounter.id] : encounter.linkedSessionIDs
                for id in ids { sessionOverrideUpdates[id] = .deleted }
            }
        }

        var keepManualID: UUID?
        if let active = plan.survivingActiveEncounter {
            for id in active.linkedSessionIDs { sessionOverrideUpdates[id] = .deleted }
            sessionOverrideUpdates[active.id] = .adjustedStart(startedAt: plan.mergedStart)
        } else {
            guard let end = plan.mergedEnd, end > plan.mergedStart else { return }
            if let target = plan.target {
                if case let .manual(id) = target.source {
                    keepManualID = id
                } else {
                    for id in target.linkedSessionIDs { sessionOverrideUpdates[id] = .deleted }
                    sessionOverrideUpdates[target.id] = .edited(startedAt: plan.mergedStart, endedAt: end)
                }
            }
        }

        write { store in
            try store.applyMergedMutation(
                pairID: snapshot.pairConfiguration?.pairID,
                keepManualID: keepManualID,
                createManual: survivor == nil,
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
        let previousPairID = snapshot.pairConfiguration?.pairID
        engine.configurePair(configuration)
        snapshot = engine.currentSnapshot()
        guard snapshot.pairConfiguration == configuration else {
            throw PairSetupError.saveFailed
        }
        confirmedPeerPairID = nil
        if let cachedPeer = try? peerSyncStore.load(), cachedPeer.pairID == configuration.pairID {
            peerSessions = cachedPeer.sessions
        } else {
            peerSessions = []
        }
        if previousPairID != configuration.pairID {
            write { try $0.clearRoleProfiles() }
        }
        write { try $0.setRoleProfile(role: configuration.localRole, bubbleColor: localBubbleColor, birthday: localBirthday) }
        engine.start()
        scheduleHistorySync(delay: .seconds(1))
        if locationMonitor.isEnabled {
            locationMonitor.startIfAuthorized()
            scheduleLocationSync(delay: .seconds(1))
        }
    }

    var hasPartnerConnectedForCurrentPair: Bool {
        guard let pair = snapshot.pairConfiguration else { return false }
        if confirmedPeerPairID == pair.pairID { return true }
        if snapshot.activeLinkCount > 0 { return true }
        if let lastAuth = snapshot.lastAuthDate, lastAuth >= pair.createdAt { return true }
        if journal.profile(for: pair.localRole.opposite) != nil { return true }
        return false
    }

    func unpair() {
        let previousConfig = snapshot.pairConfiguration
        engine.unpair()
        snapshot = engine.currentSnapshot()
        guard !snapshot.isPaired else { return }
        confirmedPeerPairID = nil
        write { try $0.clearRoleProfiles() }
        setPartnerNickname("")
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
        refreshPermissionStates()
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
            peerSyncStore: peerSyncStore,
            isPairActive: { [weak self] in
                self?.snapshot.pairConfiguration == config
            }
        )
        guard snapshot.pairConfiguration == config else { return }
        historySyncState = outcome.state
        if outcome.peerRecordDetected {
            confirmedPeerPairID = config.pairID
        }
        if let updatedJournal = outcome.journal {
            // Local edits can reach disk while CloudKit is uploading its earlier snapshot.
            journal = (try? journalStore.load()) ?? updatedJournal
            let profile = journal.profile(for: config.localRole)
            if profile?.bubbleColor != localBubbleColor || profile?.birthday != localBirthday {
                publishLocalProfile()
            } else if journal != updatedJournal {
                scheduleHistorySyncIfPaired()
            }
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
