import Foundation
import Synchronization

public enum JournalStoreError: Error, Sendable, Equatable {
    case invalidTimeRange
    case recordNotFound
}

public final class JournalStore: Sendable {
    // Serialize read-modify-write operations even when stores share a directory.
    private static let lock = Mutex(())
    public let directory: URL
    private var journalURL: URL { directory.appendingPathComponent("journal.json") }
    private static var atomicWriteOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return .atomic
        #endif
    }

    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("OurHours")) {
        self.directory = directory
    }

    public func load() throws -> JournalSnapshot {
        try Self.lock.withLock { _ in try read() }
    }

    @discardableResult
    public func setRoleProfile(
        role: PeerRole,
        bubbleColor: BubbleColorTheme,
        birthday: CalendarDateValue?,
        avatarAssetID: UUID? = nil,
        expression: BubbleExpression = .classic,
        expressionRotationPool: [BubbleExpression] = [],
        decorations: BubbleDecorationLoadout = .none
    ) throws -> JournalSnapshot {
        try modify { snapshot in
            let ts = Self.monotonicNow(after: snapshot.roleProfiles[role.shortCode]?.updatedAt ?? .distantPast)
            snapshot.roleProfiles[role.shortCode] = SyncedRoleProfile(
                bubbleColor: bubbleColor,
                birthday: birthday,
                avatarAssetID: avatarAssetID,
                expression: expression,
                expressionRotationPool: expressionRotationPool,
                decorations: decorations,
                updatedAt: ts
            )
        }
    }

    @discardableResult
    public func clearRoleProfiles() throws -> JournalSnapshot {
        try modify {
            $0.roleProfiles = [:]
            $0.anniversary = nil
        }
    }

    @discardableResult
    public func setAnniversary(_ date: CalendarDateValue?) throws -> JournalSnapshot {
        try modify { snapshot in
            let ts = Self.monotonicNow(after: snapshot.anniversary?.updatedAt ?? .distantPast)
            snapshot.anniversary = SyncedAnniversary(date: date, updatedAt: ts)
        }
    }

    @discardableResult
    public func addManualRecord(pairID: UUID?, startedAt: Date, endedAt: Date) throws -> JournalSnapshot {
        guard endedAt > startedAt else { throw JournalStoreError.invalidTimeRange }
        return try modify { snapshot in
            let now = Date()
            snapshot.manualRecords.append(ManualEncounterRecord(
                id: UUID(), pairID: pairID, startedAt: startedAt, endedAt: endedAt,
                createdAt: now, updatedAt: now
            ))
        }
    }

    @discardableResult
    public func updateManualRecord(id: UUID, startedAt: Date, endedAt: Date) throws -> JournalSnapshot {
        guard endedAt > startedAt else { throw JournalStoreError.invalidTimeRange }
        return try modify { snapshot in
            guard let index = snapshot.manualRecords.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let record = snapshot.manualRecords[index]
            let ts = Self.monotonicNow(after: record.updatedAt)
            snapshot.manualRecords[index] = ManualEncounterRecord(
                id: record.id, pairID: record.pairID, startedAt: startedAt, endedAt: endedAt,
                createdAt: record.createdAt, updatedAt: ts
            )
            snapshot.deletedManualRecords[id] = nil
        }
    }

    @discardableResult
    public func deleteManualRecord(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.manualRecords.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let record = snapshot.manualRecords.remove(at: index)
            snapshot.deletedManualRecords[id] = Self.monotonicNow(
                after: record.updatedAt,
                snapshot.deletedManualRecords[id] ?? .distantPast
            )
        }
    }

    @discardableResult
    public func setSessionOverride(sessionID: UUID, action: SessionOverrideAction, pairID: UUID? = nil) throws -> JournalSnapshot {
        try setSessionOverrides([sessionID: action], pairID: pairID)
    }

    @discardableResult
    public func setSessionOverrides(_ updates: [UUID: SessionOverrideAction], pairID: UUID? = nil) throws -> JournalSnapshot {
        for action in updates.values {
            if case let .edited(startedAt, endedAt) = action, !(endedAt > startedAt) {
                throw JournalStoreError.invalidTimeRange
            }
        }
        guard !updates.isEmpty else { return try load() }
        return try modify { snapshot in
            let floors = updates.keys.map { id in
                max(snapshot.sessionOverrides[id]?.updatedAt ?? .distantPast, snapshot.deletedSessionOverrides[id] ?? .distantPast)
            }
            let ts = Self.monotonicNow(after: floors)
            for (sessionID, action) in updates {
                snapshot.deletedSessionOverrides[sessionID] = nil
                snapshot.sessionOverrides[sessionID] = SessionOverride(
                    sessionID: sessionID,
                    action: action,
                    updatedAt: ts,
                    pairID: pairID ?? snapshot.sessionOverrides[sessionID]?.pairID
                )
            }
        }
    }

    @discardableResult
    public func clearSessionOverride(sessionID: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            snapshot.deletedSessionOverrides[sessionID] = Self.monotonicNow(
                after: snapshot.sessionOverrides[sessionID]?.updatedAt ?? .distantPast,
                snapshot.deletedSessionOverrides[sessionID] ?? .distantPast
            )
            snapshot.sessionOverrides[sessionID] = nil
        }
    }

    @discardableResult
    public func setMemo(dayKey: String, text: String, pairID: UUID? = nil, authorRole: PeerRole? = nil) throws -> JournalSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return try modify { snapshot in
            let existingMemoAt = snapshot.dailyMemos[dayKey]?.updatedAt ?? .distantPast
            let existingDeletedAt = snapshot.deletedMemoDays[dayKey] ?? .distantPast
            let ts = Self.monotonicNow(after: existingMemoAt, existingDeletedAt)
            if trimmed.isEmpty {
                snapshot.dailyMemos[dayKey] = nil
                snapshot.deletedMemoDays[dayKey] = ts
            } else {
                snapshot.dailyMemos[dayKey] = DailyMemo(
                    dayKey: dayKey, text: trimmed, updatedAt: ts,
                    pairID: pairID ?? snapshot.dailyMemos[dayKey]?.pairID,
                    authorRole: authorRole ?? snapshot.dailyMemos[dayKey]?.authorRole
                )
                snapshot.deletedMemoDays[dayKey] = nil
            }
        }
    }

    @discardableResult
    public func setRoleMemo(dayKey: String, role: PeerRole, text: String, pairID: UUID? = nil) throws -> JournalSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = DailyMemo.roleMemoKey(dayKey: dayKey, role: role)
        return try modify { snapshot in
            let existingMemoAt = snapshot.roleDailyMemos[key]?.updatedAt ?? .distantPast
            let existingDeletedAt = snapshot.deletedRoleMemoKeys[key] ?? .distantPast
            let legacyMemo = snapshot.dailyMemos[dayKey]
            let legacyMatchesRole = legacyMemo != nil && (legacyMemo?.authorRole == nil || legacyMemo?.authorRole == role)
            let legacyAt = legacyMatchesRole ? (legacyMemo?.updatedAt ?? .distantPast) : .distantPast
            let ts = Self.monotonicNow(after: existingMemoAt, existingDeletedAt, legacyAt)
            if trimmed.isEmpty {
                snapshot.roleDailyMemos[key] = nil
                snapshot.deletedRoleMemoKeys[key] = ts
                if legacyMatchesRole {
                    snapshot.dailyMemos[dayKey] = nil
                    snapshot.deletedMemoDays[dayKey] = ts
                }
            } else {
                snapshot.roleDailyMemos[key] = DailyMemo(
                    dayKey: dayKey,
                    text: trimmed,
                    updatedAt: ts,
                    pairID: pairID ?? snapshot.roleDailyMemos[key]?.pairID,
                    authorRole: role
                )
                snapshot.deletedRoleMemoKeys[key] = nil
            }
        }
    }

    @discardableResult
    public func addDayPhoto(_ photo: DayPhotoAttachment) throws -> JournalSnapshot {
        try modify { snapshot in
            let existingIndex = snapshot.dayPhotos.firstIndex(where: { $0.id == photo.id })
            let existingAt = existingIndex.map { snapshot.dayPhotos[$0].updatedAt } ?? .distantPast
            let deletedAt = snapshot.deletedDayPhotos[photo.id] ?? .distantPast
            let ts = Self.monotonicNow(after: photo.updatedAt, existingAt, deletedAt)
            let normalizedName = Self.normalizedOptionalText(photo.locationName)
            let stored = DayPhotoAttachment(
                id: photo.id, pairID: photo.pairID, dayKey: photo.dayKey, authorRole: photo.authorRole,
                mediaKind: photo.mediaKind, durationSeconds: photo.durationSeconds,
                thumbnailAssetID: photo.thumbnailAssetID, placeTagID: photo.placeTagID,
                coordinate: photo.coordinate?.isValid == true ? photo.coordinate : nil,
                capturedAt: photo.capturedAt, locationName: normalizedName,
                planID: photo.planID, excludedPlanIDs: photo.excludedPlanIDs,
                createdAt: existingIndex.map { snapshot.dayPhotos[$0].createdAt } ?? photo.createdAt,
                updatedAt: ts
            )
            if let existingIndex {
                snapshot.dayPhotos[existingIndex] = stored
            } else {
                snapshot.dayPhotos.append(stored)
            }
            snapshot.deletedDayPhotos[photo.id] = nil
        }
    }

    @discardableResult
    public func updateDayPhotoLocation(
        id: UUID,
        coordinate: GeoCoordinate?,
        locationName: String?,
        placeTagID: UUID? = nil
    ) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.dayPhotos.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let existing = snapshot.dayPhotos[index]
            let ts = Self.monotonicNow(after: existing.updatedAt, snapshot.deletedDayPhotos[id] ?? .distantPast)
            snapshot.dayPhotos[index] = DayPhotoAttachment(
                id: existing.id, pairID: existing.pairID, dayKey: existing.dayKey, authorRole: existing.authorRole,
                mediaKind: existing.mediaKind, durationSeconds: existing.durationSeconds,
                thumbnailAssetID: existing.thumbnailAssetID, placeTagID: placeTagID,
                coordinate: coordinate?.isValid == true ? coordinate : nil,
                capturedAt: existing.capturedAt, locationName: Self.normalizedOptionalText(locationName),
                planID: existing.planID, excludedPlanIDs: existing.excludedPlanIDs,
                createdAt: existing.createdAt, updatedAt: ts
            )
            snapshot.deletedDayPhotos[id] = nil
        }
    }

    @discardableResult
    public func updateDayPhotoPlanAssignment(
        id: UUID,
        planID: UUID?,
        excludedPlanIDs: [UUID]
    ) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.dayPhotos.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let existing = snapshot.dayPhotos[index]
            let ts = Self.monotonicNow(after: existing.updatedAt, snapshot.deletedDayPhotos[id] ?? .distantPast)
            snapshot.dayPhotos[index] = DayPhotoAttachment(
                id: existing.id, pairID: existing.pairID, dayKey: existing.dayKey, authorRole: existing.authorRole,
                mediaKind: existing.mediaKind, durationSeconds: existing.durationSeconds,
                thumbnailAssetID: existing.thumbnailAssetID, placeTagID: existing.placeTagID,
                coordinate: existing.coordinate, capturedAt: existing.capturedAt,
                locationName: existing.locationName,
                planID: planID,
                excludedPlanIDs: excludedPlanIDs,
                createdAt: existing.createdAt, updatedAt: ts
            )
            snapshot.deletedDayPhotos[id] = nil
        }
    }

    @discardableResult
    public func deleteDayPhoto(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.dayPhotos.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let existing = snapshot.dayPhotos.remove(at: index)
            snapshot.deletedDayPhotos[id] = Self.monotonicNow(
                after: existing.updatedAt, snapshot.deletedDayPhotos[id] ?? .distantPast
            )
        }
    }

    @discardableResult
    public func addDayPlaceTag(_ tag: DayPlaceTag) throws -> JournalSnapshot {
        let trimmedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try modify { snapshot in
            let existingIndex = snapshot.dayPlaceTags.firstIndex(where: { $0.id == tag.id })
            let existingAt = existingIndex.map { snapshot.dayPlaceTags[$0].updatedAt } ?? .distantPast
            let deletedAt = snapshot.deletedDayPlaceTags[tag.id] ?? .distantPast
            let ts = Self.monotonicNow(after: tag.updatedAt, existingAt, deletedAt)
            let stored = DayPlaceTag(
                id: tag.id, pairID: tag.pairID, dayKey: tag.dayKey, name: trimmedName,
                address: Self.normalizedOptionalText(tag.address),
                coordinate: tag.coordinate?.isValid == true ? tag.coordinate : nil,
                authorRole: tag.authorRole,
                createdAt: existingIndex.map { snapshot.dayPlaceTags[$0].createdAt } ?? tag.createdAt,
                updatedAt: ts
            )
            if let existingIndex {
                snapshot.dayPlaceTags[existingIndex] = stored
            } else {
                snapshot.dayPlaceTags.append(stored)
            }
            snapshot.deletedDayPlaceTags[tag.id] = nil
        }
    }

    @discardableResult
    public func deleteDayPlaceTag(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.dayPlaceTags.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let existing = snapshot.dayPlaceTags.remove(at: index)
            snapshot.deletedDayPlaceTags[id] = Self.monotonicNow(
                after: existing.updatedAt, snapshot.deletedDayPlaceTags[id] ?? .distantPast
            )
        }
    }

    @discardableResult
    public func upsertPlanEvent(_ event: PairPlanEvent) throws -> JournalSnapshot {
        let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChecklist = event.checklist.compactMap { item -> PairPlanChecklistItem? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return PairPlanChecklistItem(id: item.id, title: title, isDone: item.isDone, kind: item.kind)
        }
        return try modify { snapshot in
            let existingIndex = snapshot.planEvents.firstIndex(where: { $0.id == event.id })
            let existingAt = existingIndex.map { snapshot.planEvents[$0].updatedAt } ?? .distantPast
            let deletedAt = snapshot.deletedPlanEvents[event.id] ?? .distantPast
            let ts = Self.monotonicNow(after: event.updatedAt, existingAt, deletedAt)
            let stored = PairPlanEvent(
                id: event.id,
                pairID: event.pairID,
                title: trimmedTitle,
                startDayKey: event.startDayKey,
                endDayKey: event.endDayKey,
                icon: event.icon,
                memo: Self.normalizedOptionalText(event.memo),
                checklist: normalizedChecklist,
                authorRole: event.authorRole,
                createdAt: existingIndex.map { snapshot.planEvents[$0].createdAt } ?? event.createdAt,
                updatedAt: ts
            )
            if let existingIndex {
                snapshot.planEvents[existingIndex] = stored
            } else {
                snapshot.planEvents.append(stored)
            }
            snapshot.deletedPlanEvents[event.id] = nil
        }
    }

    @discardableResult
    public func deletePlanEvent(id: UUID) throws -> JournalSnapshot {
        try modify { snapshot in
            guard let index = snapshot.planEvents.firstIndex(where: { $0.id == id }) else {
                throw JournalStoreError.recordNotFound
            }
            let existing = snapshot.planEvents.remove(at: index)
            snapshot.deletedPlanEvents[id] = Self.monotonicNow(
                after: existing.updatedAt, snapshot.deletedPlanEvents[id] ?? .distantPast
            )
            for idx in snapshot.dayPhotos.indices {
                let photo = snapshot.dayPhotos[idx]
                let needsPlanClear = photo.planID == id
                let needsExcludedClear = photo.excludedPlanIDs.contains(id)
                guard needsPlanClear || needsExcludedClear else { continue }
                let ts = Self.monotonicNow(after: photo.updatedAt, snapshot.deletedDayPhotos[photo.id] ?? .distantPast)
                snapshot.dayPhotos[idx] = DayPhotoAttachment(
                    id: photo.id, pairID: photo.pairID, dayKey: photo.dayKey, authorRole: photo.authorRole,
                    mediaKind: photo.mediaKind, durationSeconds: photo.durationSeconds,
                    thumbnailAssetID: photo.thumbnailAssetID, placeTagID: photo.placeTagID,
                    coordinate: photo.coordinate, capturedAt: photo.capturedAt, locationName: photo.locationName,
                    planID: needsPlanClear ? nil : photo.planID,
                    excludedPlanIDs: photo.excludedPlanIDs.filter { $0 != id },
                    createdAt: photo.createdAt, updatedAt: ts
                )
            }
        }
    }

    private static func normalizedOptionalText(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    @discardableResult
    public func applyMergedMutation(
        pairID: UUID?,
        keepManualID: UUID?,
        createManual: Bool,
        mergedStart: Date,
        mergedEnd: Date?,
        deleteManualIDs: [UUID],
        sessionOverrideUpdates: [UUID: SessionOverrideAction]
    ) throws -> JournalSnapshot {
        if let mergedEnd {
            guard mergedEnd > mergedStart else { throw JournalStoreError.invalidTimeRange }
        } else if keepManualID != nil || createManual {
            throw JournalStoreError.invalidTimeRange
        }
        for action in sessionOverrideUpdates.values {
            if case let .edited(startedAt, endedAt) = action, !(endedAt > startedAt) {
                throw JournalStoreError.invalidTimeRange
            }
        }
        return try modify { snapshot in
            var floors: [Date] = []
            if let keepManualID {
                guard let keep = snapshot.manualRecords.first(where: { $0.id == keepManualID }) else {
                    throw JournalStoreError.recordNotFound
                }
                floors.append(keep.updatedAt)
                if let prevDel = snapshot.deletedManualRecords[keepManualID] {
                    floors.append(prevDel)
                }
            }
            for delID in deleteManualIDs where delID != keepManualID {
                if let rec = snapshot.manualRecords.first(where: { $0.id == delID }) {
                    floors.append(rec.updatedAt)
                }
                if let prevDel = snapshot.deletedManualRecords[delID] {
                    floors.append(prevDel)
                }
            }
            for sid in sessionOverrideUpdates.keys {
                if let deletedAt = snapshot.deletedSessionOverrides[sid] { floors.append(deletedAt) }
                if let prevOv = snapshot.sessionOverrides[sid] {
                    floors.append(prevOv.updatedAt)
                }
            }
            let ts = Self.monotonicNow(after: floors)

            if let keepManualID, let mergedEnd,
               let idx = snapshot.manualRecords.firstIndex(where: { $0.id == keepManualID }) {
                let existing = snapshot.manualRecords[idx]
                snapshot.manualRecords[idx] = ManualEncounterRecord(
                    id: existing.id,
                    pairID: existing.pairID,
                    startedAt: mergedStart,
                    endedAt: mergedEnd,
                    createdAt: existing.createdAt,
                    updatedAt: ts
                )
                snapshot.deletedManualRecords[keepManualID] = nil
            } else if createManual, let mergedEnd {
                snapshot.manualRecords.append(ManualEncounterRecord(
                    id: UUID(),
                    pairID: pairID,
                    startedAt: mergedStart,
                    endedAt: mergedEnd,
                    createdAt: ts,
                    updatedAt: ts
                ))
            }

            let deleteSet = Set(deleteManualIDs.filter { $0 != keepManualID })
            if !deleteSet.isEmpty {
                snapshot.manualRecords.removeAll { deleteSet.contains($0.id) }
                for delID in deleteSet {
                    snapshot.deletedManualRecords[delID] = ts
                }
            }

            for (sid, action) in sessionOverrideUpdates {
                snapshot.deletedSessionOverrides[sid] = nil
                snapshot.sessionOverrides[sid] = SessionOverride(
                    sessionID: sid,
                    action: action,
                    updatedAt: ts,
                    pairID: pairID ?? snapshot.sessionOverrides[sid]?.pairID
                )
            }
        }
    }

    @discardableResult
    public func claimUnscopedEntries(for pairID: UUID) throws -> JournalSnapshot {
        try modify { $0 = $0.stampingUnscoped(with: pairID) }
    }

    @discardableResult
    public func prepareForPairTransition(from previousPairID: UUID?, to nextPairID: UUID?) throws -> JournalSnapshot {
        try modify { snapshot in
            if let owner = previousPairID ?? nextPairID {
                snapshot = snapshot.stampingUnscoped(with: owner)
            }
            if previousPairID != nil && previousPairID != nextPairID {
                snapshot.roleProfiles = [:]
                snapshot.anniversary = nil
                snapshot.deletedMemoDays = [:]
                snapshot.deletedRoleMemoKeys = [:]
            }
        }
    }

    @discardableResult
    public func mergeRemote(_ remote: JournalSnapshot) throws -> (snapshot: JournalSnapshot, didChange: Bool) {
        try Self.lock.withLock { _ in
            let current = try read()
            let merged = JournalMerger.merge(local: current, remote: remote)
            guard merged != current else {
                return (current, false)
            }
            let data = try JSONEncoder().encode(merged)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: journalURL, options: Self.atomicWriteOptions)
            return (merged, true)
        }
    }

    private static func monotonicNow(after dates: Date...) -> Date {
        monotonicNow(after: dates)
    }

    private static func monotonicNow(after dates: [Date]) -> Date {
        let floor = dates.max() ?? .distantPast
        return max(Date(), floor.addingTimeInterval(0.001))
    }

    @discardableResult
    public func clearAll() throws -> JournalSnapshot {
        try Self.lock.withLock { _ in
            do {
                try FileManager.default.removeItem(at: journalURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return JournalSnapshot()
            }
            return JournalSnapshot()
        }
    }

    private func read() throws -> JournalSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: journalURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return JournalSnapshot()
        }
        return try JSONDecoder().decode(JournalSnapshot.self, from: data)
    }

    private func modify(_ update: (inout JournalSnapshot) throws -> Void) throws -> JournalSnapshot {
        try Self.lock.withLock { _ in
            var snapshot = try read()
            try update(&snapshot)
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: journalURL, options: Self.atomicWriteOptions)
            return snapshot
        }
    }
}
