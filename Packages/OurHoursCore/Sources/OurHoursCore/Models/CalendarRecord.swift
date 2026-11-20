import Foundation

public enum EncounterSource: Sendable, Equatable, Hashable {
    case auto(sessionID: UUID)
    case autoEdited(sessionID: UUID)
    case manual(recordID: UUID)
}

public struct ResolvedEncounter: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let source: EncounterSource
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let connectionPath: ConnectionPath?

    public var durationSeconds: TimeInterval? {
        guard status == .completed, let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }
}

public struct DayEncounterSlice: Sendable, Equatable, Identifiable {
    public var id: String { "\(encounterID.uuidString)_\(dayKey)" }
    public let encounterID: UUID
    public let dayKey: String
    public let sliceStart: Date
    public let sliceEnd: Date?
    public let status: SessionStatus
    public let source: EncounterSource
    public let fullStart: Date
    public let fullEnd: Date?

    public var durationSeconds: TimeInterval? {
        guard status == .completed, let sliceEnd else { return nil }
        return max(0, sliceEnd.timeIntervalSince(sliceStart))
    }
}

public enum BubbleIntensity: Int, Sendable, Equatable, Comparable {
    case none = 0, small, medium, large

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DaySummary: Sendable, Equatable, Identifiable {
    public var id: String { dayKey }
    public let dayKey: String
    public let date: Date
    public let slices: [DayEncounterSlice]
    public let totalRecordedSeconds: TimeInterval
    public let hasActiveSession: Bool
    public let hasUnknownEnd: Bool
    public let memo: String?

    public var bubbleIntensity: BubbleIntensity {
        if totalRecordedSeconds == 0 && !hasActiveSession && !hasUnknownEnd { return .none }
        if totalRecordedSeconds <= 7_200 { return .small }
        if totalRecordedSeconds <= 18_000 { return .medium }
        return .large
    }
}

public enum EncounterCalendarAggregator {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func resolveEncounters(
        autoSessions: [EncounterSession], journal: JournalSnapshot
    ) -> [ResolvedEncounter] {
        // Keep manual corrections authoritative when the automatic log is refreshed (SPEC §4.1).
        let automatic: [ResolvedEncounter] = autoSessions.compactMap { session in
            switch journal.sessionOverrides[session.id]?.action {
            case .deleted:
                return nil
            case let .edited(startedAt, endedAt):
                return ResolvedEncounter(
                    id: session.id, source: .autoEdited(sessionID: session.id),
                    startedAt: startedAt, endedAt: endedAt, status: .completed, connectionPath: session.connectionPath
                )
            case nil:
                return ResolvedEncounter(
                    id: session.id, source: .auto(sessionID: session.id), startedAt: session.startedAt,
                    endedAt: session.endedAt, status: session.status, connectionPath: session.connectionPath
                )
            }
        }
        let manual: [ResolvedEncounter] = journal.manualRecords.compactMap { record in
            guard record.endedAt >= record.startedAt else { return nil }
            return ResolvedEncounter(
                id: record.id, source: .manual(recordID: record.id), startedAt: record.startedAt,
                endedAt: record.endedAt, status: .completed, connectionPath: nil
            )
        }
        return (automatic + manual).sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt < $1.startedAt
        }
    }

    public static func daySummaries(
        forMonth monthDate: Date, autoSessions: [EncounterSession], journal: JournalSnapshot,
        calendar: Calendar = .current
    ) -> [String: DaySummary] {
        guard let month = calendar.dateInterval(of: .month, for: monthDate) else { return [:] }
        let encounters = resolveEncounters(autoSessions: autoSessions, journal: journal)
        var slicesByDay: [Date: [DayEncounterSlice]] = [:]
        for encounter in encounters {
            // Start inside the requested month so long encounters only visit days they can contribute to.
            var date = max(encounter.startedAt, month.start)
            while date < month.end, let day = calendar.dateInterval(of: .day, for: date),
                  let slice = makeSlice(encounter, day: day, calendar: calendar) {
                slicesByDay[day.start, default: []].append(slice)
                guard let sliceEnd = slice.sliceEnd, sliceEnd == day.end,
                      let fullEnd = slice.fullEnd, fullEnd > day.end else { break }
                date = day.end
            }
        }

        var summaries: [String: DaySummary] = [:]
        var date = month.start
        while date < month.end, let day = calendar.dateInterval(of: .day, for: date) {
            let key = dayKey(for: day.start, calendar: calendar)
            let slices = slicesByDay[day.start] ?? []
            let memo = journal.dailyMemos[key]?.text
            if !slices.isEmpty || memo != nil {
                summaries[key] = summarize(dayKey: key, date: day.start, slices: slices, memo: memo)
            }
            date = day.end
        }
        return summaries
    }

    public static func daySummary(
        for date: Date, autoSessions: [EncounterSession], journal: JournalSnapshot, calendar: Calendar = .current
    ) -> DaySummary {
        let start = calendar.startOfDay(for: date)
        let key = dayKey(for: start, calendar: calendar)
        let slices: [DayEncounterSlice]
        if let day = calendar.dateInterval(of: .day, for: start) {
            slices = resolveEncounters(autoSessions: autoSessions, journal: journal).compactMap {
                makeSlice($0, day: day, calendar: calendar)
            }
        } else {
            slices = []
        }
        return summarize(dayKey: key, date: start, slices: slices, memo: journal.dailyMemos[key]?.text)
    }

    public static func monthlyRecordedSeconds(
        forMonth monthDate: Date, autoSessions: [EncounterSession], journal: JournalSnapshot,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let summaries = daySummaries(forMonth: monthDate, autoSessions: autoSessions, journal: journal, calendar: calendar)
        return summaries.keys.sorted().reduce(0) { $0 + (summaries[$1]?.totalRecordedSeconds ?? 0) }
    }

    public static func lifetimeRecordedSeconds(
        autoSessions: [EncounterSession], journal: JournalSnapshot, calendar: Calendar = .current
    ) -> TimeInterval {
        // Absolute intervals have the same elapsed duration in every time zone.
        let intervals: [DateInterval] = resolveEncounters(autoSessions: autoSessions, journal: journal).compactMap {
            guard $0.status == .completed, let end = $0.endedAt, end > $0.startedAt else { return nil }
            return DateInterval(start: $0.startedAt, end: end)
        }
        return unionDuration(intervals)
    }

    public static func metDayCount(
        forMonth monthDate: Date, autoSessions: [EncounterSession], journal: JournalSnapshot,
        calendar: Calendar = .current
    ) -> Int {
        daySummaries(forMonth: monthDate, autoSessions: autoSessions, journal: journal, calendar: calendar)
            .values.count { !$0.slices.isEmpty }
    }

    private static func makeSlice(
        _ encounter: ResolvedEncounter, day: DateInterval, calendar: Calendar
    ) -> DayEncounterSlice? {
        guard encounter.startedAt < day.end else { return nil }
        let sliceStart = max(encounter.startedAt, day.start)
        let sliceEnd: Date?
        if encounter.status == .completed, let end = encounter.endedAt, end > encounter.startedAt {
            // A session ending at midnight has no slice on the following day (SPEC §4.4).
            guard end > day.start else { return nil }
            sliceEnd = min(end, day.end)
        } else {
            guard encounter.startedAt >= day.start else { return nil }
            sliceEnd = encounter.status == .completed && encounter.endedAt != nil ? sliceStart : nil
        }
        return DayEncounterSlice(
            encounterID: encounter.id, dayKey: dayKey(for: day.start, calendar: calendar),
            sliceStart: sliceStart, sliceEnd: sliceEnd, status: encounter.status, source: encounter.source,
            fullStart: encounter.startedAt, fullEnd: encounter.endedAt
        )
    }

    private static func summarize(
        dayKey: String, date: Date, slices: [DayEncounterSlice], memo: String?
    ) -> DaySummary {
        // Clipping the start to the day boundary preserves the start ordering from resolution.
        let intervals: [DateInterval] = slices.compactMap {
            guard $0.status == .completed, let end = $0.sliceEnd, end > $0.sliceStart else { return nil }
            return DateInterval(start: $0.sliceStart, end: end)
        }
        return DaySummary(
            dayKey: dayKey, date: date, slices: slices, totalRecordedSeconds: unionDuration(intervals),
            hasActiveSession: slices.contains { $0.status == .active },
            hasUnknownEnd: slices.contains { $0.status == .unknownEnd }, memo: memo
        )
    }

    /// Returns the elapsed seconds covered by intervals ordered by start time (SPEC §4.2).
    private static func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
        guard let first = intervals.first else { return 0 }
        var start = first.start
        var end = first.end
        var total: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.start > end {
                total += end.timeIntervalSince(start)
                start = interval.start
                end = interval.end
            } else {
                end = max(end, interval.end)
            }
        }
        return total + end.timeIntervalSince(start)
    }
}
