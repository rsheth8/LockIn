import XCTest
@testable import LockIn

/// Rahil's rhythm: wake 8:45 weekdays / 11:45 weekends, bed 1:00 AM, caffeine
/// done by 5 PM, train Mon–Thu. Term (Fall 2026) runs Sep 8 – Dec 11.
private enum Day {
    static let monday = Fixture.date(2026, 9, 14)     // STAT + CSCI 5521
    static let tuesday = Fixture.date(2026, 9, 8)     // CSCI 5715 only, term opener
    static let friday = Fixture.date(2026, 9, 11)     // STAT only, rest day
    static let saturday = Fixture.date(2026, 9, 12)   // no classes, no workout
}

final class SleepEngineTests: XCTestCase {

    private var profile: UserProfile { Fixture.rahil }

    func testWeekdayWakeIsFixedAtTheRhythmTime() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.tuesday)
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetWakeTime), 8)
        XCTAssertEqual(Calendar.current.component(.minute, from: plan.targetWakeTime), 45)
    }

    func testWeekendWakeUsesTheLaterSlot() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.saturday)
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetWakeTime), 11)
        XCTAssertEqual(Calendar.current.component(.minute, from: plan.targetWakeTime), 45)
    }

    /// The whole point of the redesign: a day with a 1:25 PM first class and a
    /// day with an 11:15 AM first class wake at the same time.
    func testWakeDoesNotFloatWithClassTimes() {
        let mon = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.monday)
        let tue = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.tuesday)
        XCTAssertEqual(Calendar.current.component(.hour, from: mon.targetWakeTime),
                       Calendar.current.component(.hour, from: tue.targetWakeTime))
        XCTAssertEqual(Calendar.current.component(.minute, from: mon.targetWakeTime),
                       Calendar.current.component(.minute, from: tue.targetWakeTime))
    }

    func testAnEarlyBlockPullsWakeBackByCommutePlusRoutine() {
        // 7:00 AM block on a weekday — earlier than the 8:45 default.
        let early = BusyBlock(title: "Field trip",
                              start: Fixture.date(2026, 9, 8, hour: 7),
                              end: Fixture.date(2026, 9, 8, hour: 9))
        let plan = SleepEngine.plan(for: profile, busyBlocks: [early], date: Day.tuesday)
        // lead (20 + 25) + 30 routine = 75 min before 7:00.
        let expected = Fixture.date(2026, 9, 8, hour: 5, minute: 45)
        XCTAssertEqual(plan.targetWakeTime.timeIntervalSince(expected), 0, accuracy: 60)
    }

    func testALaterClassNeverPushesWakePastTheRhythmTime() {
        // Tuesday's real 11:15 class is well after 8:45 — wake must stay at 8:45.
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.tuesday)
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetWakeTime), 8)
    }

    func testBedtimeIsOneAMTheFollowingMorning() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.monday)
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetBedTime), 1)
        XCTAssertGreaterThan(plan.targetBedTime, plan.targetWakeTime)
    }

    func testWindDownPrecedesBedByFortyFiveMinutes() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.monday)
        XCTAssertEqual(plan.targetBedTime.timeIntervalSince(plan.windDownStart), 45 * 60, accuracy: 1)
    }

    func testCaffeineCutoffIsFivePMAndPrecedesWindDown() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.monday)
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.caffeineCutoff), 17)
        XCTAssertLessThan(plan.caffeineCutoff, plan.windDownStart)
    }

    func testWeekdaySleepDurationIsAboutSevenAndThreeQuarterHours() {
        let plan = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.monday)
        XCTAssertEqual(plan.sleepDurationHours, 7.75, accuracy: 0.1)
    }
}

final class ScheduleEngineTests: XCTestCase {

    private func build(profile: UserProfile = Fixture.rahil, busy: [BusyBlock] = [],
                       date: Date = Day.tuesday) -> DaySchedule {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: busy, date: date)
        return ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                       busyBlocks: busy, date: date)
    }

    private func hour(_ event: ScheduledEvent?) -> Int? {
        event.map { Calendar.current.component(.hour, from: $0.time) }
    }

    // MARK: Structure

    func testEventsAreChronologicallySorted() {
        let events = build().events
        XCTAssertEqual(events.map(\.time), events.map(\.time).sorted())
    }

    func testDayContainsTheCoreRoutineEvents() {
        let kinds = Set(build().events.map(\.kind))
        for required in [EventKind.wake, .meal, .windDown, .sleep] {
            XCTAssertTrue(kinds.contains(required), "Missing \(required) from the day")
        }
    }

    func testAllEventsHaveNonEmptyTitles() {
        for event in build(date: Day.monday).events {
            XCTAssertFalse(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testMealCountMatchesProfilePreference() {
        var profile = Fixture.rahil
        profile.mealsPerDay = 3
        let meals = build(profile: profile).events.filter { $0.kind == .meal }
        XCTAssertEqual(meals.count, 3)
    }

    // MARK: Classes

    func testClassBlocksAppearForAStackedDay() {
        let classes = build(date: Day.monday).events.filter { $0.kind == .classSession }
        XCTAssertEqual(classes.count, 2, "Monday runs STAT 5421 then CSCI 5521")
        XCTAssertTrue(classes.contains { $0.title == "STAT 5421" })
        XCTAssertTrue(classes.contains { $0.title == "CSCI 5521" })
    }

    func testClassBlocksAreNotCriticalPromises() {
        for klass in build(date: Day.monday).events.filter({ $0.kind == .classSession }) {
            XCTAssertFalse(klass.isCritical, "A class is fixed structure, not a streak promise")
        }
    }

    func testNoClassBlocksBeforeTheTermStarts() {
        // Aug 27 2026 — before the Sep 8 term start.
        let classes = build(date: Fixture.date(2026, 8, 27)).events.filter { $0.kind == .classSession }
        XCTAssertTrue(classes.isEmpty)
    }

    func testALeaveByNudgePrecedesTheFirstClass() {
        let events = build(date: Day.monday).events
        guard let leave = events.first(where: { $0.kind == .commute }),
              let firstClass = events.filter({ $0.kind == .classSession }).min(by: { $0.time < $1.time }) else {
            return XCTFail("Expected a leave-by nudge and a class")
        }
        XCTAssertLessThan(leave.time, firstClass.time)
        // 20 + 25 minutes of lead.
        XCTAssertEqual(firstClass.time.timeIntervalSince(leave.time), 45 * 60, accuracy: 60)
    }

    func testLunchLandsBeforeTheAfternoonClassNotOnTopOfIt() {
        let events = build(date: Day.monday).events
        guard let stat = events.first(where: { $0.title == "STAT 5421" }) else { return XCTFail() }
        let lunch = events.filter { $0.kind == .meal }.first { m in
            let h = Calendar.current.component(.hour, from: m.time)
            return h >= 11 && h < 14
        }
        XCTAssertNotNil(lunch, "Expected a midday meal")
        XCTAssertLessThan(lunch!.time, stat.time, "Lunch must finish before the 1:25 class")
    }

    // MARK: Weigh-in / photo cadence

    func testWeighInAndPhotoAppearOnMondays() {
        let kinds = Set(build(date: Day.monday).events.map(\.kind))
        XCTAssertTrue(kinds.contains(.weighIn))
        XCTAssertTrue(kinds.contains(.progressPhoto))
    }

    func testNoWeighInOrPhotoOnOtherDays() {
        let kinds = Set(build(date: Day.tuesday).events.map(\.kind))
        XCTAssertFalse(kinds.contains(.weighIn))
        XCTAssertFalse(kinds.contains(.progressPhoto))
    }

    // MARK: Workout

    func testTrainsMondayThroughThursdayOnly() {
        XCTAssertEqual(build(date: Day.monday).events.filter { $0.kind == .workout }.count, 1)
        XCTAssertEqual(build(date: Day.tuesday).events.filter { $0.kind == .workout }.count, 1)
        XCTAssertTrue(build(date: Day.friday).events.filter { $0.kind == .workout }.isEmpty,
                      "Friday is a rest day")
        XCTAssertTrue(build(date: Day.saturday).events.filter { $0.kind == .workout }.isEmpty,
                      "Weekends are rest days")
    }

    func testWorkoutLandsAfterClassOnStackedDays() {
        let workout = build(date: Day.monday).events.first { $0.kind == .workout }
        XCTAssertGreaterThanOrEqual(hour(workout) ?? 0, 15, "Post-class on a Mon/Wed")
    }

    func testWorkoutLandsInEarlyAfternoonOnLightDays() {
        let workout = build(date: Day.tuesday).events.first { $0.kind == .workout }
        let h = hour(workout) ?? 0
        XCTAssertTrue((13...14).contains(h), "Early afternoon after lunch on a Tue/Thu, got hour \(h)")
    }

    func testWorkoutNeverOverlapsAClassBlock() {
        let events = build(date: Day.monday).events
        guard let workout = events.first(where: { $0.kind == .workout }) else { return XCTFail() }
        let wEnd = workout.time.addingTimeInterval(TimeInterval(workout.durationMinutes * 60))
        for klass in events.filter({ $0.kind == .classSession }) {
            let kEnd = klass.time.addingTimeInterval(TimeInterval(klass.durationMinutes * 60))
            XCTAssertFalse(workout.time < kEnd && wEnd > klass.time,
                           "Workout overlapped \(klass.title)")
        }
    }

    func testWorkoutDoesNotOverlapACalendarCommitment() {
        let busy = [BusyBlock(title: "Lab",
                              start: Fixture.date(2026, 9, 8, hour: 13),
                              end: Fixture.date(2026, 9, 8, hour: 18))]
        let schedule = build(busy: busy, date: Day.tuesday)
        guard let workout = schedule.events.first(where: { $0.kind == .workout }) else {
            return XCTFail("Expected a workout in the 18:00–21:00 gap")
        }
        let end = workout.time.addingTimeInterval(TimeInterval(workout.durationMinutes * 60))
        XCTAssertFalse(workout.time < busy[0].end && end > busy[0].start, "Workout overlapped a busy block")
    }

    func testNoWorkoutWhenTheAfternoonIsFullyBooked() {
        let busy = [BusyBlock(title: "All day",
                              start: Fixture.date(2026, 9, 8, hour: 12),
                              end: Fixture.date(2026, 9, 8, hour: 22))]
        let schedule = build(busy: busy, date: Day.tuesday)
        XCTAssertTrue(schedule.events.filter { $0.kind == .workout }.isEmpty)
    }

    func testWorkoutReflectsSelectedFitnessGoals() {
        var bowlerOnly = Fixture.rahil
        bowlerOnly.fitnessGoals = [.fatLoss, .fastBowling]
        let details = [Day.monday, Day.tuesday, Day.friday].compactMap { date -> String? in
            build(profile: bowlerOnly, date: date).events.first { $0.kind == .workout }?.detail
        }
        XCTAssertFalse(details.isEmpty)
        XCTAssertFalse(details.contains { $0.contains("Hiking") },
                       "Hiking sessions leaked in without the goal selected")
    }

    // MARK: Meals

    func testCriticalEventsAreFlaggedAndOptionalOnesAreNot() {
        let events = build(date: Day.monday).events
        XCTAssertEqual(events.first { $0.kind == .wake }?.isCritical, true)
        XCTAssertEqual(events.first { $0.kind == .progressPhoto }?.isCritical, false)
    }

    func testMealEventsCarryWeighableGramsAndMacros() {
        for meal in build().events.filter({ $0.kind == .meal }) {
            XCTAssertTrue(meal.detail.contains("g "), "Meal detail lacks gram amounts: \(meal.detail)")
            XCTAssertTrue(meal.detail.contains("kcal"), "Meal detail lacks macros: \(meal.detail)")
        }
    }

    func testPrepEventsPrecedeTheirMeal() {
        let events = build().events
        for prep in events.filter({ $0.kind == .mealPrep }) {
            guard let mealID = prep.linkedMealID,
                  let meal = events.first(where: { $0.linkedMealID == mealID && $0.kind == .meal }) else { continue }
            XCTAssertLessThan(prep.time, meal.time, "Prep for \(meal.title) was scheduled after the meal")
        }
    }

    func testLiveMealsOverrideTheLocalDatabase() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [], date: Day.tuesday)
        let live = MealEngine.assemble(from: Fixture.recipePool, macros: macros, profile: profile, date: Day.tuesday)

        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                               busyBlocks: [], date: Day.tuesday, liveMeals: live)
        let titles = schedule.events.filter { $0.kind == .meal }.map(\.title)
        XCTAssertTrue(titles.contains { Fixture.recipePool.map(\.title).contains($0) },
                      "Live meals should replace fallback meals, got \(titles)")
    }
}
