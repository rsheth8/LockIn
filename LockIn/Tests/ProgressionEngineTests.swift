import XCTest
@testable import LockIn

/// Double progression: hold the weight and climb the rep range, add load when
/// every set clears the top, back off when it stalls twice.
final class ProgressionEngineTests: XCTestCase {

    private let squat = ExercisePrescription(name: "Back Squat", sets: 3, reps: "5-6")
    private let facePull = ExercisePrescription(name: "Face Pull", sets: 3, reps: "15")

    private func workout(_ daysAgo: Int, _ name: String, _ sets: [(Double, Int)],
                         focus: WorkoutFocus = .lowerStrength) -> CompletedWorkout {
        CompletedWorkout(
            date: Date().addingTimeInterval(Double(-daysAgo) * 86400),
            focus: focus,
            exercises: [ExerciseLog(exerciseName: name,
                                    sets: sets.map { SetEntry(weightLbs: $0.0, reps: $0.1) })],
            durationSeconds: 2400
        )
    }

    private func advise(_ exercise: ExercisePrescription, _ history: [CompletedWorkout],
                        focus: WorkoutFocus = .lowerStrength) -> ProgressionSuggestion {
        ProgressionEngine.suggestion(for: exercise, focus: focus, history: history)
    }

    // MARK: Rep-range parsing
    //
    // This is what decides whether a lift can be progressed at all, so every
    // shape WorkoutEngine actually emits is covered.

    func testCountableRepsParseToARange() {
        let cases: [(String, ClosedRange<Int>)] = [
            ("8", 8...8), ("15", 15...15), ("5-6", 5...6), ("6-10", 6...10),
            ("12/leg", 12...12), ("6/side", 6...6), ("8-10/leg", 8...10), ("15/leg", 15...15)
        ]
        for (reps, expected) in cases {
            let exercise = ExercisePrescription(name: "X", sets: 3, reps: reps)
            XCTAssertEqual(exercise.repRange, expected, "\(reps) parsed wrong")
            XCTAssertTrue(exercise.tracksLoad, "\(reps) should be loadable")
        }
    }

    func testTimeDistanceAndEffortCuesHaveNoRepRange() {
        for reps in ["45s", "45s/side", "20-30m", "40m", "45-60 min", "5 min",
                     "10x20m, 20s rest", "conversational pace"] {
            let exercise = ExercisePrescription(name: "X", sets: 3, reps: reps)
            XCTAssertNil(exercise.repRange, "\(reps) should not parse as reps")
            XCTAssertFalse(exercise.tracksLoad, "\(reps) should not ask for a weight")
        }
    }

    /// Every prescription the engine can actually produce must classify without
    /// crashing — a new exercise with an odd rep string shouldn't break a session.
    func testEveryPrescriptionInTheSplitClassifiesCleanly() {
        for goals in [Set<FitnessGoal>([.fatLoss]),
                      [.fatLoss, .fastBowling],
                      [.fatLoss, .hikingBackpacking],
                      [.fatLoss, .fastBowling, .hikingBackpacking]] {
            for session in WorkoutEngine.weeklySplit(for: goals) {
                for exercise in session.exercises {
                    if let range = exercise.repRange {
                        XCTAssertGreaterThan(range.lowerBound, 0, "\(exercise.name): \(exercise.reps)")
                        XCTAssertGreaterThanOrEqual(range.upperBound, range.lowerBound)
                    }
                }
            }
        }
    }

    // MARK: No history

    func testTheFirstSessionAsksForABaselineRatherThanGuessing() {
        let advice = advise(squat, [])
        XCTAssertEqual(advice.kind, .baseline)
        XCTAssertNil(advice.targetWeightLbs, "Inventing a starting weight for a stranger is how people get hurt")
        XCTAssertEqual(advice.targetReps, 6)
    }

    func testTimedWorkIsMarkedUntracked() {
        let ruck = ExercisePrescription(name: "Weighted Ruck Walk", sets: 1, reps: "45-60 min")
        XCTAssertEqual(advise(ruck, []).kind, .untracked)
    }

    /// A logged session with no weights recorded (bodyweight pull-ups) still
    /// can't produce a load target.
    func testHistoryWithoutWeightsFallsBackToBaseline() {
        let past = CompletedWorkout(
            date: Date().addingTimeInterval(-86400), focus: .upperPull,
            exercises: [ExerciseLog(exerciseName: "Face Pull",
                                    sets: [SetEntry(reps: 15), SetEntry(reps: 15)])],
            durationSeconds: 600
        )
        XCTAssertEqual(advise(facePull, [past], focus: .upperPull).kind, .baseline)
    }

    // MARK: Adding weight

    func testClearingTheRangeOnEverySetAddsLoad() {
        let history = [workout(7, "Back Squat", [(185, 6), (185, 6), (185, 6)])]
        let advice = advise(squat, history)
        XCTAssertEqual(advice.kind, .increase)
        XCTAssertEqual(advice.targetWeightLbs, 195, "Lower-body compound: +10")
        XCTAssertEqual(advice.targetReps, 5, "Back to the bottom of the range at the new weight")
        XCTAssertTrue(advice.headline.contains("195"))
    }

    func testUpperBodyWorkTakesTheSmallerJump() {
        let history = [workout(7, "Face Pull", [(40, 15), (40, 15), (40, 15)], focus: .upperPull)]
        let advice = advise(facePull, history, focus: .upperPull)
        XCTAssertEqual(advice.kind, .increase)
        XCTAssertEqual(advice.targetWeightLbs, 45, "5 lb on an isolation lift, not 10")
    }

    func testOneSetShortOfTheTopHoldsTheWeight() {
        let history = [workout(7, "Back Squat", [(185, 6), (185, 6), (185, 5)])]
        let advice = advise(squat, history)
        XCTAssertEqual(advice.kind, .hold)
        XCTAssertEqual(advice.targetWeightLbs, 185)
        XCTAssertTrue(advice.reason.contains("185×6"), "Should show what was actually done")
    }

    func testTheHoldTargetsOneMoreRepThanLastTime() {
        let history = [workout(7, "Back Squat", [(185, 5), (185, 5), (185, 5)])]
        XCTAssertEqual(advise(squat, history).targetReps, 6)
    }

    /// Warm-up sets logged at a lighter weight must not drag the decision down —
    /// only the sets at the session's top weight count as working sets.
    func testLighterWarmUpSetsDoNotBlockAnIncrease() {
        let history = [workout(7, "Back Squat", [(135, 6), (185, 6), (185, 6), (185, 6)])]
        XCTAssertEqual(advise(squat, history).kind, .increase)
    }

    // MARK: Stalling

    func testOneBadSessionHoldsRatherThanDeloads() {
        let history = [workout(7, "Back Squat", [(225, 3), (225, 3), (225, 3)])]
        XCTAssertEqual(advise(squat, history).kind, .hold, "One off day is not a stall")
    }

    func testTwoSessionsUnderTheRangeTriggersADeload() {
        let history = [
            workout(14, "Back Squat", [(225, 4), (225, 3), (225, 3)]),
            workout(7, "Back Squat", [(225, 4), (225, 3), (225, 2)])
        ]
        let advice = advise(squat, history)
        XCTAssertEqual(advice.kind, .deload)
        XCTAssertEqual(advice.targetWeightLbs, 202.5, "10% off 225, rounded to a loadable 2.5 lb step")
        XCTAssertLessThan(advice.targetWeightLbs ?? 0, 225)
    }

    func testAGoodSessionBetweenTwoBadOnesResetsTheStall() {
        let history = [
            workout(21, "Back Squat", [(225, 3), (225, 3), (225, 3)]),
            workout(14, "Back Squat", [(225, 6), (225, 5), (225, 5)]),
            workout(7, "Back Squat", [(225, 4), (225, 3), (225, 3)])
        ]
        XCTAssertEqual(advise(squat, history).kind, .hold)
    }

    // MARK: Rounding and increments

    func testSuggestionsLandOnLoadableWeights() {
        for raw in [121.3, 202.49, 47.6, 0.4] {
            let rounded = ProgressionEngine.round(to: raw)
            XCTAssertEqual(rounded.truncatingRemainder(dividingBy: 2.5), 0, accuracy: 0.001,
                           "\(raw) rounded to \(rounded), which no bar can be loaded to")
            XCTAssertGreaterThanOrEqual(rounded, 2.5)
        }
    }

    func testIncrementIsBiggerForHeavyLowerBodyWork() {
        XCTAssertEqual(ProgressionEngine.increment(for: .lowerStrength), 10)
        for focus in [WorkoutFocus.upperPull, .core, .rotationalPower, .unilateralLegs] {
            XCTAssertEqual(ProgressionEngine.increment(for: focus), 5)
        }
    }

    // MARK: History lookup

    func testHistoryIsNewestFirstAndSkipsSessionsWithoutTheLift() {
        let history = [
            workout(21, "Back Squat", [(175, 5)]),
            workout(14, "Bench Press", [(155, 5)]),
            workout(7, "Back Squat", [(185, 5)])
        ]
        let squats = ProgressionEngine.history(of: "Back Squat", in: history)
        XCTAssertEqual(squats.count, 2)
        XCTAssertEqual(squats.first?.topWeightLbs, 185, "Most recent session first")
    }

    func testLookupIsByNameSinceIdsAreMintedFresh() {
        // WorkoutEngine builds a new ExercisePrescription (new UUID) every time,
        // so an id-based lookup would never match across sessions.
        let a = WorkoutEngine.session(for: Date(), goals: [.fatLoss])
        let b = WorkoutEngine.session(for: Date(), goals: [.fatLoss])
        XCTAssertEqual(a.exercises.map(\.name), b.exercises.map(\.name))
        XCTAssertNotEqual(a.exercises.first?.id, b.exercises.first?.id)
    }

    // MARK: Improvements

    func testMoreVolumeCountsAsAnImprovement() {
        let previous = workout(7, "Back Squat", [(185, 5), (185, 5)])
        let today = workout(0, "Back Squat", [(195, 5), (195, 5)])
        XCTAssertEqual(ProgressionEngine.improvements(in: today, history: [previous, today]),
                       ["Back Squat"])
    }

    func testMoreRepsAtTheSameWeightAlsoCounts() {
        let previous = workout(7, "Back Squat", [(185, 5), (185, 5)])
        let today = workout(0, "Back Squat", [(185, 6), (185, 6)])
        XCTAssertEqual(ProgressionEngine.improvements(in: today, history: [previous, today]).count, 1)
    }

    func testABackwardsSessionIsNotAnImprovement() {
        let previous = workout(7, "Back Squat", [(205, 5), (205, 5)])
        let today = workout(0, "Back Squat", [(185, 5), (185, 5)])
        XCTAssertTrue(ProgressionEngine.improvements(in: today, history: [previous, today]).isEmpty)
    }

    func testTheFirstEverSessionIsNotAnImprovement() {
        let today = workout(0, "Back Squat", [(185, 5)])
        XCTAssertTrue(ProgressionEngine.improvements(in: today, history: [today]).isEmpty,
                      "Nothing to beat yet")
    }
}
