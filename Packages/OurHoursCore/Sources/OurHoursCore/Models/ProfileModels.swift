import Foundation

public enum BubbleColorTheme: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case clear
    case skyBlue
    case sakuraPink
    case lavender
    case mint
    case honeyYellow
    case coral
    case peachCream
    case matcha
    case sodaPop
    case berryRose
    case sunsetGlow
    case oceanDeep
    case moonlight
    case champagneGold
    case auroraPrism
    case snowCrystal
    case santaRuby
    case chocoMocha
    case crimsonDawn
    case easterPastel
    case milkyWay

    public static let starterColors: [BubbleColorTheme] = [
        .clear,
        .skyBlue,
        .sakuraPink,
        .lavender,
        .mint,
        .honeyYellow,
        .coral
    ]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .clear: "透明"
        case .skyBlue: "みずいろ"
        case .sakuraPink: "さくらピンク"
        case .lavender: "ラベンダー"
        case .mint: "ミント"
        case .honeyYellow: "はちみつ"
        case .coral: "コーラル"
        case .peachCream: "ももクリーム"
        case .matcha: "まっちゃ"
        case .sodaPop: "ソーダ"
        case .berryRose: "ベリーローズ"
        case .sunsetGlow: "ゆうやけ"
        case .oceanDeep: "うみいろ"
        case .moonlight: "つきあかり"
        case .champagneGold: "シャンパン"
        case .auroraPrism: "オーロラ"
        case .snowCrystal: "ゆきホワイト"
        case .santaRuby: "サンタルビー"
        case .chocoMocha: "ショコラ"
        case .crimsonDawn: "あけぼの紅"
        case .easterPastel: "イースターパステル"
        case .milkyWay: "あまのがわ"
        }
    }
}

/// Timezone-safe calendar date (YYYY-MM-DD) for birthdays and anniversaries.
public struct CalendarDateValue: Codable, Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static var gregorianCurrent: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    public init(date: Date, calendar: Calendar = Self.gregorianCurrent) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = comps.year ?? 2000
        self.month = comps.month ?? 1
        self.day = comps.day ?? 1
    }

    public func toDate(calendar: Calendar = Self.gregorianCurrent) -> Date {
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: comps) ?? Date()
    }

    public var formattedJapanese: String {
        "\(year)年\(month)月\(day)日"
    }

    public static func < (lhs: CalendarDateValue, rhs: CalendarDateValue) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct SyncedRoleProfile: Codable, Sendable, Equatable {
    public let bubbleColor: BubbleColorTheme
    public let birthday: CalendarDateValue?
    public let avatarAssetID: UUID?
    public let expression: BubbleExpression
    public let expressionRotationPool: [BubbleExpression]
    public let decorations: BubbleDecorationLoadout
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case bubbleColor
        case birthday
        case avatarAssetID
        case expression
        case expressionRotationPool
        case decorations
        case updatedAt
    }

    public init(
        bubbleColor: BubbleColorTheme,
        birthday: CalendarDateValue?,
        avatarAssetID: UUID? = nil,
        expression: BubbleExpression = .classic,
        expressionRotationPool: [BubbleExpression] = [],
        decorations: BubbleDecorationLoadout = .none,
        updatedAt: Date
    ) {
        self.bubbleColor = bubbleColor
        self.birthday = birthday
        self.avatarAssetID = avatarAssetID
        self.expression = expression
        self.expressionRotationPool = Self.deduplicated(expressionRotationPool)
        self.decorations = decorations
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawColor = try container.decodeIfPresent(String.self, forKey: .bubbleColor)
        bubbleColor = rawColor.flatMap(BubbleColorTheme.init(rawValue:)) ?? .skyBlue
        birthday = try container.decodeIfPresent(CalendarDateValue.self, forKey: .birthday)
        avatarAssetID = try container.decodeIfPresent(UUID.self, forKey: .avatarAssetID)
        let rawExpression = try container.decodeIfPresent(String.self, forKey: .expression)
        expression = rawExpression.flatMap(BubbleExpression.init(rawValue:)) ?? .classic
        let rawPool = try container.decodeIfPresent([String].self, forKey: .expressionRotationPool) ?? []
        expressionRotationPool = Self.deduplicated(rawPool.compactMap(BubbleExpression.init(rawValue:)))
        decorations = try container.decodeIfPresent(BubbleDecorationLoadout.self, forKey: .decorations) ?? .none
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private static func deduplicated(_ pool: [BubbleExpression]) -> [BubbleExpression] {
        var seen = Set<BubbleExpression>()
        return pool.filter { seen.insert($0).inserted }
    }
}

public struct SyncedAnniversary: Codable, Sendable, Equatable {
    /// `nil` acts as an explicit cleared tombstone so clearing syncs across devices.
    public let date: CalendarDateValue?
    public let updatedAt: Date

    public init(date: CalendarDateValue?, updatedAt: Date) {
        self.date = date
        self.updatedAt = updatedAt
    }
}
