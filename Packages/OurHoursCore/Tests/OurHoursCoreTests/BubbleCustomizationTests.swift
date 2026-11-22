import Foundation
import Testing
@testable import OurHoursCore

struct BubbleCustomizationTests {
    @Test func catalogHasUniqueIDsAndCoversEveryEnumCase() {
        let allItems = BubbleUnlockCatalog.allItems
        let ids = allItems.map(\.id)
        #expect(Set(ids).count == ids.count)

        let colors = Set(allItems.compactMap { item -> BubbleColorTheme? in
            if case let .color(value) = item.payload { return value }
            return nil
        })
        #expect(colors == Set(BubbleColorTheme.allCases))

        let expressions = Set(allItems.compactMap { item -> BubbleExpression? in
            if case let .expression(value) = item.payload { return value }
            return nil
        })
        #expect(expressions == Set(BubbleExpression.allCases))

        let ears = Set(allItems.compactMap { item -> BubbleEars? in
            if case let .ears(value) = item.payload { return value }
            return nil
        })
        #expect(ears == Set(BubbleEars.allCases))

        let headwear = Set(allItems.compactMap { item -> BubbleHeadwear? in
            if case let .headwear(value) = item.payload { return value }
            return nil
        })
        #expect(headwear == Set(BubbleHeadwear.allCases))

        let outfits = Set(allItems.compactMap { item -> BubbleOutfit? in
            if case let .outfit(value) = item.payload { return value }
            return nil
        })
        #expect(outfits == Set(BubbleOutfit.allCases))

        let eyebrows = Set(allItems.compactMap { item -> BubbleEyebrows? in
            if case let .eyebrows(value) = item.payload { return value }
            return nil
        })
        #expect(eyebrows == Set(BubbleEyebrows.allCases))

        let facialHair = Set(allItems.compactMap { item -> BubbleFacialHair? in
            if case let .facialHair(value) = item.payload { return value }
            return nil
        })
        #expect(facialHair == Set(BubbleFacialHair.allCases))

        let eyewear = Set(allItems.compactMap { item -> BubbleEyewear? in
            if case let .eyewear(value) = item.payload { return value }
            return nil
        })
        #expect(eyewear == Set(BubbleEyewear.allCases))

        let moles = Set(allItems.compactMap { item -> BubbleMole? in
            if case let .mole(value) = item.payload { return value }
            return nil
        })
        #expect(moles == Set(BubbleMole.allCases))

        let makeups = Set(allItems.compactMap { item -> BubbleMakeup? in
            if case let .makeup(value) = item.payload { return value }
            return nil
        })
        #expect(makeups == Set(BubbleMakeup.allCases))

        for item in BubbleUnlockCatalog.unlockableItems {
            #expect(!item.isNoneSlot)
        }

        let coveredEvents = Set(allItems.compactMap { item -> BubbleEventKind? in
            if case let .event(eventKind) = item.requirement { return eventKind }
            return nil
        })
        #expect(coveredEvents == Set(BubbleEventKind.allCases))
    }

    @Test func progressionBoundariesUnlockWithinOneYearAndSeparateEventsAndSecret() {
        let zeroProgress = BubbleUnlockProgress(
            cumulativeSeconds: 0,
            effectiveDays: 0,
            hasDiscoveredSecretPop: false
        )
        #expect(zeroProgress.unlockedNonStarterItems.isEmpty)
        #expect(zeroProgress.unlockedItemIDs == BubbleUnlockCatalog.starterItemIDs)

        let almostYear = BubbleUnlockProgress(
            cumulativeSeconds: 1094 * 3600,
            effectiveDays: 364,
            hasDiscoveredSecretPop: false
        )
        #expect(!almostYear.unlockedItemIDs.contains("color.auroraPrism"))
        #expect(!almostYear.unlockedItemIDs.contains("headwear.crown"))
        #expect(!almostYear.unlockedItemIDs.contains("expression.royalSparkle"))
        #expect(!almostYear.unlockedItemIDs.contains("expression.poppedSurprise"))

        let fullYearNoSecretOrEvents = BubbleUnlockProgress(
            cumulativeSeconds: 1095 * 3600,
            effectiveDays: 365,
            hasDiscoveredSecretPop: false
        )
        let expectedTimeAndDayIDs = Set(
            BubbleUnlockCatalog.allItems
                .filter { !$0.requirement.isSecret && !$0.requirement.isEvent }
                .map(\.id)
        )
        #expect(fullYearNoSecretOrEvents.unlockedItemIDs == expectedTimeAndDayIDs)
        #expect(!fullYearNoSecretOrEvents.unlockedItemIDs.contains("expression.poppedSurprise"))
        #expect(!fullYearNoSecretOrEvents.unlockedItemIDs.contains("headwear.santaHat"))

        let withSecret = BubbleUnlockProgress(
            cumulativeSeconds: 0,
            effectiveDays: 0,
            hasDiscoveredSecretPop: true
        )
        #expect(withSecret.unlockedItemIDs.contains("expression.poppedSurprise"))

        let withChristmasAndAnniversary = BubbleUnlockProgress(
            cumulativeSeconds: 0,
            effectiveDays: 0,
            hasDiscoveredSecretPop: false,
            achievedEvents: [.winter, .christmas, .anniversary]
        )
        #expect(withChristmasAndAnniversary.unlockedItemIDs.contains("headwear.santaHat"))
        #expect(withChristmasAndAnniversary.unlockedItemIDs.contains("outfit.santaSuit"))
        #expect(withChristmasAndAnniversary.unlockedItemIDs.contains("facialHair.santaBeard"))
        #expect(withChristmasAndAnniversary.unlockedItemIDs.contains("headwear.snowmanHat"))
        #expect(withChristmasAndAnniversary.unlockedItemIDs.contains("headwear.tiara"))
    }

    @Test func decorationLoadoutSupportsSplitEarsHeadwearLegacyMigrationAndMultiMoles() throws {
        var loadout = BubbleDecorationLoadout(
            ears: .dogEars,
            headwear: .ribbon,
            outfit: .bowTie,
            moles: [.underLeftEye, .nearMouth, .none]
        )
        #expect(loadout.moles == [.underLeftEye, .nearMouth])
        loadout.toggleMole(.cheek)
        #expect(loadout.moles == [.underLeftEye, .nearMouth, .cheek])
        loadout.toggleMole(.nearMouth)
        #expect(loadout.moles == [.underLeftEye, .cheek])
        loadout.toggleMole(.none)
        #expect(loadout.moles.isEmpty)

        // Legacy headAccessory ("catEars") and legacy single mole ("cheek")
        let legacyEarsJSON = """
        {
          "headAccessory": "catEars",
          "outfit": "scarf",
          "mole": "cheek"
        }
        """
        let migratedEars = try JSONDecoder().decode(BubbleDecorationLoadout.self, from: Data(legacyEarsJSON.utf8))
        #expect(migratedEars.ears == .catEars)
        #expect(migratedEars.headwear == .none)
        #expect(migratedEars.outfit == .scarf)
        #expect(migratedEars.moles == [.cheek])

        // Legacy headAccessory ("crown") maps to headwear and missing makeup defaults to .none
        let legacyCrownJSON = """
        {
          "headAccessory": "crown"
        }
        """
        let migratedCrown = try JSONDecoder().decode(BubbleDecorationLoadout.self, from: Data(legacyCrownJSON.utf8))
        #expect(migratedCrown.ears == .none)
        #expect(migratedCrown.headwear == .crown)
        #expect(migratedCrown.makeup == .none)

        // Makeup round-trips and unknown raw values degrade to .none
        let withMakeup = BubbleDecorationLoadout(ears: .bunnyEars, makeup: .milkyWayGlow)
        let makeupData = try JSONEncoder().encode(withMakeup)
        let decodedMakeup = try JSONDecoder().decode(BubbleDecorationLoadout.self, from: makeupData)
        #expect(decodedMakeup.makeup == .milkyWayGlow)

        let unknownMakeupJSON = """
        {
          "makeup": "futureGalaxy",
          "eyewear": "grouchoGlasses"
        }
        """
        let fallbackMakeup = try JSONDecoder().decode(BubbleDecorationLoadout.self, from: Data(unknownMakeupJSON.utf8))
        #expect(fallbackMakeup.makeup == .none)
        #expect(fallbackMakeup.eyewear == .grouchoGlasses)
    }

    @Test func syncedRoleProfileRoundTripsRotationAndDecodesLegacyAndUnknownValues() throws {
        let base = Date(timeIntervalSinceReferenceDate: 12_345)
        let loadout = BubbleDecorationLoadout(
            ears: .dogEars,
            headwear: .tiara,
            outfit: .sailorCollar,
            eyebrows: .arched,
            facialHair: .catWhiskers,
            eyewear: .heartGlasses,
            moles: [.underLeftEye, .cheek]
        )
        let full = SyncedRoleProfile(
            bubbleColor: .auroraPrism,
            birthday: CalendarDateValue(year: 2000, month: 4, day: 12),
            avatarAssetID: UUID(),
            expression: .starry,
            expressionRotationPool: [.starry, .winkLeft, .heartEyes, .starry],
            decorations: loadout,
            updatedAt: base
        )
        let encoded = try JSONEncoder().encode(full)
        let decoded = try JSONDecoder().decode(SyncedRoleProfile.self, from: encoded)
        #expect(decoded == full)
        #expect(decoded.expressionRotationPool == [.starry, .winkLeft, .heartEyes])

        // Legacy profile without expression/rotation/decorations keys
        let legacyJSON = """
        {
          "bubbleColor": "mint",
          "updatedAt": \(base.timeIntervalSinceReferenceDate)
        }
        """
        let legacy = try JSONDecoder().decode(SyncedRoleProfile.self, from: Data(legacyJSON.utf8))
        #expect(legacy.bubbleColor == .mint)
        #expect(legacy.expression == .classic)
        #expect(legacy.expressionRotationPool.isEmpty)
        #expect(legacy.decorations == .none)

        // Unknown raw values degrade gracefully instead of failing decode
        let unknownJSON = """
        {
          "bubbleColor": "futureNeon",
          "expression": "futureSmile",
          "expressionRotationPool": ["winkLeft", "futureFace"],
          "decorations": {
            "ears": "futureEars",
            "headwear": "tiara",
            "outfit": "bowTie",
            "eyebrows": "futureBrows",
            "facialHair": "futureBeard",
            "eyewear": "futureShades",
            "moles": ["futureMole", "underLeftEye"]
          },
          "updatedAt": \(base.timeIntervalSinceReferenceDate)
        }
        """
        let fallback = try JSONDecoder().decode(SyncedRoleProfile.self, from: Data(unknownJSON.utf8))
        #expect(fallback.bubbleColor == .skyBlue)
        #expect(fallback.expression == .classic)
        #expect(fallback.expressionRotationPool == [.winkLeft])
        #expect(fallback.decorations.ears == .none)
        #expect(fallback.decorations.headwear == .tiara)
        #expect(fallback.decorations.outfit == .bowTie)
        #expect(fallback.decorations.moles == [.underLeftEye])
    }

    @Test func eventDetectorIdentifiesSeasonsHolidaysBirthdaysAndAnniversary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }

        let xmas = makeDate(2026, 12, 24)
        let xmasEvents = BubbleEventDetector.detectedEvents(
            asOf: xmas,
            anniversary: CalendarDateValue(year: 2025, month: 12, day: 24),
            myBirthday: CalendarDateValue(year: 1999, month: 12, day: 24),
            partnerBirthday: CalendarDateValue(year: 1998, month: 5, day: 10),
            calendar: cal
        )
        #expect(xmasEvents.contains(.winter))
        #expect(xmasEvents.contains(.christmas))
        #expect(xmasEvents.contains(.anniversary))
        #expect(xmasEvents.contains(.myBirthday))
        #expect(!xmasEvents.contains(.partnerBirthday))

        let valentines = makeDate(2026, 2, 14)
        let vEvents = BubbleEventDetector.detectedEvents(
            asOf: valentines,
            encounterDates: [makeDate(2026, 1, 2)],
            anniversary: nil,
            myBirthday: nil,
            partnerBirthday: nil,
            calendar: cal
        )
        #expect(vEvents.contains(.winter))
        #expect(vEvents.contains(.valentinesDay))
        #expect(vEvents.contains(.newYear))
    }

    @Test func eventDetectorHandlesEasterAndExpandedJapaneseEvents() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }

        #expect(BubbleEventDetector.gregorianEasterDate(year: 2025) == CalendarDateValue(year: 2025, month: 4, day: 20))
        #expect(BubbleEventDetector.gregorianEasterDate(year: 2026) == CalendarDateValue(year: 2026, month: 4, day: 5))
        #expect(BubbleEventDetector.gregorianEasterDate(year: 2027) == CalendarDateValue(year: 2027, month: 3, day: 28))
        #expect(BubbleEventDetector.gregorianEasterDate(year: 2028) == CalendarDateValue(year: 2028, month: 4, day: 16))

        let eventProbeDates: [(Date, BubbleEventKind)] = [
            (makeDate(2026, 2, 3), .setsubun),
            (makeDate(2026, 2, 11), .foundationDay),
            (makeDate(2026, 3, 3), .hinamatsuri),
            (makeDate(2026, 4, 1), .aprilFools),
            (makeDate(2026, 4, 5), .easter),
            (makeDate(2026, 3, 29), .easter),
            (makeDate(2026, 5, 5), .childrensDay),
            (makeDate(2026, 6, 20), .rainySeason),
            (makeDate(2026, 7, 7), .tanabata),
            (makeDate(2026, 8, 15), .summerFestival),
            (makeDate(2026, 9, 20), .otsukimi),
            (makeDate(2026, 12, 31), .newYearsEve)
        ]

        for (date, expectedEvent) in eventProbeDates {
            let detected = BubbleEventDetector.detectedEvents(
                asOf: date,
                anniversary: nil,
                myBirthday: nil,
                partnerBirthday: nil,
                calendar: cal
            )
            #expect(detected.contains(expectedEvent), "Expected \(expectedEvent.rawValue) on \(date)")
        }

        let nonEaster = BubbleEventDetector.detectedEvents(
            asOf: makeDate(2026, 4, 15),
            anniversary: nil,
            myBirthday: nil,
            partnerBirthday: nil,
            calendar: cal
        )
        #expect(!nonEaster.contains(.easter))
    }

    @Test func journalMergerPreferredProfileBreaksTiesDeterministically() {
        let base = Date(timeIntervalSinceReferenceDate: 100)
        let near = base.addingTimeInterval(0.0002)
        let lhs = SyncedRoleProfile(
            bubbleColor: .mint,
            birthday: nil,
            expression: .catMouth,
            expressionRotationPool: [.catMouth, .winkLeft],
            decorations: BubbleDecorationLoadout(ears: .bearEars, headwear: .ribbon, moles: [.underLeftEye, .cheek]),
            updatedAt: base
        )
        let rhs = SyncedRoleProfile(
            bubbleColor: .mint,
            birthday: nil,
            expression: .winkLeft,
            expressionRotationPool: [.winkLeft],
            decorations: BubbleDecorationLoadout(ears: .catEars, headwear: .tiara),
            updatedAt: near
        )
        let mergedLR = JournalMerger.merge(
            local: JournalSnapshot(roleProfiles: ["A": lhs]),
            remote: JournalSnapshot(roleProfiles: ["A": rhs])
        )
        let mergedRL = JournalMerger.merge(
            local: JournalSnapshot(roleProfiles: ["A": rhs]),
            remote: JournalSnapshot(roleProfiles: ["A": lhs])
        )
        #expect(mergedLR == mergedRL)
        #expect(mergedLR.profile(for: .partnerA) == lhs)
    }

    @Test func lifetimeMetDayCountCountsUniqueDaysAcrossOvernightAndSameDayEncounters() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        let pairID = UUID()
        let overnight = ManualEncounterRecord(
            id: UUID(),
            pairID: pairID,
            startedAt: makeDate(2026, 10, 1, 22, 0),
            endedAt: makeDate(2026, 10, 2, 9, 0),
            createdAt: makeDate(2026, 10, 1, 22, 0),
            updatedAt: makeDate(2026, 10, 1, 22, 0)
        )
        let sameDay = ManualEncounterRecord(
            id: UUID(),
            pairID: pairID,
            startedAt: makeDate(2026, 10, 2, 13, 0),
            endedAt: makeDate(2026, 10, 2, 15, 0),
            createdAt: makeDate(2026, 10, 2, 13, 0),
            updatedAt: makeDate(2026, 10, 2, 13, 0)
        )
        let separateDay = ManualEncounterRecord(
            id: UUID(),
            pairID: pairID,
            startedAt: makeDate(2026, 10, 5, 11, 0),
            endedAt: makeDate(2026, 10, 5, 14, 0),
            createdAt: makeDate(2026, 10, 5, 11, 0),
            updatedAt: makeDate(2026, 10, 5, 11, 0)
        )
        let journal = JournalSnapshot(manualRecords: [overnight, sameDay, separateDay])
        let metDays = EncounterCalendarAggregator.lifetimeMetDayCount(
            autoSessions: [],
            journal: journal,
            calendar: cal
        )
        #expect(metDays == 3)
    }
}
