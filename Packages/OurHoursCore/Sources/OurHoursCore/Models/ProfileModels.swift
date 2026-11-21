import Foundation

public enum BubbleColorTheme: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case clear
    case skyBlue
    case sakuraPink
    case lavender
    case mint
    case honeyYellow
    case coral

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
    public let updatedAt: Date

    public init(bubbleColor: BubbleColorTheme, birthday: CalendarDateValue?, updatedAt: Date) {
        self.bubbleColor = bubbleColor
        self.birthday = birthday
        self.updatedAt = updatedAt
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
