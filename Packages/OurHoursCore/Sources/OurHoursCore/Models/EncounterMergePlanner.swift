import Foundation

public struct EncounterMergePlan: Sendable, Equatable {
    public let target: ResolvedEncounter?
    public let absorbed: [ResolvedEncounter]
    public let mergedStart: Date
    public let mergedEnd: Date

    public var didMerge: Bool { !absorbed.isEmpty }

    public init(
        target: ResolvedEncounter?,
        absorbed: [ResolvedEncounter],
        mergedStart: Date,
        mergedEnd: Date
    ) {
        self.target = target
        self.absorbed = absorbed
        self.mergedStart = mergedStart
        self.mergedEnd = mergedEnd
    }
}

public enum EncounterMergePlanner {
    public static func plan(
        editing target: ResolvedEncounter?,
        proposedStart: Date,
        proposedEnd: Date,
        among allEncounters: [ResolvedEncounter]
    ) -> EncounterMergePlan {
        guard proposedEnd > proposedStart else {
            return EncounterMergePlan(
                target: target,
                absorbed: [],
                mergedStart: proposedStart,
                mergedEnd: proposedEnd
            )
        }

        var mergedStart = proposedStart
        var mergedEnd = proposedEnd
        var absorbedIDs = Set<UUID>()
        var expanded = true

        while expanded {
            expanded = false
            for candidate in allEncounters {
                guard candidate.id != target?.id,
                      candidate.status != .active,
                      !absorbedIDs.contains(candidate.id) else {
                    continue
                }

                switch candidate.status {
                case .completed:
                    guard let cEnd = candidate.endedAt, cEnd > candidate.startedAt else { continue }
                    if candidate.startedAt <= mergedEnd && cEnd >= mergedStart {
                        absorbedIDs.insert(candidate.id)
                        mergedStart = min(mergedStart, candidate.startedAt)
                        mergedEnd = max(mergedEnd, cEnd)
                        expanded = true
                    }
                case .unknownEnd:
                    if candidate.startedAt >= mergedStart && candidate.startedAt <= mergedEnd {
                        absorbedIDs.insert(candidate.id)
                        mergedStart = min(mergedStart, candidate.startedAt)
                        expanded = true
                    }
                case .active:
                    continue
                }
            }
        }

        let absorbed = allEncounters
            .filter { absorbedIDs.contains($0.id) }
            .sorted {
                if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.startedAt < $1.startedAt
            }

        return EncounterMergePlan(
            target: target,
            absorbed: absorbed,
            mergedStart: mergedStart,
            mergedEnd: mergedEnd
        )
    }
}
