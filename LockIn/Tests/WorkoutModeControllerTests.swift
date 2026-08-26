import XCTest
@testable import LockIn

@MainActor
final class WorkoutModeControllerTests: XCTestCase {

    private func session(exercises: [ExercisePrescription], focus: WorkoutFocus = .lowerStrength) -> WorkoutSession {
        WorkoutSession(focus: focus, goalTags: [.fatLoss], exercises: exercises, equipmentNote: "None")
    }

    private func exercise(_ name: String = "Test Move", sets: Int = 3, reps: String = "10") -> ExercisePrescription {
        ExercisePrescription(name: name, sets: sets, reps: reps)
    }

    // MARK: - Set / exercise progression

    func testCompleteSetBeforeLastSetStartsRestAndIncrementsSetNumber() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 3)]))
        controller.completeSet()
        XCTAssertEqual(controller.setNumber, 2)
        XCTAssertEqual(controller.phase, .resting)
        XCTAssertGreaterThan(controller.restSecondsRemaining, 0)
    }

    func testCompleteSetOnLastSetAdvancesToNextExerciseWithoutRest() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 1), exercise("Second", sets: 2)]))
        controller.completeSet() // only set of exercise 1
        XCTAssertEqual(controller.exerciseIndex, 1)
        XCTAssertEqual(controller.setNumber, 1)
        XCTAssertEqual(controller.phase, .working, "Moving to a new exercise shouldn't force a rest countdown")
    }

    func testCompleteSetOnLastSetOfLastExerciseFinishesTheSession() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 1)]))
        controller.completeSet()
        XCTAssertEqual(controller.phase, .finished)
    }

    func testSkipExerciseBehavesLikeAdvancing() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 3), exercise("Second", sets: 2)]))
        controller.skipExercise()
        XCTAssertEqual(controller.exerciseIndex, 1)
        XCTAssertEqual(controller.setNumber, 1)
    }

    // MARK: - Rest countdown

    func testTickCountsDownRestAndReturnsToWorkingAtZero() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 2)], focus: .sprintConditioning))
        controller.completeSet() // enters rest — sprintConditioning defaults to 30s
        XCTAssertEqual(controller.restSecondsRemaining, 30)
        for _ in 0..<30 { controller.tick() }
        XCTAssertEqual(controller.phase, .working)
        XCTAssertEqual(controller.restSecondsRemaining, 0)
    }

    func testSkipRestEndsItImmediately() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 2)]))
        controller.completeSet()
        XCTAssertEqual(controller.phase, .resting)
        controller.skipRest()
        XCTAssertEqual(controller.phase, .working)
        XCTAssertEqual(controller.restSecondsRemaining, 0)
    }

    func testTickWhilePausedDoesNothing() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 2)]))
        controller.completeSet()
        let remainingBefore = controller.restSecondsRemaining
        controller.isPaused = true
        controller.tick()
        XCTAssertEqual(controller.restSecondsRemaining, remainingBefore, "A paused tick shouldn't advance the countdown")
    }

    func testElapsedSecondsAccumulatesEverySecondRegardlessOfPhase() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 1)]))
        controller.tick()
        controller.tick()
        XCTAssertEqual(controller.elapsedSeconds, 2)
    }

    func testFinishStopsAdvancingElapsedTime() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 1)]))
        controller.finish()
        let before = controller.elapsedSeconds
        controller.tick()
        XCTAssertEqual(controller.elapsedSeconds, before)
    }

    // MARK: - Rest duration rules

    func testExplicitRestInRepsStringOverridesTheDefault() {
        XCTAssertEqual(WorkoutModeController.explicitRestSeconds(from: "10x20m, 20s rest"), 20)
        XCTAssertNil(WorkoutModeController.explicitRestSeconds(from: "8-10"))
    }

    func testDefaultRestSecondsVaryByFocus() {
        XCTAssertEqual(WorkoutModeController.restSeconds(focus: .lowerStrength, reps: "5-6"), 90)
        XCTAssertEqual(WorkoutModeController.restSeconds(focus: .sprintConditioning, reps: "20-30m"), 30)
        XCTAssertEqual(WorkoutModeController.restSeconds(focus: .mobilityRecovery, reps: "45s/side"), 15)
    }

    func testZeroRestFocusSkipsRestingPhaseEntirely() {
        // mobilityRecovery still returns 15s by default, but an explicit "0s
        // rest" should be honoured and skip the resting phase outright.
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 2, reps: "10, 0s rest")]))
        controller.completeSet()
        XCTAssertEqual(controller.phase, .working, "An explicit zero rest shouldn't leave the session stuck resting")
    }

    // MARK: - Progress

    func testProgressReflectsExerciseIndexNotSetNumber() {
        let controller = WorkoutModeController(session: session(exercises: [exercise(sets: 5), exercise("Second"), exercise("Third"), exercise("Fourth")]))
        XCTAssertEqual(controller.progress, 0)
        controller.skipExercise()
        XCTAssertEqual(controller.progress, 0.25, accuracy: 0.0001)
    }
}

/// Closing Workout Mode used to confirm the day's workout whenever the screen
/// had been open for twenty seconds. Credit now follows logged sets, not
/// elapsed time.
@MainActor
final class WorkoutModeCreditTests: XCTestCase {

    private func controller() -> WorkoutModeController {
        WorkoutModeController(session: WorkoutEngine.session(
            for: Date(), goals: Fixture.rahil.fitnessGoals,
            equipment: Fixture.rahil.equipment, assets: Fixture.rahil.gymAssets
        ))
    }

    func testOpeningAndClosingWithoutWorkEarnsNoCredit() {
        let c = controller()
        XCTAssertFalse(c.hasCreditableWork)
        XCTAssertEqual(c.completedSets, 0)
    }

    func testSittingOnTheScreenEarnsNoCredit() {
        let c = controller()
        for _ in 0..<120 { c.tick() }
        XCTAssertGreaterThan(c.elapsedSeconds, 20, "Expected the clock to run past the old threshold")
        XCTAssertFalse(c.hasCreditableWork, "Elapsed time alone credited a workout")
    }

    func testOneLoggedSetIsEnoughToOfferCredit() {
        let c = controller()
        c.completeSet()
        XCTAssertEqual(c.completedSets, 1)
        XCTAssertTrue(c.hasCreditableWork)
    }

    func testSkippingAnExerciseIsNotALoggedSet() {
        let c = controller()
        c.skipExercise()
        XCTAssertEqual(c.completedSets, 0)
        XCTAssertFalse(c.hasCreditableWork)
    }
}
