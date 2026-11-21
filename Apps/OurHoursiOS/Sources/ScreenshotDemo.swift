#if DEBUG
import CoreLocation
import Foundation
import OurHoursCore

enum ScreenshotScene: String, Sendable {
    case home, calendar, dayDetail, pairing, settings

    static let current: Self? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-OURHOURS_SCREENSHOT_SCENE"),
              let value = arguments.dropFirst(flag + 1).first else { return nil }
        return Self(rawValue: value)
    }()
}

// A screenshot must never instantiate a CLLocationManager, even when Settings reads its status.
struct ScreenshotLocationMonitor: LocationMonitoring {
    let authorizationStatus = CLAuthorizationStatus.notDetermined
    let isEnabled = false
    let needsSettingsGuidance = false
    let statusDescription = "オフ"
    let isReducedAccuracyWarning = false
    let lastCaptureDate: Date? = nil
    func startIfAuthorized() {}
    func enableAndRequestAuthorization() {}
    func disable() {}
    func requestFreshFix(source: LocationSampleSource) {}
}

@MainActor
enum ScreenshotDemo {
    private static let calendar = CalendarDateValue.gregorianCurrent
    private static let now = Date.now

    // Early in a month, use the preceding month so all example sessions are in the past.
    static let demoMonthDate: Date = {
        let start = calendar.dateInterval(of: .month, for: now)!.start
        return calendar.component(.day, from: now) >= 20 ? start : calendar.date(byAdding: .month, value: -1, to: start)!
    }()
    static let demoDayDate = date(day: 15)

    static func makeAppModel(for scene: ScreenshotScene) -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourhours-screenshot-demo-\(UUID())", isDirectory: true)
        let suite = "io.github.inazumimakoto.OurHours.screenshotDemo"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = PairConfigStore(
            secretStorage: InMemorySecretStorage(), pendingPurgeStorage: InMemorySecretStorage(), userDefaults: defaults
        )
        let pair = PairConfiguration(
            pairID: UUID(), sharedSecret: Data(0..<32), localRole: .partnerA, keyEpoch: 1,
            createdAt: calendar.date(byAdding: .day, value: -259, to: now)!,
            cloudShareURL: "https://www.icloud.com/share/0e8XMs2ee9DbKJm-FTh6X04Bg"
        )
        let journal = JournalStore(directory: directory)
        do {
            try configStore.savePairConfiguration(pair)
            let month = calendar.component(.month, from: demoMonthDate)
            let birthday = CalendarDateValue(year: 1999, month: month, day: 8)
            defaults.set(true, forKey: AppModel.DefaultsKey.onboarding)
            defaults.set(BubbleColorTheme.skyBlue.rawValue, forKey: AppModel.DefaultsKey.color)
            defaults.set("はる", forKey: AppModel.DefaultsKey.nickname)
            defaults.set(try JSONEncoder().encode(birthday), forKey: AppModel.DefaultsKey.birthday)
            try journal.setRoleProfile(role: .partnerB, bubbleColor: .sakuraPink,
                                       birthday: CalendarDateValue(year: 1998, month: month, day: 19))
            let anniversary = calendar.date(byAdding: .day, value: -258, to: now)!
            try journal.setAnniversary(CalendarDateValue(date: anniversary))
            try seedHistory(in: journal, pairID: pair.pairID)
        } catch {
            preconditionFailure("Could not prepare screenshot data: \(error)")
        }
        let engine = OurHoursBLEEngine(
            configStore: configStore, logStore: EncounterLogStore(directory: directory), enableStateRestoration: false
        )
        let model = AppModel(
            engine: engine, journalStore: journal, peerSyncStore: PartnerSyncStore(directory: directory),
            locationStore: LocationTimelineStore(directory: directory), locationMonitor: ScreenshotLocationMonitor(),
            userDefaults: defaults
        )
        if scene == .home {
            let elapsedSeconds = 3 * 3600 + 24 * 60 + 18
            model.screenshotFixedActiveSessionStart = Date.now.addingTimeInterval(-TimeInterval(elapsedSeconds))
        }
        return model
    }

    private static func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let dayStart = calendar.date(byAdding: .day, value: day - 1, to: demoMonthDate)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }

    private static func seedHistory(in store: JournalStore, pairID: UUID) throws {
        let sessions = [
            (1, 12, 16), (2, 10, 17), (4, 18, 21), (5, 11, 16), (7, 13, 19),
            (8, 10, 19), (10, 17, 20), (12, 12, 17), (14, 18, 20),
            (17, 13, 17), (19, 11, 19), (20, 12, 18), (21, 16, 19)
        ]
        for (day, startHour, endHour) in sessions {
            let end = date(day: day, hour: endHour, minute: day.isMultiple(of: 2) ? 30 : 0)
            if end <= now {
                try store.addManualRecord(pairID: pairID, startedAt: date(day: day, hour: startHour), endedAt: end)
            }
        }
        try store.addManualRecord(pairID: pairID, startedAt: date(day: 15, hour: 11, minute: 30),
                                  endedAt: date(day: 15, hour: 14))
        try store.addManualRecord(pairID: pairID, startedAt: date(day: 15, hour: 16),
                                  endedAt: date(day: 15, hour: 20, minute: 30))
        for (day, memo) in [(2, "駅前のカフェで待ち合わせ。"), (8, "誕生日のケーキを一緒に選んだ。"),
                            (15, "ランチしてから夕方の映画を観た！")] {
            let key = EncounterCalendarAggregator.dayKey(for: date(day: day))
            try store.setMemo(dayKey: key, text: memo, pairID: pairID)
        }
    }
}
#endif
