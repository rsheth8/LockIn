import XCTest
@testable import LockIn

final class ProfileCodingTests: XCTestCase {

    func testProfileRoundTripsThroughJSON() throws {
        let original = Fixture.rahil
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }

    func testEveryProfileFieldSurvivesEncoding() throws {
        var profile = Fixture.rahil
        profile.allergies = ["peanut", "shellfish"]
        profile.accentColor = .ocean
        profile.appleUserIdentifier = "001234.abcdef"
        profile.weightHistory = [WeightEntry(date: Fixture.date(2026, 1, 1), weightLbs: 221)]

        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))

        XCTAssertEqual(restored.allergies, ["peanut", "shellfish"])
        XCTAssertEqual(restored.accentColor, .ocean)
        XCTAssertEqual(restored.appleUserIdentifier, "001234.abcdef")
        XCTAssertEqual(restored.weightHistory.count, 1)
        XCTAssertEqual(restored.fitnessGoals, profile.fitnessGoals)
    }

    func testBlankProfileIsNeutralNotPreFilledWithOnePerson() {
        let blank = UserProfile.blank
        XCTAssertTrue(blank.name.isEmpty)
        XCTAssertEqual(blank.dietaryPattern, .omnivore, "A new user shouldn't inherit someone else's diet")
        XCTAssertEqual(blank.cuisinePreference, .noPreference)
        XCTAssertEqual(blank.fitnessGoals, [.fatLoss])
    }

    func testPresetMatchesTheKnownProfile() {
        let preset = UserProfile.rahilPreset
        XCTAssertEqual(preset.currentWeightLbs, 220)
        XCTAssertEqual(preset.goalWeightLbs, 180)
        XCTAssertEqual(preset.heightInches, 70)
        XCTAssertEqual(preset.dietaryPattern, .vegetarian)
        XCTAssertEqual(preset.deficitIntensity, .maximum)
        XCTAssertTrue(preset.foodPreferences.cuisines.contains(.southAsian))
        XCTAssertFalse(preset.foodPreferences.favouriteIngredients.isEmpty)
        XCTAssertFalse(preset.foodPreferences.pantry.isEmpty)
        XCTAssertTrue(preset.fitnessGoals.contains(.fastBowling))
        XCTAssertTrue(preset.fitnessGoals.contains(.hikingBackpacking))
    }

    func testOldProfilesDecodeWithoutTheNewFoodFields() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixture.rahil)) as! [String: Any]
        object.removeValue(forKey: "deficitIntensity")
        object.removeValue(forKey: "foodPreferences")
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.deficitIntensity, .aggressive)
        XCTAssertEqual(restored.foodPreferences.cuisines, [.southAsian],
                       "Cuisine preference must migrate into the multi-select")
    }

    func testFoodPreferencesRoundTrip() throws {
        var profile = Fixture.rahil
        profile.deficitIntensity = .maximum
        profile.foodPreferences = FoodPreferences(
            cuisines: [.southAsian, .mediterranean],
            favouriteIngredients: ["paneer", "yogurt"],
            dislikedIngredients: ["mushroom"],
            intolerances: ["peanut"],
            pantry: [PantryItem(name: "spinach")]
        )
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored.deficitIntensity, .maximum)
        XCTAssertEqual(restored.foodPreferences.cuisines, [.southAsian, .mediterranean])
        XCTAssertEqual(restored.foodPreferences.favouriteIngredients, ["paneer", "yogurt"])
        XCTAssertEqual(restored.foodPreferences.dislikedIngredients, ["mushroom"])
        XCTAssertEqual(restored.foodPreferences.pantry.map(\.name), ["spinach"])
    }

    func testEachProfileGetsAUniqueIdentity() {
        XCTAssertNotEqual(UserProfile.blank.id, UserProfile.blank.id,
                          "Two people must not share a profile ID or their cloud records collide")
    }

    func testScheduleRoundTripsWithStatuses() throws {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        var schedule = ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                               busyBlocks: [], date: Date())
        schedule.events[0].status = .confirmed
        schedule.events[1].status = .missed

        let restored = try JSONDecoder().decode(DaySchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(restored.events[0].status, .confirmed)
        XCTAssertEqual(restored.events[1].status, .missed)
        XCTAssertEqual(restored.macros, schedule.macros)
    }

    func testDayRecordsRoundTrip() throws {
        let records = (0..<10).map { Fixture.dayRecord(daysAgo: $0, confirmed: 9, weight: 220 - Double($0)) }
        let restored = try JSONDecoder().decode([DayRecord].self, from: JSONEncoder().encode(records))
        XCTAssertEqual(restored, records)
    }

    func testStreakStatusRoundTrips() throws {
        var streak = StreakStatus()
        streak.currentStreakDays = 12
        streak.longestStreakDays = 30
        streak.lastCountedDayKey = "2026-03-07"
        let restored = try JSONDecoder().decode(StreakStatus.self, from: JSONEncoder().encode(streak))
        XCTAssertEqual(restored, streak)
    }

    /// Guards the migration path: a profile saved before a field existed must
    /// still decode rather than wiping the user's setup on upgrade.
    func testDecodingIsResilientToNewOptionalFields() throws {
        var profile = Fixture.rahil
        profile.appleUserIdentifier = nil
        profile.wakeConstraintEarliest = nil
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertNil(restored.appleUserIdentifier)
    }
}

final class GoalDirectionTests: XCTestCase {

    func testAdjustmentSigns() {
        XCTAssertLessThan(GoalDirection.cut.calorieAdjustment, 0)
        XCTAssertGreaterThan(GoalDirection.gain.calorieAdjustment, 0)
        XCTAssertEqual(GoalDirection.maintain.calorieAdjustment, 0)
        XCTAssertEqual(GoalDirection.recomp.calorieAdjustment, 0)
    }

    func testSurplusIsConservative() {
        // Larger surpluses add fat without adding muscle.
        XCTAssertLessThanOrEqual(GoalDirection.gain.calorieAdjustment, 0.15)
    }

    func testDeficitStaysInTheSustainableBand() {
        XCTAssertGreaterThanOrEqual(GoalDirection.cut.calorieAdjustment, -0.25)
        XCTAssertLessThanOrEqual(GoalDirection.cut.calorieAdjustment, -0.15)
    }

    func testEveryDirectionHasUserFacingCopy() {
        for direction in GoalDirection.allCases {
            XCTAssertFalse(direction.displayName.isEmpty)
            XCTAssertFalse(direction.blurb.isEmpty)
        }
    }
}

final class AppAccentTests: XCTestCase {

    func testAllAccentsAreDistinctAndNamed() {
        XCTAssertEqual(Set(AppAccent.allCases.map(\.rawValue)).count, AppAccent.allCases.count)
        for accent in AppAccent.allCases {
            XCTAssertFalse(accent.displayName.isEmpty)
        }
    }

    func testAccentRoundTripsThroughCoding() throws {
        for accent in AppAccent.allCases {
            let restored = try JSONDecoder().decode(AppAccent.self, from: JSONEncoder().encode(accent))
            XCTAssertEqual(restored, accent)
        }
    }
}

final class WorkoutEngineTests: XCTestCase {

    func testSplitAlwaysProducesSessions() {
        for goals: Set<FitnessGoal> in [[.fatLoss], [.fatLoss, .fastBowling],
                                        [.fatLoss, .hikingBackpacking],
                                        [.fatLoss, .fastBowling, .hikingBackpacking]] {
            XCTAssertFalse(WorkoutEngine.weeklySplit(for: goals).isEmpty, "\(goals) produced no sessions")
        }
    }

    func testBowlingGoalAddsRotationalAndSprintWork() {
        let focuses = WorkoutEngine.weeklySplit(for: [.fatLoss, .fastBowling]).map(\.focus)
        XCTAssertTrue(focuses.contains(.rotationalPower))
        XCTAssertTrue(focuses.contains(.sprintConditioning))
    }

    func testHikingGoalAddsRuckingAndUnilateralWork() {
        let focuses = WorkoutEngine.weeklySplit(for: [.fatLoss, .hikingBackpacking]).map(\.focus)
        XCTAssertTrue(focuses.contains(.ruckEndurance))
        XCTAssertTrue(focuses.contains(.unilateralLegs))
    }

    func testSportSessionsAreAbsentWithoutTheirGoal() {
        let focuses = WorkoutEngine.weeklySplit(for: [.fatLoss]).map(\.focus)
        XCTAssertFalse(focuses.contains(.rotationalPower))
        XCTAssertFalse(focuses.contains(.ruckEndurance))
    }

    func testEverySessionHasExercisesAndCopy() {
        for session in WorkoutEngine.weeklySplit(for: [.fatLoss, .fastBowling, .hikingBackpacking]) {
            XCTAssertFalse(session.exercises.isEmpty, "\(session.focus) has no exercises")
            XCTAssertFalse(session.focus.title.isEmpty)
            XCTAssertFalse(session.equipmentNote.isEmpty)
            for exercise in session.exercises {
                XCTAssertGreaterThan(exercise.sets, 0)
                XCTAssertFalse(exercise.reps.isEmpty)
            }
        }
    }

    func testSessionSelectionIsStableForAGivenDate() {
        let goals: Set<FitnessGoal> = [.fatLoss, .fastBowling]
        let date = Fixture.date(2026, 5, 4)
        XCTAssertEqual(WorkoutEngine.session(for: date, goals: goals).focus,
                       WorkoutEngine.session(for: date, goals: goals).focus)
    }

    func testSessionIndexStaysInBoundsAcrossAFullYear() {
        let goals: Set<FitnessGoal> = [.fatLoss]
        for offset in 0..<365 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            // Purely an out-of-range guard — the modulo indexing has bitten before.
            _ = WorkoutEngine.session(for: date, goals: goals)
        }
    }
}
