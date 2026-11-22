import Foundation

public enum PairPlanIcon: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case trip
    case date
    case gourmet
    case outing
    case event
    case stay
    case anniversary
    case photo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .trip: "旅行"
        case .date: "デート"
        case .gourmet: "グルメ"
        case .outing: "おでかけ"
        case .event: "イベント"
        case .stay: "お泊まり"
        case .anniversary: "記念日"
        case .photo: "思い出"
        }
    }

    public var symbolName: String {
        switch self {
        case .trip: "airplane"
        case .date: "heart.fill"
        case .gourmet: "fork.knife"
        case .outing: "sparkles"
        case .event: "music.note"
        case .stay: "moon.stars.fill"
        case .anniversary: "gift.fill"
        case .photo: "camera.fill"
        }
    }
}

public enum PairPlanChecklistKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case todo
    case packing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .todo: "やりたいこと"
        case .packing: "持ち物"
        }
    }

    public var symbolName: String {
        switch self {
        case .todo: "sparkles"
        case .packing: "bag.fill"
        }
    }
}

public struct PairPlanChecklistItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var kind: PairPlanChecklistKind

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case isDone
        case kind
    }

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, kind: PairPlanChecklistKind = .todo) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
            .flatMap(PairPlanChecklistKind.init(rawValue:)) ?? .todo
    }
}

public enum PairPlanLifecycleStatus: String, Sendable, Equatable {
    case upcoming
    case ongoing
    case past
}

public struct PairPlanEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID?
    public let title: String
    public let startDayKey: String
    public let endDayKey: String
    public let icon: PairPlanIcon
    public let memo: String?
    public let checklist: [PairPlanChecklistItem]
    public let authorRole: PeerRole?
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case pairID
        case title
        case startDayKey
        case endDayKey
        case icon
        case memo
        case checklist
        case authorRole
        case createdAt
        case updatedAt
    }

    public init(
        id: UUID = UUID(),
        pairID: UUID? = nil,
        title: String,
        startDayKey: String,
        endDayKey: String? = nil,
        icon: PairPlanIcon = .trip,
        memo: String? = nil,
        checklist: [PairPlanChecklistItem] = [],
        authorRole: PeerRole? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let resolvedEnd = endDayKey ?? startDayKey
        self.id = id
        self.pairID = pairID
        self.title = title
        self.startDayKey = min(startDayKey, resolvedEnd)
        self.endDayKey = max(startDayKey, resolvedEnd)
        self.icon = icon
        self.memo = memo
        self.checklist = checklist
        self.authorRole = authorRole
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pairID = try container.decodeIfPresent(UUID.self, forKey: .pairID)
        title = try container.decode(String.self, forKey: .title)
        let decodedStart = try container.decode(String.self, forKey: .startDayKey)
        let decodedEnd = try container.decodeIfPresent(String.self, forKey: .endDayKey) ?? decodedStart
        startDayKey = min(decodedStart, decodedEnd)
        endDayKey = max(decodedStart, decodedEnd)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
            .flatMap(PairPlanIcon.init(rawValue:)) ?? .trip
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        checklist = try container.decodeIfPresent([PairPlanChecklistItem].self, forKey: .checklist) ?? []
        authorRole = try container.decodeIfPresent(PeerRole.self, forKey: .authorRole)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public var isSingleDay: Bool {
        startDayKey == endDayKey
    }

    public var todoItems: [PairPlanChecklistItem] {
        checklist.filter { $0.kind == .todo }
    }

    public var packingItems: [PairPlanChecklistItem] {
        checklist.filter { $0.kind == .packing }
    }

    public func contains(dayKey: String) -> Bool {
        dayKey >= startDayKey && dayKey <= endDayKey
    }

    public func overlaps(monthKey: String) -> Bool {
        guard !monthKey.isEmpty else { return false }
        let startMonth = String(startDayKey.prefix(7))
        let endMonth = String(endDayKey.prefix(7))
        return startMonth <= monthKey && monthKey <= endMonth
    }

    public func lifecycleStatus(asOfDayKey: String) -> PairPlanLifecycleStatus {
        if asOfDayKey < startDayKey { return .upcoming }
        if asOfDayKey > endDayKey { return .past }
        return .ongoing
    }

    public func daysUntilStart(
        asOfDayKey: String,
        calendar: Calendar = CalendarDateValue.gregorianCurrent
    ) -> Int? {
        guard let from = Self.calendarDateValue(from: asOfDayKey),
              let to = Self.calendarDateValue(from: startDayKey) else {
            return nil
        }
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = calendar.timeZone
        let startA = civil.startOfDay(for: from.toDate(calendar: civil))
        let startB = civil.startOfDay(for: to.toDate(calendar: civil))
        return civil.dateComponents([.day], from: startA, to: startB).day
    }

    public var spanDayCount: Int {
        guard let start = Self.calendarDateValue(from: startDayKey),
              let end = Self.calendarDateValue(from: endDayKey) else {
            return 1
        }
        let cal = CalendarDateValue.gregorianCurrent
        let d0 = cal.startOfDay(for: start.toDate(calendar: cal))
        let d1 = cal.startOfDay(for: end.toDate(calendar: cal))
        let diff = cal.dateComponents([.day], from: d0, to: d1).day ?? 0
        return max(1, diff + 1)
    }

    public func dayKeys(calendar: Calendar = CalendarDateValue.gregorianCurrent) -> [String] {
        guard let start = Self.calendarDateValue(from: startDayKey),
              let end = Self.calendarDateValue(from: endDayKey) else {
            return [startDayKey]
        }
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = calendar.timeZone
        let startDate = civil.startOfDay(for: start.toDate(calendar: civil))
        let endDate = civil.startOfDay(for: end.toDate(calendar: civil))
        var keys: [String] = []
        var cursor = startDate
        var safety = 0
        while cursor <= endDate && safety < 366 {
            keys.append(EncounterCalendarAggregator.dayKey(for: cursor, calendar: civil))
            guard let next = civil.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            safety += 1
        }
        return keys.isEmpty ? [startDayKey] : keys
    }

    public var formattedDateRange: String {
        guard let s = Self.calendarDateValue(from: startDayKey),
              let e = Self.calendarDateValue(from: endDayKey) else {
            return isSingleDay ? startDayKey : "\(startDayKey)〜\(endDayKey)"
        }
        if isSingleDay {
            return "\(s.month)月\(s.day)日"
        }
        if s.year != e.year {
            return "\(s.year)年\(s.month)月\(s.day)日〜\(e.year)年\(e.month)月\(e.day)日"
        }
        if s.month != e.month {
            return "\(s.month)月\(s.day)日〜\(e.month)月\(e.day)日"
        }
        return "\(s.month)月\(s.day)日〜\(e.day)日"
    }

    public func startDate(calendar: Calendar = CalendarDateValue.gregorianCurrent) -> Date {
        Self.dayKeyDate(startDayKey, calendar: calendar) ?? createdAt
    }

    public func endDate(calendar: Calendar = CalendarDateValue.gregorianCurrent) -> Date {
        Self.dayKeyDate(endDayKey, calendar: calendar) ?? createdAt
    }

    public static func calendarDateValue(from dayKey: String) -> CalendarDateValue? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return CalendarDateValue(year: year, month: month, day: day)
    }

    public static func dayKeyDate(
        _ dayKey: String,
        calendar: Calendar = CalendarDateValue.gregorianCurrent
    ) -> Date? {
        calendarDateValue(from: dayKey)?.toDate(calendar: calendar)
    }
}

public enum PairPlanAlbumResolver {
    public static func mediaAttachments(
        for plan: PairPlanEvent,
        in photos: [DayPhotoAttachment],
        pairID: UUID?
    ) -> [DayPhotoAttachment] {
        photos
            .filter { photo in
                guard pairID == nil || photo.pairID == nil || photo.pairID == pairID else { return false }
                if photo.planID == plan.id { return true }
                if photo.planID == nil {
                    return plan.contains(dayKey: photo.dayKey) && !photo.excludedPlanIDs.contains(plan.id)
                }
                return false
            }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                let lhsDate = lhs.capturedAt ?? lhs.createdAt
                let rhsDate = rhs.capturedAt ?? rhs.createdAt
                return (lhsDate, lhs.createdAt, lhs.id.uuidString) < (rhsDate, rhs.createdAt, rhs.id.uuidString)
            }
    }

    public static func placeTags(
        for plan: PairPlanEvent,
        in tags: [DayPlaceTag],
        pairID: UUID?
    ) -> [DayPlaceTag] {
        tags
            .filter { tag in
                guard pairID == nil || tag.pairID == nil || tag.pairID == pairID else { return false }
                return plan.contains(dayKey: tag.dayKey)
            }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                return (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
            }
    }

    public static func effectivePlan(
        for photo: DayPhotoAttachment,
        among plans: [PairPlanEvent]
    ) -> PairPlanEvent? {
        if let explicitID = photo.planID {
            return plans.first { $0.id == explicitID }
        }
        return plans
            .filter { $0.contains(dayKey: photo.dayKey) && !photo.excludedPlanIDs.contains($0.id) }
            .min { lhs, rhs in
                if lhs.spanDayCount != rhs.spanDayCount {
                    return lhs.spanDayCount < rhs.spanDayCount
                }
                if abs(lhs.updatedAt.timeIntervalSince(rhs.updatedAt)) >= 0.0005 {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}
