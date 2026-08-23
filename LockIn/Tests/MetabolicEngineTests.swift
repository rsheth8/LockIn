import XCTest
@testable import LockIn

/// The numbers here drive everything the user eats, so they're pinned against
/// hand-computed Mifflin-St Jeor values rather than against whatever the code
/// currently returns.
final class MetabolicEngineTests: XCTestCase {

    // MARK: - BMR

    func testBMRMatchesMifflinStJeorForMale() {
        // 220 lb = 99.79 kg, 70 in = 177.8 cm, age 22
        // 10(99.79) + 6.25(177.8) - 5(22) + 5 = 997.9 + 1111.25 - 110 + 5 = 2004.15
        XCTAssertEqual(MetabolicEngine.bmr(for: Fixture.rahil), 2004.15, accuracy: 1.0)
    }

    func testBMRMatchesMifflinStJeorForFemale() {
        // 150 lb = 68.04 kg, 66 in = 167.64 cm, age 25
        // 10(68.04) + 6.25(167.64) - 5(25) - 161 = 680.4 + 1047.75 - 125 - 161 = 1442.15
        XCTAssertEqual(MetabolicEngine.bmr(for: Fixture.femaleCut), 1442.15, accuracy: 1.0)
    }

    func testFemaleBMRIsLowerThanMaleAtIdenticalBodyMetrics() {
        var male = UserProfile.blank
        male.sex = .male
        var female = male
        female.sex = .female
        // The equations differ by a fixed 166 kcal offset (+5 vs −161).
        XCTAssertEqual(MetabolicEngine.bmr(for: male) - MetabolicEngine.bmr(for: female), 166, accuracy: 0.01)
    }

    // MARK: - TDEE

    func testTDEEAppliesActivityMultiplier() {
        var profile = Fixture.rahil
        profile.activityLevel = .sedentary
        let sedentary = MetabolicEngine.tdee(for: profile)
        profile.activityLevel = .veryActive
        let active = MetabolicEngine.tdee(for: profile)

        XCTAssertEqual(sedentary, MetabolicEngine.bmr(for: profile) * 1.2, accuracy: 0.01)
        XCTAssertEqual(active / sedentary, 1.725 / 1.2, accuracy: 0.001)
    }

    func testActivityMultipliersAreMonotonic() {
        let multipliers = ActivityLevel.allCases.map(\.multiplier)
        XCTAssertEqual(multipliers, multipliers.sorted(), "Activity levels must increase monotonically")
    }

    // MARK: - Goal direction

    func testCutProducesDeficitBelowMaintenance() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        XCTAssertLessThan(targets.calories, targets.tdeeMaintenance)
        XCTAssertEqual(Double(targets.calories) / Double(targets.tdeeMaintenance), 0.78, accuracy: 0.01)
    }

    func testGainProducesSurplusAboveMaintenance() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.maleGain)
        XCTAssertGreaterThan(targets.calories, targets.tdeeMaintenance)
        XCTAssertEqual(Double(targets.calories) / Double(targets.tdeeMaintenance), 1.10, accuracy: 0.01)
    }

    func testMaintainSitsExactlyAtMaintenance() {
        var profile = Fixture.rahil
        profile.goalDirection = .maintain
        let targets = MetabolicEngine.dailyTargets(for: profile)
        XCTAssertEqual(targets.calories, targets.tdeeMaintenance)
    }

    func testRecompSitsAtMaintenanceWithHigherProteinThanMaintain() {
        var maintain = Fixture.rahil
        maintain.goalDirection = .maintain
        var recomp = Fixture.rahil
        recomp.goalDirection = .recomp
        recomp.goalWeightLbs = recomp.currentWeightLbs   // isolate the protein multiplier

        let m = MetabolicEngine.dailyTargets(for: maintain)
        let r = MetabolicEngine.dailyTargets(for: recomp)

        XCTAssertEqual(r.calories, r.tdeeMaintenance)
        XCTAssertGreaterThan(r.proteinGrams, m.proteinGrams)
    }

    // MARK: - Protein

    func testProteinScalesToGoalWeightNotCurrentWeightOnACut() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        // 1 g per lb of the 180 lb goal, not the 220 lb starting weight.
        XCTAssertEqual(targets.proteinGrams, 180)
        XCTAssertNotEqual(targets.proteinGrams, 220)
    }

    func testProteinUsesCurrentWeightWhenMaintaining() {
        var profile = Fixture.rahil
        profile.goalDirection = .maintain
        XCTAssertEqual(MetabolicEngine.dailyTargets(for: profile).proteinGrams, 220)
    }

    // MARK: - Safety floors

    func testCalorieFloorEngagesForSmallFrameFemale() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.smallFemale)
        XCTAssertTrue(targets.hitSafetyFloor, "A sub-1200 kcal target must be clamped")
        XCTAssertEqual(targets.calories, 1200)
    }

    func testCalorieFloorIsSexSpecific() {
        var tinyMale = Fixture.smallFemale
        tinyMale.sex = .male
        let targets = MetabolicEngine.dailyTargets(for: tinyMale)
        XCTAssertTrue(targets.hitSafetyFloor)
        XCTAssertEqual(targets.calories, 1500, "Male floor is 1500, not the female 1200")
    }

    func testFloorNotEngagedForTypicalProfiles() {
        for profile in [Fixture.rahil, Fixture.femaleCut, Fixture.maleGain] {
            XCTAssertFalse(MetabolicEngine.dailyTargets(for: profile).hitSafetyFloor,
                           "\(profile.name) should not need clamping")
        }
    }

    func testTargetNeverFallsBelowFloorAcrossWideParameterSweep() {
        for weight in stride(from: 90.0, through: 300.0, by: 10) {
            for height in stride(from: 56.0, through: 80.0, by: 4) {
                for sex in Sex.allCases {
                    var profile = UserProfile.blank
                    profile.sex = sex
                    profile.currentWeightLbs = weight
                    profile.goalWeightLbs = max(weight - 20, 85)
                    profile.heightInches = height
                    profile.activityLevel = .sedentary
                    profile.goalDirection = .cut

                    let targets = MetabolicEngine.dailyTargets(for: profile)
                    let floor = sex == .female ? 1200 : 1500
                    XCTAssertGreaterThanOrEqual(targets.calories, floor,
                        "\(sex) \(weight)lb \(height)in fell below floor")
                }
            }
        }
    }

    // MARK: - Macro coherence

    func testMacrosNeverGoNegative() {
        for weight in stride(from: 90.0, through: 300.0, by: 15) {
            for direction in GoalDirection.allCases {
                var profile = UserProfile.blank
                profile.currentWeightLbs = weight
                profile.goalWeightLbs = weight - 15
                profile.goalDirection = direction

                let t = MetabolicEngine.dailyTargets(for: profile)
                XCTAssertGreaterThanOrEqual(t.proteinGrams, 0)
                XCTAssertGreaterThanOrEqual(t.fatGrams, 0)
                XCTAssertGreaterThanOrEqual(t.carbGrams, 0, "Carbs went negative at \(weight)lb \(direction)")
            }
        }
    }

    func testFatMeetsHormonalHealthFloor() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        XCTAssertGreaterThanOrEqual(Double(targets.fatGrams), Fixture.rahil.currentWeightLbs * 0.3 - 1)
    }

    // MARK: - Rate and timeline

    func testWeeklyRateLandsInSustainableBandForRahil() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let rate = MetabolicEngine.weeklyRatePercent(profile: Fixture.rahil, targets: targets)
        XCTAssertGreaterThan(rate, 0.4)
        XCTAssertLessThan(rate, 1.0, "Above 1%/week costs lean mass")
    }

    func testEstimatedWeeksIsPositiveAndFiniteWhenADeficitExists() {
        let targets = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let weeks = MetabolicEngine.estimatedWeeksToGoal(profile: Fixture.rahil, targets: targets)
        XCTAssertTrue(weeks.isFinite)
        XCTAssertGreaterThan(weeks, 0)
    }

    func testEstimatedWeeksIsInfiniteAtMaintenance() {
        var profile = Fixture.rahil
        profile.goalDirection = .maintain
        let targets = MetabolicEngine.dailyTargets(for: profile)
        XCTAssertFalse(MetabolicEngine.estimatedWeeksToGoal(profile: profile, targets: targets).isFinite)
    }

    // MARK: - Advisories

    func testAdvisoryRaisedWhenFloorEngages() {
        let profile = Fixture.smallFemale
        let notes = MetabolicEngine.advisories(profile: profile, targets: MetabolicEngine.dailyTargets(for: profile))
        XCTAssertTrue(notes.contains { $0.contains("raised") }, "Expected a floor advisory, got \(notes)")
    }

    func testAdvisoryWhenGoalWeightIsNotBelowCurrentOnACut() {
        var profile = Fixture.rahil
        profile.goalWeightLbs = profile.currentWeightLbs + 10
        let notes = MetabolicEngine.advisories(profile: profile, targets: MetabolicEngine.dailyTargets(for: profile))
        XCTAssertTrue(notes.contains { $0.contains("isn't below") }, "Expected a goal-direction advisory, got \(notes)")
    }

    func testNoAdvisoriesForAWellFormedPlan() {
        XCTAssertTrue(MetabolicEngine.advisories(
            profile: Fixture.rahil,
            targets: MetabolicEngine.dailyTargets(for: Fixture.rahil)
        ).isEmpty)
    }

    // MARK: - Labels

    func testAdjustmentLabelReflectsDirection() {
        XCTAssertEqual(MetabolicEngine.dailyTargets(for: Fixture.rahil).adjustmentLabel, "22% deficit")
        XCTAssertEqual(MetabolicEngine.dailyTargets(for: Fixture.maleGain).adjustmentLabel, "10% surplus")

        var maintain = Fixture.rahil
        maintain.goalDirection = .maintain
        XCTAssertEqual(MetabolicEngine.dailyTargets(for: maintain).adjustmentLabel, "maintenance")
    }
}
