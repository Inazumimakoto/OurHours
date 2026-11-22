import Foundation

public struct ManualEncounterRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID?
    public let startedAt: Date
    public let endedAt: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, pairID: UUID?, startedAt: Date, endedAt: Date, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.pairID = pairID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SessionOverrideAction: Codable, Sendable, Equatable {
    case edited(startedAt: Date, endedAt: Date)
    case adjustedStart(startedAt: Date)
    case deleted
}

public struct SessionOverride: Codable, Sendable, Equatable {
    public let pairID: UUID?
    public let sessionID: UUID
    public let action: SessionOverrideAction
    public let updatedAt: Date

    public init(sessionID: UUID, action: SessionOverrideAction, updatedAt: Date, pairID: UUID? = nil) {
        self.pairID = pairID
        self.sessionID = sessionID
        self.action = action
        self.updatedAt = updatedAt
    }
}

public struct DailyMemo: Codable, Sendable, Equatable, Identifiable {
    public static func roleMemoKey(dayKey: String, role: PeerRole) -> String {
        "\(dayKey)_\(role.shortCode)"
    }

    public let pairID: UUID?
    public let dayKey: String
    public let text: String
    public let authorRole: PeerRole?
    public let updatedAt: Date
    public var id: String { dayKey }

    private enum CodingKeys: String, CodingKey {
        case pairID
        case dayKey
        case text
        case authorRole
        case updatedAt
    }

    public init(dayKey: String, text: String, updatedAt: Date, pairID: UUID? = nil, authorRole: PeerRole? = nil) {
        self.pairID = pairID
        self.dayKey = dayKey
        self.text = text
        self.authorRole = authorRole
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairID = try container.decodeIfPresent(UUID.self, forKey: .pairID)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        text = try container.decode(String.self, forKey: .text)
        authorRole = try container.decodeIfPresent(PeerRole.self, forKey: .authorRole)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct JournalSnapshot: Codable, Sendable, Equatable {
    public var manualRecords: [ManualEncounterRecord]
    public var sessionOverrides: [UUID: SessionOverride]
    public var dailyMemos: [String: DailyMemo]
    public var roleDailyMemos: [String: DailyMemo]
    public var deletedManualRecords: [UUID: Date]
    public var deletedSessionOverrides: [UUID: Date]
    public var deletedMemoDays: [String: Date]
    public var deletedRoleMemoKeys: [String: Date]

    public var roleProfiles: [String: SyncedRoleProfile]
    public var anniversary: SyncedAnniversary?

    public var dayPhotos: [DayPhotoAttachment]
    public var deletedDayPhotos: [UUID: Date]
    public var dayPlaceTags: [DayPlaceTag]
    public var deletedDayPlaceTags: [UUID: Date]
    public var planEvents: [PairPlanEvent]
    public var deletedPlanEvents: [UUID: Date]

    public func profile(for role: PeerRole) -> SyncedRoleProfile? {
        roleProfiles[role.shortCode]
    }

    public func anyMemoText(forDayKey dayKey: String) -> String? {
        let candidates = [
            roleDailyMemos[DailyMemo.roleMemoKey(dayKey: dayKey, role: .partnerA)],
            roleDailyMemos[DailyMemo.roleMemoKey(dayKey: dayKey, role: .partnerB)],
            dailyMemos[dayKey]
        ].compactMap { memo -> DailyMemo? in
            guard let memo else { return nil }
            let trimmed = memo.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : memo
        }
        return candidates.max { $0.updatedAt < $1.updatedAt }?.text
    }

    private enum CodingKeys: String, CodingKey {
        case manualRecords
        case sessionOverrides
        case dailyMemos
        case roleDailyMemos
        case deletedManualRecords
        case roleProfiles
        case anniversary
        case deletedSessionOverrides
        case deletedMemoDays
        case deletedRoleMemoKeys
        case dayPhotos
        case deletedDayPhotos
        case dayPlaceTags
        case deletedDayPlaceTags
        case planEvents
        case deletedPlanEvents
    }

    public init(
        manualRecords: [ManualEncounterRecord] = [],
        sessionOverrides: [UUID: SessionOverride] = [:],
        dailyMemos: [String: DailyMemo] = [:],
        deletedManualRecords: [UUID: Date] = [:],
        deletedMemoDays: [String: Date] = [:],
        deletedSessionOverrides: [UUID: Date] = [:],
        roleProfiles: [String: SyncedRoleProfile] = [:],
        anniversary: SyncedAnniversary? = nil,
        dayPhotos: [DayPhotoAttachment] = [],
        deletedDayPhotos: [UUID: Date] = [:],
        dayPlaceTags: [DayPlaceTag] = [],
        deletedDayPlaceTags: [UUID: Date] = [:],
        roleDailyMemos: [String: DailyMemo] = [:],
        deletedRoleMemoKeys: [String: Date] = [:],
        planEvents: [PairPlanEvent] = [],
        deletedPlanEvents: [UUID: Date] = [:]
    ) {
        self.roleProfiles = roleProfiles
        self.anniversary = anniversary
        self.manualRecords = manualRecords
        self.sessionOverrides = sessionOverrides
        self.dailyMemos = dailyMemos
        self.roleDailyMemos = roleDailyMemos
        self.deletedManualRecords = deletedManualRecords
        self.deletedSessionOverrides = deletedSessionOverrides
        self.deletedMemoDays = deletedMemoDays
        self.deletedRoleMemoKeys = deletedRoleMemoKeys
        self.dayPhotos = dayPhotos
        self.deletedDayPhotos = deletedDayPhotos
        self.dayPlaceTags = dayPlaceTags
        self.deletedDayPlaceTags = deletedDayPlaceTags
        self.planEvents = planEvents
        self.deletedPlanEvents = deletedPlanEvents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.roleProfiles = try container.decodeIfPresent([String: SyncedRoleProfile].self, forKey: .roleProfiles) ?? [:]
        self.anniversary = try container.decodeIfPresent(SyncedAnniversary.self, forKey: .anniversary)
        self.manualRecords = try container.decodeIfPresent([ManualEncounterRecord].self, forKey: .manualRecords) ?? []
        self.sessionOverrides = try container.decodeIfPresent([UUID: SessionOverride].self, forKey: .sessionOverrides) ?? [:]
        self.dailyMemos = try container.decodeIfPresent([String: DailyMemo].self, forKey: .dailyMemos) ?? [:]
        self.roleDailyMemos = try container.decodeIfPresent([String: DailyMemo].self, forKey: .roleDailyMemos) ?? [:]
        self.deletedManualRecords = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedManualRecords) ?? [:]
        self.deletedSessionOverrides = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedSessionOverrides) ?? [:]
        self.deletedMemoDays = try container.decodeIfPresent([String: Date].self, forKey: .deletedMemoDays) ?? [:]
        self.deletedRoleMemoKeys = try container.decodeIfPresent([String: Date].self, forKey: .deletedRoleMemoKeys) ?? [:]
        self.dayPhotos = try container.decodeIfPresent([DayPhotoAttachment].self, forKey: .dayPhotos) ?? []
        self.deletedDayPhotos = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedDayPhotos) ?? [:]
        self.dayPlaceTags = try container.decodeIfPresent([DayPlaceTag].self, forKey: .dayPlaceTags) ?? []
        self.deletedDayPlaceTags = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedDayPlaceTags) ?? [:]
        self.planEvents = try container.decodeIfPresent([PairPlanEvent].self, forKey: .planEvents) ?? []
        self.deletedPlanEvents = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedPlanEvents) ?? [:]
    }
}

extension JournalSnapshot {
    public func scoped(to pairID: UUID, allowedSessionIDs: Set<UUID>? = nil) -> JournalSnapshot {
        var result = self
        result.manualRecords = manualRecords.filter { $0.pairID == nil || $0.pairID == pairID }
        result.dailyMemos = dailyMemos.filter { $0.value.pairID == nil || $0.value.pairID == pairID }
        result.roleDailyMemos = roleDailyMemos.filter { $0.value.pairID == nil || $0.value.pairID == pairID }
        result.dayPhotos = dayPhotos.filter { $0.pairID == nil || $0.pairID == pairID }
        result.dayPlaceTags = dayPlaceTags.filter { $0.pairID == nil || $0.pairID == pairID }
        result.planEvents = planEvents.filter { $0.pairID == nil || $0.pairID == pairID }
        result.sessionOverrides = sessionOverrides.filter { id, entry in
            entry.pairID == pairID || (entry.pairID == nil && (allowedSessionIDs?.contains(id) ?? true))
        }
        result.deletedSessionOverrides = deletedSessionOverrides.filter { allowedSessionIDs?.contains($0.key) ?? true }
        return result
    }

    public func stampingUnscoped(with pairID: UUID) -> JournalSnapshot {
        var result = self
        result.manualRecords = manualRecords.map { record in
            guard record.pairID == nil else { return record }
            return ManualEncounterRecord(id: record.id, pairID: pairID, startedAt: record.startedAt,
                                         endedAt: record.endedAt, createdAt: record.createdAt, updatedAt: record.updatedAt)
        }
        result.dailyMemos = dailyMemos.mapValues { memo in
            guard memo.pairID == nil else { return memo }
            return DailyMemo(dayKey: memo.dayKey, text: memo.text, updatedAt: memo.updatedAt,
                             pairID: pairID, authorRole: memo.authorRole)
        }
        result.roleDailyMemos = roleDailyMemos.mapValues { memo in
            guard memo.pairID == nil else { return memo }
            return DailyMemo(dayKey: memo.dayKey, text: memo.text, updatedAt: memo.updatedAt,
                             pairID: pairID, authorRole: memo.authorRole)
        }
        result.dayPhotos = dayPhotos.map { photo in
            guard photo.pairID == nil else { return photo }
            return DayPhotoAttachment(
                id: photo.id, pairID: pairID, dayKey: photo.dayKey, authorRole: photo.authorRole,
                mediaKind: photo.mediaKind, durationSeconds: photo.durationSeconds,
                thumbnailAssetID: photo.thumbnailAssetID, placeTagID: photo.placeTagID,
                coordinate: photo.coordinate, capturedAt: photo.capturedAt, locationName: photo.locationName,
                planID: photo.planID, excludedPlanIDs: photo.excludedPlanIDs,
                createdAt: photo.createdAt, updatedAt: photo.updatedAt
            )
        }
        result.dayPlaceTags = dayPlaceTags.map { tag in
            guard tag.pairID == nil else { return tag }
            return DayPlaceTag(
                id: tag.id, pairID: pairID, dayKey: tag.dayKey, name: tag.name, address: tag.address,
                coordinate: tag.coordinate, authorRole: tag.authorRole, createdAt: tag.createdAt, updatedAt: tag.updatedAt
            )
        }
        result.planEvents = planEvents.map { plan in
            guard plan.pairID == nil else { return plan }
            return PairPlanEvent(
                id: plan.id, pairID: pairID, title: plan.title,
                startDayKey: plan.startDayKey, endDayKey: plan.endDayKey,
                icon: plan.icon, memo: plan.memo, checklist: plan.checklist,
                authorRole: plan.authorRole, createdAt: plan.createdAt, updatedAt: plan.updatedAt
            )
        }
        result.sessionOverrides = sessionOverrides.mapValues { entry in
            guard entry.pairID == nil else { return entry }
            return SessionOverride(sessionID: entry.sessionID, action: entry.action, updatedAt: entry.updatedAt, pairID: pairID)
        }
        return result
    }
}
