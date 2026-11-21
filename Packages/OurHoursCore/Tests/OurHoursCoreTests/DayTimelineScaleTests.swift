import Foundation
import Testing
@testable import OurHoursCore

struct DayTimelineScaleTests {
    private let tokyo: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }()

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func makeSlice(start: Date, end: Date?, status: SessionStatus = .completed) -> DayEncounterSlice {
        let id = UUID()
        return DayEncounterSlice(
            encounterID: id,
            dayKey: "2026-11-21",
            sliceStart: start,
            sliceEnd: end,
            status: status,
            source: .auto(sessionID: id),
            fullStart: start,
            fullEnd: end
        )
    }

    @Test func computesDynamicBoundsWithoutFixed6To21() throws {
        let dayStart = try date("2026-11-21T00:00:00+09:00")
        let empty = DayTimelineScale.compute(for: [], dayStart: dayStart)
        #expect(empty == DayTimelineScale(minHour: 9, maxHour: 18))

        let early = makeSlice(
            start: try date("2026-11-21T02:30:00+09:00"),
            end: try date("2026-11-21T05:15:00+09:00")
        )
        #expect(DayTimelineScale.compute(for: [early], dayStart: dayStart) == DayTimelineScale(minHour: 2, maxHour: 6))

        let shortAfternoon = makeSlice(
            start: try date("2026-11-21T13:15:00+09:00"),
            end: try date("2026-11-21T13:45:00+09:00")
        )
        #expect(DayTimelineScale.compute(for: [shortAfternoon], dayStart: dayStart) == DayTimelineScale(minHour: 13, maxHour: 15))

        let shortLateNight = makeSlice(
            start: try date("2026-11-21T23:15:00+09:00"),
            end: try date("2026-11-21T23:45:00+09:00")
        )
        #expect(DayTimelineScale.compute(for: [shortLateNight], dayStart: dayStart) == DayTimelineScale(minHour: 22, maxHour: 24))

        let morningAndEarlyAfternoon = [
            makeSlice(
                start: try date("2026-11-21T00:54:00+09:00"),
                end: try date("2026-11-21T02:30:00+09:00")
            ),
            makeSlice(
                start: try date("2026-11-21T10:14:00+09:00"),
                end: try date("2026-11-21T13:42:00+09:00")
            )
        ]
        #expect(DayTimelineScale.compute(for: morningAndEarlyAfternoon, dayStart: dayStart) == DayTimelineScale(minHour: 0, maxHour: 14))

        let midnightEnd = makeSlice(
            start: try date("2026-11-21T22:00:00+09:00"),
            end: try date("2026-11-22T00:00:00+09:00")
        )
        let extra = DayTimelineScale.compute(
            for: [midnightEnd],
            dayStart: dayStart,
            extraMinutes: [45] // 00:45 from active drag
        )
        #expect(extra == DayTimelineScale(minHour: 0, maxHour: 24))
    }

    @Test func yPositionProjectsProportionallyUnzoomedAndZoomed() {
        let scale = DayTimelineScale(minHour: 6, maxHour: 21) // 900 min
        let h = 360.0 // 0.4 pt/min unzoomed

        #expect(scale.yPosition(forMinute: 360, viewportHeight: h, zoomFactor: 1.0, focusMinute: 600) == 0.0)
        #expect(scale.yPosition(forMinute: 420, viewportHeight: h, zoomFactor: 1.0, focusMinute: 600) == 24.0)
        #expect(scale.yPosition(forMinute: 1260, viewportHeight: h, zoomFactor: 1.0, focusMinute: 600) == 360.0)

        // At 4.0x zoom focused on 7:00 (420), spacing multiplies 4x and remains monotonic
        let y700 = scale.yPosition(forMinute: 420, viewportHeight: h, zoomFactor: 4.0, focusMinute: 420)
        let y730 = scale.yPosition(forMinute: 450, viewportHeight: h, zoomFactor: 4.0, focusMinute: 420)
        let y630 = scale.yPosition(forMinute: 390, viewportHeight: h, zoomFactor: 4.0, focusMinute: 420)
        #expect(abs((y730 - y700) - 48.0) < 0.001)
        #expect(abs((y700 - y630) - 48.0) < 0.001)
        #expect(y630 > 0) // Focus clamp keeps nearby bounds comfortably on screen
    }
}
