import Foundation
import Testing
@testable import OurHoursCore

@Suite struct SpecialDaysTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        CalendarDateValue(year: year, month: month, day: day).toDate(calendar: calendar)
    }

    private func events(
        on day: Date,
        anniversary: CalendarDateValue? = nil,
        myBirthday: CalendarDateValue? = nil,
        partnerBirthday: CalendarDateValue? = nil
    ) -> [SpecialDayEvent] {
        SpecialDayCalculator.events(
            on: day, anniversary: anniversary, myBirthday: myBirthday, partnerBirthday: partnerBirthday,
            calendar: calendar
        )
    }

    @Test func countsDaysInclusivelyAcrossLeapYear() {
        let start = CalendarDateValue(year: 2023, month: 3, day: 1)
        func count(_ date: Date) -> Int? {
            SpecialDayCalculator.daysTogether(since: start, asOf: date, calendar: calendar)
        }

        #expect(count(date(2023, 2, 28)) == nil)
        #expect(count(date(2023, 3, 1)) == 1)
        #expect(count(date(2023, 3, 2)) == 2)
        #expect(count(date(2024, 3, 1)) == 367)
    }

    @Test func anniversaryStartsAtYearZeroAndOverlapsValentinesDay() {
        let start = CalendarDateValue(year: 2024, month: 2, day: 14)
        #expect(events(on: date(2023, 2, 14), anniversary: start) == [.seasonal(.valentinesDay)])
        #expect(events(on: date(2024, 2, 14), anniversary: start) == [.anniversary(years: 0), .seasonal(.valentinesDay)])
        #expect(events(on: date(2025, 2, 14), anniversary: start) == [.anniversary(years: 1), .seasonal(.valentinesDay)])
    }

    @Test func leapDayEventsFallOnLastDayOfFebruary() {
        let target = CalendarDateValue(year: 2020, month: 2, day: 29)
        func leapDayEvents(on day: Date) -> [SpecialDayEvent] {
            events(on: day, anniversary: target, myBirthday: target, partnerBirthday: target)
        }

        #expect(leapDayEvents(on: date(2024, 2, 28)).isEmpty)
        #expect(leapDayEvents(on: date(2024, 2, 29)) == [.anniversary(years: 4), .myBirthday, .partnerBirthday])
        #expect(leapDayEvents(on: date(2025, 2, 28)) == [.anniversary(years: 5), .myBirthday, .partnerBirthday])
        #expect(leapDayEvents(on: date(2025, 3, 1)).isEmpty)
    }

    @Test func seasonalDaysIncludeWhiteDayAndChristmasBirthday() {
        let birthday = CalendarDateValue(year: 1995, month: 12, day: 25)
        #expect(events(on: date(2026, 3, 14)) == [.seasonal(.whiteDay)])
        #expect(events(on: date(2026, 12, 25), partnerBirthday: birthday) == [.partnerBirthday, .seasonal(.christmas)])
        #expect(events(on: date(2026, 12, 24), partnerBirthday: birthday).isEmpty)
    }

    @Test func markStylesRoundTripWithJapaneseNames() throws {
        let anniversaryStyles = AnniversaryMarkStyle.allCases
        let birthdayStyles = BirthdayMarkStyle.allCases
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode([AnniversaryMarkStyle].self, from: encoder.encode(anniversaryStyles)) == anniversaryStyles)
        #expect(try decoder.decode([BirthdayMarkStyle].self, from: encoder.encode(birthdayStyles)) == birthdayStyles)
        #expect(anniversaryStyles.map(\.displayName) == ["ハート", "きらきら", "インフィニティ", "ほし", "おうかん", "なし"])
        #expect(birthdayStyles.map(\.displayName) == ["ケーキ", "ふうせん", "プレゼント", "クラッカー", "おうかん", "なし"])
    }

    @Test func countsDaysAcrossMidnightDSTSpringForward() throws {
        var saoPaulo = Calendar(identifier: .gregorian)
        saoPaulo.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let start = CalendarDateValue(year: 2018, month: 11, day: 4)
        let nov5 = try #require(saoPaulo.date(from: DateComponents(year: 2018, month: 11, day: 5, hour: 0, minute: 30)))
        #expect(SpecialDayCalculator.daysTogether(since: start, asOf: nov5, calendar: saoPaulo) == 2)
    }

    @Test func ignoresNonGregorianCalendarIdentifiers() {
        let start = CalendarDateValue(year: 2024, month: 2, day: 14)
        let feb15 = date(2024, 2, 15)
        let nextYear = date(2025, 2, 14)

        for identifier in [Calendar.Identifier.japanese, .buddhist] {
            var cal = Calendar(identifier: identifier)
            cal.timeZone = .gmt
            #expect(SpecialDayCalculator.daysTogether(since: start, asOf: feb15, calendar: cal) == 2)
            #expect(SpecialDayCalculator.events(on: nextYear, anniversary: start, myBirthday: nil, partnerBirthday: nil, calendar: cal) == [.anniversary(years: 1), .seasonal(.valentinesDay)])
        }
    }

    @Test func birthdaysDoNotAppearBeforeBirthYear() {
        let birthday = CalendarDateValue(year: 1995, month: 12, day: 25)
        #expect(events(on: date(1994, 12, 25), myBirthday: birthday, partnerBirthday: birthday) == [.seasonal(.christmas)])
    }
}
