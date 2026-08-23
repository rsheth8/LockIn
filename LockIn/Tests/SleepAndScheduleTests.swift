import XCTest
@testable import LockIn

final class SleepEngineTests: XCTestCase {

    func testWakeDefaultsToSevenAMWithAnEmptyCalendar() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [])
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetWakeTime), 7)
    }

    func testWakeIsNinetyMinutesBeforeTheFirstCommitment() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [Fixture.busy("Lecture", fromHour: 9, toHour: 11)])
        let expected = Fixture.todayAt(hour: 7, minute: 30)
        XCTAssertEqual(plan.targetWakeTime.timeIntervalSince(expected), 0, accuracy: 60)
    }

    func testEarliestBlockWinsWhenSeveralExist() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [
            Fixture.busy("Afternoon lab", fromHour: 14, toHour: 16),
            Fixture.busy("Early lecture", fromHour: 8, toHour: 9),
            Fixture.busy("Midday", fromHour: 12, toHour: 13)
        ])
        // 8am minus the 90-minute morning routine.
        XCTAssertEqual(Calendar.current.component(.hour, from: plan.targetWakeTime), 6)
        XCTAssertEqual(Calendar.current.component(.minute, from: plan.targetWakeTime), 30)
    }

    /// A day's plan holds *this morning's* wake and *tonight's* bedtime, so the
    /// sleep window runs from bedtime to the following morning's wake — not
    /// between the two timestamps on the same schedule.
    func testBedtimePlusSleepDurationReachesTomorrowsWake() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [], targetSleepHours: 8)
        let tomorrowsWake = Calendar.current.date(byAdding: .day, value: 1, to: plan.targetWakeTime)!
        let sleepEnds = plan.targetBedTime.addingTimeInterval(8 * 3600)
        XCTAssertEqual(sleepEnds.timeIntervalSince(tomorrowsWake), 0, accuracy: 60)
    }

    func testBedtimeFallsInTheEveningAfterWake() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [], targetSleepHours: 8)
        XCTAssertGreaterThan(plan.targetBedTime, plan.targetWakeTime,
                             "Bedtime belongs to the evening of the same schedule day")
        XCTAssertGreaterThanOrEqual(Calendar.current.component(.hour, from: plan.targetBedTime), 21)
    }

    func testShorterSleepTargetMovesBedtimeLater() {
        let eight = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [], targetSleepHours: 8)
        let seven = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [], targetSleepHours: 7)
        XCTAssertGreaterThan(seven.targetBedTime, eight.targetBedTime)
    }

    func testWindDownPrecedesBedByFortyFiveMinutes() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [])
        XCTAssertEqual(plan.targetBedTime.timeIntervalSince(plan.windDownStart), 45 * 60, accuracy: 1)
    }

    func testCaffeineCutoffIsNineHoursBeforeBed() {
        let plan = SleepEngine.plan(for: Fixture.rahil, busyBlocks: [])
        XCTAssertEqual(plan.targetBedTime.timeIntervalSince(plan.caffeineCutoff), 9 * 3600, accuracy: 1)
    }

    func testCaffeineCutoffAlwaysPrecedesWindDown() {
        for hour in 6...11 {
            let plan = SleepEngine.plan(for: Fixture.rahil,
                                        busyBlocks: [Fixture.busy("Class", fromHour: hour, toHour: hour + 1)])
            XCTAssertLessThan(plan.caffeineCutoff, plan.windDownStart,
                              "Cutoff must precede wind-down for a \(hour):00 start")
        }
    }
}

final class ScheduleEngineTests: XCTestCase {

    private func build(profile: UserProfile = Fixture.rahil, busy: [BusyBlock] = []) -> DaySchedule {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: busy)
        return ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                       busyBlocks: busy, date: Date())
    }

    func testEventsAreChronologicallySorted() {
        let events = build().events
        XCTAssertEqual(events.map(\.time), events.map(\.time).sorted(),
                       "Timeline must be sorted or the hero card picks the wrong event")
    }

    func testDayContainsTheCoreRoutineEvents() {
        let kinds = Set(build().events.map(\.kind))
        for required in [EventKind.wake, .weighIn, .meal, .windDown, .sleep] {
            XCTAssertTrue(kinds.contains(required), "Missing \(required) from the day")
        }
    }

    func testMealCountMatchesProfilePreference() {
        var profile = Fixture.rahil
        profile.mealsPerDay = 3
        let meals = build(profile: profile).events.filter { $0.kind == .meal }
        XCTAssertEqual(meals.count, 3)
    }

    func testWorkoutIsScheduledIntoAFreeAfternoonGap() {
        let workouts = build().events.filter { $0.kind == .workout }
        XCTAssertEqual(workouts.count, 1)

        let hour = Calendar.current.component(.hour, from: workouts[0].time)
        XCTAssertGreaterThanOrEqual(hour, 14)
        XCTAssertLessThan(hour, 21)
    }

    func testWorkoutDoesNotOverlapACalendarCommitment() {
        let busy = [Fixture.busy("Lab", fromHour: 14, toHour: 18)]
        let schedule = build(busy: busy)
        guard let workout = schedule.events.first(where: { $0.kind == .workout }) else {
            return XCTFail("Expected a workout in the 18:00–21:00 gap")
        }
        let end = workout.time.addingTimeInterval(TimeInterval(workout.durationMinutes * 60))
        XCTAssertFalse(workout.time < busy[0].end && end > busy[0].start,
                       "Workout overlapped a busy block")
    }

    func testNoWorkoutWhenTheAfternoonIsFullyBooked() {
        let schedule = build(busy: [Fixture.busy("All day", fromHour: 13, toHour: 22)])
        XCTAssertTrue(schedule.events.filter { $0.kind == .workout }.isEmpty,
                      "Should not invent a workout slot that doesn't exist")
    }

    func testWorkoutPicksTheLargestGapNotTheFirst() {
        // 30-minute gap at 14:00, then a three-hour gap from 17:00.
        let busy = [
            Fixture.busy("A", fromHour: 12, toHour: 14),
            Fixture.busy("B", fromHour: 15, toHour: 17)
        ]
        guard let workout = build(busy: busy).events.first(where: { $0.kind == .workout }) else {
            return XCTFail("Expected a workout")
        }
        XCTAssertGreaterThanOrEqual(Calendar.current.component(.hour, from: workout.time), 17)
    }

    func testCriticalEventsAreFlaggedAndOptionalOnesAreNot() {
        let events = build().events
        let wake = events.first { $0.kind == .wake }
        let photo = events.first { $0.kind == .progressPhoto }

        XCTAssertEqual(wake?.isCritical, true, "Wake-up is load-bearing")
        XCTAssertEqual(photo?.isCritical, false, "Progress photo shouldn't break a streak")
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

    func testAllEventsHaveNonEmptyTitles() {
        for event in build().events {
            XCTAssertFalse(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testLiveMealsOverrideTheLocalDatabase() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let live = MealEngine.assemble(from: Fixture.recipePool, macros: macros, profile: profile, date: Date())

        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                               busyBlocks: [], date: Date(), liveMeals: live)
        let titles = schedule.events.filter { $0.kind == .meal }.map(\.title)
        XCTAssertTrue(titles.contains { Fixture.recipePool.map(\.title).contains($0) },
                      "Live meals should replace fallback meals, got \(titles)")
    }

    func testWorkoutReflectsSelectedFitnessGoals() {
        var bowlerOnly = Fixture.rahil
        bowlerOnly.fitnessGoals = [.fatLoss, .fastBowling]
        let details = (0..<7).compactMap { offset -> String? in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            let macros = MetabolicEngine.dailyTargets(for: bowlerOnly)
            let sleep = SleepEngine.plan(for: bowlerOnly, busyBlocks: [])
            return ScheduleEngine.buildDay(profile: bowlerOnly, macros: macros, sleepPlan: sleep,
                                           busyBlocks: [], date: date)
                .events.first { $0.kind == .workout }?.detail
        }
        XCTAssertFalse(details.isEmpty)
        XCTAssertFalse(details.contains { $0.contains("Hiking") },
                       "Hiking sessions leaked in without the goal selected")
    }
}
