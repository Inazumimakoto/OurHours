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

struct MediaTransferProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case importing
        case uploading
        case downloading
    }

    let phase: Phase
    let completedCount: Int
    let totalCount: Int
    let currentItemFraction: Double
    let detailText: String

    var overallFraction: Double {
        guard totalCount > 0 else { return 0 }
        let raw = (Double(completedCount) + min(1.0, max(0.0, currentItemFraction))) / Double(totalCount)
        return min(1.0, max(0.0, raw))
    }
}

struct BubbleUnlockBanner: Identifiable, Equatable, Sendable {
    let id = UUID()
    let items: [BubbleUnlockItem]

    var primaryCategory: BubbleCustomizationCategory {
        items.first?.category ?? .expression
    }

    var title: String {
        if items.count == 1, let first = items.first {
            return "「\(first.title)」をアンロック！"
        }
        return "\(items.count)個のアイテムをアンロック！"
    }

    var subtitle: String {
        let previewNames = items.prefix(3).map(\.title).joined(separator: "・")
        let suffix = items.count > 3 ? " ほか" : ""
        let requirementText = items.first?.requirement.requirementLabel ?? ""
        if requirementText.isEmpty {
            return "\(previewNames)\(suffix)"
        }
        return "\(requirementText)達成 · \(previewNames)\(suffix)"
    }
}

@MainActor @Observable
final class AppModel {
    enum DefaultsKey {
        static let onboarding = "ourhours.hasCompletedOnboarding"
        static let color = "ourhours.localBubbleColor"
        static let expression = "ourhours.localBubbleExpression"
        static let expressionRotation = "ourhours.localBubbleExpressionRotation"
        static let decorations = "ourhours.localBubbleDecorations"
        static let partnerDisplayOverride = "ourhours.partnerBubbleDisplayOverride"
        static let discoveredSecretPop = "ourhours.discoveredSecretPop"
        static let achievedBubbleEvents = "ourhours.achievedBubbleEvents"
        static let seenUnlockedItems = "ourhours.seenBubbleUnlockIDs"
        static let unseenUnlockedItems = "ourhours.unseenBubbleUnlockIDs"
        static let birthday = "ourhours.localBirthday"
        static let nickname = "ourhours.partnerNickname"
        static let anniversaryMarkStyle = "ourhours.anniversaryMarkStyle"
        static let myBirthdayMarkStyle = "ourhours.myBirthdayMarkStyle"
        static let partnerBirthdayMarkStyle = "ourhours.partnerBirthdayMarkStyle"
        static let avatarAssetID = "ourhours.localAvatarAssetID"
    }

    private let userDefaults: UserDefaults
    private(set) var hasCompletedOnboarding: Bool
    private(set) var localBubbleColor: BubbleColorTheme
    private(set) var localBubbleExpression: BubbleExpression
    private(set) var localBubbleExpressionRotation: [BubbleExpression]
    private(set) var localBubbleDecorations: BubbleDecorationLoadout
    private(set) var partnerDisplayOverride: PartnerBubbleDisplayOverride
    private(set) var hasDiscoveredSecretPop: Bool
    private(set) var achievedBubbleEvents: Set<BubbleEventKind>
    private(set) var seenUnlockedItemIDs: Set<String>
    private(set) var unseenUnlockedItemIDs: Set<String>
    private(set) var activeUnlockBanner: BubbleUnlockBanner?
    private(set) var localBirthday: CalendarDateValue?
    private(set) var localAvatarAssetID: UUID?
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
    @ObservationIgnored private var scheduledAssetSyncTask: Task<Void, Never>?
    @ObservationIgnored private var secretPopUnlockTask: Task<Void, Never>?
    @ObservationIgnored private var pairSpaceSetupTask: Task<PairSpaceContext?, Never>?
    @ObservationIgnored private var pairSpaceResetTask: Task<Void, Never>?
    @ObservationIgnored private var historySyncTask: Task<HistorySyncOutcome?, Never>?
    @ObservationIgnored private var locationSyncTask: Task<LocationSyncOutcome?, Never>?
    @ObservationIgnored private var assetSyncTask: Task<Void, Never>?
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

    private let assetStore: PairAssetStore
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()
    private(set) var assetRevision = 0
    private(set) var mediaImportProgress: MediaTransferProgress?
    private(set) var assetUploadProgress: MediaTransferProgress?
    private(set) var assetDownloadProgress: MediaTransferProgress?
    private(set) var uploadingMediaIDs: Set<UUID> = []

    var activeMediaProgress: MediaTransferProgress? {
        mediaImportProgress ?? assetUploadProgress ?? assetDownloadProgress
    }

    func isMediaUploading(id: UUID) -> Bool {
        uploadingMediaIDs.contains(id)
    }

    func setMediaImportProgress(_ progress: MediaTransferProgress?) {
        mediaImportProgress = progress
    }

    private let peerSyncStore: PartnerSyncStore
    private let historySync: CloudKitHistorySync
    private(set) var peerSessions: [SyncedPeerSession] = []
    private(set) var historySyncState: HistorySyncState = .idle

    private let locationStore: LocationTimelineStore
    private let locationSync: CloudKitLocationSync
    #if DEBUG
    private let isSandboxDemo: Bool
    var debugSimulatedActiveSessionStart: Date?
    var debugUnlockAllBubbleItems = false
    var debugBonusHours: Double = 0
    var debugBonusDays: Int = 0
    var debugSimulatedEvents: Set<BubbleEventKind> = []
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
        userDefaults: UserDefaults = .standard,
        assetStore: PairAssetStore = PairAssetStore()
    ) {
        #if DEBUG
        isSandboxDemo = locationMonitor is ScreenshotLocationMonitor
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
        localBubbleExpression = userDefaults.string(forKey: DefaultsKey.expression)
            .flatMap(BubbleExpression.init(rawValue:)) ?? .classic
        localBubbleExpressionRotation = (userDefaults.stringArray(forKey: DefaultsKey.expressionRotation) ?? [])
            .compactMap(BubbleExpression.init(rawValue:))
        localBubbleDecorations = userDefaults.data(forKey: DefaultsKey.decorations).flatMap {
            try? JSONDecoder().decode(BubbleDecorationLoadout.self, from: $0)
        } ?? .none
        partnerDisplayOverride = userDefaults.data(forKey: DefaultsKey.partnerDisplayOverride).flatMap {
            try? JSONDecoder().decode(PartnerBubbleDisplayOverride.self, from: $0)
        } ?? .none
        hasDiscoveredSecretPop = userDefaults.bool(forKey: DefaultsKey.discoveredSecretPop)
        achievedBubbleEvents = Set(
            (userDefaults.stringArray(forKey: DefaultsKey.achievedBubbleEvents) ?? [])
                .compactMap(BubbleEventKind.init(rawValue:))
        )
        var initialSeenIDs = Set(userDefaults.stringArray(forKey: DefaultsKey.seenUnlockedItems) ?? [])
        initialSeenIDs.formUnion(BubbleUnlockCatalog.starterItemIDs)
        seenUnlockedItemIDs = initialSeenIDs
        unseenUnlockedItemIDs = Set(userDefaults.stringArray(forKey: DefaultsKey.unseenUnlockedItems) ?? [])
        localBirthday = userDefaults.data(forKey: DefaultsKey.birthday).flatMap {
            try? JSONDecoder().decode(CalendarDateValue.self, from: $0)
        }
        localAvatarAssetID = userDefaults.string(forKey: DefaultsKey.avatarAssetID).flatMap(UUID.init(uuidString:))
        partnerNickname = userDefaults.string(forKey: DefaultsKey.nickname) ?? ""
        anniversaryMarkStyle = userDefaults.string(forKey: DefaultsKey.anniversaryMarkStyle)
            .flatMap(AnniversaryMarkStyle.init(rawValue:)) ?? .heart
        myBirthdayMarkStyle = userDefaults.string(forKey: DefaultsKey.myBirthdayMarkStyle)
            .flatMap(BirthdayMarkStyle.init(rawValue:)) ?? .cake
        partnerBirthdayMarkStyle = userDefaults.string(forKey: DefaultsKey.partnerBirthdayMarkStyle)
            .flatMap(BirthdayMarkStyle.init(rawValue:)) ?? .cake
        self.engine = engine
        self.journalStore = journalStore
        self.assetStore = assetStore
        self.imageCache.countLimit = 80
        self.imageCache.totalCostLimit = 60 * 1024 * 1024
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
                        role: pair.localRole,
                        bubbleColor: localBubbleColor,
                        birthday: localBirthday,
                        avatarAssetID: localAvatarAssetID,
                        expression: localBubbleExpression,
                        expressionRotationPool: localBubbleExpressionRotation,
                        decorations: localBubbleDecorations
                    )
                } else if localAvatarAssetID == nil,
                          let existingAvatar = journal.profile(for: pair.localRole)?.avatarAssetID {
                    localAvatarAssetID = existingAvatar
                    userDefaults.set(existingAvatar.uuidString, forKey: DefaultsKey.avatarAssetID)
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
        if isSandboxDemo {
            evaluateBubbleUnlocks(allowNotification: false)
            unseenUnlockedItemIDs.removeAll()
            pairSpaceStatus = .connected(scope: .privateDB, shareURL: initialSnapshot.pairConfiguration?.cloudShareURL, sameAppleID: false)
            historySyncState = .synced(.now, peerSessions: 0)
            return
        }
        #endif
        evaluateBubbleUnlocks(allowNotification: false)
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
                    self.evaluateBubbleUnlocks(allowNotification: true)
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
        scheduledAssetSyncTask?.cancel()
        secretPopUnlockTask?.cancel()
        assetSyncTask?.cancel()
    }

    private var partnerProfile: SyncedRoleProfile? {
        guard let role = snapshot.pairConfiguration?.localRole else { return nil }
        return journal.profile(for: role.opposite)
    }

    var partnerBubbleColor: BubbleColorTheme? { partnerProfile?.bubbleColor }
    var partnerBubbleExpression: BubbleExpression { partnerProfile?.expression ?? .classic }
    var partnerBubbleExpressionRotation: [BubbleExpression] { partnerProfile?.expressionRotationPool ?? [] }
    var partnerBubbleDecorations: BubbleDecorationLoadout { partnerProfile?.decorations ?? .none }
    var effectivePartnerBubbleColor: BubbleColorTheme? { partnerDisplayOverride.color ?? partnerBubbleColor }
    var effectivePartnerBubbleExpression: BubbleExpression { partnerDisplayOverride.expression ?? partnerBubbleExpression }
    var effectivePartnerBubbleExpressionRotation: [BubbleExpression] {
        partnerDisplayOverride.expressionRotationPool ?? partnerBubbleExpressionRotation
    }
    var effectivePartnerBubbleDecorations: BubbleDecorationLoadout { partnerDisplayOverride.decorations ?? partnerBubbleDecorations }
    var partnerBirthday: CalendarDateValue? { partnerProfile?.birthday }
    var partnerAvatarAssetID: UUID? { partnerProfile?.avatarAssetID }
    var localAvatarImage: UIImage? { localAvatarAssetID.flatMap { cachedOrLoadedImage(kind: .avatar, id: $0) } }
    var partnerAvatarImage: UIImage? { partnerAvatarAssetID.flatMap { cachedOrLoadedImage(kind: .avatar, id: $0) } }
    var anniversaryDate: CalendarDateValue? { journal.anniversary?.date }

    func avatarImage(for role: PeerRole?) -> UIImage? {
        guard let role else { return nil }
        if role == snapshot.pairConfiguration?.localRole { return localAvatarImage }
        if role == snapshot.pairConfiguration?.localRole.opposite { return partnerAvatarImage }
        return journal.profile(for: role)?.avatarAssetID.flatMap { cachedOrLoadedImage(kind: .avatar, id: $0) }
    }

    func dayPhotoImage(id: UUID) -> UIImage? {
        cachedOrLoadedImage(kind: .dayPhoto, id: id)
    }

    func dayMediaThumbnail(for item: DayPhotoAttachment) -> UIImage? {
        dayPhotoImage(id: item.thumbnailAssetID ?? item.id)
    }

    func dayVideoURL(id: UUID) -> URL? {
        _ = assetRevision
        guard assetStore.exists(kind: .dayVideo, id: id) else {
            if snapshot.isPaired {
                scheduleAssetSync(delay: .milliseconds(50))
            }
            return nil
        }
        return assetStore.fileURL(kind: .dayVideo, id: id)
    }

    func mediaAttachment(id: UUID) -> DayPhotoAttachment? {
        let pairID = snapshot.pairConfiguration?.pairID
        return journal.dayPhotos.first { item in
            item.id == id && (pairID == nil || item.pairID == nil || item.pairID == pairID)
        }
    }

    private func cachedOrLoadedImage(kind: PairAssetKind, id: UUID) -> UIImage? {
        _ = assetRevision
        let key = "\(kind.rawValue):\(id.uuidString)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let data = assetStore.loadData(kind: kind, id: id),
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    func localMemoText(forDayKey dayKey: String) -> String {
        let pairID = snapshot.pairConfiguration?.pairID
        if let localRole = snapshot.pairConfiguration?.localRole {
            let roleKey = DailyMemo.roleMemoKey(dayKey: dayKey, role: localRole)
            if let roleMemo = journal.roleDailyMemos[roleKey],
               pairID == nil || roleMemo.pairID == nil || roleMemo.pairID == pairID {
                return roleMemo.text
            }
            if journal.deletedRoleMemoKeys[roleKey] != nil {
                return ""
            }
            if let legacy = journal.dailyMemos[dayKey],
               pairID == nil || legacy.pairID == nil || legacy.pairID == pairID,
               legacy.authorRole == nil || legacy.authorRole == localRole {
                return legacy.text
            }
            return ""
        }
        if let legacy = journal.dailyMemos[dayKey],
           pairID == nil || legacy.pairID == nil || legacy.pairID == pairID {
            return legacy.text
        }
        return ""
    }

    func partnerMemoText(forDayKey dayKey: String) -> String? {
        guard let pair = snapshot.pairConfiguration else { return nil }
        let partnerRole = pair.localRole.opposite
        let roleKey = DailyMemo.roleMemoKey(dayKey: dayKey, role: partnerRole)
        if let roleMemo = journal.roleDailyMemos[roleKey],
           roleMemo.pairID == nil || roleMemo.pairID == pair.pairID {
            let trimmed = roleMemo.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : roleMemo.text
        }
        if journal.deletedRoleMemoKeys[roleKey] != nil {
            return nil
        }
        if let legacy = journal.dailyMemos[dayKey],
           legacy.pairID == nil || legacy.pairID == pair.pairID,
           legacy.authorRole == partnerRole {
            let trimmed = legacy.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : legacy.text
        }
        return nil
    }

    func memo(forDayKey dayKey: String) -> DailyMemo? {
        let pairID = snapshot.pairConfiguration?.pairID
        let candidates = [
            snapshot.pairConfiguration.map { journal.roleDailyMemos[DailyMemo.roleMemoKey(dayKey: dayKey, role: $0.localRole)] } ?? nil,
            snapshot.pairConfiguration.map { journal.roleDailyMemos[DailyMemo.roleMemoKey(dayKey: dayKey, role: $0.localRole.opposite)] } ?? nil,
            journal.dailyMemos[dayKey]
        ].compactMap { memo -> DailyMemo? in
            guard let memo, pairID == nil || memo.pairID == nil || memo.pairID == pairID else { return nil }
            let trimmed = memo.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : memo
        }
        return candidates.max { $0.updatedAt < $1.updatedAt }
    }

    func photos(forDayKey dayKey: String) -> [DayPhotoAttachment] {
        let pairID = snapshot.pairConfiguration?.pairID
        return journal.dayPhotos
            .filter { photo in
                photo.dayKey == dayKey && (pairID == nil || photo.pairID == nil || photo.pairID == pairID)
            }
            .sorted {
                let lhsDate = $0.capturedAt ?? $0.createdAt
                let rhsDate = $1.capturedAt ?? $1.createdAt
                return (lhsDate, $0.createdAt, $0.id.uuidString) < (rhsDate, $1.createdAt, $1.id.uuidString)
            }
    }

    func placeTags(forDayKey dayKey: String) -> [DayPlaceTag] {
        let pairID = snapshot.pairConfiguration?.pairID
        return journal.dayPlaceTags
            .filter { tag in
                tag.dayKey == dayKey && (pairID == nil || tag.pairID == nil || tag.pairID == pairID)
            }
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
    }

    var allMediaAttachments: [DayPhotoAttachment] {
        let pairID = snapshot.pairConfiguration?.pairID
        return journal.dayPhotos
            .filter { pairID == nil || $0.pairID == nil || $0.pairID == pairID }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey > rhs.dayKey }
                let lhsDate = lhs.capturedAt ?? lhs.createdAt
                let rhsDate = rhs.capturedAt ?? rhs.createdAt
                return (lhsDate, lhs.createdAt, lhs.id.uuidString) > (rhsDate, rhs.createdAt, rhs.id.uuidString)
            }
    }

    func mediaAttachments(linkedToPlaceTagID tagID: UUID, onDayKey dayKey: String) -> [DayPhotoAttachment] {
        photos(forDayKey: dayKey).filter { $0.placeTagID == tagID }
    }

    var allPlanEvents: [PairPlanEvent] {
        let pairID = snapshot.pairConfiguration?.pairID
        return journal.planEvents
            .filter { pairID == nil || $0.pairID == nil || $0.pairID == pairID }
            .sorted { lhs, rhs in
                if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey > rhs.startDayKey }
                if lhs.endDayKey != rhs.endDayKey { return lhs.endDayKey > rhs.endDayKey }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func planEvent(id: UUID) -> PairPlanEvent? {
        allPlanEvents.first { $0.id == id }
    }

    func planEvents(forDayKey dayKey: String) -> [PairPlanEvent] {
        allPlanEvents
            .filter { $0.contains(dayKey: dayKey) }
            .sorted { lhs, rhs in
                if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func planEvents(overlappingMonth monthDate: Date) -> [PairPlanEvent] {
        let cal = CalendarDateValue.gregorianCurrent
        let comps = cal.dateComponents([.year, .month], from: monthDate)
        let monthKey = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        return allPlanEvents
            .filter { $0.overlaps(monthKey: monthKey) }
            .sorted { lhs, rhs in
                if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func upcomingPlanEvents(asOf date: Date = .now) -> [PairPlanEvent] {
        let todayKey = EncounterCalendarAggregator.dayKey(for: date, calendar: CalendarDateValue.gregorianCurrent)
        return allPlanEvents
            .filter { $0.endDayKey >= todayKey }
            .sorted { lhs, rhs in
                if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func mediaAttachments(for plan: PairPlanEvent) -> [DayPhotoAttachment] {
        PairPlanAlbumResolver.mediaAttachments(
            for: plan,
            in: journal.dayPhotos,
            pairID: snapshot.pairConfiguration?.pairID
        )
    }

    func placeTags(for plan: PairPlanEvent) -> [DayPlaceTag] {
        PairPlanAlbumResolver.placeTags(
            for: plan,
            in: journal.dayPlaceTags,
            pairID: snapshot.pairConfiguration?.pairID
        )
    }

    func effectivePlan(for photo: DayPhotoAttachment) -> PairPlanEvent? {
        PairPlanAlbumResolver.effectivePlan(for: photo, among: allPlanEvents)
    }

    func recordedSeconds(for plan: PairPlanEvent, asOf now: Date = .now) -> TimeInterval {
        let cal = CalendarDateValue.gregorianCurrent
        let startDayStart = cal.startOfDay(for: plan.startDate(calendar: cal))
        let endDayStart = cal.startOfDay(for: plan.endDate(calendar: cal))
        guard let rangeEnd = cal.date(byAdding: .day, value: 1, to: endDayStart),
              rangeEnd > startDayStart else {
            return 0
        }
        let targetInterval = DateInterval(start: startDayStart, end: rangeEnd)
        let intervals: [DateInterval] = resolvedEncounters.compactMap { enc in
            let endDate: Date? = switch enc.status {
            case .completed: enc.endedAt
            case .active: max(enc.startedAt, now)
            case .unknownEnd: nil
            }
            guard let endDate, endDate > enc.startedAt else { return nil }
            let clampedStart = max(enc.startedAt, targetInterval.start)
            let clampedEnd = min(endDate, targetInterval.end)
            guard clampedEnd > clampedStart else { return nil }
            return DateInterval(start: clampedStart, end: clampedEnd)
        }
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var curStart = sorted[0].start
        var curEnd = sorted[0].end
        for interval in sorted.dropFirst() {
            if interval.start <= curEnd {
                curEnd = max(curEnd, interval.end)
            } else {
                total += curEnd.timeIntervalSince(curStart)
                curStart = interval.start
                curEnd = interval.end
            }
        }
        total += curEnd.timeIntervalSince(curStart)
        return total
    }

    var memoryMapPins: [MemoryMapPin] {
        MemoryMapPinBuilder.buildPins(from: journal, pairID: snapshot.pairConfiguration?.pairID)
    }

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

    func setLocalBubbleExpression(_ expression: BubbleExpression) {
        localBubbleExpression = expression
        userDefaults.set(expression.rawValue, forKey: DefaultsKey.expression)
        publishLocalProfile()
    }

    func setLocalBubbleExpressionRotation(_ pool: [BubbleExpression]) {
        var seen = Set<BubbleExpression>()
        let deduplicated = pool.filter { seen.insert($0).inserted }
        localBubbleExpressionRotation = deduplicated
        userDefaults.set(deduplicated.map(\.rawValue), forKey: DefaultsKey.expressionRotation)
        publishLocalProfile()
    }

    func setLocalBubbleDecorations(_ decorations: BubbleDecorationLoadout) {
        localBubbleDecorations = decorations
        if let encoded = try? JSONEncoder().encode(decorations) {
            userDefaults.set(encoded, forKey: DefaultsKey.decorations)
        }
        publishLocalProfile()
    }

    func setPartnerDisplayOverride(_ override: PartnerBubbleDisplayOverride) {
        partnerDisplayOverride = override
        if override.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.partnerDisplayOverride)
        } else if let encoded = try? JSONEncoder().encode(override) {
            userDefaults.set(encoded, forKey: DefaultsKey.partnerDisplayOverride)
        }
    }

    func clearPartnerDisplayOverride() {
        partnerDisplayOverride = .none
        userDefaults.removeObject(forKey: DefaultsKey.partnerDisplayOverride)
    }

    func setLocalBirthday(_ birthday: CalendarDateValue?) {
        localBirthday = birthday
        let encoded = birthday.flatMap { try? JSONEncoder().encode($0) }
        userDefaults.set(encoded, forKey: DefaultsKey.birthday)
        publishLocalProfile()
        evaluateBubbleUnlocks(allowNotification: true)
    }

    private func publishLocalProfile() {
        guard let role = snapshot.pairConfiguration?.localRole else { return }
        write {
            try $0.setRoleProfile(
                role: role,
                bubbleColor: localBubbleColor,
                birthday: localBirthday,
                avatarAssetID: localAvatarAssetID,
                expression: localBubbleExpression,
                expressionRotationPool: localBubbleExpressionRotation,
                decorations: localBubbleDecorations
            )
        }
        scheduleHistorySyncIfPaired()
    }

    @discardableResult
    func setLocalAvatar(rawImageData: Data) -> Bool {
        guard let jpegData = PhotoMetadataProcessor.processAvatar(from: rawImageData) else { return false }
        return setLocalAvatar(croppedJPEGData: jpegData)
    }

    @discardableResult
    func setLocalAvatar(croppedJPEGData jpegData: Data) -> Bool {
        let newID = UUID()
        do {
            try assetStore.saveData(jpegData, kind: .avatar, id: newID)
        } catch {
            journalError = error.localizedDescription
            return false
        }
        let previousID = localAvatarAssetID
        localAvatarAssetID = newID
        userDefaults.set(newID.uuidString, forKey: DefaultsKey.avatarAssetID)
        if let image = UIImage(data: jpegData) {
            imageCache.setObject(image, forKey: "\(PairAssetKind.avatar.rawValue):\(newID.uuidString)" as NSString)
        }
        if let previousID {
            assetStore.deleteData(kind: .avatar, id: previousID)
            imageCache.removeObject(forKey: "\(PairAssetKind.avatar.rawValue):\(previousID.uuidString)" as NSString)
            deleteRemoteAssetBestEffort(kind: .avatar, id: previousID)
        }
        assetRevision += 1
        publishLocalProfile()
        scheduleAssetSync(delay: .seconds(1))
        return true
    }

    func clearLocalAvatar() {
        let previousID = localAvatarAssetID
        localAvatarAssetID = nil
        userDefaults.removeObject(forKey: DefaultsKey.avatarAssetID)
        if let previousID {
            assetStore.deleteData(kind: .avatar, id: previousID)
            imageCache.removeObject(forKey: "\(PairAssetKind.avatar.rawValue):\(previousID.uuidString)" as NSString)
            deleteRemoteAssetBestEffort(kind: .avatar, id: previousID)
        }
        assetRevision += 1
        publishLocalProfile()
    }

    func setPartnerNickname(_ nickname: String) {
        partnerNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(partnerNickname, forKey: DefaultsKey.nickname)
    }

    func setAnniversaryDate(_ date: CalendarDateValue?) {
        write { try $0.setAnniversary(date) }
        evaluateBubbleUnlocks(allowNotification: true)
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
        if isSandboxDemo { return }
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
        if let debugSimulatedActiveSessionStart { return debugSimulatedActiveSessionStart }
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
        if let localRole = snapshot.pairConfiguration?.localRole {
            write {
                try $0.setRoleMemo(
                    dayKey: dayKey,
                    role: localRole,
                    text: text,
                    pairID: snapshot.pairConfiguration?.pairID
                )
            }
        } else {
            write {
                try $0.setMemo(dayKey: dayKey, text: text, pairID: nil, authorRole: nil)
            }
        }
        scheduleHistorySyncIfPaired()
    }

    @discardableResult
    func addDayPhoto(
        dayKey: String,
        rawImageData: Data,
        overrideCoordinate: GeoCoordinate? = nil,
        overrideLocationName: String? = nil,
        placeTagID: UUID? = nil,
        planID: UUID? = nil
    ) async -> DayPhotoAttachment? {
        guard let processed = await Task.detached(priority: .userInitiated, operation: {
            PhotoMetadataProcessor.processDayPhoto(from: rawImageData)
        }).value else { return nil }
        return await commitProcessedPhoto(
            processed,
            dayKey: dayKey,
            overrideCoordinate: overrideCoordinate,
            overrideLocationName: overrideLocationName,
            placeTagID: placeTagID,
            planID: planID
        )
    }

    @discardableResult
    func addAlbumPhoto(
        rawImageData: Data,
        planID: UUID? = nil,
        fallbackDayKey: String? = nil
    ) async -> DayPhotoAttachment? {
        guard let processed = await Task.detached(priority: .userInitiated, operation: {
            PhotoMetadataProcessor.processDayPhoto(from: rawImageData)
        }).value else { return nil }
        let dayKey = processed.capturedAt.map { EncounterCalendarAggregator.dayKey(for: $0) }
            ?? fallbackDayKey
            ?? EncounterCalendarAggregator.dayKey(for: .now)
        return await commitProcessedPhoto(processed, dayKey: dayKey, planID: planID)
    }

    private func commitProcessedPhoto(
        _ processed: ProcessedDayPhoto,
        dayKey: String,
        overrideCoordinate: GeoCoordinate? = nil,
        overrideLocationName: String? = nil,
        placeTagID: UUID? = nil,
        planID: UUID? = nil
    ) async -> DayPhotoAttachment? {
        let resolvedCoord = overrideCoordinate?.isValid == true ? overrideCoordinate : processed.coordinate
        let resolvedName = await resolveLocationName(overrideLocationName: overrideLocationName, coordinate: resolvedCoord)

        let photoID = UUID()
        do {
            try assetStore.saveData(processed.jpegData, kind: .dayPhoto, id: photoID)
        } catch {
            journalError = error.localizedDescription
            return nil
        }
        if let image = UIImage(data: processed.jpegData) {
            imageCache.setObject(image, forKey: "\(PairAssetKind.dayPhoto.rawValue):\(photoID.uuidString)" as NSString)
        }

        let attachment = DayPhotoAttachment(
            id: photoID,
            pairID: snapshot.pairConfiguration?.pairID,
            dayKey: dayKey,
            authorRole: snapshot.pairConfiguration?.localRole,
            mediaKind: .photo,
            placeTagID: placeTagID,
            coordinate: resolvedCoord,
            capturedAt: processed.capturedAt,
            locationName: resolvedName,
            planID: planID
        )
        write { try $0.addDayPhoto(attachment) }
        assetRevision += 1
        scheduleHistorySyncIfPaired()
        scheduleAssetSync(delay: .milliseconds(300))
        return attachment
    }

    @discardableResult
    func addDayVideo(
        dayKey: String,
        fileURL: URL,
        overrideCoordinate: GeoCoordinate? = nil,
        overrideLocationName: String? = nil,
        placeTagID: UUID? = nil,
        planID: UUID? = nil,
        onExportProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> DayPhotoAttachment? {
        guard let processed = await PhotoMetadataProcessor.processDayVideo(
            from: fileURL,
            onProgress: onExportProgress
        ) else {
            return nil
        }
        return await commitProcessedVideo(
            processed,
            dayKey: dayKey,
            overrideCoordinate: overrideCoordinate,
            overrideLocationName: overrideLocationName,
            placeTagID: placeTagID,
            planID: planID
        )
    }

    @discardableResult
    func addAlbumVideo(
        fileURL: URL,
        planID: UUID? = nil,
        fallbackDayKey: String? = nil,
        onExportProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> DayPhotoAttachment? {
        guard let processed = await PhotoMetadataProcessor.processDayVideo(
            from: fileURL,
            onProgress: onExportProgress
        ) else {
            return nil
        }
        let dayKey = processed.capturedAt.map { EncounterCalendarAggregator.dayKey(for: $0) }
            ?? fallbackDayKey
            ?? EncounterCalendarAggregator.dayKey(for: .now)
        return await commitProcessedVideo(processed, dayKey: dayKey, planID: planID)
    }

    private func commitProcessedVideo(
        _ processed: ProcessedDayVideo,
        dayKey: String,
        overrideCoordinate: GeoCoordinate? = nil,
        overrideLocationName: String? = nil,
        placeTagID: UUID? = nil,
        planID: UUID? = nil
    ) async -> DayPhotoAttachment? {
        let resolvedCoord = overrideCoordinate?.isValid == true ? overrideCoordinate : processed.coordinate
        let resolvedName = await resolveLocationName(overrideLocationName: overrideLocationName, coordinate: resolvedCoord)

        let videoID = UUID()
        let thumbID = UUID()
        do {
            try assetStore.saveData(processed.videoData, kind: .dayVideo, id: videoID)
            try assetStore.saveData(processed.thumbnailJPEGData, kind: .dayPhoto, id: thumbID)
        } catch {
            assetStore.deleteData(kind: .dayVideo, id: videoID)
            assetStore.deleteData(kind: .dayPhoto, id: thumbID)
            journalError = error.localizedDescription
            return nil
        }
        if let thumbImage = UIImage(data: processed.thumbnailJPEGData) {
            imageCache.setObject(thumbImage, forKey: "\(PairAssetKind.dayPhoto.rawValue):\(thumbID.uuidString)" as NSString)
        }

        let attachment = DayPhotoAttachment(
            id: videoID,
            pairID: snapshot.pairConfiguration?.pairID,
            dayKey: dayKey,
            authorRole: snapshot.pairConfiguration?.localRole,
            mediaKind: .video,
            durationSeconds: processed.durationSeconds,
            thumbnailAssetID: thumbID,
            placeTagID: placeTagID,
            coordinate: resolvedCoord,
            capturedAt: processed.capturedAt,
            locationName: resolvedName,
            planID: planID
        )
        write { try $0.addDayPhoto(attachment) }
        assetRevision += 1
        scheduleHistorySyncIfPaired()
        scheduleAssetSync(delay: .milliseconds(300))
        return attachment
    }

    private func resolveLocationName(overrideLocationName: String?, coordinate: GeoCoordinate?) async -> String? {
        let trimmed = overrideLocationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        guard let coordinate else { return nil }
        #if DEBUG
        if isSandboxDemo { return nil }
        #endif
        return await PhotoMetadataProcessor.reverseGeocodeName(for: coordinate)
    }

    func updateDayPhotoLocation(
        id: UUID,
        coordinate: GeoCoordinate?,
        locationName: String?,
        placeTagID: UUID? = nil
    ) {
        write {
            try $0.updateDayPhotoLocation(
                id: id,
                coordinate: coordinate,
                locationName: locationName,
                placeTagID: placeTagID
            )
        }
        scheduleHistorySyncIfPaired()
    }

    func linkMedia(id: UUID, to placeTag: DayPlaceTag) {
        let existing = mediaAttachment(id: id)
        let coord = placeTag.coordinate ?? existing?.coordinate
        updateDayPhotoLocation(
            id: id,
            coordinate: coord,
            locationName: placeTag.name,
            placeTagID: placeTag.id
        )
    }

    func unlinkMediaFromPlaceTag(id: UUID) {
        guard let existing = mediaAttachment(id: id) else { return }
        updateDayPhotoLocation(
            id: id,
            coordinate: existing.coordinate,
            locationName: existing.locationName,
            placeTagID: nil
        )
    }

    func setLinkedMedia(_ selectedIDs: Set<UUID>, for tag: DayPlaceTag) {
        for photo in photos(forDayKey: tag.dayKey) {
            if selectedIDs.contains(photo.id) {
                let targetCoord = tag.coordinate ?? photo.coordinate
                if photo.placeTagID != tag.id || photo.locationName != tag.name || photo.coordinate != targetCoord {
                    linkMedia(id: photo.id, to: tag)
                }
            } else if photo.placeTagID == tag.id {
                unlinkMediaFromPlaceTag(id: photo.id)
            }
        }
    }

    func deleteDayPhoto(id: UUID) {
        let existing = mediaAttachment(id: id)
        if existing?.mediaKind == .video {
            assetStore.deleteData(kind: .dayVideo, id: id)
            deleteRemoteAssetBestEffort(kind: .dayVideo, id: id)
            if let thumbID = existing?.thumbnailAssetID {
                assetStore.deleteData(kind: .dayPhoto, id: thumbID)
                imageCache.removeObject(forKey: "\(PairAssetKind.dayPhoto.rawValue):\(thumbID.uuidString)" as NSString)
                deleteRemoteAssetBestEffort(kind: .dayPhoto, id: thumbID)
            }
        } else {
            assetStore.deleteData(kind: .dayPhoto, id: id)
            imageCache.removeObject(forKey: "\(PairAssetKind.dayPhoto.rawValue):\(id.uuidString)" as NSString)
            deleteRemoteAssetBestEffort(kind: .dayPhoto, id: id)
        }
        write { try $0.deleteDayPhoto(id: id) }
        assetRevision += 1
        scheduleHistorySyncIfPaired()
    }

    @discardableResult
    func addDayPlaceTag(
        dayKey: String,
        name: String,
        address: String? = nil,
        coordinate: GeoCoordinate? = nil
    ) -> DayPlaceTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tag = DayPlaceTag(
            pairID: snapshot.pairConfiguration?.pairID,
            dayKey: dayKey,
            name: trimmed,
            address: address,
            coordinate: coordinate,
            authorRole: snapshot.pairConfiguration?.localRole
        )
        write { try $0.addDayPlaceTag(tag) }
        scheduleHistorySyncIfPaired()
        return tag
    }

    @discardableResult
    func updateDayPlaceTag(
        _ existing: DayPlaceTag,
        name: String,
        address: String?,
        coordinate: GeoCoordinate?
    ) -> DayPlaceTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let updated = DayPlaceTag(
            id: existing.id,
            pairID: existing.pairID ?? snapshot.pairConfiguration?.pairID,
            dayKey: existing.dayKey,
            name: trimmed,
            address: address,
            coordinate: coordinate,
            authorRole: existing.authorRole ?? snapshot.pairConfiguration?.localRole,
            createdAt: existing.createdAt,
            updatedAt: .now
        )
        write { try $0.addDayPlaceTag(updated) }
        for photo in photos(forDayKey: existing.dayKey) where photo.placeTagID == existing.id {
            updateDayPhotoLocation(
                id: photo.id,
                coordinate: updated.coordinate ?? photo.coordinate,
                locationName: updated.name,
                placeTagID: updated.id
            )
        }
        scheduleHistorySyncIfPaired()
        return updated
    }

    func deleteDayPlaceTag(id: UUID) {
        let linkedPhotos = journal.dayPhotos.filter { $0.placeTagID == id }
        write { try $0.deleteDayPlaceTag(id: id) }
        for photo in linkedPhotos {
            updateDayPhotoLocation(
                id: photo.id,
                coordinate: photo.coordinate,
                locationName: photo.locationName,
                placeTagID: nil
            )
        }
        scheduleHistorySyncIfPaired()
    }

    @discardableResult
    func savePlanEvent(
        existingID: UUID? = nil,
        title: String,
        startDayKey: String,
        endDayKey: String,
        icon: PairPlanIcon,
        memo: String?,
        checklist: [PairPlanChecklistItem]
    ) -> PairPlanEvent? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = existingID.flatMap { planEvent(id: $0) }
        let normalizedChecklist = checklist.compactMap { item -> PairPlanChecklistItem? in
            let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemTitle.isEmpty else { return nil }
            return PairPlanChecklistItem(id: item.id, title: itemTitle, isDone: item.isDone, kind: item.kind)
        }
        let event = PairPlanEvent(
            id: existing?.id ?? existingID ?? UUID(),
            pairID: existing?.pairID ?? snapshot.pairConfiguration?.pairID,
            title: trimmed,
            startDayKey: startDayKey,
            endDayKey: endDayKey,
            icon: icon,
            memo: memo,
            checklist: normalizedChecklist,
            authorRole: existing?.authorRole ?? snapshot.pairConfiguration?.localRole,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        write { try $0.upsertPlanEvent(event) }
        scheduleHistorySyncIfPaired()
        return planEvent(id: event.id) ?? event
    }

    @discardableResult
    func appendPlanChecklistItem(planID: UUID, title: String, kind: PairPlanChecklistKind) -> PairPlanChecklistItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let plan = planEvent(id: planID) else { return nil }
        let newItem = PairPlanChecklistItem(title: trimmed, isDone: false, kind: kind)
        var checklist = plan.checklist
        checklist.append(newItem)
        let updated = PairPlanEvent(
            id: plan.id,
            pairID: plan.pairID ?? snapshot.pairConfiguration?.pairID,
            title: plan.title,
            startDayKey: plan.startDayKey,
            endDayKey: plan.endDayKey,
            icon: plan.icon,
            memo: plan.memo,
            checklist: checklist,
            authorRole: plan.authorRole ?? snapshot.pairConfiguration?.localRole,
            createdAt: plan.createdAt,
            updatedAt: .now
        )
        write { try $0.upsertPlanEvent(updated) }
        scheduleHistorySyncIfPaired()
        return newItem
    }

    func removePlanChecklistItem(planID: UUID, itemID: UUID) {
        guard let plan = planEvent(id: planID) else { return }
        let filtered = plan.checklist.filter { $0.id != itemID }
        guard filtered.count != plan.checklist.count else { return }
        let updated = PairPlanEvent(
            id: plan.id,
            pairID: plan.pairID ?? snapshot.pairConfiguration?.pairID,
            title: plan.title,
            startDayKey: plan.startDayKey,
            endDayKey: plan.endDayKey,
            icon: plan.icon,
            memo: plan.memo,
            checklist: filtered,
            authorRole: plan.authorRole ?? snapshot.pairConfiguration?.localRole,
            createdAt: plan.createdAt,
            updatedAt: .now
        )
        write { try $0.upsertPlanEvent(updated) }
        scheduleHistorySyncIfPaired()
    }

    func togglePlanChecklistItem(planID: UUID, itemID: UUID) {
        guard let plan = planEvent(id: planID),
              let index = plan.checklist.firstIndex(where: { $0.id == itemID }) else { return }
        var checklist = plan.checklist
        checklist[index].isDone.toggle()
        let updated = PairPlanEvent(
            id: plan.id,
            pairID: plan.pairID ?? snapshot.pairConfiguration?.pairID,
            title: plan.title,
            startDayKey: plan.startDayKey,
            endDayKey: plan.endDayKey,
            icon: plan.icon,
            memo: plan.memo,
            checklist: checklist,
            authorRole: plan.authorRole ?? snapshot.pairConfiguration?.localRole,
            createdAt: plan.createdAt,
            updatedAt: .now
        )
        write { try $0.upsertPlanEvent(updated) }
        scheduleHistorySyncIfPaired()
    }

    func deletePlanEvent(id: UUID) {
        write { try $0.deletePlanEvent(id: id) }
        scheduleHistorySyncIfPaired()
    }

    func assignMedia(id: UUID, toPlanID planID: UUID?) {
        guard let existing = mediaAttachment(id: id) else { return }
        let nextExcluded = planID.map { pid in existing.excludedPlanIDs.filter { $0 != pid } } ?? existing.excludedPlanIDs
        write {
            try $0.updateDayPhotoPlanAssignment(
                id: id,
                planID: planID,
                excludedPlanIDs: nextExcluded
            )
        }
        scheduleHistorySyncIfPaired()
    }

    func excludeMedia(id: UUID, fromPlanID planID: UUID) {
        guard let existing = mediaAttachment(id: id) else { return }
        let nextPlanID = existing.planID == planID ? nil : existing.planID
        var nextExcluded = existing.excludedPlanIDs
        if let plan = planEvent(id: planID), plan.contains(dayKey: existing.dayKey), !nextExcluded.contains(planID) {
            nextExcluded.append(planID)
        }
        write {
            try $0.updateDayPhotoPlanAssignment(
                id: id,
                planID: nextPlanID,
                excludedPlanIDs: nextExcluded
            )
        }
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
        evaluateBubbleUnlocks(allowNotification: true)
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

    func lifetimeMetDayCount(asOf date: Date = .now) -> Int {
        EncounterCalendarAggregator.lifetimeMetDayCount(
            autoSessions: snapshot.sessions,
            peerSessions: activePairPeerSessions,
            locationSessions: locationMatchedSessions,
            journal: journal,
            activeReferenceDate: date
        )
    }

    func currentCumulativeSeconds(asOf date: Date = .now) -> TimeInterval {
        let base = lifetimeRecordedSeconds()
        let activeElapsed: TimeInterval
        if let start = activeSessionStartDate {
            activeElapsed = max(0, date.timeIntervalSince(start))
        } else {
            activeElapsed = 0
        }
        #if DEBUG
        return base + activeElapsed + max(0, debugBonusHours) * 3600.0
        #else
        return base + activeElapsed
        #endif
    }

    func currentEffectiveDays(asOf date: Date = .now) -> Int {
        let anniversaryDays = daysTogetherCount(asOf: date) ?? 0
        let metDays = lifetimeMetDayCount(asOf: date)
        let base = max(anniversaryDays, metDays)
        #if DEBUG
        return base + max(0, debugBonusDays)
        #else
        return base
        #endif
    }

    private func detectedEventsSnapshot(asOf date: Date) -> Set<BubbleEventKind> {
        let encounterDates = resolvedEncounters.flatMap { encounter -> [Date] in
            if let end = encounter.endedAt {
                return [encounter.startedAt, end]
            }
            return [encounter.startedAt]
        }
        var detected = BubbleEventDetector.detectedEvents(
            asOf: date,
            encounterDates: encounterDates,
            anniversary: anniversaryDate,
            myBirthday: localBirthday,
            partnerBirthday: partnerBirthday
        )
        detected.formUnion(achievedBubbleEvents)
        #if DEBUG
        detected.formUnion(debugSimulatedEvents)
        #endif
        return detected
    }

    func bubbleUnlockProgress(asOf date: Date = .now) -> BubbleUnlockProgress {
        #if DEBUG
        let unlockAll = debugUnlockAllBubbleItems
        #else
        let unlockAll = false
        #endif
        return BubbleUnlockProgress(
            cumulativeSeconds: currentCumulativeSeconds(asOf: date),
            effectiveDays: currentEffectiveDays(asOf: date),
            hasDiscoveredSecretPop: hasDiscoveredSecretPop,
            achievedEvents: detectedEventsSnapshot(asOf: date),
            unlockAllOverride: unlockAll
        )
    }

    func evaluateBubbleUnlocks(asOf date: Date = .now, allowNotification: Bool = true) {
        let detected = detectedEventsSnapshot(asOf: date)
        #if DEBUG
        let persistentEvents = isSandboxDemo
            ? detected
            : detected.subtracting(debugSimulatedEvents)
        #else
        let persistentEvents = detected
        #endif
        if !persistentEvents.isSubset(of: achievedBubbleEvents) {
            achievedBubbleEvents.formUnion(persistentEvents)
            userDefaults.set(achievedBubbleEvents.map(\.rawValue).sorted(), forKey: DefaultsKey.achievedBubbleEvents)
        }

        let progress = BubbleUnlockProgress(
            cumulativeSeconds: currentCumulativeSeconds(asOf: date),
            effectiveDays: currentEffectiveDays(asOf: date),
            hasDiscoveredSecretPop: hasDiscoveredSecretPop,
            achievedEvents: detected,
            unlockAllOverride: {
                #if DEBUG
                return debugUnlockAllBubbleItems
                #else
                return false
                #endif
            }()
        )
        let newlyUnlocked = progress.unlockedNonStarterItems.filter { !seenUnlockedItemIDs.contains($0.id) }
        guard !newlyUnlocked.isEmpty else { return }

        for item in newlyUnlocked {
            seenUnlockedItemIDs.insert(item.id)
            unseenUnlockedItemIDs.insert(item.id)
        }
        userDefaults.set(Array(seenUnlockedItemIDs).sorted(), forKey: DefaultsKey.seenUnlockedItems)
        userDefaults.set(Array(unseenUnlockedItemIDs).sorted(), forKey: DefaultsKey.unseenUnlockedItems)

        var canShowBanner = allowNotification && hasCompletedOnboarding
        #if DEBUG
        if ScreenshotScene.current != nil {
            canShowBanner = false
        }
        #endif
        if canShowBanner {
            if let existing = activeUnlockBanner {
                var merged = existing.items
                for item in newlyUnlocked where !merged.contains(where: { $0.id == item.id }) {
                    merged.append(item)
                }
                activeUnlockBanner = BubbleUnlockBanner(items: merged)
            } else {
                activeUnlockBanner = BubbleUnlockBanner(items: newlyUnlocked)
            }
        }
    }

    func recordSecretBubblePop() {
        let alreadyDiscovered = hasDiscoveredSecretPop
        if !alreadyDiscovered {
            hasDiscoveredSecretPop = true
            userDefaults.set(true, forKey: DefaultsKey.discoveredSecretPop)
        }
        guard !alreadyDiscovered else { return }
        secretPopUnlockTask?.cancel()
        let delay: Duration = UIAccessibility.isReduceMotionEnabled ? .milliseconds(450) : .milliseconds(2700)
        secretPopUnlockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluateBubbleUnlocks(allowNotification: true)
        }
    }

    func dismissUnlockBanner() {
        activeUnlockBanner = nil
    }

    func markBubbleUnlocksSeen() {
        guard !unseenUnlockedItemIDs.isEmpty else { return }
        unseenUnlockedItemIDs.removeAll()
        userDefaults.removeObject(forKey: DefaultsKey.unseenUnlockedItems)
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
        #if DEBUG
        if isSandboxDemo { return nil }
        #endif
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
        if isSandboxDemo { throw PairSetupError.saveFailed }
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
        write {
            try $0.setRoleProfile(
                role: configuration.localRole,
                bubbleColor: localBubbleColor,
                birthday: localBirthday,
                avatarAssetID: localAvatarAssetID,
                expression: localBubbleExpression,
                expressionRotationPool: localBubbleExpressionRotation,
                decorations: localBubbleDecorations
            )
        }
        if let transitionError { journalError = transitionError }
        if let metadata = pendingExternalShareMetadata {
            pendingExternalShareMetadata = nil
            if metadata.share.recordID.zoneID.zoneName == PairSpaceCrypto.zoneName(for: configuration) {
                handleAcceptedExternalShare(metadata)
            }
        }
        engine.start()
        scheduleHistorySync(delay: .seconds(1))
        scheduleAssetSync(delay: .seconds(2))
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
        if isSandboxDemo { return }
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
        clearPartnerDisplayOverride()
        scheduledSyncTask?.cancel()
        scheduledHistorySyncTask?.cancel()
        scheduledAssetSyncTask?.cancel()
        assetSyncTask?.cancel()
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
        assetUploadProgress = nil
        assetDownloadProgress = nil
        uploadingMediaIDs = []

        if let config { engine.enqueuePendingPurge(config) }

        let previousReset = pairSpaceResetTask
        let setup = pairSpaceSetupTask
        let history = historySyncTask
        let location = locationSyncTask
        let assets = assetSyncTask
        pairSpaceSetupTask = nil
        historySyncTask = nil
        locationSyncTask = nil
        assetSyncTask = nil
        pairSpaceResetTask = Task { [weak self, pairSpace] in
            await previousReset?.value
            _ = await setup?.value
            _ = await history?.value
            _ = await location?.value
            _ = await assets?.value
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
        #if DEBUG
        if isSandboxDemo { return }
        #endif
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
        if isSandboxDemo { return }
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
        evaluateBubbleUnlocks(allowNotification: true)
    }

    func handleBackgroundLocationLaunch() {
        #if DEBUG
        if isSandboxDemo { return }
        #endif
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
        if isSandboxDemo { return nil }
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
            if localAvatarAssetID == nil, let recoveredAvatar = profile?.avatarAssetID {
                localAvatarAssetID = recoveredAvatar
                userDefaults.set(recoveredAvatar.uuidString, forKey: DefaultsKey.avatarAssetID)
                assetRevision += 1
            } else if profile?.bubbleColor != localBubbleColor
                        || profile?.birthday != localBirthday
                        || profile?.avatarAssetID != localAvatarAssetID
                        || profile?.expression != localBubbleExpression
                        || profile?.expressionRotationPool != localBubbleExpressionRotation
                        || profile?.decorations != localBubbleDecorations {
                publishLocalProfile()
            }
        }
        if let updatedPeer = outcome.peerSessions {
            peerSessions = updatedPeer
        }
        evaluateBubbleUnlocks(allowNotification: true)
        if outcome.invalidateContext {
            activePairSpaceContext = nil
            pairSpaceStatus = .settingUp
            await pairSpace.invalidate()
        } else if context != nil {
            scheduleAssetSync(delay: .milliseconds(250))
        }
        if isPairActive(config, generation: generation),
           historyInputRevision != startedRevision || journalChangedDuringSync {
            scheduleHistorySyncIfPaired()
        }
        return outcome
    }

    @discardableResult
    func syncLocationNow(requestFreshFix: Bool) async -> LocationSyncOutcome? {
        #if DEBUG
        if isSandboxDemo { return nil }
        #endif
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
        evaluateBubbleUnlocks(allowNotification: true)
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
        #if DEBUG
        if isSandboxDemo { return .noData }
        #endif
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
        if isSandboxDemo { return }
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

    private func scheduleAssetSync(delay: Duration = .seconds(1)) {
        #if DEBUG
        if isSandboxDemo { return }
        #endif
        guard snapshot.isPaired else { return }
        scheduledAssetSyncTask?.cancel()
        scheduledAssetSyncTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncEncryptedAssetsIfNeeded()
        }
    }

    private func deleteRemoteAssetBestEffort(kind: PairAssetKind, id: UUID) {
        #if DEBUG
        if isSandboxDemo { return }
        #endif
        guard let config = snapshot.pairConfiguration, let context = activePairSpaceContext else { return }
        Task { [pairSpace] in
            try? await pairSpace.deleteEncryptedAsset(kind: kind, assetID: id, config: config, context: context)
        }
    }

    func syncEncryptedAssetsIfNeeded() async {
        #if DEBUG
        if isSandboxDemo { return }
        #endif
        guard let config = snapshot.pairConfiguration else { return }
        if let assetSyncTask {
            await assetSyncTask.value
            return
        }
        let generation = pairGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await performAssetSync(config: config, generation: generation)
            if generation == pairGeneration { assetSyncTask = nil }
        }
        assetSyncTask = task
        await task.value
    }

    private func performAssetSync(config: PairConfiguration, generation: Int) async {
        guard isPairActive(config, generation: generation),
              let context = await ensurePairSpaceReady(),
              isPairActive(config, generation: generation) else { return }

        defer {
            if isPairActive(config, generation: generation) {
                assetUploadProgress = nil
                assetDownloadProgress = nil
                uploadingMediaIDs = []
            }
        }

        let uploadedKey = "ourhours.uploadedAssets.\(context.zoneID.zoneName)"
        var uploaded = Set(userDefaults.stringArray(forKey: uploadedKey) ?? [])
        var seenUploadKeys = Set<String>()
        var uploadTargets: [(kind: PairAssetKind, id: UUID, token: String, mediaID: UUID?)] = []

        func enqueueUpload(_ kind: PairAssetKind, _ id: UUID?, mediaID: UUID? = nil) {
            guard let id else { return }
            let token = "\(kind.rawValue):\(id.uuidString)"
            guard seenUploadKeys.insert(token).inserted else { return }
            uploadTargets.append((kind, id, token, mediaID))
        }

        enqueueUpload(.avatar, localAvatarAssetID)
        enqueueUpload(.avatar, journal.profile(for: config.localRole)?.avatarAssetID)
        for photo in journal.dayPhotos where photo.pairID == nil || photo.pairID == config.pairID {
            if photo.mediaKind == .video {
                enqueueUpload(.dayPhoto, photo.thumbnailAssetID, mediaID: photo.id)
                enqueueUpload(.dayVideo, photo.id, mediaID: photo.id)
            } else {
                enqueueUpload(.dayPhoto, photo.id, mediaID: photo.id)
            }
        }

        let pendingUploads: [(kind: PairAssetKind, id: UUID, token: String, mediaID: UUID?, data: Data)] = uploadTargets.compactMap { target in
            guard !uploaded.contains(target.token),
                  let data = assetStore.loadData(kind: target.kind, id: target.id) else {
                return nil
            }
            return (target.kind, target.id, target.token, target.mediaID, data)
        }

        if !pendingUploads.isEmpty {
            let total = pendingUploads.count
            uploadingMediaIDs = Set(pendingUploads.compactMap(\.mediaID))
            for (index, item) in pendingUploads.enumerated() {
                guard isPairActive(config, generation: generation) else { return }
                let label = "iCloudへアップロード中 (\(index + 1)/\(total))"
                assetUploadProgress = MediaTransferProgress(
                    phase: .uploading,
                    completedCount: index,
                    totalCount: total,
                    currentItemFraction: 0,
                    detailText: label
                )
                do {
                    try await pairSpace.saveEncryptedAsset(
                        item.data,
                        kind: item.kind,
                        assetID: item.id,
                        config: config,
                        context: context
                    ) { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.isPairActive(config, generation: generation) else { return }
                            self.assetUploadProgress = MediaTransferProgress(
                                phase: .uploading,
                                completedCount: index,
                                totalCount: total,
                                currentItemFraction: fraction,
                                detailText: label
                            )
                        }
                    }
                    guard isPairActive(config, generation: generation) else { return }
                    uploaded.insert(item.token)
                    userDefaults.set(Array(uploaded), forKey: uploadedKey)
                    assetUploadProgress = MediaTransferProgress(
                        phase: .uploading,
                        completedCount: index + 1,
                        totalCount: total,
                        currentItemFraction: 0,
                        detailText: label
                    )
                    if let mediaID = item.mediaID {
                        let stillPending = pendingUploads.dropFirst(index + 1).contains { $0.mediaID == mediaID }
                        if !stillPending {
                            uploadingMediaIDs.remove(mediaID)
                        }
                    }
                } catch {
                    // Retry on the next sync pass.
                }
            }
            assetUploadProgress = nil
            uploadingMediaIDs = []
        }

        var seenDownloadKeys = Set<String>()
        var downloadTargets: [(kind: PairAssetKind, id: UUID)] = []

        func enqueueDownload(_ kind: PairAssetKind, _ id: UUID?) {
            guard let id else { return }
            let token = "\(kind.rawValue):\(id.uuidString)"
            guard seenDownloadKeys.insert(token).inserted,
                  !assetStore.exists(kind: kind, id: id) else { return }
            downloadTargets.append((kind, id))
        }

        enqueueDownload(.avatar, journal.profile(for: config.localRole.opposite)?.avatarAssetID)
        enqueueDownload(.avatar, journal.profile(for: config.localRole)?.avatarAssetID)
        enqueueDownload(.avatar, localAvatarAssetID)
        for photo in journal.dayPhotos where photo.pairID == nil || photo.pairID == config.pairID {
            if photo.mediaKind == .video {
                enqueueDownload(.dayPhoto, photo.thumbnailAssetID)
                enqueueDownload(.dayVideo, photo.id)
            } else {
                enqueueDownload(.dayPhoto, photo.id)
            }
        }

        var didDownloadAny = false
        if !downloadTargets.isEmpty {
            let downloadTotal = downloadTargets.count
            for (index, target) in downloadTargets.enumerated() {
                guard isPairActive(config, generation: generation) else { return }
                assetDownloadProgress = MediaTransferProgress(
                    phase: .downloading,
                    completedCount: index,
                    totalCount: downloadTotal,
                    currentItemFraction: 0.35,
                    detailText: "iCloudから読み込み中 (\(index + 1)/\(downloadTotal))"
                )
                guard let data = try? await pairSpace.fetchEncryptedAsset(
                    kind: target.kind, assetID: target.id, config: config, context: context
                ) else { continue }
                try? assetStore.saveData(data, kind: target.kind, id: target.id)
                if target.kind != .dayVideo, let image = UIImage(data: data) {
                    imageCache.setObject(image, forKey: "\(target.kind.rawValue):\(target.id.uuidString)" as NSString)
                }
                didDownloadAny = true
            }
            assetDownloadProgress = nil
        }

        if didDownloadAny && isPairActive(config, generation: generation) {
            assetRevision += 1
        }
    }

    func export(_ format: LogExport.Format) -> LogExport {
        LogExport(engine: engine, format: format)
    }

    func diagnosticSummaryText() -> String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "1"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        #if DEBUG
        let buildType = "DEBUG"
        #else
        let buildType = "RELEASE"
        #endif
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let pairLine: String
        if let pair = snapshot.pairConfiguration {
            let shortID = String(pair.pairID.uuidString.prefix(8))
            pairLine = "Paired (id=\(shortID), role=\(pair.localRole.shortCode), epoch=\(pair.keyEpoch))"
        } else {
            pairLine = "Unpaired"
        }

        let unknownEndCount = snapshot.sessions.count(where: { $0.status == .unknownEnd })
        let activeCount = snapshot.sessions.count(where: { $0.status == .active })
        let pathText = (snapshot.activeSession?.connectionPath ?? snapshot.lastConnectionPath)?.rawValue ?? "none"
        let lastAuthText = snapshot.lastAuthDate.map { iso.string(from: $0) } ?? "none"
        let lastErrorText = snapshot.lastErrorMessage ?? "none"
        let cleanPairSpace = pairSpaceStatusText.replacingOccurrences(of: "\n", with: " / ")

        return [
            "OurHours Diagnostic Summary",
            "Generated: \(iso.string(from: .now))",
            "App: \(shortVersion) (\(buildVersion)) [\(buildType)]",
            "Bundle ID: \(bundleID)",
            "Pair: \(pairLine)",
            "AutoRecording: \(isAutoRecordingEnabled ? "ON" : "OFF")",
            "BLE: central=\(snapshot.centralState), peripheral=\(snapshot.peripheralState), scanning=\(snapshot.isScanning), advertising=\(snapshot.isAdvertising), activeLinks=\(snapshot.activeLinkCount), path=\(pathText), lastAuth=\(lastAuthText)",
            "BLE Sessions: total=\(snapshot.sessions.count), active=\(activeCount), unknownEnd=\(unknownEndCount)",
            "BLE LastError: \(lastErrorText)",
            "CloudKit PairSpace: \(cleanPairSpace)",
            "CloudKit HistorySync: \(historySyncStatusText) (peerSessions=\(syncedPeerSessionCount))",
            "Location: enabled=\(locationMonitor.isEnabled ? "ON" : "OFF"), status=\(locationMonitor.statusDescription)",
            "Location Sync: \(locationSyncStatusText) (matched=\(locationMatchedSessions.count))"
        ].joined(separator: "\n")
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
