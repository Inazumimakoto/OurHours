import CloudKit
import CoreBluetooth
import CoreLocation
import Observation
import OurHoursCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
protocol LocationMonitoring {
    var authorizationStatus: CLAuthorizationStatus { get }
    var isEnabled: Bool { get }
    var needsSettingsGuidance: Bool { get }
    var statusDescription: String { get }
    var isReducedAccuracyWarning: Bool { get }
    var lastCaptureDate: Date? { get }
    func startIfAuthorized()
    func enableAndRequestAuthorization()
    func disable()
    func requestFreshFix(source: LocationSampleSource)
}

extension LocationPresenceMonitor: LocationMonitoring {}

@MainActor @Observable
final class AppModel {
    enum DefaultsKey {
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
    @ObservationIgnored private var accountChangeTask: Task<Void, Never>?
    @ObservationIgnored private var pendingExternalShareMetadata: CKShare.Metadata?
    @ObservationIgnored private var scheduledSyncTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledHistorySyncTask: Task<Void, Never>?
    @ObservationIgnored private var pairSpaceSetupTask: Task<PairSpaceContext?, Never>?
    @ObservationIgnored private var pairSpaceResetTask: Task<Void, Never>?
    @ObservationIgnored private var historySyncTask: Task<HistorySyncOutcome?, Never>?
    @ObservationIgnored private var locationSyncTask: Task<LocationSyncOutcome?, Never>?
    @ObservationIgnored private var pairGeneration = 0
    @ObservationIgnored private var historyInputRevision = 0
    @ObservationIgnored private var locationInputRevision = 0

    let pairSpace = CloudKitPairSpace()
    private(set) var pairSpaceStatus: PairSpaceStatus = .idle
    private(set) var activePairSpaceContext: PairSpaceContext?
    private(set) var lastHistorySyncBackend: SyncStorageBackend?

    private let journalStore: JournalStore
    private(set) var journal = JournalSnapshot()
    var journalError: String?

    private let peerSyncStore: PartnerSyncStore
    private let historySync: CloudKitHistorySync
    private(set) var peerSessions: [SyncedPeerSession] = []
    private(set) var historySyncState: HistorySyncState = .idle

    private let locationStore: LocationTimelineStore
    private let locationSync: CloudKitLocationSync
    #if DEBUG
    private let isScreenshotDemo: Bool
    var screenshotFixedActiveSessionStart: Date?
    #endif
    let locationMonitor: any LocationMonitoring
    private(set) var locationMatchedSessions: [LocationMatchedSession] = []
    private(set) var locationSyncState: LocationSyncState = .idle

    init(
        engine: OurHoursBLEEngine,
        journalStore: JournalStore = JournalStore(),
        peerSyncStore: PartnerSyncStore = PartnerSyncStore(),
        historySync: CloudKitHistorySync = CloudKitHistorySync(),
        locationStore: LocationTimelineStore = LocationTimelineStore(),
        locationSync: CloudKitLocationSync = CloudKitLocationSync(),
        locationMonitor: (any LocationMonitoring)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        #if DEBUG
        isScreenshotDemo = locationMonitor is ScreenshotLocationMonitor
        #endif
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

        self.locationMonitor = locationMonitor ?? LocationPresenceMonitor(
            defaults: userDefaults,
            onVisit: { visit, arrivalUnknown in sink?(visit, arrivalUnknown) },
            onPoint: { point in pointSink?(point) },
            onWake: { [weak engine] source in
                engine?.handleBackgroundWake(source: source)
            }
        )

        do {
            if let pair = initialSnapshot.pairConfiguration {
                journal = try journalStore.prepareForPairTransition(from: nil, to: pair.pairID)
                if journal.profile(for: pair.localRole) == nil {
                    journal = try journalStore.setRoleProfile(
                        role: pair.localRole, bubbleColor: localBubbleColor, birthday: localBirthday
                    )
                }
            } else {
                journal = try journalStore.load()
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

        #if DEBUG
        if isScreenshotDemo {
            pairSpaceStatus = .connected(scope: .privateDB, shareURL: initialSnapshot.pairConfiguration?.cloudShareURL, sameAppleID: false)
            historySyncState = .synced(.now, peerSessions: 0)
            return
        }
        #endif
        let snapshots = engine.snapshotStream()
        subscription = Task { [weak self] in
            for await publishedSnapshot in snapshots {
                guard let self else { break }
                let value = publishedSnapshot.pairConfiguration == self.snapshot.pairConfiguration
                    ? publishedSnapshot : engine.currentSnapshot()
                let previousNonActive = self.snapshot.sessions.filter { $0.status != .active }
                let nextNonActive = value.sessions.filter { $0.status != .active }
                self.snapshot = value
                self.refreshPermissionStates()
                if nextNonActive != previousNonActive {
                    self.historyInputRevision += 1
                    if value.isPaired {
                        self.scheduleHistorySync(delay: .seconds(1.5))
                    }
                }
            }
        }
        accountChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { break }
                self.invalidatePairSpaceForAccountOrZoneChange()
            }
        }
    }

    deinit {
        subscription?.cancel()
        accountChangeTask?.cancel()
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
        #if DEBUG
        if isScreenshotDemo { return }
        #endif
        engine.start()
        refreshPermissionStates()
    }

    func refreshPermissionStates() {
        bluetoothAuthorization = CBManager.authorization
    }

    var isAutoRecordingEnabled: Bool { snapshot.isAutoRecordingEnabled }

    var isTogetherNow: Bool { activeSessionStartDate != nil }
    var activeSessionStartDate: Date? {
        #if DEBUG
        if let screenshotFixedActiveSessionStart { return screenshotFixedActiveSessionStart }
        #endif
        return EncounterCalendarAggregator.coalescedActiveSessionStart(
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

    var pairSpaceStatusText: String {
        switch pairSpaceStatus {
        case .idle:
            return "未設定"
        case .settingUp:
            return lastHistorySyncBackend == .publicFallback
                ? "Public DB（共有スペースを準備中）" : "共有スペースを準備中…"
        case .connected(.privateDB, _, true):
            return "Private DB（同一Apple ID）"
        case .connected(.privateDB, _, false):
            return "Private DB 共有"
        case .connected(.sharedDB, _, _):
            return "Shared DB 接続中"
        case let .unavailable(reason), let .failed(reason):
            return lastHistorySyncBackend == .publicFallback ? "Public DB（移行待機中）\n\(reason)" : reason
        }
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
            historyInputRevision += 1
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
            write { try $0.setSessionOverrides(updates, pairID: snapshot.pairConfiguration?.pairID) }
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
                write { try $0.setSessionOverrides(updates, pairID: snapshot.pairConfiguration?.pairID) }
                scheduleHistorySyncIfPaired()
            }
        }
    }

    func saveMemo(dayKey: String, text: String) {
        write { try $0.setMemo(dayKey: dayKey, text: text, pairID: snapshot.pairConfiguration?.pairID) }
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
            journal: journal,
            activeReferenceDate: .now
        )
    }

    func daySummary(for date: Date) -> DaySummary {
        EncounterCalendarAggregator.daySummary(
            for: date,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal,
            activeReferenceDate: .now
        )
    }

    func monthlyRecordedSeconds(forMonth monthDate: Date) -> TimeInterval {
        EncounterCalendarAggregator.monthlyRecordedSeconds(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal,
            activeReferenceDate: .now
        )
    }

    func metDayCount(forMonth monthDate: Date) -> Int {
        EncounterCalendarAggregator.metDayCount(
            forMonth: monthDate,
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal,
            activeReferenceDate: .now
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

    func prepareInvitePairing(cloudSetupTimeout: Duration = .seconds(2.5)) async throws -> String {
        try Task.checkCancellation()
        let bundle = PairingPayloadCodec.makePairingBundle()
        try configure(bundle.localConfiguration)
        let generation = pairGeneration
        let setupTask = Task { await ensurePairSpaceReady() }
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        Task {
            _ = await setupTask.value
            continuation.finish()
        }
        let timer = Task {
            do {
                try await Task.sleep(for: cloudSetupTimeout)
                continuation.finish()
            } catch is CancellationError {
                return
            } catch {
                continuation.finish()
            }
        }
        defer { timer.cancel() }
        var iterator = completion.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
        guard isPairActive(bundle.localConfiguration, generation: generation),
              let updated = snapshot.pairConfiguration else { throw CancellationError() }
        return updated.cloudShareURL == nil ? bundle.peerQRPayload : PairingPayloadCodec.encode(updated, for: .partnerB)
    }

    func ensureInviteShareURLForExistingPair() async -> String? {
        guard let pair = snapshot.pairConfiguration, pair.localRole == .partnerA else { return nil }
        let generation = pairGeneration
        if pair.cloudShareURL == nil {
            await ensurePairSpaceReady()
        }
        guard isPairActive(pair, generation: generation), let current = snapshot.pairConfiguration else { return nil }
        return PairingPayloadCodec.encode(current, for: .partnerB)
    }

    @discardableResult
    func ensurePairSpaceReady() async -> PairSpaceContext? {
        guard let config = snapshot.pairConfiguration else { return nil }
        if let activePairSpaceContext, !activePairSpaceContext.needsMaintenance { return activePairSpaceContext }
        if let pairSpaceSetupTask { return await pairSpaceSetupTask.value }
        return await resolvePairSpace(config: config)
    }

    private func resolvePairSpace(config: PairConfiguration, metadata: CKShare.Metadata? = nil) async -> PairSpaceContext? {
        let generation = pairGeneration
        let reset = pairSpaceResetTask
        if activePairSpaceContext == nil {
            pairSpaceStatus = .settingUp
        }
        let setup = Task { [weak self, pairSpace] () -> PairSpaceContext? in
            await reset?.value
            guard let self, generation == pairGeneration else { return nil }
            let result: PairSpaceResolutionResult
            if let metadata {
                result = await pairSpace.acceptExternalShareMetadata(metadata, expectedConfig: config)
            } else {
                result = await pairSpace.resolveContext(for: config)
            }
            guard generation == pairGeneration else { return nil }
            pairSpaceSetupTask = nil
            guard isPairActive(config, generation: generation) else { return nil }
            if result.context != nil || activePairSpaceContext == nil {
                pairSpaceStatus = result.status
                activePairSpaceContext = result.context
            }
            if let current = snapshot.pairConfiguration, let shareURL = result.discoveredShareURL,
               shareURL != current.cloudShareURL {
                engine.configurePair(current.withCloudShareURL(shareURL))
                snapshot = engine.currentSnapshot()
            }
            return activePairSpaceContext
        }
        pairSpaceSetupTask = setup
        return await setup.value
    }

    private func isPairActive(_ config: PairConfiguration, generation: Int) -> Bool {
        pairGeneration == generation && snapshot.pairConfiguration?.matchesCredentials(of: config) == true
    }

    func completePairing(fromURLString value: String) throws {
        let configuration = try PairingPayloadCodec.decode(value)
        guard configuration.localRole == .partnerB else { throw PairingPayloadError.invalidRole }
        try configure(configuration)
    }

    private func configure(_ configuration: PairConfiguration) throws {
        #if DEBUG
        if isScreenshotDemo { throw PairSetupError.saveFailed }
        #endif
        let previous = snapshot.pairConfiguration
        engine.configurePair(configuration)
        snapshot = engine.currentSnapshot()
        guard snapshot.pairConfiguration == configuration else {
            throw PairSetupError.saveFailed
        }
        if previous?.matchesCredentials(of: configuration) != true {
            resetPairSpace()
            historySyncState = .idle
            locationSyncState = .idle
        }
        write { try $0.prepareForPairTransition(from: previous?.pairID, to: configuration.pairID) }
        let transitionError = journalError
        confirmedPeerPairID = nil
        if let cachedPeer = try? peerSyncStore.load(), cachedPeer.pairID == configuration.pairID {
            peerSessions = cachedPeer.sessions
        } else {
            peerSessions = []
        }
        if previous?.pairID != configuration.pairID {
            if previous != nil {
                _ = try? locationStore.clearAll()
                locationMatchedSessions = []
            }
            write { try $0.clearRoleProfiles() }
        }
        write { try $0.setRoleProfile(role: configuration.localRole, bubbleColor: localBubbleColor, birthday: localBirthday) }
        if let transitionError { journalError = transitionError }
        if let metadata = pendingExternalShareMetadata {
            pendingExternalShareMetadata = nil
            if metadata.share.recordID.zoneID.zoneName == PairSpaceCrypto.zoneName(for: configuration) {
                handleAcceptedExternalShare(metadata)
            }
        }
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
        #if DEBUG
        if isScreenshotDemo { return }
        #endif
        pendingExternalShareMetadata = nil
        let previousConfig = snapshot.pairConfiguration
        let previousContext = activePairSpaceContext
        engine.unpair()
        snapshot = engine.currentSnapshot()
        guard !snapshot.isPaired else { return }
        confirmedPeerPairID = nil
        write { try $0.prepareForPairTransition(from: previousConfig?.pairID, to: nil) }
        let transitionError = journalError
        write { try $0.clearRoleProfiles() }
        if let transitionError { journalError = transitionError }
        setPartnerNickname("")
        scheduledSyncTask?.cancel()
        scheduledHistorySyncTask?.cancel()
        _ = try? locationStore.clearAll()
        try? peerSyncStore.clearAll()
        peerSessions = []
        historySyncState = .idle
        locationMatchedSessions = []
        locationSyncState = .idle
        resetPairSpace(purging: previousConfig, context: previousContext)
    }

    private func resetPairSpace(purging config: PairConfiguration? = nil, context: PairSpaceContext? = nil) {
        pairGeneration += 1
        activePairSpaceContext = nil
        pairSpaceStatus = .idle
        lastHistorySyncBackend = nil

        if let config { engine.enqueuePendingPurge(config) }

        let previousReset = pairSpaceResetTask
        let setup = pairSpaceSetupTask
        let history = historySyncTask
        let location = locationSyncTask
        pairSpaceSetupTask = nil
        historySyncTask = nil
        locationSyncTask = nil
        pairSpaceResetTask = Task { [weak self, pairSpace] in
            await previousReset?.value
            _ = await setup?.value
            _ = await history?.value
            _ = await location?.value
            await pairSpace.invalidate()
            await self?.drainPendingPurges(priorityConfig: config, context: context)
        }
    }

    private func drainPendingPurges(
        priorityConfig: PairConfiguration? = nil, context: PairSpaceContext? = nil
    ) async {
        var pending = engine.loadPendingPurges()
        if let priorityConfig {
            pending.removeAll { $0.matchesCredentials(of: priorityConfig) }
            pending.insert(priorityConfig, at: 0)
        }
        for config in pending {
            guard snapshot.pairConfiguration?.matchesCredentials(of: config) != true else { continue }
            let cachedContext = priorityConfig?.matchesCredentials(of: config) == true ? context : nil
            let historyPurged = await historySync.purgeOwnRecord(config: config, context: cachedContext, pairSpace: pairSpace)
            let locationPurged = await locationSync.purgeOwnRecords(config: config, context: cachedContext, pairSpace: pairSpace)
            // Keep the zone accessible until both record purges have succeeded.
            if historyPurged, locationPurged,
               snapshot.pairConfiguration?.matchesCredentials(of: config) != true,
               await pairSpace.purgePairSpace(config: config) {
                engine.removePendingPurge(config)
            }
        }
    }

    private func invalidatePairSpaceForAccountOrZoneChange() {
        resetPairSpace()
        pairSpaceStatus = snapshot.isPaired ? .settingUp : .idle
        guard snapshot.isPaired else { return }
        Task { await syncSharedHistoryNow() }
        if locationMonitor.isEnabled && isAutoRecordingEnabled {
            Task { await syncLocationNow(requestFreshFix: false) }
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
        #if DEBUG
        if isScreenshotDemo { return }
        #endif
        refreshPermissionStates()
        engine.handleForegroundActivation()
        locationMonitor.startIfAuthorized()
        if !engine.loadPendingPurges().isEmpty {
            let priorReset = pairSpaceResetTask
            pairSpaceResetTask = Task { [weak self] in
                await priorReset?.value
                await self?.drainPendingPurges()
            }
        }
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

    @discardableResult
    func syncSharedHistoryNow() async -> HistorySyncOutcome? {
        #if DEBUG
        if isScreenshotDemo { return nil }
        #endif
        guard let config = snapshot.pairConfiguration else { return nil }
        if let historySyncTask { return await historySyncTask.value }
        let generation = pairGeneration
        historySyncState = .syncing
        let task = Task { [weak self] () -> HistorySyncOutcome? in
            guard let self else { return nil }
            let outcome = await performHistorySync(config: config, generation: generation)
            if generation == pairGeneration { historySyncTask = nil }
            return outcome
        }
        historySyncTask = task
        return await task.value
    }

    private func performHistorySync(config: PairConfiguration, generation: Int) async -> HistorySyncOutcome? {
        guard isPairActive(config, generation: generation) else { return nil }
        let startedRevision = historyInputRevision
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

        let context = await ensurePairSpaceReady()
        guard isPairActive(config, generation: generation) else { return nil }
        let outcome = await historySync.sync(
            config: config,
            localSessions: snapshot.sessions,
            journalStore: journalStore,
            peerSyncStore: peerSyncStore,
            context: context,
            pairSpace: pairSpace,
            isPairActive: { [weak self] in
                self?.isPairActive(config, generation: generation) == true
            }
        )
        guard isPairActive(config, generation: generation) else { return nil }
        historySyncState = outcome.state
        lastHistorySyncBackend = outcome.backend
        if outcome.peerRecordDetected {
            confirmedPeerPairID = config.pairID
        }
        if !outcome.recoveredOwnSessions.isEmpty {
            engine.importRecoveredSessions(outcome.recoveredOwnSessions)
            snapshot = engine.currentSnapshot()
        }
        var journalChangedDuringSync = false
        if let updatedJournal = outcome.journal {
            // Local edits can reach disk while CloudKit is uploading its earlier snapshot.
            journal = (try? journalStore.load()) ?? updatedJournal
            journalChangedDuringSync = journal != updatedJournal
            let profile = journal.profile(for: config.localRole)
            if profile?.bubbleColor != localBubbleColor || profile?.birthday != localBirthday {
                publishLocalProfile()
            }
        }
        if let updatedPeer = outcome.peerSessions {
            peerSessions = updatedPeer
        }
        if outcome.invalidateContext {
            activePairSpaceContext = nil
            pairSpaceStatus = .settingUp
            await pairSpace.invalidate()
        }
        if isPairActive(config, generation: generation),
           historyInputRevision != startedRevision || journalChangedDuringSync {
            scheduleHistorySyncIfPaired()
        }
        return outcome
    }

    @discardableResult
    func syncLocationNow(requestFreshFix: Bool) async -> LocationSyncOutcome? {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled, locationMonitor.isEnabled else {
            return nil
        }
        if requestFreshFix {
            locationMonitor.requestFreshFix(source: .manualSyncFix)
        }
        if let locationSyncTask { return await locationSyncTask.value }
        let generation = pairGeneration
        locationSyncState = .syncing
        let task = Task { [weak self] () -> LocationSyncOutcome? in
            guard let self else { return nil }
            let outcome = await performLocationSync(config: config, generation: generation)
            if generation == pairGeneration { locationSyncTask = nil }
            return outcome
        }
        locationSyncTask = task
        return await task.value
    }

    private func performLocationSync(config: PairConfiguration, generation: Int) async -> LocationSyncOutcome? {
        guard isPairActive(config, generation: generation) else { return nil }
        let startedRevision = locationInputRevision
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

        let context = await ensurePairSpaceReady()
        guard isPairActive(config, generation: generation) else { return nil }
        let outcome = await locationSync.sync(
            config: config,
            store: locationStore,
            context: context,
            pairSpace: pairSpace,
            isPairActive: { [weak self] in
                self?.isPairActive(config, generation: generation) == true
            }
        )
        guard isPairActive(config, generation: generation) else { return nil }
        locationSyncState = outcome.state
        if let updated = try? locationStore.load() {
            locationMatchedSessions = updated.matchedSessions
        }
        if outcome.invalidateContext {
            activePairSpaceContext = nil
            pairSpaceStatus = .settingUp
            await pairSpace.invalidate()
        }
        if isPairActive(config, generation: generation), locationInputRevision != startedRevision {
            scheduleLocationSync(delay: .seconds(1))
        }
        return outcome
    }

    func handleRemoteCloudKitPush() async -> UIBackgroundFetchResult {
        guard let config = snapshot.pairConfiguration else { return .noData }
        let generation = pairGeneration
        // A sync that was already running may have fetched before the pushed change.
        _ = await historySyncTask?.value
        guard isPairActive(config, generation: generation) else { return .noData }
        let history = await syncSharedHistoryNow()
        var location: LocationSyncOutcome?
        if isPairActive(config, generation: generation), locationMonitor.isEnabled, isAutoRecordingEnabled {
            _ = await locationSyncTask?.value
            if isPairActive(config, generation: generation) {
                location = await syncLocationNow(requestFreshFix: false)
            }
        }
        if history?.didApplyRemoteChanges == true || location?.didApplyRemoteChanges == true { return .newData }
        switch (history?.state, location?.state) {
        case (.failed?, _), (_, .failed?):
            return .failed
        default:
            return .noData
        }
    }

    func handleAcceptedExternalShare(_ metadata: CKShare.Metadata) {
        #if DEBUG
        if isScreenshotDemo { return }
        #endif
        guard let config = snapshot.pairConfiguration else {
            pendingExternalShareMetadata = metadata
            return
        }
        guard metadata.share.recordID.zoneID.zoneName == PairSpaceCrypto.zoneName(for: config) else { return }
        let generation = pairGeneration
        Task { [weak self] in
            guard let self else { return }
            while let setup = pairSpaceSetupTask, generation == pairGeneration {
                _ = await setup.value
            }
            guard generation == pairGeneration else { return }
            guard await resolvePairSpace(config: config, metadata: metadata) != nil,
                  isPairActive(config, generation: generation) else { return }
            _ = await handleRemoteCloudKitPush()
        }
    }

    private func handleCapturedVisit(_ visit: LocationVisitRecord, arrivalUnknown: Bool) {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled else { return }
        locationInputRevision += 1
        _ = try? locationStore.recordVisit(visit, role: config.localRole, arrivalUnknown: arrivalUnknown, now: .now)
        if let matched = try? locationStore.recomputeMatches(pairID: config.pairID, now: .now) {
            locationMatchedSessions = matched.matchedSessions
        }
        scheduleLocationSync(delay: .seconds(1))
    }

    private func handleCapturedPoint(_ point: LocationPointSample) {
        guard let config = snapshot.pairConfiguration, isAutoRecordingEnabled else { return }
        locationInputRevision += 1
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
