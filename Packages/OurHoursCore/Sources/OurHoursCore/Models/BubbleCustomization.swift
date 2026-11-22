import Foundation

public enum BubbleExpression: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case classic
    case smile
    case sleepy
    case winkLeft
    case squeezed
    case catMouth
    case starry
    case pout
    case heartEyes
    case shy
    case relaxed
    case cool
    case dreamy
    case laughing
    case royalSparkle
    case poppedSurprise
    case mischievous
    case partyPop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: "おまかせ"
        case .smile: "にこにこ"
        case .sleepy: "すやすや"
        case .winkLeft: "ウィンク"
        case .squeezed: "ぎゅっ（><）"
        case .catMouth: "ねこぐち"
        case .starry: "きらきら"
        case .pout: "ぷくー"
        case .heartEyes: "めろめろ"
        case .shy: "てれてれ"
        case .relaxed: "ほっこり"
        case .cool: "きりっ"
        case .dreamy: "うっとり"
        case .laughing: "わはは"
        case .royalSparkle: "きらめき"
        case .poppedSurprise: "びっくり！"
        case .mischievous: "にやり"
        case .partyPop: "わくわく！"
        }
    }
}

public enum BubbleEars: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case catEars
    case dogEars
    case koalaEars
    case bunnyEars
    case bearEars

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .catEars: "ねこ耳"
        case .dogEars: "いぬ耳"
        case .koalaEars: "コアラ耳"
        case .bunnyEars: "うさぎ耳"
        case .bearEars: "くま耳"
        }
    }
}

public enum BubbleHeadwear: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case ribbon
    case crown
    case tiara
    case santaHat
    case snowmanHat
    case flowerCrown
    case strawHat
    case beret
    case heartHeadband
    case partyHat
    case witchHat
    case newYearMikan
    case oniHorns
    case risingSunHeadband
    case peachBlossom
    case jesterHat
    case easterEggHat
    case samuraiKabuto
    case frogRainHat
    case tanabataStar
    case festivalMask
    case moonDango
    case countdownSpark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .ribbon: "リボン"
        case .crown: "おうかん"
        case .tiara: "ティアラ"
        case .santaHat: "サンタ帽"
        case .snowmanHat: "雪だるまバケツ"
        case .flowerCrown: "花かんむり"
        case .strawHat: "麦わら帽子"
        case .beret: "ベレー帽"
        case .heartHeadband: "ハートカチューシャ"
        case .partyHat: "お誕生日ハット"
        case .witchHat: "まじょ帽子"
        case .newYearMikan: "かがみもちみかん"
        case .oniHorns: "おにのツノ"
        case .risingSunHeadband: "お祝いハチマキ"
        case .peachBlossom: "ももの花かんざし"
        case .jesterHat: "ピエロ帽"
        case .easterEggHat: "イースターエッグ"
        case .samuraiKabuto: "おりがみカブト"
        case .frogRainHat: "かえるレイン帽"
        case .tanabataStar: "おりひめ星飾り"
        case .festivalMask: "お祭りきつね面"
        case .moonDango: "お月見だんご"
        case .countdownSpark: "年越しクラッカー"
        }
    }
}

public enum BubbleOutfit: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case bowTie
    case sailorCollar
    case scarf
    case hoodie
    case overalls
    case ribbonDress
    case santaSuit
    case snowmanBody
    case kimonoCollar
    case halloweenCape
    case chocolateApron
    case whiteDayTuxedo
    case raincoat
    case yukataCollar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .bowTie: "ちょうネクタイ"
        case .sailorCollar: "セーラー服"
        case .scarf: "マフラー"
        case .hoodie: "パーカー"
        case .overalls: "オーバーオール"
        case .ribbonDress: "フリルワンピ"
        case .santaSuit: "サンタ服"
        case .snowmanBody: "雪だるまコーデ"
        case .kimonoCollar: "はれぎ"
        case .halloweenCape: "おばけマント"
        case .chocolateApron: "ショコラリボン"
        case .whiteDayTuxedo: "タキシード"
        case .raincoat: "レインコート"
        case .yukataCollar: "ゆかた"
        }
    }
}

public enum BubbleEyebrows: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case soft
    case thick
    case arched
    case worried

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .soft: "ふんわり眉"
        case .thick: "太まゆ"
        case .arched: "きりり眉"
        case .worried: "たれ眉"
        }
    }
}

public enum BubbleFacialHair: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case catWhiskers
    case gentlemanMustache
    case fullBeard
    case santaBeard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .catWhiskers: "ねこひげ"
        case .gentlemanMustache: "ちょびひげ"
        case .fullBeard: "ふわひげ"
        case .santaBeard: "サンタひげ"
        }
    }
}

public enum BubbleEyewear: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case roundGlasses
    case squareGlasses
    case heartGlasses
    case sunglasses
    case starGlasses
    case grouchoGlasses

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .roundGlasses: "丸めがね"
        case .squareGlasses: "スクエアめがね"
        case .heartGlasses: "ハートめがね"
        case .sunglasses: "サングラス"
        case .starGlasses: "スターめがね"
        case .grouchoGlasses: "ひげめがね"
        }
    }
}

public enum BubbleMole: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case underLeftEye
    case underRightEye
    case nearMouth
    case cheek

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .underLeftEye: "泣きぼくろ（左）"
        case .underRightEye: "泣きぼくろ（右）"
        case .nearMouth: "口もとぼくろ"
        case .cheek: "ほっぺぼくろ"
        }
    }
}

public enum BubbleMakeup: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case none
    case rosyCheeks
    case freckles
    case glitterTears
    case starStamps
    case goldHighlighter
    case milkyWayGlow
    case heartStamps
    case sakuraPetals
    case snowCrystals
    case pastelConfetti
    case spookyMoon

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .rosyCheeks: "じゅわっとチーク"
        case .freckles: "そばかす"
        case .glitterTears: "うるうるラメ"
        case .starStamps: "お星さまシール"
        case .goldHighlighter: "きらめきハイライト"
        case .milkyWayGlow: "あまのがわメイク"
        case .heartStamps: "ハートシール"
        case .sakuraPetals: "さくらチーク"
        case .snowCrystals: "ゆき結晶ペイント"
        case .pastelConfetti: "イースターペイント"
        case .spookyMoon: "こあくまメイク"
        }
    }
}

public struct BubbleDecorationLoadout: Codable, Sendable, Equatable, Hashable {
    public var ears: BubbleEars
    public var headwear: BubbleHeadwear
    public var outfit: BubbleOutfit
    public var eyebrows: BubbleEyebrows
    public var facialHair: BubbleFacialHair
    public var eyewear: BubbleEyewear
    public var moles: Set<BubbleMole>
    public var makeup: BubbleMakeup

    public static let none = BubbleDecorationLoadout()

    private enum CodingKeys: String, CodingKey {
        case ears
        case headwear
        case outfit
        case eyebrows
        case facialHair
        case eyewear
        case moles
        case makeup
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case headAccessory
        case mole
    }

    public init(
        ears: BubbleEars = .none,
        headwear: BubbleHeadwear = .none,
        outfit: BubbleOutfit = .none,
        eyebrows: BubbleEyebrows = .none,
        facialHair: BubbleFacialHair = .none,
        eyewear: BubbleEyewear = .none,
        moles: Set<BubbleMole> = [],
        makeup: BubbleMakeup = .none
    ) {
        self.ears = ears
        self.headwear = headwear
        self.outfit = outfit
        self.eyebrows = eyebrows
        self.facialHair = facialHair
        self.eyewear = eyewear
        self.moles = moles.filter { $0 != .none }
        self.makeup = makeup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        let legacyHeadRaw = try legacy.decodeIfPresent(String.self, forKey: .headAccessory)
        if let rawEars = try container.decodeIfPresent(String.self, forKey: .ears) {
            ears = BubbleEars(rawValue: rawEars) ?? .none
        } else if let legacyHeadRaw {
            ears = BubbleEars(rawValue: legacyHeadRaw) ?? .none
        } else {
            ears = .none
        }

        if let rawHeadwear = try container.decodeIfPresent(String.self, forKey: .headwear) {
            headwear = BubbleHeadwear(rawValue: rawHeadwear) ?? .none
        } else if let legacyHeadRaw {
            headwear = BubbleHeadwear(rawValue: legacyHeadRaw) ?? .none
        } else {
            headwear = .none
        }

        outfit = try container.decodeIfPresent(String.self, forKey: .outfit)
            .flatMap(BubbleOutfit.init(rawValue:)) ?? .none
        eyebrows = try container.decodeIfPresent(String.self, forKey: .eyebrows)
            .flatMap(BubbleEyebrows.init(rawValue:)) ?? .none
        facialHair = try container.decodeIfPresent(String.self, forKey: .facialHair)
            .flatMap(BubbleFacialHair.init(rawValue:)) ?? .none
        eyewear = try container.decodeIfPresent(String.self, forKey: .eyewear)
            .flatMap(BubbleEyewear.init(rawValue:)) ?? .none

        if let rawMoles = try container.decodeIfPresent([String].self, forKey: .moles) {
            moles = Set(rawMoles.compactMap(BubbleMole.init(rawValue:)).filter { $0 != .none })
        } else if let legacyMoleRaw = try legacy.decodeIfPresent(String.self, forKey: .mole),
                  let legacyMole = BubbleMole(rawValue: legacyMoleRaw),
                  legacyMole != .none {
            moles = [legacyMole]
        } else {
            moles = []
        }

        makeup = try container.decodeIfPresent(String.self, forKey: .makeup)
            .flatMap(BubbleMakeup.init(rawValue:)) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ears.rawValue, forKey: .ears)
        try container.encode(headwear.rawValue, forKey: .headwear)
        try container.encode(outfit.rawValue, forKey: .outfit)
        try container.encode(eyebrows.rawValue, forKey: .eyebrows)
        try container.encode(facialHair.rawValue, forKey: .facialHair)
        try container.encode(eyewear.rawValue, forKey: .eyewear)
        try container.encode(moles.map(\.rawValue).sorted(), forKey: .moles)
        try container.encode(makeup.rawValue, forKey: .makeup)
    }

    public mutating func toggleMole(_ mole: BubbleMole) {
        if mole == .none {
            moles.removeAll()
        } else if moles.contains(mole) {
            moles.remove(mole)
        } else {
            moles.insert(mole)
        }
    }

    public var isEmpty: Bool {
        ears == .none
            && headwear == .none
            && outfit == .none
            && eyebrows == .none
            && facialHair == .none
            && eyewear == .none
            && moles.isEmpty
            && makeup == .none
    }

    public var sortKey: String {
        let moleList = moles.map(\.rawValue).sorted().joined(separator: ",")
        return [
            ears.rawValue,
            headwear.rawValue,
            outfit.rawValue,
            eyebrows.rawValue,
            facialHair.rawValue,
            eyewear.rawValue,
            moleList,
            makeup.rawValue
        ].joined(separator: "|")
    }
}

/// Local-only visual customization applied when rendering the partner's bubble on this device.
public struct PartnerBubbleDisplayOverride: Codable, Sendable, Equatable, Hashable {
    public var color: BubbleColorTheme?
    public var expression: BubbleExpression?
    public var expressionRotationPool: [BubbleExpression]?
    public var decorations: BubbleDecorationLoadout?

    public static let none = PartnerBubbleDisplayOverride()

    private enum CodingKeys: String, CodingKey {
        case color
        case expression
        case expressionRotationPool
        case decorations
    }

    public init(
        color: BubbleColorTheme? = nil,
        expression: BubbleExpression? = nil,
        expressionRotationPool: [BubbleExpression]? = nil,
        decorations: BubbleDecorationLoadout? = nil
    ) {
        self.color = color
        self.expression = expression
        if let expressionRotationPool {
            var seen = Set<BubbleExpression>()
            self.expressionRotationPool = expressionRotationPool.filter { seen.insert($0).inserted }
        } else {
            self.expressionRotationPool = nil
        }
        self.decorations = decorations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(String.self, forKey: .color)
            .flatMap(BubbleColorTheme.init(rawValue:))
        expression = try container.decodeIfPresent(String.self, forKey: .expression)
            .flatMap(BubbleExpression.init(rawValue:))
        if let rawPool = try container.decodeIfPresent([String].self, forKey: .expressionRotationPool) {
            var seen = Set<BubbleExpression>()
            expressionRotationPool = rawPool.compactMap(BubbleExpression.init(rawValue:)).filter {
                seen.insert($0).inserted
            }
        } else {
            expressionRotationPool = nil
        }
        decorations = try container.decodeIfPresent(BubbleDecorationLoadout.self, forKey: .decorations)
    }

    public var isEmpty: Bool {
        color == nil
            && expression == nil
            && (expressionRotationPool == nil || expressionRotationPool?.isEmpty == true)
            && (decorations == nil || decorations?.isEmpty == true)
    }
}

public enum BubbleCustomizationCategory: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case color
    case expression
    case makeup
    case ears
    case headwear
    case outfit
    case eyebrows
    case facialHair
    case eyewear
    case mole

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .color: "色"
        case .expression: "表情"
        case .makeup: "メイク"
        case .ears: "耳"
        case .headwear: "あたま"
        case .outfit: "ふく"
        case .eyebrows: "まゆげ"
        case .facialHair: "ひげ"
        case .eyewear: "めがね"
        case .mole: "ほくろ"
        }
    }

    public var symbolName: String {
        switch self {
        case .color: "paintpalette.fill"
        case .expression: "face.smiling.inverse"
        case .makeup: "sparkles"
        case .ears: "pawprint.fill"
        case .headwear: "crown.fill"
        case .outfit: "tshirt.fill"
        case .eyebrows: "eyebrow"
        case .facialHair: "mustache.fill"
        case .eyewear: "eyeglasses"
        case .mole: "sparkle"
        }
    }
}

public enum BubbleEventKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case spring
    case summer
    case autumn
    case winter
    case newYear
    case setsubun
    case foundationDay
    case valentinesDay
    case hinamatsuri
    case whiteDay
    case aprilFools
    case easter
    case childrensDay
    case rainySeason
    case tanabata
    case summerFestival
    case otsukimi
    case halloween
    case christmas
    case newYearsEve
    case myBirthday
    case partnerBirthday
    case anniversary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spring: "春"
        case .summer: "夏"
        case .autumn: "秋"
        case .winter: "冬"
        case .newYear: "お正月"
        case .setsubun: "節分"
        case .foundationDay: "建国記念の日"
        case .valentinesDay: "バレンタイン"
        case .hinamatsuri: "ひなまつり"
        case .whiteDay: "ホワイトデー"
        case .aprilFools: "エイプリルフール"
        case .easter: "イースター"
        case .childrensDay: "こどもの日"
        case .rainySeason: "梅雨"
        case .tanabata: "七夕"
        case .summerFestival: "夏祭り"
        case .otsukimi: "お月見"
        case .halloween: "ハロウィン"
        case .christmas: "クリスマス"
        case .newYearsEve: "大晦日"
        case .myBirthday: "自分の誕生日"
        case .partnerBirthday: "相手の誕生日"
        case .anniversary: "記念日"
        }
    }

    public var unlockConditionLabel: String {
        switch self {
        case .spring: "春（3〜5月）"
        case .summer: "夏（6〜8月）"
        case .autumn: "秋（9〜11月）"
        case .winter: "冬（12〜2月）"
        case .newYear: "お正月（1/1〜7）"
        case .setsubun: "節分（2/1〜3）"
        case .foundationDay: "建国記念の日（2/11）"
        case .valentinesDay: "バレンタイン（2/1〜14）"
        case .hinamatsuri: "ひなまつり（3/1〜3）"
        case .whiteDay: "ホワイトデー（3/1〜14）"
        case .aprilFools: "エイプリルフール（4/1）"
        case .easter: "イースター（春）"
        case .childrensDay: "こどもの日（5/1〜5）"
        case .rainySeason: "梅雨（6/10〜7/5）"
        case .tanabata: "七夕（7/1〜7）"
        case .summerFestival: "夏祭り（8/1〜20）"
        case .otsukimi: "お月見（9/10〜30）"
        case .halloween: "ハロウィン（10/15〜31）"
        case .christmas: "クリスマス（12/1〜25）"
        case .newYearsEve: "大晦日（12/31）"
        case .myBirthday: "自分の誕生日"
        case .partnerBirthday: "相手の誕生日"
        case .anniversary: "記念日"
        }
    }

    public var hintText: String {
        switch self {
        case .spring, .summer, .autumn, .winter:
            "\(unlockConditionLabel)の季節にアプリを開くか記録すると解放されます"
        case .foundationDay, .aprilFools, .newYearsEve:
            "\(unlockConditionLabel)にアプリを開くか記録すると解放されます"
        case .easter:
            "イースターの時期（復活祭の前後）にアプリを開くか記録すると解放されます"
        case .newYear, .setsubun, .valentinesDay, .hinamatsuri, .whiteDay, .childrensDay,
                .rainySeason, .tanabata, .summerFestival, .otsukimi, .halloween, .christmas:
            "\(unlockConditionLabel)の期間中にアプリを開くか記録すると解放されます"
        case .myBirthday:
            "設定した自分の誕生日を迎えると解放されます"
        case .partnerBirthday:
            "相手の誕生日を迎えると解放されます"
        case .anniversary:
            "設定した記念日を迎えると解放されます"
        }
    }
}

public enum BubbleEventDetector {
    /// Anonymous Gregorian Easter Sunday algorithm (Meeus/Jones/Butcher).
    public static func gregorianEasterDate(year: Int) -> CalendarDateValue {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return CalendarDateValue(year: year, month: month, day: day)
    }

    public static func detectedEvents(
        asOf referenceDate: Date,
        encounterDates: [Date] = [],
        anniversary: CalendarDateValue?,
        myBirthday: CalendarDateValue?,
        partnerBirthday: CalendarDateValue?,
        calendar: Calendar = CalendarDateValue.gregorianCurrent
    ) -> Set<BubbleEventKind> {
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone

        var result = Set<BubbleEventKind>()
        let probeDates = [referenceDate] + encounterDates

        for date in probeDates {
            let comps = civilCalendar.dateComponents([.year, .month, .day], from: date)
            if let year = comps.year, let month = comps.month, let day = comps.day {
                switch month {
                case 3, 4, 5: result.insert(.spring)
                case 6, 7, 8: result.insert(.summer)
                case 9, 10, 11: result.insert(.autumn)
                case 12, 1, 2: result.insert(.winter)
                default: break
                }

                if month == 1 && (1...7).contains(day) { result.insert(.newYear) }
                if month == 2 && (1...3).contains(day) { result.insert(.setsubun) }
                if month == 2 && day == 11 { result.insert(.foundationDay) }
                if month == 2 && (1...14).contains(day) { result.insert(.valentinesDay) }
                if month == 3 && (1...3).contains(day) { result.insert(.hinamatsuri) }
                if month == 3 && (1...14).contains(day) { result.insert(.whiteDay) }
                if month == 4 && day == 1 { result.insert(.aprilFools) }
                if month == 5 && (1...5).contains(day) { result.insert(.childrensDay) }
                if (month == 6 && day >= 10) || (month == 7 && day <= 5) { result.insert(.rainySeason) }
                if month == 7 && (1...7).contains(day) { result.insert(.tanabata) }
                if month == 8 && (1...20).contains(day) { result.insert(.summerFestival) }
                if month == 9 && (10...30).contains(day) { result.insert(.otsukimi) }
                if month == 10 && (15...31).contains(day) { result.insert(.halloween) }
                if month == 12 && (1...25).contains(day) { result.insert(.christmas) }
                if month == 12 && day == 31 { result.insert(.newYearsEve) }

                let easterDate = gregorianEasterDate(year: year).toDate(calendar: civilCalendar)
                let easterStart = civilCalendar.startOfDay(for: easterDate)
                let probeStart = civilCalendar.startOfDay(for: date)
                if let diffDays = civilCalendar.dateComponents([.day], from: easterStart, to: probeStart).day,
                   (-7...2).contains(diffDays) {
                    result.insert(.easter)
                }
            }

            let specialEvents = SpecialDayCalculator.events(
                on: date,
                anniversary: anniversary,
                myBirthday: myBirthday,
                partnerBirthday: partnerBirthday,
                calendar: civilCalendar
            )
            for special in specialEvents {
                switch special {
                case .anniversary: result.insert(.anniversary)
                case .myBirthday: result.insert(.myBirthday)
                case .partnerBirthday: result.insert(.partnerBirthday)
                case .seasonal(.valentinesDay): result.insert(.valentinesDay)
                case .seasonal(.whiteDay): result.insert(.whiteDay)
                case .seasonal(.christmas): result.insert(.christmas)
                }
            }
        }

        if let anniversary,
           let days = SpecialDayCalculator.daysTogether(since: anniversary, asOf: referenceDate, calendar: civilCalendar),
           days >= 365 {
            result.insert(.anniversary)
        }

        return result
    }
}

public enum BubbleUnlockRequirement: Sendable, Equatable, Hashable {
    case starter
    case cumulativeHours(Int)
    case daysTogether(Int)
    case event(BubbleEventKind)
    case secretRapidPop

    public var requirementLabel: String {
        switch self {
        case .starter: "最初から"
        case let .cumulativeHours(hours): "累計 \(hours)時間"
        case let .daysTogether(days): "\(days)日目"
        case let .event(eventKind): eventKind.unlockConditionLabel
        case .secretRapidPop: "ひみつの条件"
        }
    }

    public var isSecret: Bool {
        if case .secretRapidPop = self { return true }
        return false
    }

    public var isEvent: Bool {
        if case .event = self { return true }
        return false
    }
}

public enum BubbleUnlockPayload: Sendable, Equatable, Hashable {
    case color(BubbleColorTheme)
    case expression(BubbleExpression)
    case makeup(BubbleMakeup)
    case ears(BubbleEars)
    case headwear(BubbleHeadwear)
    case outfit(BubbleOutfit)
    case eyebrows(BubbleEyebrows)
    case facialHair(BubbleFacialHair)
    case eyewear(BubbleEyewear)
    case mole(BubbleMole)

    public var isNoneSlot: Bool {
        switch self {
        case .color, .expression: false
        case let .makeup(v): v == .none
        case let .ears(v): v == .none
        case let .headwear(v): v == .none
        case let .outfit(v): v == .none
        case let .eyebrows(v): v == .none
        case let .facialHair(v): v == .none
        case let .eyewear(v): v == .none
        case let .mole(v): v == .none
        }
    }
}

public struct BubbleUnlockItem: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let category: BubbleCustomizationCategory
    public let title: String
    public let requirement: BubbleUnlockRequirement
    public let payload: BubbleUnlockPayload

    public init(
        id: String,
        category: BubbleCustomizationCategory,
        title: String,
        requirement: BubbleUnlockRequirement,
        payload: BubbleUnlockPayload
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.requirement = requirement
        self.payload = payload
    }

    public var isNoneSlot: Bool {
        payload.isNoneSlot
    }
}

public struct BubbleUnlockProgress: Sendable, Equatable {
    public static let maxTargetHours = 1095
    public static let maxTargetDays = 365

    public let cumulativeSeconds: TimeInterval
    public let effectiveDays: Int
    public let hasDiscoveredSecretPop: Bool
    public let achievedEvents: Set<BubbleEventKind>
    public let unlockAllOverride: Bool

    public init(
        cumulativeSeconds: TimeInterval,
        effectiveDays: Int,
        hasDiscoveredSecretPop: Bool,
        achievedEvents: Set<BubbleEventKind> = [],
        unlockAllOverride: Bool = false
    ) {
        self.cumulativeSeconds = max(0, cumulativeSeconds)
        self.effectiveDays = max(0, effectiveDays)
        self.hasDiscoveredSecretPop = hasDiscoveredSecretPop
        self.achievedEvents = achievedEvents
        self.unlockAllOverride = unlockAllOverride
    }

    public var cumulativeHours: Double {
        cumulativeSeconds / 3600.0
    }

    public func isUnlocked(_ requirement: BubbleUnlockRequirement) -> Bool {
        if unlockAllOverride { return true }
        switch requirement {
        case .starter:
            return true
        case let .cumulativeHours(targetHours):
            return cumulativeSeconds >= TimeInterval(targetHours) * 3600.0
        case let .daysTogether(targetDays):
            return effectiveDays >= targetDays
        case let .event(eventKind):
            return achievedEvents.contains(eventKind)
        case .secretRapidPop:
            return hasDiscoveredSecretPop
        }
    }

    public func isUnlocked(_ item: BubbleUnlockItem) -> Bool {
        isUnlocked(item.requirement)
    }

    public func progressFraction(for requirement: BubbleUnlockRequirement) -> Double {
        if isUnlocked(requirement) { return 1.0 }
        switch requirement {
        case .starter:
            return 1.0
        case let .cumulativeHours(targetHours):
            guard targetHours > 0 else { return 1.0 }
            return min(1.0, max(0.0, cumulativeHours / Double(targetHours)))
        case let .daysTogether(targetDays):
            guard targetDays > 0 else { return 1.0 }
            return min(1.0, max(0.0, Double(effectiveDays) / Double(targetDays)))
        case let .event(eventKind):
            return achievedEvents.contains(eventKind) ? 1.0 : 0.0
        case .secretRapidPop:
            return hasDiscoveredSecretPop ? 1.0 : 0.0
        }
    }

    public func remainingText(for requirement: BubbleUnlockRequirement) -> String? {
        guard !isUnlocked(requirement) else { return nil }
        switch requirement {
        case .starter:
            return nil
        case let .cumulativeHours(targetHours):
            let remainingSeconds = max(0, TimeInterval(targetHours) * 3600.0 - cumulativeSeconds)
            let remHours = Int(remainingSeconds) / 3600
            let remMinutes = max(1, (Int(remainingSeconds) % 3600 + 59) / 60)
            if remHours > 0 {
                return "あと約\(remHours)時間"
            }
            return "あと\(remMinutes)分"
        case let .daysTogether(targetDays):
            let remainingDays = max(1, targetDays - effectiveDays)
            return "あと\(remainingDays)日"
        case let .event(eventKind):
            return eventKind.hintText
        case .secretRapidPop:
            return "ホームのシャボン玉を素早く連打すると…？"
        }
    }

    public var unlockedItemIDs: Set<String> {
        Set(BubbleUnlockCatalog.allItems.filter { isUnlocked($0) }.map(\.id))
    }

    public var unlockedNonStarterItems: [BubbleUnlockItem] {
        BubbleUnlockCatalog.allItems.filter { $0.requirement != .starter && isUnlocked($0) }
    }
}

public enum BubbleUnlockCatalog {
    public static let allItems: [BubbleUnlockItem] = {
        var items: [BubbleUnlockItem] = []

        // Colors (7 starters + 9 time/day + 3 event = 19)
        let colorRequirements: [(BubbleColorTheme, BubbleUnlockRequirement)] = [
            (.clear, .starter),
            (.skyBlue, .starter),
            (.sakuraPink, .starter),
            (.lavender, .starter),
            (.mint, .starter),
            (.honeyYellow, .starter),
            (.coral, .starter),
            (.peachCream, .cumulativeHours(6)),
            (.matcha, .cumulativeHours(100)),
            (.sunsetGlow, .daysTogether(100)),
            (.sodaPop, .cumulativeHours(200)),
            (.moonlight, .daysTogether(180)),
            (.berryRose, .cumulativeHours(450)),
            (.oceanDeep, .cumulativeHours(680)),
            (.champagneGold, .cumulativeHours(950)),
            (.auroraPrism, .cumulativeHours(1095)),
            (.snowCrystal, .event(.winter)),
            (.santaRuby, .event(.christmas)),
            (.chocoMocha, .event(.valentinesDay)),
            (.crimsonDawn, .event(.foundationDay)),
            (.easterPastel, .event(.easter)),
            (.milkyWay, .event(.tanabata))
        ]
        for (color, req) in colorRequirements {
            items.append(BubbleUnlockItem(
                id: "color.\(color.rawValue)",
                category: .color,
                title: color.displayName,
                requirement: req,
                payload: .color(color)
            ))
        }

        // Expressions (3 starters + 12 progression + 2 event + 1 secret = 18)
        let expressionRequirements: [(BubbleExpression, BubbleUnlockRequirement)] = [
            (.classic, .starter),
            (.smile, .starter),
            (.sleepy, .starter),
            (.winkLeft, .cumulativeHours(3)),
            (.squeezed, .daysTogether(3)),
            (.starry, .daysTogether(7)),
            (.catMouth, .cumulativeHours(10)),
            (.heartEyes, .daysTogether(30)),
            (.pout, .cumulativeHours(36)),
            (.relaxed, .daysTogether(60)),
            (.shy, .cumulativeHours(150)),
            (.dreamy, .daysTogether(150)),
            (.cool, .cumulativeHours(350)),
            (.laughing, .cumulativeHours(550)),
            (.royalSparkle, .daysTogether(365)),
            (.mischievous, .event(.aprilFools)),
            (.partyPop, .event(.newYearsEve)),
            (.poppedSurprise, .secretRapidPop)
        ]
        for (expr, req) in expressionRequirements {
            items.append(BubbleUnlockItem(
                id: "expression.\(expr.rawValue)",
                category: .expression,
                title: expr.displayName,
                requirement: req,
                payload: .expression(expr)
            ))
        }

        // Ears (none + 5 unlockables = 6)
        let earRequirements: [(BubbleEars, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.catEars, .cumulativeHours(15)),
            (.bunnyEars, .daysTogether(180)),
            (.dogEars, .cumulativeHours(200)),
            (.bearEars, .daysTogether(300)),
            (.koalaEars, .cumulativeHours(550))
        ]
        for (ear, req) in earRequirements {
            items.append(BubbleUnlockItem(
                id: "ears.\(ear.rawValue)",
                category: .ears,
                title: ear.displayName,
                requirement: req,
                payload: .ears(ear)
            ))
        }

        // Headwear (none + 2 time/day + 21 event = 24)
        let headwearRequirements: [(BubbleHeadwear, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.ribbon, .daysTogether(14)),
            (.crown, .cumulativeHours(1095)),
            (.tiara, .event(.anniversary)),
            (.santaHat, .event(.christmas)),
            (.snowmanHat, .event(.winter)),
            (.flowerCrown, .event(.spring)),
            (.strawHat, .event(.summer)),
            (.beret, .event(.autumn)),
            (.heartHeadband, .event(.valentinesDay)),
            (.partyHat, .event(.myBirthday)),
            (.witchHat, .event(.halloween)),
            (.newYearMikan, .event(.newYear)),
            (.oniHorns, .event(.setsubun)),
            (.risingSunHeadband, .event(.foundationDay)),
            (.peachBlossom, .event(.hinamatsuri)),
            (.jesterHat, .event(.aprilFools)),
            (.easterEggHat, .event(.easter)),
            (.samuraiKabuto, .event(.childrensDay)),
            (.frogRainHat, .event(.rainySeason)),
            (.tanabataStar, .event(.tanabata)),
            (.festivalMask, .event(.summerFestival)),
            (.moonDango, .event(.otsukimi)),
            (.countdownSpark, .event(.newYearsEve))
        ]
        for (hw, req) in headwearRequirements {
            items.append(BubbleUnlockItem(
                id: "headwear.\(hw.rawValue)",
                category: .headwear,
                title: hw.displayName,
                requirement: req,
                payload: .headwear(hw)
            ))
        }

        // Outfits (none + 6 time/day + 8 event = 15)
        let outfitRequirements: [(BubbleOutfit, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.bowTie, .cumulativeHours(24)),
            (.sailorCollar, .daysTogether(90)),
            (.ribbonDress, .daysTogether(240)),
            (.hoodie, .cumulativeHours(270)),
            (.scarf, .cumulativeHours(680)),
            (.overalls, .cumulativeHours(800)),
            (.santaSuit, .event(.christmas)),
            (.snowmanBody, .event(.winter)),
            (.kimonoCollar, .event(.newYear)),
            (.chocolateApron, .event(.valentinesDay)),
            (.whiteDayTuxedo, .event(.whiteDay)),
            (.halloweenCape, .event(.halloween)),
            (.raincoat, .event(.rainySeason)),
            (.yukataCollar, .event(.summerFestival))
        ]
        for (outfit, req) in outfitRequirements {
            items.append(BubbleUnlockItem(
                id: "outfit.\(outfit.rawValue)",
                category: .outfit,
                title: outfit.displayName,
                requirement: req,
                payload: .outfit(outfit)
            ))
        }

        // Eyebrows (none + 1 starter + 3 unlockables = 5)
        let eyebrowRequirements: [(BubbleEyebrows, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.soft, .starter),
            (.arched, .daysTogether(50)),
            (.thick, .cumulativeHours(100)),
            (.worried, .daysTogether(150))
        ]
        for (eyebrows, req) in eyebrowRequirements {
            items.append(BubbleUnlockItem(
                id: "eyebrows.\(eyebrows.rawValue)",
                category: .eyebrows,
                title: eyebrows.displayName,
                requirement: req,
                payload: .eyebrows(eyebrows)
            ))
        }

        // Facial hair (none + 3 time + 1 event = 5)
        let facialHairRequirements: [(BubbleFacialHair, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.catWhiskers, .cumulativeHours(75)),
            (.gentlemanMustache, .cumulativeHours(450)),
            (.fullBeard, .cumulativeHours(950)),
            (.santaBeard, .event(.christmas))
        ]
        for (hair, req) in facialHairRequirements {
            items.append(BubbleUnlockItem(
                id: "facialHair.\(hair.rawValue)",
                category: .facialHair,
                title: hair.displayName,
                requirement: req,
                payload: .facialHair(hair)
            ))
        }

        // Eyewear (none + 4 time/day + 2 event = 7)
        let eyewearRequirements: [(BubbleEyewear, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.roundGlasses, .cumulativeHours(50)),
            (.heartGlasses, .daysTogether(100)),
            (.squareGlasses, .cumulativeHours(350)),
            (.sunglasses, .cumulativeHours(800)),
            (.starGlasses, .event(.partnerBirthday)),
            (.grouchoGlasses, .event(.aprilFools))
        ]
        for (eyewear, req) in eyewearRequirements {
            items.append(BubbleUnlockItem(
                id: "eyewear.\(eyewear.rawValue)",
                category: .eyewear,
                title: eyewear.displayName,
                requirement: req,
                payload: .eyewear(eyewear)
            ))
        }

        // Moles (none + 1 starter + 3 unlockables = 5)
        let moleRequirements: [(BubbleMole, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.underLeftEye, .starter),
            (.underRightEye, .cumulativeHours(1)),
            (.cheek, .daysTogether(1)),
            (.nearMouth, .daysTogether(30))
        ]
        for (mole, req) in moleRequirements {
            items.append(BubbleUnlockItem(
                id: "mole.\(mole.rawValue)",
                category: .mole,
                title: mole.displayName,
                requirement: req,
                payload: .mole(mole)
            ))
        }

        // Makeup (none + 1 starter + 4 progression + 6 event = 12)
        let makeupRequirements: [(BubbleMakeup, BubbleUnlockRequirement)] = [
            (.none, .starter),
            (.rosyCheeks, .starter),
            (.freckles, .cumulativeHours(12)),
            (.glitterTears, .daysTogether(20)),
            (.starStamps, .daysTogether(45)),
            (.goldHighlighter, .cumulativeHours(240)),
            (.milkyWayGlow, .event(.tanabata)),
            (.heartStamps, .event(.valentinesDay)),
            (.sakuraPetals, .event(.spring)),
            (.snowCrystals, .event(.winter)),
            (.pastelConfetti, .event(.easter)),
            (.spookyMoon, .event(.halloween))
        ]
        for (makeup, req) in makeupRequirements {
            items.append(BubbleUnlockItem(
                id: "makeup.\(makeup.rawValue)",
                category: .makeup,
                title: makeup.displayName,
                requirement: req,
                payload: .makeup(makeup)
            ))
        }

        return items
    }()

    public static let starterItemIDs: Set<String> = Set(
        allItems.filter { $0.requirement == .starter }.map(\.id)
    )

    public static let unlockableItems: [BubbleUnlockItem] = allItems.filter { !$0.isNoneSlot }

    public static let nonStarterItems: [BubbleUnlockItem] = allItems.filter { $0.requirement != .starter }

    private static let itemsByID: [String: BubbleUnlockItem] = Dictionary(
        uniqueKeysWithValues: allItems.map { ($0.id, $0) }
    )

    public static func item(for id: String) -> BubbleUnlockItem? {
        itemsByID[id]
    }

    public static func items(in category: BubbleCustomizationCategory) -> [BubbleUnlockItem] {
        allItems.filter { $0.category == category }
    }

    public static func requirement(for color: BubbleColorTheme) -> BubbleUnlockRequirement {
        item(for: "color.\(color.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for expression: BubbleExpression) -> BubbleUnlockRequirement {
        item(for: "expression.\(expression.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for ears: BubbleEars) -> BubbleUnlockRequirement {
        item(for: "ears.\(ears.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for headwear: BubbleHeadwear) -> BubbleUnlockRequirement {
        item(for: "headwear.\(headwear.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for outfit: BubbleOutfit) -> BubbleUnlockRequirement {
        item(for: "outfit.\(outfit.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for eyebrows: BubbleEyebrows) -> BubbleUnlockRequirement {
        item(for: "eyebrows.\(eyebrows.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for facialHair: BubbleFacialHair) -> BubbleUnlockRequirement {
        item(for: "facialHair.\(facialHair.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for eyewear: BubbleEyewear) -> BubbleUnlockRequirement {
        item(for: "eyewear.\(eyewear.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for mole: BubbleMole) -> BubbleUnlockRequirement {
        item(for: "mole.\(mole.rawValue)")?.requirement ?? .starter
    }

    public static func requirement(for makeup: BubbleMakeup) -> BubbleUnlockRequirement {
        item(for: "makeup.\(makeup.rawValue)")?.requirement ?? .starter
    }
}
