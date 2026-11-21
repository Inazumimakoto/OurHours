import Foundation

public enum JournalMerger {
    public static func merge(local: JournalSnapshot, remote: JournalSnapshot) -> JournalSnapshot {
        let manual = mergeManualRecords(local: local, remote: remote)
        let overrides = mergeOverrides(local: local.sessionOverrides, remote: remote.sessionOverrides)
        let memos = mergeMemos(local: local, remote: remote)
        return JournalSnapshot(
            manualRecords: manual.records,
            sessionOverrides: overrides,
            dailyMemos: memos.memos,
            deletedManualRecords: manual.tombstones,
            deletedMemoDays: memos.tombstones,
            roleProfiles: local.roleProfiles.merging(remote.roleProfiles, uniquingKeysWith: preferredProfile),
            anniversary: preferredAnniversary(local.anniversary, remote.anniversary)
        )
    }

    private static func preferredProfile(_ lhs: SyncedRoleProfile, _ rhs: SyncedRoleProfile) -> SyncedRoleProfile {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if (lhs.birthday == nil) != (rhs.birthday == nil) {
            return lhs.birthday != nil ? lhs : rhs
        }
        if lhs.bubbleColor != rhs.bubbleColor {
            return lhs.bubbleColor.rawValue < rhs.bubbleColor.rawValue ? lhs : rhs
        }
        if let left = lhs.birthday, let right = rhs.birthday, left != right {
            return left < right ? lhs : rhs
        }
        return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    private static func preferredAnniversary(
        _ lhs: SyncedAnniversary?, _ rhs: SyncedAnniversary?
    ) -> SyncedAnniversary? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        switch (lhs.date, rhs.date) {
        case (.some, nil): return lhs
        case (nil, .some): return rhs
        case let (left?, right?) where left != right: return left < right ? lhs : rhs
        default: return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
    }

    private static func mergeManualRecords(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (records: [ManualEncounterRecord], tombstones: [UUID: Date]) {
        var recordsByID: [UUID: ManualEncounterRecord] = [:]
        for record in local.manualRecords + remote.manualRecords {
            if let existing = recordsByID[record.id] {
                recordsByID[record.id] = preferredManualRecord(existing, record)
            } else {
                recordsByID[record.id] = record
            }
        }

        var tombstonesByID = local.deletedManualRecords
        for (id, date) in remote.deletedManualRecords {
            if let existing = tombstonesByID[id] {
                tombstonesByID[id] = max(existing, date)
            } else {
                tombstonesByID[id] = date
            }
        }

        let allIDs = Set(recordsByID.keys).union(tombstonesByID.keys)
        var kept: [ManualEncounterRecord] = []
        var keptTombstones: [UUID: Date] = [:]

        for id in allIDs {
            let record = recordsByID[id]
            let deletedAt = tombstonesByID[id]
            if let deletedAt, record == nil || deletedAt >= record!.updatedAt {
                keptTombstones[id] = deletedAt
            } else if let record {
                kept.append(record)
            }
        }

        kept.sort {
            if $0.startedAt == $1.startedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.startedAt < $1.startedAt
        }
        return (kept, keptTombstones)
    }

    private static func preferredManualRecord(
        _ lhs: ManualEncounterRecord,
        _ rhs: ManualEncounterRecord
    ) -> ManualEncounterRecord {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt ? lhs : rhs
        }
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt ? lhs : rhs
        }
        return lhs.endedAt <= rhs.endedAt ? lhs : rhs
    }

    private static func mergeOverrides(
        local: [UUID: SessionOverride],
        remote: [UUID: SessionOverride]
    ) -> [UUID: SessionOverride] {
        var result: [UUID: SessionOverride] = local
        for (id, candidate) in remote {
            if let existing = result[id] {
                result[id] = preferredOverride(existing, candidate)
            } else {
                result[id] = candidate
            }
        }
        return result
    }

    private static func preferredOverride(_ lhs: SessionOverride, _ rhs: SessionOverride) -> SessionOverride {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        switch (lhs.action, rhs.action) {
        case (.edited, .deleted):
            return lhs
        case (.deleted, .edited):
            return rhs
        case let (.edited(ls, le), .edited(rs, re)):
            if ls != rs { return ls < rs ? lhs : rhs }
            if le != re { return le < re ? lhs : rhs }
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        case (.deleted, .deleted):
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
    }

    private static func mergeMemos(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (memos: [String: DailyMemo], tombstones: [String: Date]) {
        var memosByDay = local.dailyMemos
        for (dayKey, candidate) in remote.dailyMemos {
            if let existing = memosByDay[dayKey] {
                memosByDay[dayKey] = preferredMemo(existing, candidate)
            } else {
                memosByDay[dayKey] = candidate
            }
        }

        var tombstonesByDay = local.deletedMemoDays
        for (dayKey, deletedAt) in remote.deletedMemoDays {
            if let existing = tombstonesByDay[dayKey] {
                tombstonesByDay[dayKey] = max(existing, deletedAt)
            } else {
                tombstonesByDay[dayKey] = deletedAt
            }
        }

        let allDays = Set(memosByDay.keys).union(tombstonesByDay.keys)
        var keptMemos: [String: DailyMemo] = [:]
        var keptTombstones: [String: Date] = [:]

        for dayKey in allDays {
            let memo = memosByDay[dayKey]
            let deletedAt = tombstonesByDay[dayKey]
            if let deletedAt, memo == nil || deletedAt >= memo!.updatedAt {
                keptTombstones[dayKey] = deletedAt
            } else if let memo {
                keptMemos[dayKey] = memo
            }
        }
        return (keptMemos, keptTombstones)
    }

    private static func preferredMemo(_ lhs: DailyMemo, _ rhs: DailyMemo) -> DailyMemo {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        return lhs.text <= rhs.text ? lhs : rhs
    }
}
