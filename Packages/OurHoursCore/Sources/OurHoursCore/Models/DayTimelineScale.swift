import Foundation

public struct DayTimelineScale: Sendable, Equatable {
    public static let emptyMinHour = 9
    public static let emptyMaxHour = 18
    public static let minimumSpanHours = 2

    public let minHour: Int
    public let maxHour: Int

    public var minMinute: Int { minHour * 60 }
    public var maxMinute: Int { maxHour * 60 }
    public var totalMinutes: Int { max(60, maxMinute - minMinute) }

    public init(minHour: Int, maxHour: Int) {
        let clampedMin = max(0, min(23, minHour))
        let clampedMax = min(24, max(clampedMin + 1, maxHour))
        self.minHour = clampedMin
        self.maxHour = clampedMax
    }

    public static func compute(
        for slices: [DayEncounterSlice],
        dayStart: Date,
        extraMinutes: [Int] = [],
        now: Date = Date()
    ) -> DayTimelineScale {
        var earliestMinute: Int?
        var latestMinute: Int?

        func include(_ startMin: Int, _ endMin: Int) {
            earliestMinute = earliestMinute.map { min($0, startMin) } ?? startMin
            latestMinute = latestMinute.map { max($0, endMin) } ?? endMin
        }

        for slice in slices {
            let sMin = max(0, min(1440, Int(floor(slice.sliceStart.timeIntervalSince(dayStart) / 60.0))))
            let eMin: Int
            switch slice.status {
            case .completed:
                if let end = slice.sliceEnd {
                    eMin = max(sMin, min(1440, Int(ceil(end.timeIntervalSince(dayStart) / 60.0))))
                } else {
                    eMin = min(1440, sMin + 60)
                }
            case .unknownEnd:
                eMin = min(1440, sMin + 60)
            case .active:
                if let end = slice.sliceEnd {
                    eMin = max(sMin, min(1440, Int(ceil(end.timeIntervalSince(dayStart) / 60.0))))
                } else {
                    let liveMin = Int(ceil(now.timeIntervalSince(dayStart) / 60.0))
                    eMin = min(1440, max(sMin + 30, liveMin))
                }
            }
            include(sMin, eMin)
        }

        for extra in extraMinutes {
            let clamped = max(0, min(1440, extra))
            include(clamped, clamped)
        }

        guard let earliest = earliestMinute, let latest = latestMinute else {
            return DayTimelineScale(minHour: emptyMinHour, maxHour: emptyMaxHour)
        }

        var resolvedMinHour = max(0, min(23, earliest / 60))
        var resolvedMaxHour = min(24, max(resolvedMinHour + 1, (latest + 59) / 60))
        while resolvedMaxHour - resolvedMinHour < minimumSpanHours {
            if resolvedMaxHour < 24 {
                resolvedMaxHour += 1
            } else if resolvedMinHour > 0 {
                resolvedMinHour -= 1
            } else {
                break
            }
        }
        return DayTimelineScale(minHour: resolvedMinHour, maxHour: resolvedMaxHour)
    }

    public func ptsPerMinute(viewportHeight: Double, zoomFactor: Double) -> Double {
        guard viewportHeight > 0 else { return 0 }
        return (viewportHeight / Double(totalMinutes)) * max(1.0, zoomFactor)
    }

    public func yPosition(
        forMinute minute: Double,
        viewportHeight: Double,
        zoomFactor: Double,
        focusMinute: Double
    ) -> Double {
        let total = Double(totalMinutes)
        let basePtsPerMin = viewportHeight / total
        if zoomFactor <= 1.0001 {
            return (minute - Double(minMinute)) * basePtsPerMin
        }
        let rawFocusRatio = (focusMinute - Double(minMinute)) / total
        let clampedFocusRatio = max(0.18, min(0.82, rawFocusRatio))
        let focusAnchorY = clampedFocusRatio * viewportHeight
        let zoomedPtsPerMin = basePtsPerMin * zoomFactor
        return focusAnchorY + (minute - focusMinute) * zoomedPtsPerMin
    }
}
