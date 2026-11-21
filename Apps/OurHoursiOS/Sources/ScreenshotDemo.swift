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
            let elapsedSeconds = 16 * 3600 + 42 * 60 + 18
            model.screenshotFixedActiveSessionStart = Date.now.addingTimeInterval(-TimeInterval(elapsedSeconds))
        }
        return model
    }

    private static func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let dayStart = calendar.date(byAdding: .day, value: day - 1, to: demoMonthDate)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }

    private static func seedHistory(in store: JournalStore, pairID: UUID) throws {
        let monthEnd = calendar.dateInterval(of: .month, for: demoMonthDate)!.end
        let cutoff = min(monthEnd, calendar.startOfDay(for: now))
        let lastDay = calendar.dateComponents([.day], from: demoMonthDate, to: cutoff).day!
        var occupiedDays: Set<Int> = [15]

        // Each window has room for its streak even when a Saturday splits the window.
        // The demo month always has at least 19 completed days.
        let streaks = [(3...7, 3, 18), (10...14, 2, 19), ((lastDay - 3)...lastDay, 2, 18)]
        for (window, length, startHour) in streaks {
            let firstDay = window.first { day in
                let weekday = calendar.component(.weekday, from: date(day: day))
                return day + length - 1 <= window.upperBound && weekday + length - 1 <= 7
            }!
            let endDay = firstDay + length - 1
            try store.addManualRecord(pairID: pairID, startedAt: date(day: firstDay, hour: startHour),
                                      endedAt: date(day: endDay, hour: startHour + 2))
            occupiedDays.formUnion(firstDay...endDay)
        }

        // Keep the café and birthday dates, then spread seven more visits across the month.
        var singleDays = [2, 8]
        let availableDays = (1...lastDay).filter { !occupiedDays.contains($0) && !singleDays.contains($0) }
        for index in 0..<7 {
            singleDays.append(availableDays[index * (availableDays.count - 1) / 6])
        }
        let durations = [4, 9, 3, 7, 5, 8, 4, 6, 3]
        for (day, hours) in zip(singleDays, durations) {
            let startHour = 10 + day % 4
            try store.addManualRecord(pairID: pairID, startedAt: date(day: day, hour: startHour),
                                      endedAt: date(day: day, hour: startHour + hours))
        }
        try store.addManualRecord(pairID: pairID, startedAt: date(day: 15, hour: 10, minute: 30),
                                  endedAt: date(day: 15, hour: 14, minute: 30))
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
