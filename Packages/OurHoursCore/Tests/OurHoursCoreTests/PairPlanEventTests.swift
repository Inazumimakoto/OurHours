import Foundation
import Testing
@testable import OurHoursCore

struct PairPlanEventTests {
    @Test func legacyPayloadsDecodeWithoutPlanFields() throws {
        let legacySnapshotJSON = """
        {
          "manualRecords": [],
          "sessionOverrides": [],
          "dailyMemos": {},
          "deletedManualRecords": [],
          "deletedSessionOverrides": [],
          "deletedMemoDays": {},
          "roleProfiles": {},
          "dayPhotos": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "dayKey": "2026-11-20",
              "createdAt": 100,
              "updatedAt": 100
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(JournalSnapshot.self, from: Data(legacySnapshotJSON.utf8))
        #expect(decoded.planEvents.isEmpty)
        #expect(decoded.deletedPlanEvents.isEmpty)
        #expect(decoded.dayPhotos.count == 1)
        #expect(decoded.dayPhotos.first?.planID == nil)
        #expect(decoded.dayPhotos.first?.excludedPlanIDs.isEmpty == true)
    }

    @Test func planEventNormalizesRangeAndComputesLifecycleAndLabels() {
        let plan = PairPlanEvent(
            title: "京都旅行",
            startDayKey: "2026-11-25",
            endDayKey: "2026-11-22",
            icon: .trip
        )
        #expect(plan.startDayKey == "2026-11-22")
        #expect(plan.endDayKey == "2026-11-25")
        #expect(!plan.isSingleDay)
        #expect(plan.spanDayCount == 4)
        #expect(plan.contains(dayKey: "2026-11-23"))
        #expect(!plan.contains(dayKey: "2026-11-26"))
        #expect(plan.overlaps(monthKey: "2026-11"))
        #expect(!plan.overlaps(monthKey: "2026-12"))
        #expect(plan.formattedDateRange == "11月22日〜25日")

        #expect(plan.lifecycleStatus(asOfDayKey: "2026-11-20") == .upcoming)
        #expect(plan.daysUntilStart(asOfDayKey: "2026-11-20") == 2)
        #expect(plan.lifecycleStatus(asOfDayKey: "2026-11-23") == .ongoing)
        #expect(plan.lifecycleStatus(asOfDayKey: "2026-11-26") == .past)

        let crossYear = PairPlanEvent(
            title: "年末年始",
            startDayKey: "2026-12-30",
            endDayKey: "2027-01-02",
            icon: .stay
        )
        #expect(crossYear.overlaps(monthKey: "2026-12"))
        #expect(crossYear.overlaps(monthKey: "2027-01"))
        #expect(crossYear.formattedDateRange == "2026年12月30日〜2027年1月2日")
    }

    @Test func journalStorePersistsPlansAndUpdatesAndPreservesPhotoPlanAssignments() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("PairPlanStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(directory: directory)
        let pairID = UUID()

        let plan = PairPlanEvent(
            pairID: pairID,
            title: "  箱根温泉  ",
            startDayKey: "2026-11-28",
            endDayKey: "2026-11-29",
            icon: .stay,
            memo: "  露天風呂  ",
            checklist: [
                PairPlanChecklistItem(title: "  切符予約 ", isDone: true),
                PairPlanChecklistItem(title: "   ", isDone: false)
            ],
            authorRole: .partnerA
        )
        let afterUpsert = try store.upsertPlanEvent(plan)
        #expect(afterUpsert.planEvents.count == 1)
        #expect(afterUpsert.planEvents.first?.title == "箱根温泉")
        #expect(afterUpsert.planEvents.first?.memo == "露天風呂")
        #expect(afterUpsert.planEvents.first?.checklist.count == 1)
        #expect(afterUpsert.planEvents.first?.checklist.first?.title == "切符予約")
        #expect(afterUpsert.planEvents.first?.checklist.first?.kind == .todo)

        let categorized = PairPlanEvent(
            id: plan.id,
            pairID: pairID,
            title: "箱根温泉",
            startDayKey: "2026-11-28",
            endDayKey: "2026-11-29",
            icon: .stay,
            checklist: [
                PairPlanChecklistItem(title: "温泉めぐり", isDone: false, kind: .todo),
                PairPlanChecklistItem(title: "歯ブラシ", isDone: true, kind: .packing)
            ],
            authorRole: .partnerA
        )
        let afterCategories = try store.upsertPlanEvent(categorized)
        #expect(afterCategories.planEvents.first?.todoItems.map(\.title) == ["温泉めぐり"])
        #expect(afterCategories.planEvents.first?.packingItems.map(\.title) == ["歯ブラシ"])

        // Legacy checklist items without "kind" decode as .todo
        let legacyChecklistJSON = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "title": "ランチ",
          "isDone": false
        }
        """
        let decodedLegacyItem = try JSONDecoder().decode(PairPlanChecklistItem.self, from: Data(legacyChecklistJSON.utf8))
        #expect(decodedLegacyItem.kind == .todo)

        let coord = GeoCoordinate(latitude: 35.2323, longitude: 139.1069)
        let photo = DayPhotoAttachment(
            pairID: pairID,
            dayKey: "2026-11-28",
            coordinate: coord,
            planID: plan.id
        )
        _ = try store.addDayPhoto(photo)

        let afterLocation = try store.updateDayPhotoLocation(
            id: photo.id,
            coordinate: coord,
            locationName: "箱根湯本",
            placeTagID: nil
        )
        #expect(afterLocation.dayPhotos.first?.planID == plan.id)
        #expect(afterLocation.dayPhotos.first?.locationName == "箱根湯本")

        let afterExclude = try store.updateDayPhotoPlanAssignment(
            id: photo.id,
            planID: nil,
            excludedPlanIDs: [plan.id, plan.id]
        )
        #expect(afterExclude.dayPhotos.first?.planID == nil)
        #expect(afterExclude.dayPhotos.first?.excludedPlanIDs == [plan.id])

        _ = try store.updateDayPhotoPlanAssignment(id: photo.id, planID: plan.id, excludedPlanIDs: [])
        let afterDelete = try store.deletePlanEvent(id: plan.id)
        #expect(afterDelete.planEvents.isEmpty)
        #expect(afterDelete.deletedPlanEvents[plan.id] != nil)
        #expect(afterDelete.dayPhotos.first?.planID == nil)
        #expect(afterDelete.dayPhotos.first?.excludedPlanIDs.isEmpty == true)
    }

    @Test func journalMergerAndScopingHandlePlanEventsAndAssignments() {
        let base = Date(timeIntervalSinceReferenceDate: 2_000)
        let later = base.addingTimeInterval(10)
        let pairA = UUID()
        let pairB = UUID()

        let keepID = UUID()
        let deleteID = UUID()

        let local = JournalSnapshot(
            dayPhotos: [
                DayPhotoAttachment(id: UUID(), pairID: nil, dayKey: "2026-11-20", planID: keepID, createdAt: base, updatedAt: base)
            ],
            planEvents: [
                PairPlanEvent(id: keepID, pairID: pairA, title: "古いタイトル", startDayKey: "2026-11-20", endDayKey: "2026-11-21", createdAt: base, updatedAt: base),
                PairPlanEvent(id: deleteID, pairID: pairA, title: "削除予定", startDayKey: "2026-11-25", endDayKey: "2026-11-25", createdAt: base, updatedAt: base)
            ]
        )
        let remote = JournalSnapshot(
            planEvents: [
                PairPlanEvent(id: keepID, pairID: pairA, title: "新しいタイトル", startDayKey: "2026-11-20", endDayKey: "2026-11-22", createdAt: base, updatedAt: later),
                PairPlanEvent(id: UUID(), pairID: pairB, title: "他ペア", startDayKey: "2026-11-10", endDayKey: "2026-11-10", createdAt: base, updatedAt: later)
            ],
            deletedPlanEvents: [deleteID: later]
        )

        let merged = JournalMerger.merge(local: local, remote: remote)
        #expect(merged.planEvents.count == 2)
        #expect(merged.planEvents.first(where: { $0.id == keepID })?.title == "新しいタイトル")
        #expect(merged.deletedPlanEvents[deleteID] == later)

        let scopedA = merged.scoped(to: pairA)
        #expect(scopedA.planEvents.count == 1)
        #expect(scopedA.planEvents.first?.id == keepID)

        let stamped = scopedA.stampingUnscoped(with: pairA)
        #expect(stamped.dayPhotos.first?.pairID == pairA)
        #expect(stamped.dayPhotos.first?.planID == keepID)
    }

    @Test func albumResolverMatchesByRangeOverridesAndExclusions() {
        let pairID = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 5_000)

        let trip = PairPlanEvent(
            pairID: pairID,
            title: "沖縄旅行",
            startDayKey: "2026-11-10",
            endDayKey: "2026-11-12",
            icon: .trip,
            createdAt: base,
            updatedAt: base
        )
        let dinner = PairPlanEvent(
            pairID: pairID,
            title: "初日ディナー",
            startDayKey: "2026-11-10",
            endDayKey: "2026-11-10",
            icon: .gourmet,
            createdAt: base,
            updatedAt: base
        )

        let autoPhoto = DayPhotoAttachment(pairID: pairID, dayKey: "2026-11-11", createdAt: base, updatedAt: base)
        let explicitOutsidePhoto = DayPhotoAttachment(pairID: pairID, dayKey: "2026-11-13", planID: trip.id, createdAt: base, updatedAt: base)
        let explicitDinnerOnly = DayPhotoAttachment(pairID: pairID, dayKey: "2026-11-10", planID: dinner.id, createdAt: base, updatedAt: base)
        let excludedPhoto = DayPhotoAttachment(pairID: pairID, dayKey: "2026-11-12", excludedPlanIDs: [trip.id], createdAt: base, updatedAt: base)
        let sharedDay10 = DayPhotoAttachment(pairID: pairID, dayKey: "2026-11-10", createdAt: base, updatedAt: base)

        let allPhotos = [autoPhoto, explicitOutsidePhoto, explicitDinnerOnly, excludedPhoto, sharedDay10]
        let tripMedia = PairPlanAlbumResolver.mediaAttachments(for: trip, in: allPhotos, pairID: pairID)
        #expect(Set(tripMedia.map(\.id)) == Set([sharedDay10.id, autoPhoto.id, explicitOutsidePhoto.id]))

        let dinnerMedia = PairPlanAlbumResolver.mediaAttachments(for: dinner, in: allPhotos, pairID: pairID)
        #expect(Set(dinnerMedia.map(\.id)) == Set([sharedDay10.id, explicitDinnerOnly.id]))

        #expect(PairPlanAlbumResolver.effectivePlan(for: sharedDay10, among: [trip, dinner])?.id == dinner.id)
        #expect(PairPlanAlbumResolver.effectivePlan(for: explicitOutsidePhoto, among: [trip, dinner])?.id == trip.id)
        #expect(PairPlanAlbumResolver.effectivePlan(for: excludedPhoto, among: [trip, dinner]) == nil)
    }
}
