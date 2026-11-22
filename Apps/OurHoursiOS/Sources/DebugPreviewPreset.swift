#if DEBUG
import Foundation
import OurHoursCore
import UIKit

enum DebugPreviewPreset: String, CaseIterable, Identifiable, Sendable {
    case togetherLong
    case togetherJustStarted
    case apartPaired
    case anniversaryToday
    case unknownEnd
    case unpaired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togetherLong: "いま一緒（長時間・3時間25分）"
        case .togetherJustStarted: "いま一緒（開始直後・2分）"
        case .apartPaired: "ペア済み（離れている）"
        case .anniversaryToday: "1年記念日＆誕生日月"
        case .unknownEnd: "終了不明あり"
        case .unpaired: "未ペア（ひとりモード）"
        }
    }

    var shortBadgeTitle: String {
        switch self {
        case .togetherLong: "一緒 3h25m"
        case .togetherJustStarted: "一緒 2m"
        case .apartPaired: "ペア済み"
        case .anniversaryToday: "1年記念日"
        case .unknownEnd: "終了不明"
        case .unpaired: "未ペア"
        }
    }

    var subtitle: String {
        switch self {
        case .togetherLong: "タイマー稼働・シャボン玉成長・充実カレンダー"
        case .togetherJustStarted: "小さいシャボン玉・分秒タイマー表示"
        case .apartPaired: "今月集計・連泊ブリッジ・メモ付きカレンダー"
        case .anniversaryToday: "今日が1年記念日・記念日/誕生日マークの確認"
        case .unknownEnd: "ホームの警告ボタン＆タイムライン結合の確認"
        case .unpaired: "シャボン玉1体・ペア設定導線の確認"
        }
    }
}

struct DebugPreviewHandle {
    let preset: DebugPreviewPreset
    let model: AppModel
    let sandboxDirectory: URL
    let defaultsSuiteName: String

    func cleanup() {
        try? FileManager.default.removeItem(at: sandboxDirectory)
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
    }
}

@MainActor
enum DebugPreviewFactory {
    static func makeHandle(for preset: DebugPreviewPreset) -> DebugPreviewHandle {
        let now = Date.now
        let calendar = CalendarDateValue.gregorianCurrent
        let todayStart = calendar.startOfDay(for: now)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourhours-debug-preview-\(UUID().uuidString)", isDirectory: true)
        let suite = "io.github.inazumimakoto.OurHours.debugPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let configStore = PairConfigStore(
            secretStorage: InMemorySecretStorage(),
            pendingPurgeStorage: InMemorySecretStorage(),
            userDefaults: defaults
        )
        let journalStore = JournalStore(directory: directory)
        let logStore = EncounterLogStore(directory: directory)
        let assetStore = PairAssetStore(directory: directory)

        defaults.set(true, forKey: AppModel.DefaultsKey.onboarding)
        defaults.set(BubbleColorTheme.skyBlue.rawValue, forKey: AppModel.DefaultsKey.color)

        if preset != .unpaired {
            let pair = PairConfiguration(
                pairID: UUID(),
                sharedSecret: Data(0..<32),
                localRole: .partnerA,
                keyEpoch: 1,
                createdAt: calendar.date(byAdding: .day, value: -260, to: now) ?? now
            )
            do {
                try configStore.savePairConfiguration(pair)
                let currentMonth = calendar.component(.month, from: todayStart)
                let todayDay = calendar.component(.day, from: todayStart)
                let myBirthdayDay = todayDay == 8 ? 7 : 8
                let partnerBirthdayDay = todayDay == 19 ? 20 : 19
                let myBirthday = CalendarDateValue(year: 1999, month: currentMonth, day: myBirthdayDay)
                let partnerBirthday = CalendarDateValue(year: 1998, month: currentMonth, day: partnerBirthdayDay)

                let myAvatarID = UUID()
                let partnerAvatarID = UUID()
                if let myAvatarData = renderBubbleAvatarJPEG(
                    top: UIColor(red: 0.68, green: 0.88, blue: 1.0, alpha: 1.0),
                    bottom: UIColor(red: 0.42, green: 0.72, blue: 0.96, alpha: 1.0),
                    initial: "み"
                ) {
                    try assetStore.saveData(myAvatarData, kind: .avatar, id: myAvatarID)
                    defaults.set(myAvatarID.uuidString, forKey: AppModel.DefaultsKey.avatarAssetID)
                }
                if let partnerAvatarData = renderBubbleAvatarJPEG(
                    top: UIColor(red: 1.0, green: 0.84, blue: 0.91, alpha: 1.0),
                    bottom: UIColor(red: 0.96, green: 0.62, blue: 0.76, alpha: 1.0),
                    initial: "は"
                ) {
                    try assetStore.saveData(partnerAvatarData, kind: .avatar, id: partnerAvatarID)
                }

                defaults.set("はる", forKey: AppModel.DefaultsKey.nickname)
                defaults.set(try JSONEncoder().encode(myBirthday), forKey: AppModel.DefaultsKey.birthday)
                try journalStore.setRoleProfile(
                    role: .partnerA, bubbleColor: .skyBlue, birthday: myBirthday, avatarAssetID: myAvatarID
                )
                try journalStore.setRoleProfile(
                    role: .partnerB, bubbleColor: .sakuraPink, birthday: partnerBirthday, avatarAssetID: partnerAvatarID
                )

                let anniversarySource: Date = if preset == .anniversaryToday {
                    calendar.date(byAdding: .year, value: -1, to: todayStart) ?? todayStart
                } else {
                    calendar.date(byAdding: .day, value: -258, to: todayStart) ?? todayStart
                }
                try journalStore.setAnniversary(CalendarDateValue(date: anniversarySource))

                try seedHistory(
                    in: journalStore,
                    logStore: logStore,
                    assetStore: assetStore,
                    pairID: pair.pairID,
                    preset: preset,
                    todayStart: todayStart,
                    calendar: calendar
                )
            } catch {
                preconditionFailure("Could not prepare debug preview data: \(error)")
            }
        }

        let engine = OurHoursBLEEngine(
            configStore: configStore,
            logStore: logStore,
            enableStateRestoration: false
        )
        let model = AppModel(
            engine: engine,
            journalStore: journalStore,
            peerSyncStore: PartnerSyncStore(directory: directory),
            locationStore: LocationTimelineStore(directory: directory),
            locationMonitor: ScreenshotLocationMonitor(),
            userDefaults: defaults,
            assetStore: assetStore
        )

        switch preset {
        case .togetherLong:
            let elapsed: TimeInterval = (3 * 3600) + (25 * 60) + 12
            model.debugSimulatedActiveSessionStart = now.addingTimeInterval(-elapsed)
        case .togetherJustStarted:
            model.debugSimulatedActiveSessionStart = now.addingTimeInterval(-135)
        case .apartPaired, .anniversaryToday, .unknownEnd, .unpaired:
            model.debugSimulatedActiveSessionStart = nil
        }

        return DebugPreviewHandle(
            preset: preset,
            model: model,
            sandboxDirectory: directory,
            defaultsSuiteName: suite
        )
    }

    private static func seedHistory(
        in journalStore: JournalStore,
        logStore: EncounterLogStore,
        assetStore: PairAssetStore,
        pairID: UUID,
        preset: DebugPreviewPreset,
        todayStart: Date,
        calendar: Calendar
    ) throws {
        func time(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) ?? todayStart
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // Overnight stay (4 days ago evening -> 3 days ago morning)
        try journalStore.addManualRecord(
            pairID: pairID,
            startedAt: time(daysAgo: 4, hour: 19, minute: 30),
            endedAt: time(daysAgo: 3, hour: 11, minute: 15)
        )

        let singleVisitSpecs: [(daysAgo: Int, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)] = [
            (2, 11, 30, 16, 45),
            (6, 12, 0, 18, 20),
            (9, 17, 15, 21, 30),
            (12, 13, 0, 19, 10),
            (15, 10, 30, 15, 0),
            (18, 14, 0, 20, 0)
        ]
        for spec in singleVisitSpecs {
            try journalStore.addManualRecord(
                pairID: pairID,
                startedAt: time(daysAgo: spec.daysAgo, hour: spec.startHour, minute: spec.startMinute),
                endedAt: time(daysAgo: spec.daysAgo, hour: spec.endHour, minute: spec.endMinute)
            )
        }

        if preset != .unknownEnd {
            try journalStore.addManualRecord(
                pairID: pairID,
                startedAt: time(daysAgo: 1, hour: 12, minute: 10),
                endedAt: time(daysAgo: 1, hour: 15, minute: 40)
            )
        } else {
            let unknownSession = EncounterSession(
                pairID: pairID,
                startedAt: time(daysAgo: 1, hour: 19, minute: 0),
                endedAt: nil,
                status: .unknownEnd,
                connectionPath: .scanDiscovery,
                startRole: .central,
                endReason: .terminatedWhileActive
            )
            try logStore.saveSessions([unknownSession])
        }

        let memos: [(daysAgo: Int, role: PeerRole, text: String)] = [
            (2, .partnerA, "代官山のカフェでおしゃべりしすぎた！"),
            (2, .partnerB, "駅前のカフェで待ち合わせ。"),
            (6, .partnerA, "ランチしてから夕方の映画を観た！"),
            (6, .partnerB, "みなとみらいの夜景きれいだった〜"),
            (12, .partnerB, "誕生日のケーキを一緒に選んだ。")
        ]
        for memo in memos {
            let key = EncounterCalendarAggregator.dayKey(for: time(daysAgo: memo.daysAgo, hour: 12))
            try journalStore.setRoleMemo(dayKey: key, role: memo.role, text: memo.text, pairID: pairID)
        }

        let spotSamples: [(
            daysAgo: Int,
            placeName: String,
            address: String,
            lat: Double,
            lon: Double,
            photoLabel: String,
            top: UIColor,
            bottom: UIColor
        )] = [
            (
                2, "代官山カフェ", "東京都渋谷区代官山町", 35.6481, 139.7032, "CAFE",
                UIColor(red: 0.99, green: 0.85, blue: 0.72, alpha: 1.0),
                UIColor(red: 0.88, green: 0.62, blue: 0.56, alpha: 1.0)
            ),
            (
                6, "横浜みなとみらい", "神奈川県横浜市西区", 35.4549, 139.6314, "BAY",
                UIColor(red: 0.64, green: 0.85, blue: 0.99, alpha: 1.0),
                UIColor(red: 0.36, green: 0.58, blue: 0.88, alpha: 1.0)
            ),
            (
                12, "江ノ島", "神奈川県藤沢市江の島", 35.2999, 139.4803, "SEA",
                UIColor(red: 0.62, green: 0.91, blue: 0.90, alpha: 1.0),
                UIColor(red: 0.31, green: 0.67, blue: 0.78, alpha: 1.0)
            ),
            (
                15, "浅草", "東京都台東区浅草", 35.7148, 139.7967, "WALK",
                UIColor(red: 0.96, green: 0.76, blue: 0.84, alpha: 1.0),
                UIColor(red: 0.74, green: 0.54, blue: 0.82, alpha: 1.0)
            )
        ]

        for (idx, spot) in spotSamples.enumerated() {
            let moment = time(daysAgo: spot.daysAgo, hour: 14, minute: 30)
            let dayKey = EncounterCalendarAggregator.dayKey(for: moment)
            let coord = GeoCoordinate(latitude: spot.lat, longitude: spot.lon)
            let photoID = UUID()
            if let photoData = renderScenicPhotoJPEG(top: spot.top, bottom: spot.bottom, title: spot.photoLabel) {
                try assetStore.saveData(photoData, kind: .dayPhoto, id: photoID)
                try journalStore.addDayPhoto(DayPhotoAttachment(
                    id: photoID,
                    pairID: pairID,
                    dayKey: dayKey,
                    authorRole: idx.isMultiple(of: 2) ? .partnerA : .partnerB,
                    coordinate: coord,
                    capturedAt: moment,
                    locationName: spot.placeName,
                    createdAt: moment,
                    updatedAt: moment
                ))
            }
            if spot.daysAgo == 12,
               let secondPhotoData = renderScenicPhotoJPEG(
                   top: UIColor(red: 1.0, green: 0.83, blue: 0.66, alpha: 1.0),
                   bottom: UIColor(red: 0.88, green: 0.52, blue: 0.62, alpha: 1.0),
                   title: "SUNSET"
               ) {
                let secondID = UUID()
                try assetStore.saveData(secondPhotoData, kind: .dayPhoto, id: secondID)
                try journalStore.addDayPhoto(DayPhotoAttachment(
                    id: secondID,
                    pairID: pairID,
                    dayKey: dayKey,
                    authorRole: .partnerB,
                    coordinate: GeoCoordinate(latitude: spot.lat + 0.0003, longitude: spot.lon + 0.0002),
                    capturedAt: moment.addingTimeInterval(3600),
                    locationName: spot.placeName,
                    createdAt: moment.addingTimeInterval(3600),
                    updatedAt: moment.addingTimeInterval(3600)
                ))
            }
            if idx < 3 {
                try journalStore.addDayPlaceTag(DayPlaceTag(
                    pairID: pairID,
                    dayKey: dayKey,
                    name: spot.placeName,
                    address: spot.address,
                    coordinate: coord,
                    authorRole: idx.isMultiple(of: 2) ? .partnerA : .partnerB,
                    createdAt: moment,
                    updatedAt: moment
                ))
            }
        }

        // Place-only pin (no photo) so the "すべて / 写真・動画 / 場所タグ" filter distinction is immediately clear.
        let kamakuraDay = time(daysAgo: 18, hour: 15)
        try journalStore.addDayPlaceTag(DayPlaceTag(
            pairID: pairID,
            dayKey: EncounterCalendarAggregator.dayKey(for: kamakuraDay),
            name: "鎌倉小町通り",
            address: "神奈川県鎌倉市小町",
            coordinate: GeoCoordinate(latitude: 35.3204, longitude: 139.5513),
            authorRole: .partnerA,
            createdAt: kamakuraDay,
            updatedAt: kamakuraDay
        ))

        let homeKey = EncounterCalendarAggregator.dayKey(for: time(daysAgo: 9, hour: 19))
        try journalStore.addDayPlaceTag(DayPlaceTag(
            pairID: pairID,
            dayKey: homeKey,
            name: "おうち映画",
            address: nil,
            coordinate: nil,
            authorRole: .partnerB,
            createdAt: time(daysAgo: 9, hour: 19),
            updatedAt: time(daysAgo: 9, hour: 19)
        ))

        let weekendStart = EncounterCalendarAggregator.dayKey(for: time(daysAgo: 4, hour: 12), calendar: calendar)
        let weekendEnd = EncounterCalendarAggregator.dayKey(for: time(daysAgo: 2, hour: 12), calendar: calendar)
        try journalStore.upsertPlanEvent(PairPlanEvent(
            pairID: pairID,
            title: "週末お泊まり＆代官山",
            startDayKey: weekendStart,
            endDayKey: weekendEnd,
            icon: .stay,
            memo: "お泊まりしてから代官山でカフェ巡りしたよ",
            checklist: [
                PairPlanChecklistItem(title: "お泊まりセット準備", isDone: true, kind: .packing),
                PairPlanChecklistItem(title: "代官山カフェでランチ", isDone: true, kind: .todo)
            ],
            authorRole: .partnerA,
            createdAt: time(daysAgo: 5, hour: 10),
            updatedAt: time(daysAgo: 2, hour: 18)
        ))

        let enoshimaDay = EncounterCalendarAggregator.dayKey(for: time(daysAgo: 12, hour: 12), calendar: calendar)
        try journalStore.upsertPlanEvent(PairPlanEvent(
            pairID: pairID,
            title: "江ノ島サンセット旅",
            startDayKey: enoshimaDay,
            endDayKey: enoshimaDay,
            icon: .trip,
            memo: "海の夕日がすごくきれいだった",
            checklist: [
                PairPlanChecklistItem(title: "シーキャンドルに登る", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "しらす丼を食べる", isDone: true, kind: .todo)
            ],
            authorRole: .partnerB,
            createdAt: time(daysAgo: 14, hour: 20),
            updatedAt: time(daysAgo: 12, hour: 20)
        ))

        let futureStartDate = calendar.date(byAdding: .day, value: 5, to: todayStart) ?? todayStart
        let futureEndDate = calendar.date(byAdding: .day, value: 6, to: todayStart) ?? futureStartDate
        try journalStore.upsertPlanEvent(PairPlanEvent(
            pairID: pairID,
            title: "箱根温泉旅行",
            startDayKey: EncounterCalendarAggregator.dayKey(for: futureStartDate, calendar: calendar),
            endDayKey: EncounterCalendarAggregator.dayKey(for: futureEndDate, calendar: calendar),
            icon: .trip,
            memo: "露天風呂付きの宿でのんびりする予定！",
            checklist: [
                PairPlanChecklistItem(title: "ロマンスカー予約", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "彫刻の森美術館", isDone: false, kind: .todo),
                PairPlanChecklistItem(title: "大涌谷の黒たまご", isDone: false, kind: .todo),
                PairPlanChecklistItem(title: "カメラの充電", isDone: false, kind: .packing),
                PairPlanChecklistItem(title: "スキンケアセット", isDone: false, kind: .packing)
            ],
            authorRole: .partnerA,
            createdAt: todayStart,
            updatedAt: todayStart
        ))
    }

    private static func renderBubbleAvatarJPEG(top: UIColor, bottom: UIColor, initial: String) -> Data? {
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            UIColor.white.withAlphaComponent(0.32).setFill()
            cg.fillEllipse(in: CGRect(x: 34, y: 28, width: 52, height: 34))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                .foregroundColor: UIColor(red: 0.14, green: 0.16, blue: 0.28, alpha: 0.82)
            ]
            let textSize = (initial as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: (size.width - textSize.width) * 0.5,
                y: (size.height - textSize.height) * 0.5,
                width: textSize.width,
                height: textSize.height
            )
            (initial as NSString).draw(in: rect, withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static func renderScenicPhotoJPEG(top: UIColor, bottom: UIColor, title: String) -> Data? {
        let size = CGSize(width: 720, height: 540)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            UIColor.white.withAlphaComponent(0.28).setFill()
            cg.fillEllipse(in: CGRect(x: 78, y: 74, width: 140, height: 140))
            UIColor.white.withAlphaComponent(0.18).setFill()
            cg.fillEllipse(in: CGRect(x: 420, y: 120, width: 220, height: 220))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.88)
            ]
            let textSize = (title as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: (size.width - textSize.width) * 0.5,
                y: (size.height - textSize.height) * 0.52,
                width: textSize.width,
                height: textSize.height
            )
            (title as NSString).draw(in: rect, withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.82)
    }
}
#endif
