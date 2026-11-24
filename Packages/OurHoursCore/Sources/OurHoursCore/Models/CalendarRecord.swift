import Foundation

public enum EncounterSource: Sendable, Equatable, Hashable {
    case auto(sessionID: UUID)
    case peerAuto(sessionID: UUID)
    case peerCompleted(sessionID: UUID)
    case autoEdited(sessionID: UUID)
    case locationMatched(sessionID: UUID)
    case manual(recordID: UUID)
}

public struct ResolvedEncounter: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let source: EncounterSource
    public let linkedSessionIDs: [UUID]
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let connectionPath: ConnectionPath?

    public init(
        id: UUID,
        source: EncounterSource,
        linkedSessionIDs: [UUID]? = nil,
        startedAt: Date,
        endedAt: Date?,
        status: SessionStatus,
        connectionPath: ConnectionPath?
    ) {
        self.id = id
        self.source = source
        if let linkedSessionIDs {
            self.linkedSessionIDs = linkedSessionIDs
        } else if case .manual = source {
            self.linkedSessionIDs = []
        } else {
            self.linkedSessionIDs = [id]
        }
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.connectionPath = connectionPath
    }

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

    public var continuesFromPreviousDay: Bool {
        fullStart < sliceStart
    }

    public var continuesToNextDay: Bool {
        guard let sliceEnd else { return false }
        if let fullEnd { return fullEnd > sliceEnd }
        return status == .active
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

    public var continuesFromPreviousDay: Bool {
        slices.contains(where: \.continuesFromPreviousDay)
    }

    public var continuesToNextDay: Bool {
        slices.contains(where: \.continuesToNextDay)
    }
}

public enum EncounterCalendarAggregator {
    public static let bleShortGapMergeSeconds: TimeInterval = 600

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private typealias PairedEncounter = (encounter: ResolvedEncounter, pairID: UUID)

    public static func resolveEncounters(
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot
    ) -> [ResolvedEncounter] {
        // Keep manual corrections authoritative when automatic logs refresh (SPEC §4.1).
        let activeAutomatic: [PairedEncounter] = autoSessions.compactMap { session in
            guard session.status == .active else { return nil }
            let encounter: ResolvedEncounter
            switch journal.sessionOverrides[session.id]?.action {
            case .deleted:
                return nil
            case let .edited(startedAt, endedAt):
                encounter = ResolvedEncounter(
                    id: session.id, source: .autoEdited(sessionID: session.id), linkedSessionIDs: [session.id],
                    startedAt: startedAt, endedAt: endedAt, status: .completed, connectionPath: session.connectionPath
                )
            case let .adjustedStart(startedAt):
                encounter = ResolvedEncounter(
                    id: session.id, source: .autoEdited(sessionID: session.id), linkedSessionIDs: [session.id],
                    startedAt: startedAt, endedAt: nil, status: .active, connectionPath: session.connectionPath
                )
            case nil:
                encounter = ResolvedEncounter(
                    id: session.id, source: .auto(sessionID: session.id), linkedSessionIDs: [session.id],
                    startedAt: session.startedAt, endedAt: session.endedAt, status: session.status,
                    connectionPath: session.connectionPath
                )
            }
            return (encounter, session.pairID)
        }

        let mergedNonActive = resolveCrossDeviceNonActiveBLE(
            localSessions: autoSessions.filter { $0.status != .active },
            peerSessions: peerSessions.filter { $0.status != .active },
            allLocalIDs: Set(autoSessions.map(\.id)),
            overrides: journal.sessionOverrides
        )

        var automaticEntries = activeAutomatic + coalesceShortGapBLE(mergedNonActive)
        let completedBleIntervals = mergedDateIntervals(automaticEntries.compactMap { entry in
            let encounter = entry.encounter
            guard encounter.status == .completed, let end = encounter.endedAt, end > encounter.startedAt else { return nil }
            return DateInterval(start: encounter.startedAt, end: end)
        })

        var locationEntries: [PairedEncounter] = []
        var suppressedUneditedLocations: [LocationMatchedSession] = []
        for loc in locationSessions {
            switch journal.sessionOverrides[loc.id]?.action {
            case .deleted:
                continue
            case let .edited(startedAt, endedAt):
                locationEntries.append((
                    ResolvedEncounter(
                        id: loc.id, source: .autoEdited(sessionID: loc.id), linkedSessionIDs: [loc.id],
                        startedAt: startedAt, endedAt: endedAt, status: .completed, connectionPath: nil
                    ),
                    loc.pairID
                ))
            case let .adjustedStart(startedAt):
                let validEnd = loc.endedAt > startedAt ? loc.endedAt : nil
                locationEntries.append((
                    ResolvedEncounter(
                        id: loc.id, source: .autoEdited(sessionID: loc.id), linkedSessionIDs: [loc.id],
                        startedAt: startedAt, endedAt: validEnd,
                        status: validEnd == nil ? .unknownEnd : .completed, connectionPath: nil
                    ),
                    loc.pairID
                ))
            case nil:
                guard loc.endedAt > loc.startedAt else { continue }
                let locInterval = DateInterval(start: loc.startedAt, end: loc.endedAt)
                let covered = coveredDuration(of: locInterval, by: completedBleIntervals)
                if locInterval.duration > 0, (covered / locInterval.duration) >= 0.95 {
                    suppressedUneditedLocations.append(loc)
                    continue
                }
                locationEntries.append((
                    ResolvedEncounter(
                        id: loc.id, source: .locationMatched(sessionID: loc.id), linkedSessionIDs: [loc.id],
                        startedAt: loc.startedAt, endedAt: loc.endedAt, status: .completed, connectionPath: nil
                    ),
                    loc.pairID
                ))
            }
        }

        let manualEntries: [(encounter: ResolvedEncounter, pairID: UUID?)] = journal.manualRecords.compactMap { record in
            guard record.endedAt >= record.startedAt else { return nil }
            return (
                ResolvedEncounter(
                    id: record.id, source: .manual(recordID: record.id), linkedSessionIDs: [],
                    startedAt: record.startedAt, endedAt: record.endedAt, status: .completed, connectionPath: nil
                ),
                record.pairID
            )
        }

        absorbCoveredUnknownEnd(
            automaticEntries: &automaticEntries,
            locationEntries: &locationEntries,
            suppressedUneditedLocations: suppressedUneditedLocations,
            manualEntries: manualEntries
        )

        return (automaticEntries.map(\.encounter) + locationEntries.map(\.encounter) + manualEntries.map(\.encounter)).sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt < $1.startedAt
        }
    }

    public static func daySummaries(
        forMonth monthDate: Date,
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current,
        activeReferenceDate: Date? = nil
    ) -> [String: DaySummary] {
        guard let month = calendar.dateInterval(of: .month, for: monthDate) else { return [:] }
        let encounters = resolveEncounters(
            autoSessions: autoSessions,
            peerSessions: peerSessions,
            locationSessions: locationSessions,
            journal: journal
        )
        var slicesByDay: [Date: [DayEncounterSlice]] = [:]
        for encounter in encounters {
            // Start inside the requested month so long encounters only visit days they can contribute to.
            var date = max(encounter.startedAt, month.start)
            while date < month.end, let day = calendar.dateInterval(of: .day, for: date),
                  let slice = makeSlice(encounter, day: day, calendar: calendar, activeReferenceDate: activeReferenceDate) {
                slicesByDay[day.start, default: []].append(slice)
                guard slice.continuesToNextDay else { break }
                date = day.end
            }
        }

        var summaries: [String: DaySummary] = [:]
        var date = month.start
        while date < month.end, let day = calendar.dateInterval(of: .day, for: date) {
            let key = dayKey(for: day.start, calendar: calendar)
            let slices = slicesByDay[day.start] ?? []
            let memo = journal.anyMemoText(forDayKey: key)
            if !slices.isEmpty || memo != nil {
                summaries[key] = summarize(dayKey: key, date: day.start, slices: slices, memo: memo)
            }
            date = day.end
        }
        return summaries
    }

    public static func daySummary(
        for date: Date,
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current,
        activeReferenceDate: Date? = nil
    ) -> DaySummary {
        let start = calendar.startOfDay(for: date)
        let key = dayKey(for: start, calendar: calendar)
        let slices: [DayEncounterSlice]
        if let day = calendar.dateInterval(of: .day, for: start) {
            slices = resolveEncounters(
                autoSessions: autoSessions,
                peerSessions: peerSessions,
                locationSessions: locationSessions,
                journal: journal
            ).compactMap {
                makeSlice($0, day: day, calendar: calendar, activeReferenceDate: activeReferenceDate)
            }
        } else {
            slices = []
        }
        return summarize(dayKey: key, date: start, slices: slices, memo: journal.anyMemoText(forDayKey: key))
    }

    public static func monthlyRecordedSeconds(
        forMonth monthDate: Date,
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current,
        activeReferenceDate: Date? = nil
    ) -> TimeInterval {
        let summaries = daySummaries(
            forMonth: monthDate,
            autoSessions: autoSessions,
            peerSessions: peerSessions,
            locationSessions: locationSessions,
            journal: journal,
            calendar: calendar,
            activeReferenceDate: activeReferenceDate
        )
        return summaries.keys.sorted().reduce(0) { $0 + (summaries[$1]?.totalRecordedSeconds ?? 0) }
    }

    public static func lifetimeRecordedSeconds(
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current
    ) -> TimeInterval {
        // Absolute intervals have the same elapsed duration in every time zone.
        let intervals: [DateInterval] = resolveEncounters(
            autoSessions: autoSessions,
            peerSessions: peerSessions,
            locationSessions: locationSessions,
            journal: journal
        ).compactMap {
            guard $0.status == .completed, let end = $0.endedAt, end > $0.startedAt else { return nil }
            return DateInterval(start: $0.startedAt, end: end)
        }
        return unionDuration(intervals)
    }

    public static func metDayCount(
        forMonth monthDate: Date,
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current,
        activeReferenceDate: Date? = nil
    ) -> Int {
        daySummaries(
            forMonth: monthDate,
            autoSessions: autoSessions,
            peerSessions: peerSessions,
            locationSessions: locationSessions,
            journal: journal,
            calendar: calendar,
            activeReferenceDate: activeReferenceDate
        )
            .values.count { !$0.slices.isEmpty }
    }

    public static func lifetimeMetDayCount(
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot,
        calendar: Calendar = .current,
        activeReferenceDate: Date? = nil
    ) -> Int {
        let encounters = resolveEncounters(
            autoSessions: autoSessions,
            peerSessions: peerSessions,
            locationSessions: locationSessions,
            journal: journal
        )
        var dayKeys = Set<String>()
        for encounter in encounters {
            var cursor = encounter.startedAt
            while let day = calendar.dateInterval(of: .day, for: cursor),
                  let slice = makeSlice(encounter, day: day, calendar: calendar, activeReferenceDate: activeReferenceDate) {
                dayKeys.insert(slice.dayKey)
                guard slice.continuesToNextDay else { break }
                cursor = day.end
            }
        }
        return dayKeys.count
    }

    public static func coalescedActiveSessionStart(
        autoSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession] = [],
        locationSessions: [LocationMatchedSession] = [],
        journal: JournalSnapshot
    ) -> Date? {
        let candidates: [(session: EncounterSession, start: Date, adjusted: Bool)] = autoSessions.compactMap { session in
            guard session.status == .active else { return nil }
            switch journal.sessionOverrides[session.id]?.action {
            case nil: return (session, session.startedAt, false)
            case let .adjustedStart(start): return (session, start, true)
            case .deleted, .edited: return nil
            }
        }
        guard let chosen = candidates.min(by: {
            ($0.start, $0.session.id.uuidString) < ($1.start, $1.session.id.uuidString)
        }) else { return nil }
        if chosen.adjusted { return chosen.start }

        let pairID = chosen.session.pairID
        let resolvedForPair = resolveEncounters(
            autoSessions: autoSessions.filter { $0.pairID == pairID },
            peerSessions: peerSessions.filter { $0.pairID == pairID },
            locationSessions: locationSessions.filter { $0.pairID == pairID },
            journal: journal
        )
        let completedForPair: [(start: Date, end: Date)] = resolvedForPair.compactMap { encounter in
            guard encounter.status == .completed,
                  let end = encounter.endedAt,
                  end > encounter.startedAt else {
                return nil
            }
            return (encounter.startedAt, end)
        }

        var effectiveStart = chosen.start
        var extended = true
        while extended {
            extended = false
            let threshold = effectiveStart.addingTimeInterval(-bleShortGapMergeSeconds)
            for item in completedForPair where item.end >= threshold && item.start < effectiveStart {
                effectiveStart = item.start
                extended = true
            }
        }
        return effectiveStart
    }

    private struct BLENode {
        let id: UUID
        let pairID: UUID
        let isLocal: Bool
        let startedAt: Date
        let endedAt: Date?
        let status: SessionStatus
        let connectionPath: ConnectionPath?
    }

    private static func resolveCrossDeviceNonActiveBLE(
        localSessions: [EncounterSession],
        peerSessions: [SyncedPeerSession],
        allLocalIDs: Set<UUID>,
        overrides: [UUID: SessionOverride]
    ) -> [(encounter: ResolvedEncounter, pairID: UUID)] {
        var seenLocal = Set<UUID>()
        var localNodes: [BLENode] = []
        for s in localSessions where seenLocal.insert(s.id).inserted {
            localNodes.append(BLENode(
                id: s.id, pairID: s.pairID, isLocal: true, startedAt: s.startedAt, endedAt: s.endedAt,
                status: s.status, connectionPath: s.connectionPath
            ))
        }

        var seenPeer = Set<UUID>()
        var peerNodes: [BLENode] = []
        for s in peerSessions where !allLocalIDs.contains(s.id) && seenPeer.insert(s.id).inserted {
            peerNodes.append(BLENode(
                id: s.id, pairID: s.pairID, isLocal: false, startedAt: s.startedAt, endedAt: s.endedAt,
                status: s.status, connectionPath: s.connectionPath
            ))
        }

        var localAdj = Array(repeating: [Int](), count: localNodes.count)
        var peerAdj = Array(repeating: [Int](), count: peerNodes.count)
        for li in localNodes.indices {
            for pi in peerNodes.indices where shouldLink(localNodes[li], peerNodes[pi]) {
                localAdj[li].append(pi)
                peerAdj[pi].append(li)
            }
        }

        var visitedLocal = Array(repeating: false, count: localNodes.count)
        var visitedPeer = Array(repeating: false, count: peerNodes.count)
        var resolved: [(encounter: ResolvedEncounter, pairID: UUID)] = []

        func bfs(startLocal: Int?, startPeer: Int?) -> [BLENode] {
            var queue: [(isLocal: Bool, index: Int)] = []
            var head = 0
            if let li = startLocal {
                visitedLocal[li] = true
                queue.append((true, li))
            }
            if let pi = startPeer {
                visitedPeer[pi] = true
                queue.append((false, pi))
            }
            var component: [BLENode] = []
            while head < queue.count {
                let item = queue[head]
                head += 1
                if item.isLocal {
                    component.append(localNodes[item.index])
                    for pi in localAdj[item.index] where !visitedPeer[pi] {
                        visitedPeer[pi] = true
                        queue.append((false, pi))
                    }
                } else {
                    component.append(peerNodes[item.index])
                    for li in peerAdj[item.index] where !visitedLocal[li] {
                        visitedLocal[li] = true
                        queue.append((true, li))
                    }
                }
            }
            return component
        }

        for li in localNodes.indices where !visitedLocal[li] {
            if let encounter = resolveComponent(bfs(startLocal: li, startPeer: nil), overrides: overrides) {
                resolved.append(encounter)
            }
        }
        for pi in peerNodes.indices where !visitedPeer[pi] {
            if let encounter = resolveComponent(bfs(startLocal: nil, startPeer: pi), overrides: overrides) {
                resolved.append(encounter)
            }
        }
        return resolved
    }

    private static func shouldLink(_ a: BLENode, _ b: BLENode) -> Bool {
        guard a.pairID == b.pairID else { return false }
        if a.status == .completed, b.status == .completed, let ae = a.endedAt, let be = b.endedAt {
            if ae > a.startedAt, be > b.startedAt, min(ae, be) > max(a.startedAt, b.startedAt) {
                return true
            }
            return abs(a.startedAt.timeIntervalSince(b.startedAt)) <= 60
                && abs(ae.timeIntervalSince(be)) <= 60
        }
        if a.status == .completed, let ae = a.endedAt, ae > a.startedAt, b.status == .unknownEnd {
            return b.startedAt >= a.startedAt.addingTimeInterval(-600) && b.startedAt < ae
        }
        if b.status == .completed, let be = b.endedAt, be > b.startedAt, a.status == .unknownEnd {
            return a.startedAt >= b.startedAt.addingTimeInterval(-600) && a.startedAt < be
        }
        if a.status == .unknownEnd, b.status == .unknownEnd {
            return abs(a.startedAt.timeIntervalSince(b.startedAt)) <= 600
        }
        return false
    }

    private static func resolveComponent(
        _ group: [BLENode],
        overrides: [UUID: SessionOverride]
    ) -> (encounter: ResolvedEncounter, pairID: UUID)? {
        guard let firstNode = group.first else { return nil }
        let pairID = firstNode.pairID
        let allIDs = group.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let primaryID = allIDs[0]
        let localNodes = group.filter(\.isLocal).sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt < $1.startedAt
        }
        let localPath = localNodes.first?.connectionPath

        let groupOverrides = allIDs.compactMap { overrides[$0] }
        if let maxUpdated = groupOverrides.map(\.updatedAt).max() {
            let newest = groupOverrides.filter { abs($0.updatedAt.timeIntervalSince(maxUpdated)) < 0.0005 }
            let edits: [(UUID, Date, Date)] = newest.compactMap { ov in
                guard case let .edited(s, e) = ov.action else { return nil }
                return (ov.sessionID, s, e)
            }.sorted { $0.0.uuidString < $1.0.uuidString }
            if let chosen = edits.first {
                let enc = ResolvedEncounter(
                    id: primaryID,
                    source: .autoEdited(sessionID: primaryID),
                    linkedSessionIDs: allIDs,
                    startedAt: chosen.1,
                    endedAt: chosen.2,
                    status: .completed,
                    connectionPath: localPath
                )
                return (enc, pairID)
            }
            let hasNewestAdjustedStart = newest.contains {
                if case .adjustedStart = $0.action { return true }
                return false
            }
            if hasNewestAdjustedStart {
                let adjusted: [(start: Date, id: String)] = groupOverrides.compactMap { override in
                    guard case let .adjustedStart(start) = override.action else { return nil }
                    return (start, override.sessionID.uuidString)
                }
                if let chosen = adjusted.min(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
                    let end = group
                        .filter { $0.status == .completed }
                        .compactMap(\.endedAt)
                        .filter { $0 > chosen.start }
                        .max()
                    let encounter = ResolvedEncounter(
                        id: primaryID, source: .autoEdited(sessionID: primaryID), linkedSessionIDs: allIDs,
                        startedAt: chosen.start, endedAt: end,
                        status: end == nil ? .unknownEnd : .completed, connectionPath: localPath
                    )
                    return (encounter, pairID)
                }
            }
            return nil
        }

        let completed = group.filter { $0.status == .completed && $0.endedAt != nil }
        let startedAt = group.map(\.startedAt).min() ?? Date()
        if !completed.isEmpty {
            let endedAt = max(startedAt, completed.compactMap(\.endedAt).max() ?? startedAt)
            let hasCompletedLocal = localNodes.contains { $0.status == .completed && $0.endedAt != nil }
            let source: EncounterSource
            if localNodes.isEmpty {
                source = .peerAuto(sessionID: primaryID)
            } else if !hasCompletedLocal {
                source = .peerCompleted(sessionID: primaryID)
            } else {
                source = .auto(sessionID: primaryID)
            }
            let enc = ResolvedEncounter(
                id: primaryID,
                source: source,
                linkedSessionIDs: allIDs,
                startedAt: startedAt,
                endedAt: endedAt,
                status: .completed,
                connectionPath: localPath
            )
            return (enc, pairID)
        }

        let source: EncounterSource = localNodes.isEmpty ? .peerAuto(sessionID: primaryID) : .auto(sessionID: primaryID)
        let enc = ResolvedEncounter(
            id: primaryID,
            source: source,
            linkedSessionIDs: allIDs,
            startedAt: startedAt,
            endedAt: nil,
            status: .unknownEnd,
            connectionPath: localPath
        )
        return (enc, pairID)
    }

    private static func coalesceShortGapBLE(
        _ entries: [PairedEncounter]
    ) -> [PairedEncounter] {
        var edited: [PairedEncounter] = []
        var completedByPair: [UUID: [ResolvedEncounter]] = [:]
        var unknownByPair: [UUID: [ResolvedEncounter]] = [:]

        for entry in entries {
            let enc = entry.encounter
            if case .autoEdited = enc.source {
                edited.append(entry)
                continue
            }
            if enc.status == .completed, enc.endedAt != nil {
                completedByPair[entry.pairID, default: []].append(enc)
            } else if enc.status == .unknownEnd {
                unknownByPair[entry.pairID, default: []].append(enc)
            }
        }

        let allPairIDs = Set(completedByPair.keys)
            .union(unknownByPair.keys)
            .sorted { $0.uuidString < $1.uuidString }

        var output: [PairedEncounter] = edited

        func isLocalAuto(_ source: EncounterSource) -> Bool {
            if case .auto = source { return true }
            return false
        }

        for pairID in allPairIDs {
            let sortedCompleted = (completedByPair[pairID] ?? []).sorted {
                if $0.startedAt == $1.startedAt {
                    let e0 = $0.endedAt ?? $0.startedAt
                    let e1 = $1.endedAt ?? $1.startedAt
                    if e0 == e1 { return $0.id.uuidString < $1.id.uuidString }
                    return e0 < e1
                }
                return $0.startedAt < $1.startedAt
            }

            var mergedCompleted: [ResolvedEncounter] = []
            for next in sortedCompleted {
                guard let nextEnd = next.endedAt else { continue }
                if let last = mergedCompleted.last,
                   let lastEnd = last.endedAt,
                   next.startedAt.timeIntervalSince(lastEnd) <= bleShortGapMergeSeconds {
                    let mergedStart = min(last.startedAt, next.startedAt)
                    let mergedEnd = max(lastEnd, nextEnd)
                    let linkedIDs = Array(Set(last.linkedSessionIDs + next.linkedSessionIDs))
                        .sorted { $0.uuidString < $1.uuidString }
                    let primaryID = linkedIDs.first ?? last.id
                    let mergedSource: EncounterSource
                    switch (last.source, next.source) {
                    case (.auto, _), (_, .auto):
                        mergedSource = .auto(sessionID: primaryID)
                    case (.peerCompleted, _), (_, .peerCompleted):
                        mergedSource = .peerCompleted(sessionID: primaryID)
                    default:
                        mergedSource = .peerAuto(sessionID: primaryID)
                    }
                    mergedCompleted[mergedCompleted.count - 1] = ResolvedEncounter(
                        id: primaryID,
                        source: mergedSource,
                        linkedSessionIDs: linkedIDs,
                        startedAt: mergedStart,
                        endedAt: mergedEnd,
                        status: .completed,
                        connectionPath: last.connectionPath ?? next.connectionPath
                    )
                } else {
                    mergedCompleted.append(next)
                }
            }

            var remainingUnknown: [ResolvedEncounter] = []
            for unknown in unknownByPair[pairID] ?? [] {
                if let idx = mergedCompleted.firstIndex(where: { completed in
                    guard let cEnd = completed.endedAt else { return false }
                    return unknown.startedAt >= completed.startedAt.addingTimeInterval(-bleShortGapMergeSeconds)
                        && unknown.startedAt < cEnd
                }) {
                    let existing = mergedCompleted[idx]
                    let linkedIDs = Array(Set(existing.linkedSessionIDs + unknown.linkedSessionIDs))
                        .sorted { $0.uuidString < $1.uuidString }
                    let primaryID = linkedIDs.first ?? existing.id
                    let hasLocal = isLocalAuto(existing.source) || isLocalAuto(unknown.source)
                    let mergedSource: EncounterSource = hasLocal
                        ? .auto(sessionID: primaryID)
                        : .peerCompleted(sessionID: primaryID)
                    mergedCompleted[idx] = ResolvedEncounter(
                        id: primaryID,
                        source: mergedSource,
                        linkedSessionIDs: linkedIDs,
                        startedAt: min(existing.startedAt, unknown.startedAt),
                        endedAt: existing.endedAt,
                        status: .completed,
                        connectionPath: existing.connectionPath ?? unknown.connectionPath
                    )
                } else {
                    remainingUnknown.append(unknown)
                }
            }

            let sortedUnknown = remainingUnknown.sorted {
                if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.startedAt < $1.startedAt
            }
            var mergedUnknown: [ResolvedEncounter] = []
            for next in sortedUnknown {
                if let last = mergedUnknown.last,
                   next.startedAt.timeIntervalSince(last.startedAt) <= bleShortGapMergeSeconds {
                    let linkedIDs = Array(Set(last.linkedSessionIDs + next.linkedSessionIDs))
                        .sorted { $0.uuidString < $1.uuidString }
                    let primaryID = linkedIDs.first ?? last.id
                    let hasLocal = isLocalAuto(last.source) || isLocalAuto(next.source)
                    mergedUnknown[mergedUnknown.count - 1] = ResolvedEncounter(
                        id: primaryID,
                        source: hasLocal ? .auto(sessionID: primaryID) : .peerAuto(sessionID: primaryID),
                        linkedSessionIDs: linkedIDs,
                        startedAt: min(last.startedAt, next.startedAt),
                        endedAt: nil,
                        status: .unknownEnd,
                        connectionPath: last.connectionPath ?? next.connectionPath
                    )
                } else {
                    mergedUnknown.append(next)
                }
            }

            output.append(contentsOf: mergedCompleted.map { ($0, pairID) })
            output.append(contentsOf: mergedUnknown.map { ($0, pairID) })
        }

        return output
    }

    private static func isUneditedUnknownEnd(_ encounter: ResolvedEncounter) -> Bool {
        guard encounter.status == .unknownEnd else { return false }
        switch encounter.source {
        case .auto, .peerAuto:
            return true
        case .peerCompleted, .autoEdited, .locationMatched, .manual:
            return false
        }
    }

    private static func isLocalAutoSource(_ source: EncounterSource) -> Bool {
        if case .auto = source { return true }
        return false
    }

    private static func absorbCoveredUnknownEnd(
        automaticEntries: inout [PairedEncounter],
        locationEntries: inout [PairedEncounter],
        suppressedUneditedLocations: [LocationMatchedSession],
        manualEntries: [(encounter: ResolvedEncounter, pairID: UUID?)]
    ) {
        var keptAutomatic: [PairedEncounter] = []
        var pendingUnknown: [PairedEncounter] = []

        for entry in automaticEntries {
            if isUneditedUnknownEnd(entry.encounter) {
                pendingUnknown.append(entry)
            } else {
                keptAutomatic.append(entry)
            }
        }
        guard !pendingUnknown.isEmpty else { return }

        pendingUnknown.sort {
            if $0.encounter.startedAt == $1.encounter.startedAt {
                return $0.encounter.id.uuidString < $1.encounter.id.uuidString
            }
            return $0.encounter.startedAt < $1.encounter.startedAt
        }

        func mergeIDs(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
            Array(Set(lhs + rhs)).sorted { $0.uuidString < $1.uuidString }
        }

        for unknownEntry in pendingUnknown {
            let unknown = unknownEntry.encounter
            let pairID = unknownEntry.pairID

            // 1. Authoritative .autoEdited completed encounters (BLE or location) keep bounds and absorb IDs.
            if let idx = keptAutomatic.firstIndex(where: { entry in
                guard entry.pairID == pairID,
                      case .autoEdited = entry.encounter.source,
                      entry.encounter.status == .completed,
                      let end = entry.encounter.endedAt,
                      end > entry.encounter.startedAt else { return false }
                return unknown.startedAt >= entry.encounter.startedAt && unknown.startedAt < end
            }) {
                let existing = keptAutomatic[idx].encounter
                keptAutomatic[idx].encounter = ResolvedEncounter(
                    id: existing.id,
                    source: existing.source,
                    linkedSessionIDs: mergeIDs(existing.linkedSessionIDs, unknown.linkedSessionIDs),
                    startedAt: existing.startedAt,
                    endedAt: existing.endedAt,
                    status: existing.status,
                    connectionPath: existing.connectionPath
                )
                continue
            }

            if let idx = locationEntries.firstIndex(where: { entry in
                guard entry.pairID == pairID,
                      case .autoEdited = entry.encounter.source,
                      entry.encounter.status == .completed,
                      let end = entry.encounter.endedAt,
                      end > entry.encounter.startedAt else { return false }
                return unknown.startedAt >= entry.encounter.startedAt && unknown.startedAt < end
            }) {
                let existing = locationEntries[idx].encounter
                locationEntries[idx].encounter = ResolvedEncounter(
                    id: existing.id,
                    source: existing.source,
                    linkedSessionIDs: mergeIDs(existing.linkedSessionIDs, unknown.linkedSessionIDs),
                    startedAt: existing.startedAt,
                    endedAt: existing.endedAt,
                    status: existing.status,
                    connectionPath: existing.connectionPath
                )
                continue
            }

            // 2. Completed manual records suppress trailing unedited unknownEnd strictly inside their range.
            if manualEntries.contains(where: { entry in
                guard entry.pairID == nil || entry.pairID == pairID,
                      entry.encounter.status == .completed,
                      let end = entry.encounter.endedAt,
                      end > entry.encounter.startedAt else { return false }
                return unknown.startedAt >= entry.encounter.startedAt && unknown.startedAt < end
            }) {
                continue
            }

            // 3. Emitted unedited locationMatched covering (or <= 10m after) unknownStart absorbs it.
            if let idx = locationEntries.firstIndex(where: { entry in
                guard entry.pairID == pairID,
                      case .locationMatched = entry.encounter.source,
                      entry.encounter.status == .completed,
                      let end = entry.encounter.endedAt,
                      end > entry.encounter.startedAt else { return false }
                return unknown.startedAt >= entry.encounter.startedAt.addingTimeInterval(-bleShortGapMergeSeconds)
                    && unknown.startedAt < end
            }) {
                let loc = locationEntries[idx].encounter
                locationEntries[idx].encounter = ResolvedEncounter(
                    id: loc.id,
                    source: loc.source,
                    linkedSessionIDs: mergeIDs(loc.linkedSessionIDs, unknown.linkedSessionIDs),
                    startedAt: min(loc.startedAt, unknown.startedAt),
                    endedAt: loc.endedAt,
                    status: .completed,
                    connectionPath: loc.connectionPath
                )
                continue
            }

            // 4. Suppressed unedited LocationMatchedSession (>=95% covered by BLE) resolves trailing unknownEnd.
            if let suppressedLoc = suppressedUneditedLocations.first(where: { loc in
                loc.pairID == pairID
                    && unknown.startedAt >= loc.startedAt.addingTimeInterval(-bleShortGapMergeSeconds)
                    && unknown.startedAt < loc.endedAt
            }) {
                if let idx = keptAutomatic.firstIndex(where: { entry in
                    guard entry.pairID == pairID,
                          entry.encounter.status == .completed,
                          let cEnd = entry.encounter.endedAt,
                          cEnd > entry.encounter.startedAt else { return false }
                    if case .autoEdited = entry.encounter.source { return false }
                    return unknown.startedAt <= cEnd.addingTimeInterval(bleShortGapMergeSeconds)
                        && suppressedLoc.endedAt >= entry.encounter.startedAt.addingTimeInterval(-bleShortGapMergeSeconds)
                }) {
                    let completed = keptAutomatic[idx].encounter
                    let completedEnd = completed.endedAt ?? completed.startedAt
                    let mergedStart = min(completed.startedAt, unknown.startedAt)
                    let mergedEnd = max(completedEnd, suppressedLoc.endedAt)
                    let linkedIDs = mergeIDs(completed.linkedSessionIDs, unknown.linkedSessionIDs)
                    let primaryID = linkedIDs.first ?? completed.id
                    let mergedSource: EncounterSource =
                        (isLocalAutoSource(completed.source) || isLocalAutoSource(unknown.source))
                        ? .auto(sessionID: primaryID)
                        : .peerCompleted(sessionID: primaryID)
                    keptAutomatic[idx].encounter = ResolvedEncounter(
                        id: primaryID,
                        source: mergedSource,
                        linkedSessionIDs: linkedIDs,
                        startedAt: mergedStart,
                        endedAt: mergedEnd,
                        status: .completed,
                        connectionPath: completed.connectionPath ?? unknown.connectionPath
                    )
                } else {
                    let primaryID = unknown.linkedSessionIDs.first ?? unknown.id
                    let resolvedSource: EncounterSource = isLocalAutoSource(unknown.source)
                        ? .auto(sessionID: primaryID)
                        : .peerCompleted(sessionID: primaryID)
                    keptAutomatic.append((
                        ResolvedEncounter(
                            id: primaryID,
                            source: resolvedSource,
                            linkedSessionIDs: unknown.linkedSessionIDs,
                            startedAt: unknown.startedAt,
                            endedAt: suppressedLoc.endedAt,
                            status: .completed,
                            connectionPath: unknown.connectionPath
                        ),
                        pairID
                    ))
                }
                continue
            }

            keptAutomatic.append(unknownEntry)
        }

        automaticEntries = keptAutomatic
    }

    private static func makeSlice(
        _ encounter: ResolvedEncounter,
        day: DateInterval,
        calendar: Calendar,
        activeReferenceDate: Date? = nil
    ) -> DayEncounterSlice? {
        guard encounter.startedAt < day.end else { return nil }
        let sliceStart = max(encounter.startedAt, day.start)
        let sliceEnd: Date?
        if encounter.status == .completed, let end = encounter.endedAt, end > encounter.startedAt {
            // A session ending at midnight has no slice on the following day (SPEC §4.4).
            guard end > day.start else { return nil }
            sliceEnd = min(end, day.end)
        } else if encounter.status == .active, let now = activeReferenceDate {
            let effectiveEnd = max(encounter.startedAt, now)
            guard effectiveEnd >= day.start else { return nil }
            sliceEnd = effectiveEnd >= day.end ? day.end : nil
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
        mergedDateIntervals(intervals).reduce(0) { $0 + $1.duration }
    }

    private static func mergedDateIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let ordered = intervals.filter { $0.end > $0.start }.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        guard let first = ordered.first else { return [] }
        var result = [first]
        for interval in ordered.dropFirst() {
            let last = result[result.count - 1]
            if interval.start > last.end {
                result.append(interval)
            } else if interval.end > last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: interval.end)
            }
        }
        return result
    }

    private static func coveredDuration(of target: DateInterval, by merged: [DateInterval]) -> TimeInterval {
        var total: TimeInterval = 0
        for item in merged {
            let s = max(target.start, item.start)
            let e = min(target.end, item.end)
            if e > s { total += e.timeIntervalSince(s) }
        }
        return total
    }
}
