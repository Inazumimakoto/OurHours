import Foundation

public struct EncounterMergePlan: Sendable, Equatable {
    public let target: ResolvedEncounter?
    public let absorbed: [ResolvedEncounter]
    public let mergedStart: Date
    public let mergedEnd: Date?
    public let survivingActiveEncounter: ResolvedEncounter?

    public var didMerge: Bool { !absorbed.isEmpty }
    public var keepsActiveSession: Bool { survivingActiveEncounter != nil }

    public init(
        target: ResolvedEncounter?,
        absorbed: [ResolvedEncounter],
        mergedStart: Date,
        mergedEnd: Date?,
        survivingActiveEncounter: ResolvedEncounter? = nil
    ) {
        self.target = target
        self.absorbed = absorbed
        self.mergedStart = mergedStart
        self.mergedEnd = mergedEnd
        self.survivingActiveEncounter = survivingActiveEncounter
    }
}

public enum EncounterMergePlanner {
    public static func plan(
        editing target: ResolvedEncounter?,
        proposedStart: Date,
        proposedEnd: Date?,
        among allEncounters: [ResolvedEncounter],
        now: Date = Date()
    ) -> EncounterMergePlan {
        var mergedStart = proposedStart
        var searchEnd: Date
        var survivingActive: ResolvedEncounter?
        let editingActive = target?.status == .active
        if let target, editingActive {
            searchEnd = max(target.startedAt, now)
            guard proposedStart <= searchEnd else {
                return EncounterMergePlan(target: target, absorbed: [], mergedStart: proposedStart, mergedEnd: nil)
            }
            survivingActive = target
        } else {
            guard let proposedEnd, proposedEnd > proposedStart else {
                return EncounterMergePlan(target: target, absorbed: [], mergedStart: proposedStart, mergedEnd: proposedEnd)
            }
            searchEnd = proposedEnd
        }

        func startsEarlier(_ lhs: ResolvedEncounter, _ rhs: ResolvedEncounter) -> Bool {
            (lhs.startedAt, lhs.id.uuidString) < (rhs.startedAt, rhs.id.uuidString)
        }

        var absorbedIDs = Set<UUID>()
        var absorbed: [ResolvedEncounter] = []
        var expanded = true
        while expanded {
            expanded = false
            for candidate in allEncounters where candidate.id != target?.id && !absorbedIDs.contains(candidate.id) {
                let end: Date
                switch candidate.status {
                case .completed:
                    guard let completedEnd = candidate.endedAt, completedEnd > candidate.startedAt else { continue }
                    end = completedEnd
                case .unknownEnd:
                    end = candidate.startedAt
                case .active:
                    guard !editingActive else { continue }
                    end = max(candidate.startedAt, now)
                }
                guard candidate.startedAt <= searchEnd, end >= mergedStart else { continue }
                absorbedIDs.insert(candidate.id)
                absorbed.append(candidate)
                mergedStart = min(mergedStart, candidate.startedAt)
                if !editingActive { searchEnd = max(searchEnd, end) }
                if candidate.status == .active, survivingActive.map({ startsEarlier(candidate, $0) }) ?? true {
                    survivingActive = candidate
                }
                expanded = true
            }
        }

        return EncounterMergePlan(
            target: target, absorbed: absorbed.sorted(by: startsEarlier), mergedStart: mergedStart,
            mergedEnd: survivingActive == nil ? searchEnd : nil, survivingActiveEncounter: survivingActive
        )
    }
}
