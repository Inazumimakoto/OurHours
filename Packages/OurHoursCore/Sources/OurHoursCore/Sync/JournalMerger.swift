import Foundation

public enum JournalMerger {
    public static func merge(local: JournalSnapshot, remote: JournalSnapshot) -> JournalSnapshot {
        let manual = mergeManualRecords(local: local, remote: remote)
        let overrides = mergeOverrides(local: local, remote: remote)
        let memos = mergeMemoDictionary(
            localMemos: local.dailyMemos,
            remoteMemos: remote.dailyMemos,
            localTombstones: local.deletedMemoDays,
            remoteTombstones: remote.deletedMemoDays
        )
        let roleMemos = mergeMemoDictionary(
            localMemos: local.roleDailyMemos,
            remoteMemos: remote.roleDailyMemos,
            localTombstones: local.deletedRoleMemoKeys,
            remoteTombstones: remote.deletedRoleMemoKeys
        )
        let photos = mergeDayPhotos(local: local, remote: remote)
        let placeTags = mergeDayPlaceTags(local: local, remote: remote)
        let plans = mergePlanEvents(local: local, remote: remote)
        return JournalSnapshot(
            manualRecords: manual.records,
            sessionOverrides: overrides.overrides,
            dailyMemos: memos.memos,
            deletedManualRecords: manual.tombstones,
            deletedMemoDays: memos.tombstones,
            deletedSessionOverrides: overrides.tombstones,
            roleProfiles: local.roleProfiles.merging(remote.roleProfiles, uniquingKeysWith: preferredProfile),
            anniversary: preferredAnniversary(local.anniversary, remote.anniversary),
            dayPhotos: photos.items,
            deletedDayPhotos: photos.tombstones,
            dayPlaceTags: placeTags.items,
            deletedDayPlaceTags: placeTags.tombstones,
            roleDailyMemos: roleMemos.memos,
            deletedRoleMemoKeys: roleMemos.tombstones,
            planEvents: plans.items,
            deletedPlanEvents: plans.tombstones
        )
    }

    private static func preferredProfile(_ lhs: SyncedRoleProfile, _ rhs: SyncedRoleProfile) -> SyncedRoleProfile {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        if (lhs.birthday == nil) != (rhs.birthday == nil) {
            return lhs.birthday != nil ? lhs : rhs
        }
        if (lhs.avatarAssetID == nil) != (rhs.avatarAssetID == nil) {
            return lhs.avatarAssetID != nil ? lhs : rhs
        }
        if lhs.bubbleColor != rhs.bubbleColor {
            return lhs.bubbleColor.rawValue < rhs.bubbleColor.rawValue ? lhs : rhs
        }
        if let left = lhs.birthday, let right = rhs.birthday, left != right {
            return left < right ? lhs : rhs
        }
        if let left = lhs.avatarAssetID, let right = rhs.avatarAssetID, left != right {
            return left.uuidString < right.uuidString ? lhs : rhs
        }
        if lhs.expression != rhs.expression {
            return lhs.expression.rawValue < rhs.expression.rawValue ? lhs : rhs
        }
        let lhsPoolKey = lhs.expressionRotationPool.map(\.rawValue).joined(separator: ",")
        let rhsPoolKey = rhs.expressionRotationPool.map(\.rawValue).joined(separator: ",")
        if lhsPoolKey != rhsPoolKey {
            return lhsPoolKey < rhsPoolKey ? lhs : rhs
        }
        if lhs.decorations != rhs.decorations {
            return lhs.decorations.sortKey < rhs.decorations.sortKey ? lhs : rhs
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
        let result = mergeTimestampedItems(
            localItems: local.manualRecords,
            remoteItems: remote.manualRecords,
            localTombstones: local.deletedManualRecords,
            remoteTombstones: remote.deletedManualRecords,
            updatedAt: \.updatedAt,
            preferTieBreak: preferredManualRecord,
            sortOrder: {
                if $0.startedAt == $1.startedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.startedAt < $1.startedAt
            }
        )
        return (result.items, result.tombstones)
    }

    private static func mergeDayPhotos(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (items: [DayPhotoAttachment], tombstones: [UUID: Date]) {
        mergeTimestampedItems(
            localItems: local.dayPhotos,
            remoteItems: remote.dayPhotos,
            localTombstones: local.deletedDayPhotos,
            remoteTombstones: remote.deletedDayPhotos,
            updatedAt: \.updatedAt,
            preferTieBreak: preferredDayPhoto,
            sortOrder: {
                if $0.dayKey != $1.dayKey { return $0.dayKey < $1.dayKey }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    private static func mergeDayPlaceTags(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (items: [DayPlaceTag], tombstones: [UUID: Date]) {
        mergeTimestampedItems(
            localItems: local.dayPlaceTags,
            remoteItems: remote.dayPlaceTags,
            localTombstones: local.deletedDayPlaceTags,
            remoteTombstones: remote.deletedDayPlaceTags,
            updatedAt: \.updatedAt,
            preferTieBreak: preferredDayPlaceTag,
            sortOrder: {
                if $0.dayKey != $1.dayKey { return $0.dayKey < $1.dayKey }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    private static func mergePlanEvents(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (items: [PairPlanEvent], tombstones: [UUID: Date]) {
        mergeTimestampedItems(
            localItems: local.planEvents,
            remoteItems: remote.planEvents,
            localTombstones: local.deletedPlanEvents,
            remoteTombstones: remote.deletedPlanEvents,
            updatedAt: \.updatedAt,
            preferTieBreak: preferredPlanEvent,
            sortOrder: {
                if $0.startDayKey != $1.startDayKey { return $0.startDayKey < $1.startDayKey }
                if $0.endDayKey != $1.endDayKey { return $0.endDayKey < $1.endDayKey }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        )
    }

    private static func mergeTimestampedItems<Item: Identifiable>(
        localItems: [Item],
        remoteItems: [Item],
        localTombstones: [UUID: Date],
        remoteTombstones: [UUID: Date],
        updatedAt: (Item) -> Date,
        preferTieBreak: (Item, Item) -> Item,
        sortOrder: (Item, Item) -> Bool
    ) -> (items: [Item], tombstones: [UUID: Date]) where Item.ID == UUID {
        var itemsByID: [UUID: Item] = [:]
        for item in localItems + remoteItems {
            if let existing = itemsByID[item.id] {
                let lhsDate = updatedAt(existing)
                let rhsDate = updatedAt(item)
                if abs(lhsDate.timeIntervalSince(rhsDate)) >= 0.0005 {
                    itemsByID[item.id] = lhsDate > rhsDate ? existing : item
                } else {
                    itemsByID[item.id] = preferTieBreak(existing, item)
                }
            } else {
                itemsByID[item.id] = item
            }
        }

        let tombstonesByID = localTombstones.merging(remoteTombstones, uniquingKeysWith: max)
        let allIDs = Set(itemsByID.keys).union(tombstonesByID.keys)
        var kept: [Item] = []
        var keptTombstones: [UUID: Date] = [:]

        for id in allIDs {
            let item = itemsByID[id]
            let deletedAt = tombstonesByID[id]
            if let deletedAt, item == nil || deletedAt >= updatedAt(item!) {
                keptTombstones[id] = deletedAt
            } else if let item {
                kept.append(item)
            }
        }

        kept.sort(by: sortOrder)
        return (kept, keptTombstones)
    }

    private static func preferredManualRecord(
        _ lhs: ManualEncounterRecord,
        _ rhs: ManualEncounterRecord
    ) -> ManualEncounterRecord {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt ? lhs : rhs
        }
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt ? lhs : rhs
        }
        return lhs.endedAt <= rhs.endedAt ? lhs : rhs
    }

    private static func preferredDayPhoto(
        _ lhs: DayPhotoAttachment,
        _ rhs: DayPhotoAttachment
    ) -> DayPhotoAttachment {
        if (lhs.placeTagID == nil) != (rhs.placeTagID == nil) {
            return lhs.placeTagID != nil ? lhs : rhs
        }
        if (lhs.planID == nil) != (rhs.planID == nil) {
            return lhs.planID != nil ? lhs : rhs
        }
        if let lp = lhs.planID, let rp = rhs.planID, lp != rp {
            return lp.uuidString < rp.uuidString ? lhs : rhs
        }
        if (lhs.coordinate == nil) != (rhs.coordinate == nil) {
            return lhs.coordinate != nil ? lhs : rhs
        }
        if (lhs.locationName ?? "") != (rhs.locationName ?? "") {
            return (lhs.locationName ?? "") >= (rhs.locationName ?? "") ? lhs : rhs
        }
        let lEx = lhs.excludedPlanIDs.map(\.uuidString).sorted().joined(separator: ",")
        let rEx = rhs.excludedPlanIDs.map(\.uuidString).sorted().joined(separator: ",")
        if lEx != rEx {
            return lEx < rEx ? lhs : rhs
        }
        return lhs.createdAt <= rhs.createdAt ? lhs : rhs
    }

    private static func preferredDayPlaceTag(
        _ lhs: DayPlaceTag,
        _ rhs: DayPlaceTag
    ) -> DayPlaceTag {
        if (lhs.coordinate == nil) != (rhs.coordinate == nil) {
            return lhs.coordinate != nil ? lhs : rhs
        }
        if lhs.name != rhs.name {
            return lhs.name <= rhs.name ? lhs : rhs
        }
        return lhs.createdAt <= rhs.createdAt ? lhs : rhs
    }

    private static func preferredPlanEvent(
        _ lhs: PairPlanEvent,
        _ rhs: PairPlanEvent
    ) -> PairPlanEvent {
        if lhs.title != rhs.title {
            return lhs.title < rhs.title ? lhs : rhs
        }
        if lhs.startDayKey != rhs.startDayKey {
            return lhs.startDayKey < rhs.startDayKey ? lhs : rhs
        }
        if lhs.endDayKey != rhs.endDayKey {
            return lhs.endDayKey < rhs.endDayKey ? lhs : rhs
        }
        if (lhs.memo ?? "") != (rhs.memo ?? "") {
            return (lhs.memo ?? "") >= (rhs.memo ?? "") ? lhs : rhs
        }
        if lhs.checklist.count != rhs.checklist.count {
            return lhs.checklist.count > rhs.checklist.count ? lhs : rhs
        }
        return lhs.createdAt <= rhs.createdAt ? lhs : rhs
    }

    private static func mergeOverrides(
        local: JournalSnapshot,
        remote: JournalSnapshot
    ) -> (overrides: [UUID: SessionOverride], tombstones: [UUID: Date]) {
        var overrides = local.sessionOverrides.merging(remote.sessionOverrides) { lhs, rhs in
            let winner = preferredOverride(lhs, rhs)
            return SessionOverride(sessionID: winner.sessionID, action: winner.action, updatedAt: winner.updatedAt,
                                   pairID: winner.pairID ?? lhs.pairID ?? rhs.pairID)
        }
        var tombstones = local.deletedSessionOverrides.merging(remote.deletedSessionOverrides, uniquingKeysWith: max)
        for (id, deletedAt) in tombstones {
            if let entry = overrides[id], entry.updatedAt > deletedAt {
                tombstones[id] = nil
            } else {
                overrides[id] = nil
            }
        }
        return (overrides, tombstones)
    }

    private static func preferredOverride(_ lhs: SessionOverride, _ rhs: SessionOverride) -> SessionOverride {
        if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        switch (lhs.action, rhs.action) {
        case (.edited, .deleted), (.edited, .adjustedStart), (.adjustedStart, .deleted):
            return lhs
        case (.deleted, .edited), (.adjustedStart, .edited), (.deleted, .adjustedStart):
            return rhs
        case let (.edited(ls, le), .edited(rs, re)):
            if ls != rs { return ls < rs ? lhs : rhs }
            if le != re { return le < re ? lhs : rhs }
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        case let (.adjustedStart(ls), .adjustedStart(rs)):
            if ls != rs { return ls < rs ? lhs : rhs }
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        case (.deleted, .deleted):
            return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
        }
    }

    private static func mergeMemoDictionary(
        localMemos: [String: DailyMemo],
        remoteMemos: [String: DailyMemo],
        localTombstones: [String: Date],
        remoteTombstones: [String: Date]
    ) -> (memos: [String: DailyMemo], tombstones: [String: Date]) {
        var memosByKey = localMemos
        for (key, candidate) in remoteMemos {
            if let existing = memosByKey[key] {
                let winner = preferredMemo(existing, candidate)
                memosByKey[key] = DailyMemo(
                    dayKey: winner.dayKey,
                    text: winner.text,
                    updatedAt: winner.updatedAt,
                    pairID: winner.pairID ?? existing.pairID ?? candidate.pairID,
                    authorRole: winner.authorRole ?? existing.authorRole ?? candidate.authorRole
                )
            } else {
                memosByKey[key] = candidate
            }
        }

        let tombstonesByKey = localTombstones.merging(remoteTombstones, uniquingKeysWith: max)
        let allKeys = Set(memosByKey.keys).union(tombstonesByKey.keys)
        var keptMemos: [String: DailyMemo] = [:]
        var keptTombstones: [String: Date] = [:]

        for key in allKeys {
            let memo = memosByKey[key]
            let deletedAt = tombstonesByKey[key]
            if let deletedAt, memo == nil || deletedAt >= memo!.updatedAt {
                keptTombstones[key] = deletedAt
            } else if let memo {
                keptMemos[key] = memo
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
