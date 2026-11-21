import Foundation

public enum AnniversaryMarkStyle: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case heart
    case sparkles
    case infinity
    case star
    case crown
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heart: "ハート"
        case .sparkles: "きらきら"
        case .infinity: "インフィニティ"
        case .star: "ほし"
        case .crown: "おうかん"
        case .none: "なし"
        }
    }
}

public enum BirthdayMarkStyle: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case cake
    case balloon
    case gift
    case popper
    case crown
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cake: "ケーキ"
        case .balloon: "ふうせん"
        case .gift: "プレゼント"
        case .popper: "クラッカー"
        case .crown: "おうかん"
        case .none: "なし"
        }
    }
}

public enum SeasonalDayKind: String, Sendable, Equatable, Hashable {
    case valentinesDay
    case whiteDay
    case christmas

    public var displayName: String {
        switch self {
        case .valentinesDay: "バレンタイン"
        case .whiteDay: "ホワイトデー"
        case .christmas: "クリスマス"
        }
    }
}

public enum SpecialDayEvent: Sendable, Equatable, Hashable, Identifiable {
    case anniversary(years: Int)
    case myBirthday
    case partnerBirthday
    case seasonal(SeasonalDayKind)

    public var id: String {
        switch self {
        case let .anniversary(years): "anniversary-\(years)"
        case .myBirthday: "myBirthday"
        case .partnerBirthday: "partnerBirthday"
        case let .seasonal(kind): "seasonal-\(kind.rawValue)"
        }
    }
}

public enum SpecialDayCalculator {
    private static let utcGregorian = gregorianCalendar(timeZone: .gmt)

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func isGregorianLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }

    /// 1-based inclusive day count since `anniversary` (start date itself == 1). Returns `nil` if `referenceDate` is before `anniversary`.
    public static func daysTogether(
        since anniversary: CalendarDateValue,
        asOf referenceDate: Date = .now,
        calendar: Calendar = CalendarDateValue.gregorianCurrent
    ) -> Int? {
        let civilCalendar = gregorianCalendar(timeZone: calendar.timeZone)
        let refDay = CalendarDateValue(date: referenceDate, calendar: civilCalendar)
        guard refDay >= anniversary else { return nil }
        guard let start = DateComponents(
            calendar: utcGregorian, year: anniversary.year, month: anniversary.month, day: anniversary.day, hour: 12
        ).date,
            let end = DateComponents(
                calendar: utcGregorian, year: refDay.year, month: refDay.month, day: refDay.day, hour: 12
            ).date,
            let delta = utcGregorian.dateComponents([.day], from: start, to: end).day,
            delta >= 0 else {
            return nil
        }
        return delta + 1
    }

    public static func events(
        on date: Date,
        anniversary: CalendarDateValue?,
        myBirthday: CalendarDateValue?,
        partnerBirthday: CalendarDateValue?,
        calendar: Calendar = CalendarDateValue.gregorianCurrent
    ) -> [SpecialDayEvent] {
        let civilCalendar = gregorianCalendar(timeZone: calendar.timeZone)
        let day = CalendarDateValue(date: date, calendar: civilCalendar)
        var result: [SpecialDayEvent] = []

        if let anniversary, day >= anniversary, matchesAnnual(day, target: anniversary) {
            let years = max(0, day.year - anniversary.year)
            result.append(.anniversary(years: years))
        }
        if let myBirthday, day >= myBirthday, matchesAnnual(day, target: myBirthday) {
            result.append(.myBirthday)
        }
        if let partnerBirthday, day >= partnerBirthday, matchesAnnual(day, target: partnerBirthday) {
            result.append(.partnerBirthday)
        }
        if let seasonal = seasonalEvent(month: day.month, day: day.day) {
            result.append(.seasonal(seasonal))
        }
        return result
    }

    public static func seasonalEvent(month: Int, day: Int) -> SeasonalDayKind? {
        switch (month, day) {
        case (2, 14): .valentinesDay
        case (3, 14): .whiteDay
        case (12, 25): .christmas
        default: nil
        }
    }

    private static func matchesAnnual(_ day: CalendarDateValue, target: CalendarDateValue) -> Bool {
        if target.month == 2 && target.day == 29 {
            if day.month == 2 && day.day == 29 { return true }
            if day.month == 2 && day.day == 28 {
                return !isGregorianLeapYear(day.year)
            }
            return false
        }
        return day.month == target.month && day.day == target.day
    }
}
