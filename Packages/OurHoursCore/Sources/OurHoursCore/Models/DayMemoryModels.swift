import Foundation

public struct GeoCoordinate: Codable, Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return false }
        // Reject uninitialized (0, 0) coordinates emitted by malformed EXIF/metadata.
        return !(abs(latitude) < 0.0001 && abs(longitude) < 0.0001)
    }

    public func distanceMeters(to other: GeoCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = latitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let dLat = (other.latitude - latitude) * .pi / 180.0
        let dLon = (other.longitude - longitude) * .pi / 180.0
        let sinHalfLat = sin(dLat / 2.0)
        let sinHalfLon = sin(dLon / 2.0)
        let a = sinHalfLat * sinHalfLat + cos(lat1) * cos(lat2) * sinHalfLon * sinHalfLon
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return earthRadiusMeters * c
    }
}

public enum DayMediaKind: String, Codable, Sendable, Equatable {
    case photo
    case video
}

public struct DayPhotoAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID?
    public let dayKey: String
    public let authorRole: PeerRole?
    public let mediaKind: DayMediaKind
    public let durationSeconds: Double?
    public let thumbnailAssetID: UUID?
    public let placeTagID: UUID?
    public let coordinate: GeoCoordinate?
    public let capturedAt: Date?
    public let locationName: String?
    public let planID: UUID?
    public let excludedPlanIDs: [UUID]
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case pairID
        case dayKey
        case authorRole
        case mediaKind
        case durationSeconds
        case thumbnailAssetID
        case placeTagID
        case coordinate
        case capturedAt
        case locationName
        case planID
        case excludedPlanIDs
        case createdAt
        case updatedAt
    }

    public init(
        id: UUID = UUID(),
        pairID: UUID? = nil,
        dayKey: String,
        authorRole: PeerRole? = nil,
        mediaKind: DayMediaKind = .photo,
        durationSeconds: Double? = nil,
        thumbnailAssetID: UUID? = nil,
        placeTagID: UUID? = nil,
        coordinate: GeoCoordinate? = nil,
        capturedAt: Date? = nil,
        locationName: String? = nil,
        planID: UUID? = nil,
        excludedPlanIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pairID = pairID
        self.dayKey = dayKey
        self.authorRole = authorRole
        self.mediaKind = mediaKind
        self.durationSeconds = durationSeconds
        self.thumbnailAssetID = thumbnailAssetID
        self.placeTagID = placeTagID
        self.coordinate = coordinate
        self.capturedAt = capturedAt
        self.locationName = locationName
        self.planID = planID
        var seen = Set<UUID>()
        self.excludedPlanIDs = excludedPlanIDs.filter { seen.insert($0).inserted }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pairID = try container.decodeIfPresent(UUID.self, forKey: .pairID)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        authorRole = try container.decodeIfPresent(PeerRole.self, forKey: .authorRole)
        mediaKind = try container.decodeIfPresent(DayMediaKind.self, forKey: .mediaKind) ?? .photo
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        thumbnailAssetID = try container.decodeIfPresent(UUID.self, forKey: .thumbnailAssetID)
        placeTagID = try container.decodeIfPresent(UUID.self, forKey: .placeTagID)
        coordinate = try container.decodeIfPresent(GeoCoordinate.self, forKey: .coordinate)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
        let rawExcluded = try container.decodeIfPresent([UUID].self, forKey: .excludedPlanIDs) ?? []
        var seen = Set<UUID>()
        excludedPlanIDs = rawExcluded.filter { seen.insert($0).inserted }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct DayPlaceTag: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pairID: UUID?
    public let dayKey: String
    public let name: String
    public let address: String?
    public let coordinate: GeoCoordinate?
    public let authorRole: PeerRole?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        pairID: UUID? = nil,
        dayKey: String,
        name: String,
        address: String? = nil,
        coordinate: GeoCoordinate? = nil,
        authorRole: PeerRole? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pairID = pairID
        self.dayKey = dayKey
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.authorRole = authorRole
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MemoryMapPin: Sendable, Equatable, Identifiable {
    public let id: String
    public let dayKey: String
    public let coordinate: GeoCoordinate
    public let title: String
    public let subtitle: String?
    public let photoIDs: [UUID]
    public let placeTagIDs: [UUID]

    public var hasPhotos: Bool { !photoIDs.isEmpty }
    public var hasPlaceTags: Bool { !placeTagIDs.isEmpty }

    public init(
        id: String,
        dayKey: String,
        coordinate: GeoCoordinate,
        title: String,
        subtitle: String?,
        photoIDs: [UUID],
        placeTagIDs: [UUID]
    ) {
        self.id = id
        self.dayKey = dayKey
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.photoIDs = photoIDs
        self.placeTagIDs = placeTagIDs
    }
}

public enum MemoryMapPinBuilder {
    private struct PinCluster {
        let primaryID: UUID
        let dayKey: String
        var coordinate: GeoCoordinate
        var title: String
        var subtitle: String?
        var hasExplicitTitle: Bool
        var photoIDs: [UUID]
        var placeTagIDs: [UUID]
    }

    public static func buildPins(
        from journal: JournalSnapshot,
        pairID: UUID?,
        clusterRadiusMeters: Double = 150
    ) -> [MemoryMapPin] {
        let placeTags = journal.dayPlaceTags.filter { tag in
            (pairID == nil || tag.pairID == nil || tag.pairID == pairID)
                && (tag.coordinate?.isValid == true)
        }
        let validTagByID = Dictionary(uniqueKeysWithValues: placeTags.map { ($0.id, $0) })

        let photos = journal.dayPhotos.filter { photo in
            guard pairID == nil || photo.pairID == nil || photo.pairID == pairID else { return false }
            if photo.coordinate?.isValid == true { return true }
            if let linkedID = photo.placeTagID, validTagByID[linkedID] != nil { return true }
            return false
        }

        let photosByDay = Dictionary(grouping: photos, by: \.dayKey)
        let tagsByDay = Dictionary(grouping: placeTags, by: \.dayKey)
        let allDays = Set(photosByDay.keys).union(tagsByDay.keys)
        var pins: [MemoryMapPin] = []

        for dayKey in allDays {
            var clusters: [PinCluster] = []
            var clusterIndexByTagID: [UUID: Int] = [:]

            let sortedTags = (tagsByDay[dayKey] ?? []).sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            for tag in sortedTags {
                guard let coord = tag.coordinate, coord.isValid else { continue }
                if let index = nearestClusterIndex(to: coord, in: clusters, maxDistance: clusterRadiusMeters) {
                    clusters[index].placeTagIDs.append(tag.id)
                    clusterIndexByTagID[tag.id] = index
                    if clusters[index].subtitle == nil, let addr = nonEmpty(tag.address) {
                        clusters[index].subtitle = addr
                    }
                } else {
                    let index = clusters.count
                    clusters.append(PinCluster(
                        primaryID: tag.id,
                        dayKey: dayKey,
                        coordinate: coord,
                        title: tag.name,
                        subtitle: nonEmpty(tag.address),
                        hasExplicitTitle: true,
                        photoIDs: [],
                        placeTagIDs: [tag.id]
                    ))
                    clusterIndexByTagID[tag.id] = index
                }
            }

            let sortedPhotos = (photosByDay[dayKey] ?? []).sorted {
                let lhsDate = $0.capturedAt ?? $0.createdAt
                let rhsDate = $1.capturedAt ?? $1.createdAt
                return (lhsDate, $0.createdAt, $0.id.uuidString) < (rhsDate, $1.createdAt, $1.id.uuidString)
            }
            for photo in sortedPhotos {
                if let linkedID = photo.placeTagID, let index = clusterIndexByTagID[linkedID] {
                    clusters[index].photoIDs.append(photo.id)
                    continue
                }
                guard let coord = photo.coordinate, coord.isValid else { continue }
                if let index = nearestClusterIndex(to: coord, in: clusters, maxDistance: clusterRadiusMeters) {
                    clusters[index].photoIDs.append(photo.id)
                    if !clusters[index].hasExplicitTitle, let name = nonEmpty(photo.locationName) {
                        clusters[index].title = name
                        clusters[index].hasExplicitTitle = true
                    }
                } else {
                    let locationName = nonEmpty(photo.locationName)
                    clusters.append(PinCluster(
                        primaryID: photo.id,
                        dayKey: dayKey,
                        coordinate: coord,
                        title: locationName ?? formattedDayTitle(dayKey),
                        subtitle: nil,
                        hasExplicitTitle: locationName != nil,
                        photoIDs: [photo.id],
                        placeTagIDs: []
                    ))
                }
            }

            for cluster in clusters {
                pins.append(MemoryMapPin(
                    id: "\(dayKey)_\(cluster.primaryID.uuidString)",
                    dayKey: cluster.dayKey,
                    coordinate: cluster.coordinate,
                    title: cluster.title,
                    subtitle: cluster.subtitle,
                    photoIDs: cluster.photoIDs,
                    placeTagIDs: cluster.placeTagIDs
                ))
            }
        }

        return pins.sorted {
            if $0.dayKey == $1.dayKey { return $0.id < $1.id }
            return $0.dayKey > $1.dayKey
        }
    }

    private static func nearestClusterIndex(
        to coordinate: GeoCoordinate,
        in clusters: [PinCluster],
        maxDistance: Double
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance = maxDistance
        for (index, cluster) in clusters.enumerated() {
            let distance = cluster.coordinate.distanceMeters(to: coordinate)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public static func formattedDayTitle(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return dayKey
        }
        return "\(month)月\(day)日"
    }
}
