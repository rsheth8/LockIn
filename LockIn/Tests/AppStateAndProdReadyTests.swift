import XCTest
@testable import LockIn

final class ScheduleRefreshTaskTests: XCTestCase {
    func testStaleWhenScheduleMissing() {
        XCTAssertTrue(ScheduleRefreshTask.isStale(nil))
    }

    func testStaleWhenScheduleIsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let schedule = DaySchedule(
            date: yesterday,
            events: [],
            macros: MetabolicEngine.dailyTargets(for: Fixture.rahil),
            sleepPlan: SleepEngine.plan(for: Fixture.rahil, busyBlocks: [])
        )
        XCTAssertTrue(ScheduleRefreshTask.isStale(schedule))
    }

    func testNotStaleWhenScheduleIsToday() {
        let schedule = DaySchedule(
            date: Date(),
            events: [],
            macros: MetabolicEngine.dailyTargets(for: Fixture.rahil),
            sleepPlan: SleepEngine.plan(for: Fixture.rahil, busyBlocks: [])
        )
        XCTAssertFalse(ScheduleRefreshTask.isStale(schedule))
    }

    func testSecondsUntilMidnightIsPositiveAndUnderADay() {
        let seconds = ScheduleRefreshTask.secondsUntilNextMidnight()
        XCTAssertGreaterThan(seconds, 0)
        XCTAssertLessThanOrEqual(seconds, 86_400)
    }
}

/// `AppState` and `PersistenceStore` are main-actor confined (they own a
/// SwiftData `ModelContext`), so the tests that drive them are too.
@MainActor
final class AppStateCheckInTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Isolate from the developer's real on-device store.
        PersistenceStore.shared.clearAll()
    }

    func testConfirmUpdatesStatusAndDayRecord() {
        let state = AppState()
        state.saveProfile(Fixture.rahil)
        state.regenerateToday(calendarBusyBlocks: [])

        guard let event = state.todaySchedule?.events.first(where: { $0.kind == .wake }) else {
            return XCTFail("Expected a wake event")
        }
        state.confirm(event)

        XCTAssertEqual(state.todaySchedule?.events.first(where: { $0.id == event.id })?.status, .confirmed)
        XCTAssertEqual(state.dayRecords.last?.criticalConfirmed, 1)
    }

    func testMissResetsStreakForCriticalEvents() {
        let state = AppState()
        state.saveProfile(Fixture.rahil)
        state.streak.currentStreakDays = 5
        state.regenerateToday(calendarBusyBlocks: [])

        guard let event = state.todaySchedule?.events.first(where: { $0.isCritical && $0.kind == .wake }) else {
            return XCTFail("Expected a critical wake event")
        }
        state.markMissed(event)

        XCTAssertEqual(state.streak.currentStreakDays, 0)
        XCTAssertEqual(state.streak.lastMissedEvent, event.title)
    }

    func testWeighInWritesProfileWeight() {
        let state = AppState()
        state.saveProfile(Fixture.rahil)
        state.regenerateToday(calendarBusyBlocks: [])

        guard let event = state.todaySchedule?.events.first(where: { $0.kind == .weighIn }) else {
            return XCTFail("Expected a weigh-in event")
        }
        let health = HealthKitManager()
        state.applyWeighIn(pounds: 214.5, event: event, healthKit: health)

        XCTAssertEqual(state.profile.currentWeightLbs, 214.5, accuracy: 0.01)
        XCTAssertEqual(state.todaySchedule?.events.first(where: { $0.id == event.id })?.status, .confirmed)
        XCTAssertEqual(state.profile.weightHistory.last?.weightLbs, 214.5)
    }

    func testFullCriticalConfirmAdvancesStreakOnce() {
        let state = AppState()
        state.saveProfile(Fixture.rahil)
        state.regenerateToday(calendarBusyBlocks: [])

        guard let schedule = state.todaySchedule else {
            return XCTFail("Expected a schedule")
        }
        for event in schedule.events where event.isCritical {
            state.confirm(event)
        }
        XCTAssertGreaterThanOrEqual(state.streak.currentStreakDays, 1)
        let before = state.streak.currentStreakDays
        // Confirming again must not double-count the same day.
        if let wake = state.todaySchedule?.events.first(where: { $0.kind == .wake }) {
            state.confirm(wake)
        }
        XCTAssertEqual(state.streak.currentStreakDays, before)
    }
}

final class EquipmentAdaptationTests: XCTestCase {
    func testBodyweightTierReplacesBarbellSquat() {
        let session = WorkoutEngine.weeklySplit(for: [.fatLoss], equipment: [.bodyweightOnly])
            .first { $0.focus == .legs }
        let names = session?.exercises.map(\.name) ?? []
        XCTAssertFalse(names.contains(where: { $0.contains("Smith") || $0.contains("Barbell") }))
        XCTAssertTrue(names.contains("Air Squat"), "Expected Air Squat, got \(names)")
        XCTAssertTrue(session?.equipmentNote.lowercased().contains("bodyweight") == true)
    }

    func testFullGymKeepsBarbellWhenAvailable() {
        let session = WorkoutEngine.weeklySplit(for: [.fatLoss], equipment: [.fullGym])
            .first { $0.focus == .legs }
        XCTAssertEqual(session?.exercises.first?.name, "Back Squat")
    }

    func testHomeTierUsesDumbbellVariants() {
        let session = WorkoutEngine.weeklySplit(for: [.fatLoss], equipment: [.homeEquipment])
            .first { $0.focus == .legs }
        XCTAssertEqual(session?.exercises.first?.name, "Goblet Squat")
    }

    func testApartmentGymUsesSmithAndCables() {
        let session = WorkoutEngine.weeklySplit(
            for: [.fatLoss, .fastBowling],
            equipment: [.apartmentGym],
            assets: GymAsset.apartmentDefault
        ).first { $0.focus == .legs }
        XCTAssertEqual(session?.exercises.first?.name, "Smith Squat")
        let pull = WorkoutEngine.weeklySplit(
            for: [.fatLoss],
            equipment: [.apartmentGym],
            assets: GymAsset.apartmentDefault
        ).first { $0.focus == .pull }
        XCTAssertTrue(pull?.exercises.contains(where: { $0.name.contains("Cable") || $0.name.contains("Lat") }) == true)
    }

    func testPPLSplitIncludesPushPullLegs() {
        let focuses = WorkoutEngine.weeklySplit(for: [.fatLoss], equipment: [.apartmentGym]).map(\.focus)
        XCTAssertTrue(focuses.contains(.push))
        XCTAssertTrue(focuses.contains(.pull))
        XCTAssertTrue(focuses.contains(.legs))
    }
}

final class AccountabilityGoalCopyTests: XCTestCase {
    func testToughLoveUsesProfileGoalWeights() {
        let event = ScheduledEvent(kind: .workout, title: "Workout", detail: "",
                                   time: Date(), durationMinutes: 60, isCritical: true)
        let message = AccountabilityEngine.message(
            for: event, tier: 2, tone: .toughLove, streak: StreakStatus(),
            currentWeightLbs: 220, goalWeightLbs: 180
        )
        XCTAssertTrue(message.contains("220 to 180"), message)
    }

    func testHardcoreUsesGoalWeight() {
        let event = ScheduledEvent(kind: .meal, title: "Lunch", detail: "",
                                   time: Date(), durationMinutes: 25, isCritical: true)
        let message = AccountabilityEngine.message(
            for: event, tier: 2, tone: .hardcore, streak: StreakStatus(),
            currentWeightLbs: 200, goalWeightLbs: 175
        )
        XCTAssertTrue(message.contains("175"), message)
    }
}
