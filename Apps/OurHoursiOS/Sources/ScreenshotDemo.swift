#if DEBUG
import CoreLocation
import Foundation
import OurHoursCore
import UIKit

enum ScreenshotScene: String, Sendable {
    case home, calendar, gallery, map, customizer, dayDetail, pairing, settings

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

    private enum MemorySceneStyle {
        case sakuraPark
        case hakoneOnsen
        case hakoneLake
        case hakoneMaple
        case cafeLatte
        case birthdayCake
        case enoshimaSunset
        case yokohamaHarbor
        case yokohamaFerris
        case asakusaLantern
    }

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
        let assetStore = PairAssetStore(directory: directory)

        let isCustomizer = scene == .customizer
        let localColor: BubbleColorTheme = isCustomizer ? .milkyWay : .skyBlue
        let localExpression: BubbleExpression = isCustomizer ? .starry : .smile
        let localDecorations: BubbleDecorationLoadout = isCustomizer
            ? BubbleDecorationLoadout(ears: .catEars, headwear: .tiara, makeup: .milkyWayGlow)
            : BubbleDecorationLoadout(headwear: .beret, makeup: .rosyCheeks)
        let partnerColor: BubbleColorTheme = .sakuraPink
        let partnerExpression: BubbleExpression = .starry
        let partnerDecorations = BubbleDecorationLoadout(
            ears: .bunnyEars,
            headwear: .ribbon,
            makeup: .starStamps
        )

        do {
            try configStore.savePairConfiguration(pair)
            let month = calendar.component(.month, from: demoMonthDate)
            let birthday = CalendarDateValue(year: 1999, month: month, day: 8)
            let partnerBirthday = CalendarDateValue(year: 1998, month: month, day: 19)

            defaults.set(true, forKey: AppModel.DefaultsKey.onboarding)
            defaults.set(localColor.rawValue, forKey: AppModel.DefaultsKey.color)
            defaults.set(localExpression.rawValue, forKey: AppModel.DefaultsKey.expression)
            defaults.set(try JSONEncoder().encode(localDecorations), forKey: AppModel.DefaultsKey.decorations)
            defaults.set("はる", forKey: AppModel.DefaultsKey.nickname)
            defaults.set(try JSONEncoder().encode(birthday), forKey: AppModel.DefaultsKey.birthday)

            if isCustomizer {
                let demoEvents: [BubbleEventKind] = [
                    .spring, .winter, .tanabata, .valentinesDay, .christmas, .anniversary
                ]
                defaults.set(demoEvents.map(\.rawValue), forKey: AppModel.DefaultsKey.achievedBubbleEvents)
            }
            defaults.set(
                BubbleUnlockCatalog.allItems.map(\.id),
                forKey: AppModel.DefaultsKey.seenUnlockedItems
            )
            defaults.set([String](), forKey: AppModel.DefaultsKey.unseenUnlockedItems)

            try journal.setRoleProfile(
                role: .partnerA,
                bubbleColor: localColor,
                birthday: birthday,
                expression: localExpression,
                decorations: localDecorations
            )
            try journal.setRoleProfile(
                role: .partnerB,
                bubbleColor: partnerColor,
                birthday: partnerBirthday,
                expression: partnerExpression,
                decorations: partnerDecorations
            )
            let anniversary = calendar.date(byAdding: .day, value: -258, to: now)!
            try journal.setAnniversary(CalendarDateValue(date: anniversary))
            try seedHistory(in: journal, assetStore: assetStore, pairID: pair.pairID)
        } catch {
            preconditionFailure("Could not prepare screenshot data: \(error)")
        }

        let engine = OurHoursBLEEngine(
            configStore: configStore, logStore: EncounterLogStore(directory: directory), enableStateRestoration: false
        )
        let model = AppModel(
            engine: engine,
            journalStore: journal,
            peerSyncStore: PartnerSyncStore(directory: directory),
            locationStore: LocationTimelineStore(directory: directory),
            locationMonitor: ScreenshotLocationMonitor(),
            userDefaults: defaults,
            assetStore: assetStore
        )
        if isCustomizer {
            model.debugBonusHours = 45
            model.evaluateBubbleUnlocks(asOf: now, allowNotification: false)
            model.markBubbleUnlocksSeen()
        }
        if scene == .home || scene == .customizer {
            let elapsedSeconds = 16 * 3600 + 42 * 60 + 18
            model.debugSimulatedActiveSessionStart = Date.now.addingTimeInterval(-TimeInterval(elapsedSeconds))
        }
        return model
    }

    private static func date(day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let dayStart = calendar.date(byAdding: .day, value: day - 1, to: demoMonthDate)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }

    private static func seedHistory(in store: JournalStore, assetStore: PairAssetStore, pairID: UUID) throws {
        let monthEnd = calendar.dateInterval(of: .month, for: demoMonthDate)!.end
        let cutoff = min(monthEnd, calendar.startOfDay(for: now))
        let lastDay = calendar.dateComponents([.day], from: demoMonthDate, to: cutoff).day!
        var occupiedDays: Set<Int> = [15]
        var streakRanges: [(start: Int, end: Int)] = []

        // Each window has room for its streak even when a Saturday splits the window.
        // The demo month always has at least 19 completed days.
        let streaks = [(3...7, 3, 18), (10...14, 2, 19), ((lastDay - 3)...lastDay, 2, 18)]
        for (window, length, startHour) in streaks {
            let firstDay = window.first { day in
                let weekday = calendar.component(.weekday, from: date(day: day))
                return day + length - 1 <= window.upperBound && weekday + length - 1 <= 7
            }!
            let endDay = firstDay + length - 1
            try store.addManualRecord(
                pairID: pairID,
                startedAt: date(day: firstDay, hour: startHour),
                endedAt: date(day: endDay, hour: startHour + 2)
            )
            occupiedDays.formUnion(firstDay...endDay)
            streakRanges.append((firstDay, endDay))
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
            try store.addManualRecord(
                pairID: pairID,
                startedAt: date(day: day, hour: startHour),
                endedAt: date(day: day, hour: startHour + hours)
            )
        }
        try store.addManualRecord(
            pairID: pairID,
            startedAt: date(day: 15, hour: 10, minute: 30),
            endedAt: date(day: 15, hour: 14, minute: 30)
        )
        try store.addManualRecord(
            pairID: pairID,
            startedAt: date(day: 15, hour: 16),
            endedAt: date(day: 15, hour: 20, minute: 30)
        )

        for (day, memo) in [
            (2, "駅前のカフェで待ち合わせ。"),
            (8, "誕生日のケーキを一緒に選んだ。"),
            (15, "ランチしてから夕方の映画を観た！")
        ] {
            let key = EncounterCalendarAggregator.dayKey(for: date(day: day))
            try store.setMemo(dayKey: key, text: memo, pairID: pairID)
        }
        try store.setRoleMemo(
            dayKey: EncounterCalendarAggregator.dayKey(for: date(day: 15)),
            role: .partnerB,
            text: "夜の観覧車もすごくきれいだった〜！",
            pairID: pairID
        )

        // Plans & Trips
        let tripRange = streakRanges[0]
        let hakoneStartKey = EncounterCalendarAggregator.dayKey(for: date(day: tripRange.start))
        let hakoneEndKey = EncounterCalendarAggregator.dayKey(for: date(day: tripRange.end))
        let hakonePlan = PairPlanEvent(
            pairID: pairID,
            title: "箱根温泉旅行",
            startDayKey: hakoneStartKey,
            endDayKey: hakoneEndKey,
            icon: .trip,
            memo: "露天風呂付きの宿でのんびり過ごしたよ",
            checklist: [
                PairPlanChecklistItem(title: "ロマンスカーに乗る", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "芦ノ湖で遊覧船", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "お泊まりセット", isDone: true, kind: .packing)
            ],
            authorRole: .partnerA,
            createdAt: date(day: max(1, tripRange.start - 1), hour: 20),
            updatedAt: date(day: tripRange.end, hour: 19)
        )
        try store.upsertPlanEvent(hakonePlan)

        let daikanyamaRange = streakRanges[1]
        let stayPlan = PairPlanEvent(
            pairID: pairID,
            title: "週末お泊まり＆代官山",
            startDayKey: EncounterCalendarAggregator.dayKey(for: date(day: daikanyamaRange.start)),
            endDayKey: EncounterCalendarAggregator.dayKey(for: date(day: daikanyamaRange.end)),
            icon: .stay,
            memo: "モーニングから代官山カフェ巡り",
            checklist: [
                PairPlanChecklistItem(title: "カフェでラテを飲む", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "フィルムカメラ", isDone: true, kind: .packing)
            ],
            authorRole: .partnerB,
            createdAt: date(day: daikanyamaRange.start, hour: 18),
            updatedAt: date(day: daikanyamaRange.end, hour: 17)
        )
        try store.upsertPlanEvent(stayPlan)

        let minatomiraiKey = EncounterCalendarAggregator.dayKey(for: date(day: 15))
        let yokohamaPlan = PairPlanEvent(
            pairID: pairID,
            title: "横浜みなとみらいデート",
            startDayKey: minatomiraiKey,
            endDayKey: minatomiraiKey,
            icon: .date,
            memo: "観覧車と赤レンガの夜景がきれいだった",
            checklist: [
                PairPlanChecklistItem(title: "ランチ＆映画", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "海沿いさんぽ", isDone: true, kind: .todo)
            ],
            authorRole: .partnerA,
            createdAt: date(day: 15, hour: 10),
            updatedAt: date(day: 15, hour: 20)
        )
        try store.upsertPlanEvent(yokohamaPlan)

        let upcomingStart = calendar.date(byAdding: .day, value: 4, to: now) ?? now
        let upcomingEnd = calendar.date(byAdding: .day, value: 5, to: now) ?? upcomingStart
        try store.upsertPlanEvent(PairPlanEvent(
            pairID: pairID,
            title: "京都もみじ旅",
            startDayKey: EncounterCalendarAggregator.dayKey(for: upcomingStart),
            endDayKey: EncounterCalendarAggregator.dayKey(for: upcomingEnd),
            icon: .trip,
            memo: "清水寺のライトアップと抹茶スイーツ",
            checklist: [
                PairPlanChecklistItem(title: "新幹線チケット予約", isDone: true, kind: .todo),
                PairPlanChecklistItem(title: "嵐山で食べ歩き", isDone: false, kind: .todo),
                PairPlanChecklistItem(title: "モバイルバッテリー", isDone: false, kind: .packing),
                PairPlanChecklistItem(title: "あたたかいマフラー", isDone: false, kind: .packing)
            ],
            authorRole: .partnerA,
            createdAt: now,
            updatedAt: now
        ))

        // Photos & Place Tags for Album, Memory Map & Day Detail
        let mediaSpecs: [(
            day: Int,
            hour: Int,
            style: MemorySceneStyle,
            placeName: String,
            address: String,
            lat: Double,
            lon: Double,
            role: PeerRole,
            planID: UUID?,
            createTag: Bool
        )] = [
            (15, 17, .yokohamaHarbor, "横浜みなとみらい", "神奈川県横浜市西区", 35.4549, 139.6314, .partnerA, yokohamaPlan.id, true),
            (15, 19, .yokohamaFerris, "横浜みなとみらい", "神奈川県横浜市西区", 35.4552, 139.6320, .partnerB, yokohamaPlan.id, false),
            (13, 17, .enoshimaSunset, "江ノ島", "神奈川県藤沢市江の島", 35.2999, 139.4803, .partnerB, nil, true),
            (daikanyamaRange.start, 14, .cafeLatte, "代官山カフェ", "東京都渋谷区代官山町", 35.6481, 139.7032, .partnerA, stayPlan.id, true),
            (tripRange.start, 16, .hakoneOnsen, "箱根湯本", "神奈川県足柄下郡箱根町", 35.2324, 139.1069, .partnerA, hakonePlan.id, true),
            (tripRange.start + 1, 11, .hakoneLake, "芦ノ湖", "神奈川県足柄下郡箱根町", 35.2039, 139.0252, .partnerB, hakonePlan.id, false),
            (tripRange.end, 14, .hakoneMaple, "強羅公園", "神奈川県足柄下郡箱根町", 35.2491, 139.0448, .partnerA, hakonePlan.id, false),
            (8, 15, .birthdayCake, "自由が丘", "東京都目黒区自由が丘", 35.6073, 139.6686, .partnerB, nil, true),
            (2, 13, .sakuraPark, "代々木公園", "東京都渋谷区代々木神園町", 35.6717, 139.6949, .partnerA, nil, true)
        ]

        for spec in mediaSpecs {
            let captured = date(day: spec.day, hour: spec.hour, minute: 20)
            let dayKey = EncounterCalendarAggregator.dayKey(for: captured)
            let coord = GeoCoordinate(latitude: spec.lat, longitude: spec.lon)
            var linkedTagID: UUID?
            if spec.createTag {
                let tag = DayPlaceTag(
                    pairID: pairID,
                    dayKey: dayKey,
                    name: spec.placeName,
                    address: spec.address,
                    coordinate: coord,
                    authorRole: spec.role,
                    createdAt: captured,
                    updatedAt: captured
                )
                try store.addDayPlaceTag(tag)
                linkedTagID = tag.id
            }
            if let jpeg = renderIllustratedMemoryJPEG(style: spec.style) {
                let photoID = UUID()
                try assetStore.saveData(jpeg, kind: .dayPhoto, id: photoID)
                try store.addDayPhoto(DayPhotoAttachment(
                    id: photoID,
                    pairID: pairID,
                    dayKey: dayKey,
                    authorRole: spec.role,
                    mediaKind: .photo,
                    placeTagID: linkedTagID,
                    coordinate: coord,
                    capturedAt: captured,
                    locationName: spec.placeName,
                    planID: spec.planID,
                    createdAt: captured,
                    updatedAt: captured
                ))
            }
        }

        // Extra map-pinned places in Tokyo bay area (place tag & evening photo)
        let extraDay = singleDays.last ?? 18
        let asakusaTime = date(day: extraDay, hour: 18, minute: 40)
        let asakusaKey = EncounterCalendarAggregator.dayKey(for: asakusaTime)
        let asakusaCoord = GeoCoordinate(latitude: 35.7148, longitude: 139.7967)
        let asakusaTag = DayPlaceTag(
            pairID: pairID,
            dayKey: asakusaKey,
            name: "浅草寺・仲見世",
            address: "東京都台東区浅草",
            coordinate: asakusaCoord,
            authorRole: .partnerA,
            createdAt: asakusaTime,
            updatedAt: asakusaTime
        )
        try store.addDayPlaceTag(asakusaTag)
        if let asakusaData = renderIllustratedMemoryJPEG(style: .asakusaLantern) {
            let photoID = UUID()
            try assetStore.saveData(asakusaData, kind: .dayPhoto, id: photoID)
            try store.addDayPhoto(DayPhotoAttachment(
                id: photoID,
                pairID: pairID,
                dayKey: asakusaKey,
                authorRole: .partnerA,
                mediaKind: .photo,
                placeTagID: asakusaTag.id,
                coordinate: asakusaCoord,
                capturedAt: asakusaTime,
                locationName: "浅草",
                createdAt: asakusaTime,
                updatedAt: asakusaTime
            ))
        }

        let kamakuraDay = date(day: 6, hour: 15)
        try store.addDayPlaceTag(DayPlaceTag(
            pairID: pairID,
            dayKey: EncounterCalendarAggregator.dayKey(for: kamakuraDay),
            name: "鎌倉小町通り",
            address: "神奈川県鎌倉市小町",
            coordinate: GeoCoordinate(latitude: 35.3204, longitude: 139.5513),
            authorRole: .partnerB,
            createdAt: kamakuraDay,
            updatedAt: kamakuraDay
        ))
    }

    private static func renderIllustratedMemoryJPEG(style: MemorySceneStyle) -> Data? {
        let size = CGSize(width: 720, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext

            func fillVerticalGradient(_ top: UIColor, _ bottom: UIColor) {
                let colors = [top.cgColor, bottom.cgColor] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors,
                    locations: [0, 1]
                ) {
                    cg.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: 0, y: size.height),
                        options: []
                    )
                }
            }

            func fillGlow(center: CGPoint, radius: CGFloat, color: UIColor) {
                let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                if let radial = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors,
                    locations: [0, 1]
                ) {
                    cg.drawRadialGradient(
                        radial,
                        startCenter: center,
                        startRadius: 0,
                        endCenter: center,
                        endRadius: radius,
                        options: []
                    )
                }
            }

            switch style {
            case .yokohamaHarbor:
                fillVerticalGradient(
                    UIColor(red: 0.25, green: 0.34, blue: 0.64, alpha: 1),
                    UIColor(red: 0.96, green: 0.64, blue: 0.72, alpha: 1)
                )
                fillGlow(center: CGPoint(x: 470, y: 260), radius: 260, color: UIColor(red: 1, green: 0.85, blue: 0.68, alpha: 0.55))
                UIColor(red: 0.14, green: 0.18, blue: 0.36, alpha: 0.82).setFill()
                cg.fill(CGRect(x: 0, y: 495, width: 720, height: 225))
                let buildings: [(CGFloat, CGFloat, CGFloat)] = [
                    (50, 120, 195), (150, 95, 240), (245, 75, 165), (345, 110, 290), (470, 85, 210), (575, 105, 180)
                ]
                for (x, w, h) in buildings {
                    UIColor(red: 0.18, green: 0.21, blue: 0.40, alpha: 0.92).setFill()
                    cg.fill(CGRect(x: x, y: 495 - h, width: w, height: h))
                    UIColor(red: 1, green: 0.90, blue: 0.66, alpha: 0.78).setFill()
                    for row in stride(from: 495 - h + 20, to: 470, by: 28) {
                        for col in stride(from: x + 14, to: x + w - 18, by: 22) {
                            cg.fill(CGRect(x: col, y: row, width: 10, height: 14))
                        }
                    }
                }
                for (i, x) in [120.0, 280.0, 440.0, 610.0].enumerated() {
                    fillGlow(
                        center: CGPoint(x: x, y: CGFloat(555 + (i % 2) * 35)),
                        radius: 56,
                        color: UIColor(red: 1, green: 0.82, blue: 0.68, alpha: 0.45)
                    )
                }

            case .yokohamaFerris:
                fillVerticalGradient(
                    UIColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1),
                    UIColor(red: 0.56, green: 0.44, blue: 0.74, alpha: 1)
                )
                let hub = CGPoint(x: 360, y: 315)
                fillGlow(center: hub, radius: 250, color: UIColor(red: 1.0, green: 0.74, blue: 0.88, alpha: 0.45))
                UIColor(red: 0.12, green: 0.14, blue: 0.30, alpha: 0.92).setFill()
                cg.fill(CGRect(x: 0, y: 550, width: 720, height: 170))
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.90).cgColor)
                cg.setLineWidth(10)
                cg.strokeEllipse(in: CGRect(x: 150, y: 105, width: 420, height: 420))
                cg.setLineWidth(4)
                for step in 0..<12 {
                    let angle = Double(step) * (.pi / 6.0)
                    let px = hub.x + CGFloat(cos(angle)) * 210
                    let py = hub.y + CGFloat(sin(angle)) * 210
                    cg.move(to: hub)
                    cg.addLine(to: CGPoint(x: px, y: py))
                    cg.strokePath()
                    UIColor(hue: CGFloat(step) / 12.0, saturation: 0.45, brightness: 1.0, alpha: 0.95).setFill()
                    cg.fillEllipse(in: CGRect(x: px - 14, y: py - 14, width: 28, height: 28))
                }
                UIColor(red: 0.16, green: 0.19, blue: 0.36, alpha: 1).setStroke()
                cg.setLineWidth(14)
                cg.move(to: hub)
                cg.addLine(to: CGPoint(x: 245, y: 560))
                cg.move(to: hub)
                cg.addLine(to: CGPoint(x: 475, y: 560))
                cg.strokePath()

            case .enoshimaSunset:
                fillVerticalGradient(
                    UIColor(red: 0.99, green: 0.73, blue: 0.65, alpha: 1),
                    UIColor(red: 0.99, green: 0.91, blue: 0.74, alpha: 1)
                )
                let sunCenter = CGPoint(x: 360, y: 375)
                fillGlow(center: sunCenter, radius: 220, color: UIColor(red: 1, green: 0.96, blue: 0.72, alpha: 0.85))
                UIColor(red: 1, green: 0.95, blue: 0.76, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 270, y: 285, width: 180, height: 180))
                let seaTop: CGFloat = 430
                let seaColors = [
                    UIColor(red: 0.40, green: 0.59, blue: 0.82, alpha: 1).cgColor,
                    UIColor(red: 0.22, green: 0.36, blue: 0.62, alpha: 1).cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: seaColors, locations: [0, 1]) {
                    cg.saveGState()
                    cg.clip(to: CGRect(x: 0, y: seaTop, width: 720, height: 720 - seaTop))
                    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: seaTop), end: CGPoint(x: 0, y: 720), options: [])
                    cg.restoreGState()
                }
                for row in 0..<8 {
                    let y = seaTop + 20 + CGFloat(row) * 34
                    let halfW = CGFloat(90 - row * 7)
                    UIColor(red: 1, green: 0.90, blue: 0.68, alpha: CGFloat(0.75 - Double(row) * 0.06)).setFill()
                    cg.fill(CGRect(x: 360 - halfW, y: y, width: halfW * 2, height: 9))
                }

            case .cafeLatte:
                fillVerticalGradient(
                    UIColor(red: 0.97, green: 0.88, blue: 0.78, alpha: 1),
                    UIColor(red: 0.86, green: 0.70, blue: 0.58, alpha: 1)
                )
                fillGlow(center: CGPoint(x: 220, y: 180), radius: 280, color: UIColor.white.withAlphaComponent(0.60))
                UIColor.white.withAlphaComponent(0.95).setFill()
                cg.fillEllipse(in: CGRect(x: 165, y: 215, width: 390, height: 390))
                UIColor(red: 0.76, green: 0.56, blue: 0.40, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 205, y: 255, width: 310, height: 310))
                UIColor(red: 0.98, green: 0.94, blue: 0.89, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 270, y: 310, width: 95, height: 95))
                cg.fillEllipse(in: CGRect(x: 355, y: 310, width: 95, height: 95))
                let heartPath = UIBezierPath()
                heartPath.move(to: CGPoint(x: 270, y: 360))
                heartPath.addLine(to: CGPoint(x: 360, y: 472))
                heartPath.addLine(to: CGPoint(x: 450, y: 360))
                heartPath.close()
                heartPath.fill()
                UIColor.white.withAlphaComponent(0.94).setStroke()
                cg.setLineWidth(24)
                cg.strokeEllipse(in: CGRect(x: 525, y: 365, width: 85, height: 85))

            case .hakoneOnsen:
                fillVerticalGradient(
                    UIColor(red: 0.62, green: 0.79, blue: 0.88, alpha: 1),
                    UIColor(red: 0.96, green: 0.84, blue: 0.74, alpha: 1)
                )
                let backMtn = UIBezierPath()
                backMtn.move(to: CGPoint(x: 0, y: 500))
                backMtn.addLine(to: CGPoint(x: 210, y: 260))
                backMtn.addLine(to: CGPoint(x: 460, y: 430))
                backMtn.addLine(to: CGPoint(x: 620, y: 290))
                backMtn.addLine(to: CGPoint(x: 720, y: 410))
                backMtn.addLine(to: CGPoint(x: 720, y: 720))
                backMtn.addLine(to: CGPoint(x: 0, y: 720))
                backMtn.close()
                UIColor(red: 0.42, green: 0.56, blue: 0.66, alpha: 0.85).setFill()
                backMtn.fill()
                UIColor(red: 0.42, green: 0.74, blue: 0.82, alpha: 0.92).setFill()
                cg.fill(CGRect(x: 0, y: 495, width: 720, height: 225))
                for x in [170.0, 340.0, 520.0] {
                    fillGlow(center: CGPoint(x: x, y: 475), radius: 130, color: UIColor.white.withAlphaComponent(0.65))
                }

            case .hakoneLake:
                fillVerticalGradient(
                    UIColor(red: 0.52, green: 0.82, blue: 0.98, alpha: 1),
                    UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
                )
                UIColor(red: 0.34, green: 0.66, blue: 0.88, alpha: 1).setFill()
                cg.fill(CGRect(x: 0, y: 445, width: 720, height: 275))
                UIColor(red: 0.88, green: 0.32, blue: 0.30, alpha: 1).setFill()
                cg.fill(CGRect(x: 285, y: 310, width: 20, height: 155))
                cg.fill(CGRect(x: 415, y: 310, width: 20, height: 155))
                cg.fill(CGRect(x: 240, y: 295, width: 240, height: 22))
                cg.fill(CGRect(x: 265, y: 345, width: 190, height: 16))

            case .hakoneMaple:
                fillVerticalGradient(
                    UIColor(red: 0.99, green: 0.84, blue: 0.68, alpha: 1),
                    UIColor(red: 0.90, green: 0.48, blue: 0.40, alpha: 1)
                )
                let leaves: [(CGFloat, CGFloat, CGFloat, UIColor)] = [
                    (170, 210, 96, UIColor(red: 0.92, green: 0.32, blue: 0.26, alpha: 0.90)),
                    (460, 240, 118, UIColor(red: 0.98, green: 0.54, blue: 0.28, alpha: 0.88)),
                    (310, 420, 126, UIColor(red: 0.88, green: 0.26, blue: 0.32, alpha: 0.85)),
                    (555, 490, 92, UIColor(red: 0.99, green: 0.72, blue: 0.34, alpha: 0.90))
                ]
                for (x, y, r, color) in leaves {
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                fillGlow(center: CGPoint(x: 230, y: 160), radius: 220, color: UIColor.white.withAlphaComponent(0.45))

            case .birthdayCake:
                fillVerticalGradient(
                    UIColor(red: 1.0, green: 0.89, blue: 0.94, alpha: 1),
                    UIColor(red: 0.97, green: 0.77, blue: 0.88, alpha: 1)
                )
                fillGlow(center: CGPoint(x: 360, y: 240), radius: 210, color: UIColor(red: 1, green: 0.95, blue: 0.74, alpha: 0.72))
                UIColor.white.setFill()
                cg.fill(CGRect(x: 185, y: 350, width: 350, height: 195))
                UIColor(red: 0.99, green: 0.52, blue: 0.64, alpha: 1).setFill()
                cg.fill(CGRect(x: 185, y: 430, width: 350, height: 26))
                for x in [250.0, 360.0, 470.0] {
                    UIColor(red: 0.96, green: 0.28, blue: 0.36, alpha: 1).setFill()
                    cg.fillEllipse(in: CGRect(x: x - 26, y: 315, width: 52, height: 52))
                }
                UIColor(red: 1, green: 0.80, blue: 0.42, alpha: 1).setFill()
                cg.fill(CGRect(x: 350, y: 235, width: 20, height: 85))
                UIColor(red: 1, green: 0.62, blue: 0.28, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 344, y: 192, width: 32, height: 46))

            case .sakuraPark:
                fillVerticalGradient(
                    UIColor(red: 0.74, green: 0.89, blue: 1.0, alpha: 1),
                    UIColor(red: 0.98, green: 0.90, blue: 0.95, alpha: 1)
                )
                let clouds: [(CGFloat, CGFloat, CGFloat, UIColor)] = [
                    (200, 260, 175, UIColor(red: 1.0, green: 0.78, blue: 0.88, alpha: 0.92)),
                    (475, 295, 190, UIColor(red: 1.0, green: 0.84, blue: 0.92, alpha: 0.92)),
                    (340, 200, 165, UIColor(red: 0.99, green: 0.72, blue: 0.84, alpha: 0.86))
                ]
                for (x, y, r, color) in clouds {
                    color.setFill()
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                UIColor(red: 0.62, green: 0.85, blue: 0.66, alpha: 1).setFill()
                cg.fill(CGRect(x: 0, y: 515, width: 720, height: 205))
                UIColor(red: 0.44, green: 0.34, blue: 0.32, alpha: 1).setFill()
                cg.fill(CGRect(x: 332, y: 340, width: 42, height: 195))

            case .asakusaLantern:
                fillVerticalGradient(
                    UIColor(red: 0.20, green: 0.22, blue: 0.44, alpha: 1),
                    UIColor(red: 0.48, green: 0.34, blue: 0.56, alpha: 1)
                )
                fillGlow(center: CGPoint(x: 360, y: 375), radius: 220, color: UIColor(red: 1.0, green: 0.58, blue: 0.42, alpha: 0.65))
                UIColor(red: 0.92, green: 0.25, blue: 0.24, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 245, y: 205, width: 230, height: 325))
                UIColor(red: 0.16, green: 0.14, blue: 0.22, alpha: 1).setFill()
                cg.fill(CGRect(x: 280, y: 195, width: 160, height: 32))
                cg.fill(CGRect(x: 280, y: 505, width: 160, height: 32))
            }
        }
        return image.jpegData(compressionQuality: 0.86)
    }
}
#endif
