import XCTest
@testable import LockIn

final class DayRecordTests: XCTestCase {

    func testAdherenceIsConfirmedOverTotal() {
        XCTAssertEqual(Fixture.dayRecord(daysAgo: 1, total: 8, confirmed: 6).adherence, 0.75, accuracy: 0.001)
    }

    func testAdherenceIsZeroRatherThanNaNWhenNothingWasTracked() {
        let record = Fixture.dayRecord(daysAgo: 1, total: 0, confirmed: 0)
        XCTAssertEqual(record.adherence, 0)
        XCTAssertFalse(record.adherence.isNaN)
    }

    func testCleanRequiresEverythingConfirmedAndNothingMissed() {
        XCTAssertTrue(Fixture.dayRecord(daysAgo: 1, total: 9, confirmed: 9).isClean)
        XCTAssertFalse(Fixture.dayRecord(daysAgo: 1, total: 9, confirmed: 8).isClean)
        XCTAssertFalse(Fixture.dayRecord(daysAgo: 1, total: 9, confirmed: 9, missed: 1).isClean)
    }

    func testUntrackedDayIsNotClean() {
        XCTAssertFalse(Fixture.dayRecord(daysAgo: 1, total: 0, confirmed: 0).isClean,
                       "A day with nothing planned must not count as a win")
    }

    func testDayKeyIsStableAndSortable() {
        let key = DayRecord.key(for: Fixture.date(2026, 3, 7))
        XCTAssertEqual(key, "2026-03-07")
        XCTAssertLessThan(DayRecord.key(for: Fixture.date(2026, 3, 7)),
                          DayRecord.key(for: Fixture.date(2026, 3, 8)))
    }

    func testDayKeyIsIndependentOfTimeOfDay() {
        XCTAssertEqual(DayRecord.key(for: Fixture.date(2026, 3, 7, hour: 0, minute: 1)),
                       DayRecord.key(for: Fixture.date(2026, 3, 7, hour: 23, minute: 59)))
    }
}

final class AccountabilityEngineTests: XCTestCase {

    private var event: ScheduledEvent {
        ScheduledEvent(kind: .workout, title: "Workout", detail: "",
                       time: Date(), durationMinutes: 60, isCritical: true)
    }

    func testEveryToneAndTierProducesNonEmptyDistinctCopy() {
        for tone in ToneIntensity.allCases {
            var seen = Set<String>()
            for tier in 0...2 {
                let message = AccountabilityEngine.message(for: event, tier: tier, tone: tone,
                                                           streak: StreakStatus())
                XCTAssertFalse(message.isEmpty, "\(tone) tier \(tier) produced empty copy")
                XCTAssertTrue(seen.insert(message).inserted,
                              "\(tone) repeated the same line across tiers")
            }
        }
    }

    func testMessagesNameTheEvent() {
        for tone in ToneIntensity.allCases {
            let message = AccountabilityEngine.message(for: event, tier: 0, tone: tone, streak: StreakStatus())
            XCTAssertTrue(message.contains("Workout"), "\(tone) didn't reference the event: \(message)")
        }
    }

    func testEscalationGetsLongerAsTiersRise() {
        let tier0 = AccountabilityEngine.message(for: event, tier: 0, tone: .toughLove, streak: StreakStatus())
        let tier2 = AccountabilityEngine.message(for: event, tier: 2, tone: .toughLove, streak: StreakStatus())
        XCTAssertGreaterThan(tier2.count, tier0.count, "Later tiers should carry more weight")
    }

    /// The tone is meant to attack the lapse, never the person. This guards
    /// against a future edit sliding into genuine abuse.
    func testCopyNeverAttacksTheUsersWorth() {
        let banned = ["worthless", "pathetic", "loser", "disgusting", "failure", "stupid", "fat pig", "hate yourself"]
        for tone in ToneIntensity.allCases {
            for tier in 0...2 {
                let message = AccountabilityEngine.message(for: event, tier: tier, tone: tone,
                                                           streak: StreakStatus()).lowercased()
                for word in banned {
                    XCTAssertFalse(message.contains(word),
                                   "\(tone) tier \(tier) contained \"\(word)\": \(message)")
                }
            }
        }
    }

    func testStreakIsReferencedWhenOneIsAtRisk() {
        var streak = StreakStatus()
        streak.currentStreakDays = 12
        let message = AccountabilityEngine.message(for: event, tier: 2, tone: .toughLove, streak: streak)
        XCTAssertTrue(message.contains("12"), "A live streak should be named as the thing at stake")
    }

    func testWinMessageOnlyFiresOnWeeklyMilestones() {
        for day in 1...21 {
            var streak = StreakStatus()
            streak.currentStreakDays = day
            let message = AccountabilityEngine.winMessage(streak: streak)
            if day % 7 == 0 {
                XCTAssertNotNil(message, "Day \(day) should be a milestone")
            } else {
                XCTAssertNil(message, "Day \(day) should stay quiet")
            }
        }
    }

    func testNoWinMessageAtZeroStreak() {
        XCTAssertNil(AccountabilityEngine.winMessage(streak: StreakStatus()))
    }
}

final class WeightSyncEngineTests: XCTestCase {

    func testSyncIsDueWhenNoHistoryExists() {
        var profile = Fixture.rahil
        profile.weightHistory = []
        XCTAssertTrue(WeightSyncEngine.shouldSync(profile: profile))
    }

    func testSyncIsNotDueImmediatelyAfterAReading() {
        var profile = Fixture.rahil
        profile.weightHistory = [WeightEntry(date: Date(), weightLbs: 220)]
        XCTAssertFalse(WeightSyncEngine.shouldSync(profile: profile))
    }

    func testSyncBecomesDueAfterTheInterval() {
        var profile = Fixture.rahil
        profile.weightHistory = [WeightEntry(date: Date().addingTimeInterval(-21 * 3600), weightLbs: 220)]
        XCTAssertTrue(WeightSyncEngine.shouldSync(profile: profile))
    }
}

final class RecipeCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private var cache: RecipeCache!
    private let suite = "RecipeCacheTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        cache = RecipeCache(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testPoolRoundTripsThroughTheCache() {
        let signature = RecipeCache.signature(calories: 2149, profile: Fixture.rahil)
        cache.store(pool: Fixture.recipePool, signature: signature)
        XCTAssertEqual(cache.cachedPool(signature: signature)?.map(\.id), Fixture.recipePool.map(\.id))
    }

    func testCacheMissesWhenCalorieTargetChanges() {
        cache.store(pool: Fixture.recipePool,
                    signature: RecipeCache.signature(calories: 2149, profile: Fixture.rahil))
        // A new calorie goal must not keep serving last week's numbers.
        XCTAssertNil(cache.cachedPool(signature: RecipeCache.signature(calories: 1800, profile: Fixture.rahil)))
    }

    func testCacheMissesWhenDietChanges() {
        cache.store(pool: Fixture.recipePool,
                    signature: RecipeCache.signature(calories: 2149, profile: Fixture.rahil))
        XCTAssertNil(cache.cachedPool(signature: RecipeCache.signature(calories: 2149, profile: Fixture.vegan)))
    }

    func testSignatureIncludesDietCuisineAndAllergies() {
        var withAllergy = Fixture.rahil
        withAllergy.allergies = ["peanut"]
        XCTAssertNotEqual(RecipeCache.signature(calories: 2000, profile: Fixture.rahil),
                          RecipeCache.signature(calories: 2000, profile: withAllergy))
    }

    func testSignatureIsStableForIdenticalInputs() {
        XCTAssertEqual(RecipeCache.signature(calories: 2000, profile: Fixture.rahil),
                       RecipeCache.signature(calories: 2000, profile: Fixture.rahil))
    }

    func testQuotaBlockPersistsAndClears() {
        XCTAssertFalse(cache.isQuotaBlocked)
        cache.markQuotaExceeded()
        XCTAssertTrue(cache.isQuotaBlocked, "A 402 should stop further calls today")
        cache.clear()
        XCTAssertFalse(cache.isQuotaBlocked)
    }
}
