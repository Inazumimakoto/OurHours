import Foundation
import Testing
@testable import OurHoursCore

struct DayMemoryTests {
    @Test func legacyV1PayloadsDecodeWithoutNewFields() throws {
        let json = """
        {
          "manualRecords": [],
          "sessionOverrides": [],
          "dailyMemos": {
            "2026-11-21": {
              "dayKey": "2026-11-21",
              "text": "Legacy memo",
              "updatedAt": 100
            }
          },
          "deletedManualRecords": [],
          "deletedSessionOverrides": [],
          "deletedMemoDays": {},
          "roleProfiles": {
            "A": {
              "bubbleColor": "skyBlue",
              "updatedAt": 100
            }
          }
        }
        """
        let decoded = try JSONDecoder().decode(JournalSnapshot.self, from: Data(json.utf8))
        #expect(decoded.dailyMemos["2026-11-21"]?.text == "Legacy memo")
        #expect(decoded.dailyMemos["2026-11-21"]?.authorRole == nil)
        #expect(decoded.roleProfiles["A"]?.avatarAssetID == nil)
        #expect(decoded.dayPhotos.isEmpty)
        #expect(decoded.deletedDayPhotos.isEmpty)
        #expect(decoded.dayPlaceTags.isEmpty)
        #expect(decoded.deletedDayPlaceTags.isEmpty)
    }

    @Test func journalStorePersistsPhotoPlaceTagsAvatarAndMemoAuthor() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("DayMemoryStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(directory: directory)
        let pairID = UUID()
        let avatarID = UUID()
        let enoshima = GeoCoordinate(latitude: 35.2999, longitude: 139.4803)

        let withProfile = try store.setRoleProfile(
            role: .partnerA, bubbleColor: .mint, birthday: nil, avatarAssetID: avatarID
        )
        #expect(withProfile.profile(for: .partnerA)?.avatarAssetID == avatarID)

        let withMemo = try store.setMemo(dayKey: "2026-11-21", text: "海に行った", pairID: pairID, authorRole: .partnerA)
        #expect(withMemo.dailyMemos["2026-11-21"]?.authorRole == .partnerA)

        let photo = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-21", authorRole: .partnerA,
            coordinate: enoshima, locationName: "  藤沢市  "
        )
        let afterPhoto = try store.addDayPhoto(photo)
        #expect(afterPhoto.dayPhotos.count == 1)
        #expect(afterPhoto.dayPhotos.first?.locationName == "藤沢市")
        #expect(afterPhoto.dayPhotos.first?.coordinate == enoshima)

        let updatedPhoto = try store.updateDayPhotoLocation(id: photo.id, coordinate: nil, locationName: nil)
        #expect(updatedPhoto.dayPhotos.first?.coordinate == nil)
        #expect(updatedPhoto.dayPhotos.first?.locationName == nil)

        let tag = DayPlaceTag(pairID: pairID, dayKey: "2026-11-21", name: " 江ノ島 ", address: "神奈川県藤沢市", coordinate: enoshima, authorRole: .partnerB)
        let afterTag = try store.addDayPlaceTag(tag)
        #expect(afterTag.dayPlaceTags.count == 1)
        #expect(afterTag.dayPlaceTags.first?.name == "江ノ島")

        let afterDeletes = try store.deleteDayPhoto(id: photo.id)
        #expect(afterDeletes.dayPhotos.isEmpty)
        #expect(afterDeletes.deletedDayPhotos[photo.id] != nil)

        let afterTagDelete = try store.deleteDayPlaceTag(id: tag.id)
        #expect(afterTagDelete.dayPlaceTags.isEmpty)
        #expect(afterTagDelete.deletedDayPlaceTags[tag.id] != nil)
    }

    @Test func journalMergerMergesPhotosPlaceTagsTombstonesAndAvatarTies() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let earlier = base
        let later = base.addingTimeInterval(5)
        let pairID = UUID()
        let photoKeepID = UUID()
        let photoDeleteID = UUID()
        let tagKeepID = UUID()
        let tagDeleteID = UUID()
        let avatarID = UUID()

        let coord = GeoCoordinate(latitude: 35.6481, longitude: 139.7032)

        let local = JournalSnapshot(
            roleProfiles: ["A": SyncedRoleProfile(bubbleColor: .skyBlue, birthday: nil, avatarAssetID: nil, updatedAt: base)],
            dayPhotos: [
                DayPhotoAttachment(id: photoKeepID, pairID: pairID, dayKey: "2026-11-20", coordinate: nil, createdAt: earlier, updatedAt: earlier),
                DayPhotoAttachment(id: photoDeleteID, pairID: pairID, dayKey: "2026-11-20", coordinate: coord, createdAt: earlier, updatedAt: earlier)
            ],
            deletedDayPhotos: [:],
            dayPlaceTags: [
                DayPlaceTag(id: tagKeepID, pairID: pairID, dayKey: "2026-11-21", name: "代官山", coordinate: coord, createdAt: earlier, updatedAt: later)
            ],
            deletedDayPlaceTags: [tagDeleteID: later]
        )

        let remote = JournalSnapshot(
            roleProfiles: ["A": SyncedRoleProfile(bubbleColor: .skyBlue, birthday: nil, avatarAssetID: avatarID, updatedAt: base)],
            dayPhotos: [
                DayPhotoAttachment(id: photoKeepID, pairID: pairID, dayKey: "2026-11-20", coordinate: coord, locationName: "渋谷区", createdAt: earlier, updatedAt: later)
            ],
            deletedDayPhotos: [photoDeleteID: later],
            dayPlaceTags: [
                DayPlaceTag(id: tagKeepID, pairID: pairID, dayKey: "2026-11-21", name: "旧名", coordinate: nil, createdAt: earlier, updatedAt: earlier),
                DayPlaceTag(id: tagDeleteID, pairID: pairID, dayKey: "2026-11-21", name: "削除済み", coordinate: coord, createdAt: earlier, updatedAt: earlier)
            ]
        )

        let merged = JournalMerger.merge(local: local, remote: remote)
        #expect(merged.profile(for: PeerRole.partnerA)?.avatarAssetID == avatarID)
        #expect(merged.dayPhotos.count == 1)
        #expect(merged.dayPhotos.first?.id == photoKeepID)
        #expect(merged.dayPhotos.first?.coordinate == coord)
        #expect(merged.dayPhotos.first?.locationName == "渋谷区")
        #expect(merged.deletedDayPhotos[photoDeleteID] == later)
        #expect(merged.dayPlaceTags.count == 1)
        #expect(merged.dayPlaceTags.first?.id == tagKeepID)
        #expect(merged.dayPlaceTags.first?.name == "代官山")
        #expect(merged.deletedDayPlaceTags[tagDeleteID] == later)
    }

    @Test func snapshotScopingAndUnscopedStampingHandlePhotosAndPlaceTags() {
        let pairA = UUID()
        let pairB = UUID()
        let snapshot = JournalSnapshot(
            dayPhotos: [
                DayPhotoAttachment(pairID: nil, dayKey: "2026-11-18"),
                DayPhotoAttachment(pairID: pairA, dayKey: "2026-11-19"),
                DayPhotoAttachment(pairID: pairB, dayKey: "2026-11-20")
            ],
            dayPlaceTags: [
                DayPlaceTag(pairID: nil, dayKey: "2026-11-18", name: "カフェ"),
                DayPlaceTag(pairID: pairB, dayKey: "2026-11-20", name: "公園")
            ]
        )

        let scopedA = snapshot.scoped(to: pairA)
        #expect(scopedA.dayPhotos.count == 2)
        #expect(scopedA.dayPlaceTags.count == 1)

        let stamped = scopedA.stampingUnscoped(with: pairA)
        #expect(stamped.dayPhotos.allSatisfy { $0.pairID == pairA })
        #expect(stamped.dayPlaceTags.allSatisfy { $0.pairID == pairA })
    }

    @Test func memoryMapPinBuilderClustersSameDayNearbyItemsAndExcludesInvalidCoordinates() {
        let pairID = UUID()
        let otherPairID = UUID()
        let enoshimaTag = DayPlaceTag(
            pairID: pairID, dayKey: "2026-11-20", name: "江ノ島", address: "神奈川県藤沢市",
            coordinate: GeoCoordinate(latitude: 35.2999, longitude: 139.4803)
        )
        let nearbyPhoto = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-20",
            coordinate: GeoCoordinate(latitude: 35.3005, longitude: 139.4809), // ~86m from tag
            locationName: "藤沢市"
        )
        let farSameDayPhoto = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-20",
            coordinate: GeoCoordinate(latitude: 35.4549, longitude: 139.6314), // Yokohama (~22km away)
            locationName: "みなとみらい"
        )
        let newerDayPhoto = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-21",
            coordinate: GeoCoordinate(latitude: 35.6481, longitude: 139.7032),
            locationName: nil
        )
        let invalidZero = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-19",
            coordinate: GeoCoordinate(latitude: 0, longitude: 0)
        )
        let textOnlyTag = DayPlaceTag(
            pairID: pairID, dayKey: "2026-11-19", name: "おうち映画", coordinate: nil
        )
        let wrongPairTag = DayPlaceTag(
            pairID: otherPairID, dayKey: "2026-11-21", name: "別ペア",
            coordinate: GeoCoordinate(latitude: 35.68, longitude: 139.76)
        )

        let journal = JournalSnapshot(
            dayPhotos: [nearbyPhoto, farSameDayPhoto, newerDayPhoto, invalidZero],
            dayPlaceTags: [enoshimaTag, textOnlyTag, wrongPairTag]
        )

        let pins = MemoryMapPinBuilder.buildPins(from: journal, pairID: pairID)
        #expect(pins.count == 3)
        #expect(pins[0].dayKey == "2026-11-21")
        #expect(pins[0].title == "11月21日")
        #expect(pins[0].photoIDs == [newerDayPhoto.id])

        let day20Pins = pins.filter { $0.dayKey == "2026-11-20" }
        #expect(day20Pins.count == 2)
        let clusteredPin = day20Pins.first { $0.placeTagIDs == [enoshimaTag.id] }
        #expect(clusteredPin?.title == "江ノ島")
        #expect(clusteredPin?.subtitle == "神奈川県藤沢市")
        #expect(clusteredPin?.photoIDs == [nearbyPhoto.id])

        let yokohamaPin = day20Pins.first { $0.title == "みなとみらい" }
        #expect(yokohamaPin?.photoIDs == [farSameDayPhoto.id])
    }

    @Test func roleMemosVideoDecodingAndPlaceTagLinkedMediaWorkAcrossMergeAndPins() throws {
        let legacyPhotoJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "dayKey": "2026-11-21",
          "createdAt": 100,
          "updatedAt": 100
        }
        """
        let decodedPhoto = try JSONDecoder().decode(DayPhotoAttachment.self, from: Data(legacyPhotoJSON.utf8))
        #expect(decodedPhoto.mediaKind == .photo)
        #expect(decodedPhoto.durationSeconds == nil)
        #expect(decodedPhoto.thumbnailAssetID == nil)
        #expect(decodedPhoto.placeTagID == nil)

        let directoryA = URL.temporaryDirectory.appendingPathComponent("RoleMemoA-\(UUID().uuidString)")
        let directoryB = URL.temporaryDirectory.appendingPathComponent("RoleMemoB-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }
        let pairID = UUID()
        let storeA = JournalStore(directory: directoryA)
        let storeB = JournalStore(directory: directoryB)

        _ = try storeA.setRoleMemo(dayKey: "2026-11-21", role: .partnerA, text: "今日は楽しかった！", pairID: pairID)
        _ = try storeB.setRoleMemo(dayKey: "2026-11-21", role: .partnerB, text: "また行こうね", pairID: pairID)

        let merged = JournalMerger.merge(local: try storeA.load(), remote: try storeB.load())
        #expect(merged.roleDailyMemos["2026-11-21_A"]?.text == "今日は楽しかった！")
        #expect(merged.roleDailyMemos["2026-11-21_B"]?.text == "また行こうね")
        #expect(merged.anyMemoText(forDayKey: "2026-11-21") != nil)

        let tag = DayPlaceTag(
            pairID: pairID, dayKey: "2026-11-21", name: "水族館",
            coordinate: GeoCoordinate(latitude: 35.3001, longitude: 139.4801)
        )
        let linkedVideo = DayPhotoAttachment(
            pairID: pairID, dayKey: "2026-11-21", authorRole: .partnerA,
            mediaKind: .video, durationSeconds: 8.5, thumbnailAssetID: UUID(),
            placeTagID: tag.id, coordinate: nil
        )
        let withMedia = JournalSnapshot(dayPhotos: [linkedVideo], dayPlaceTags: [tag])
        let pins = MemoryMapPinBuilder.buildPins(from: withMedia, pairID: pairID)
        #expect(pins.count == 1)
        #expect(pins.first?.photoIDs == [linkedVideo.id])
        #expect(pins.first?.placeTagIDs == [tag.id])
    }

    @Test func placeTagUpsertPhotoUnlinkAndUnlimitedSameDayPhotosMergeAndPinCleanly() throws {
        let dirA = URL.temporaryDirectory.appendingPathComponent("PlaceEditA-\(UUID().uuidString)")
        let dirB = URL.temporaryDirectory.appendingPathComponent("PlaceEditB-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }

        let pairID = UUID()
        let storeA = JournalStore(directory: dirA)
        let storeB = JournalStore(directory: dirB)

        let initialCoord = GeoCoordinate(latitude: 35.6580, longitude: 139.7016)
        let adjustedCoord = GeoCoordinate(latitude: 35.6591, longitude: 139.7024)
        let originalTag = DayPlaceTag(
            pairID: pairID,
            dayKey: "2026-11-22",
            name: "渋谷",
            address: "東京都渋谷区",
            coordinate: initialCoord,
            authorRole: .partnerA
        )
        let createdSnapshot = try storeA.addDayPlaceTag(originalTag)
        let createdAt = createdSnapshot.dayPlaceTags.first?.createdAt

        let editedTag = DayPlaceTag(
            id: originalTag.id,
            pairID: pairID,
            dayKey: "2026-11-22",
            name: "ブルーボトルコーヒー渋谷",
            address: "東京都渋谷区神南",
            coordinate: adjustedCoord,
            authorRole: .partnerA,
            createdAt: originalTag.createdAt,
            updatedAt: Date().addingTimeInterval(1)
        )
        let editedSnapshot = try storeA.addDayPlaceTag(editedTag)
        #expect(editedSnapshot.dayPlaceTags.count == 1)
        #expect(editedSnapshot.dayPlaceTags.first?.name == "ブルーボトルコーヒー渋谷")
        #expect(editedSnapshot.dayPlaceTags.first?.createdAt == createdAt)

        var lastSnapshot = editedSnapshot
        var addedIDs: [UUID] = []
        for idx in 0..<12 {
            let photo = DayPhotoAttachment(
                pairID: pairID,
                dayKey: "2026-11-22",
                authorRole: .partnerA,
                placeTagID: idx == 0 ? originalTag.id : nil,
                coordinate: idx == 0 ? adjustedCoord : nil,
                locationName: idx == 0 ? "ブルーボトルコーヒー渋谷" : nil
            )
            addedIDs.append(photo.id)
            lastSnapshot = try storeA.addDayPhoto(photo)
        }
        #expect(lastSnapshot.dayPhotos.count == 12)

        _ = try storeA.updateDayPhotoLocation(
            id: addedIDs[0],
            coordinate: adjustedCoord,
            locationName: "ブルーボトルコーヒー渋谷",
            placeTagID: nil
        )
        _ = try storeB.addDayPlaceTag(originalTag)

        let merged = JournalMerger.merge(local: try storeA.load(), remote: try storeB.load())
        #expect(merged.dayPlaceTags.count == 1)
        #expect(merged.dayPlaceTags.first?.name == "ブルーボトルコーヒー渋谷")
        #expect(merged.dayPhotos.count == 12)
        #expect(merged.dayPhotos.first(where: { $0.id == addedIDs[0] })?.placeTagID == nil)

        let pins = MemoryMapPinBuilder.buildPins(from: merged, pairID: pairID)
        #expect(pins.count == 1)
        #expect(pins.first?.title == "ブルーボトルコーヒー渋谷")
        #expect(pins.first?.photoIDs == [addedIDs[0]])
    }
}
