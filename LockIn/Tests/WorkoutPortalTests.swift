import XCTest
@testable import LockIn

/// The portal's state machine. Every test drives the clock through `tick()`
/// rather than waiting, so a 2:30 rest costs 150 loop iterations, not 150s.
@MainActor
final class WorkoutRunnerTests: XCTestCase {

    private let eventID = UUID()
    private let dayKey = "2026-09-14"

    /// Two exercises, 3 and 2 sets — 5 sets total. Lower-body focus, so rest
    /// between sets is 150s.
    private var session: WorkoutSession {
        WorkoutSession(
            focus: .lowerStrength,
            goalTags: [.fatLoss],
            exercises: [
                ExercisePrescription(name: "Back Squat", sets: 3, reps: "5"),
                ExercisePrescription(name: "RDL", sets: 2, reps: "8")
            ],
            equipmentNote: "Gym."
        )
    }

    /// Single continuous effort — the shape that must never open a rest clock.
    private var ruck: WorkoutSession {
        WorkoutSession(
            focus: .ruckEndurance,
            goalTags: [.hikingBackpacking],
            exercises: [ExercisePrescription(name: "Weighted Ruck", sets: 1, reps: "45 min")],
            equipmentNote: "Pack."
        )
    }

    private func makeRunner(_ session: WorkoutSession? = nil,
                            resuming: WorkoutProgress? = nil) -> WorkoutRunner {
        WorkoutRunner(session: session ?? self.session, eventID: eventID,
                      dayKey: dayKey, resuming: resuming)
    }

    // MARK: Set progression

    func testStartsOnTheFirstExerciseWithNothingBanked() {
        let runner = makeRunner()
        XCTAssertEqual(runner.exerciseIndex, 0)
        XCTAssertEqual(runner.setsDone, 0)
        XCTAssertEqual(runner.totalSets, 5)
        XCTAssertEqual(runner.phase, .working)
    }

    func testCompletingASetOpensTheRestClock() {
        let runner = makeRunner()
        runner.completeSet()
        XCTAssertEqual(runner.phase, .resting)
        XCTAssertEqual(runner.restRemaining, WorkoutFocus.lowerStrength.restSeconds)
        XCTAssertEqual(runner.currentSetsDone, 1)
        XCTAssertEqual(runner.exerciseIndex, 0, "Still on the same exercise with sets owed")
    }

    func testRestRunsOutAndReturnsToWorking() {
        let runner = makeRunner()
        runner.completeSet()
        for _ in 0..<WorkoutFocus.lowerStrength.restSeconds { runner.tick() }
        XCTAssertEqual(runner.phase, .working)
        XCTAssertEqual(runner.restRemaining, 0)
    }

    func testFinishingAnExerciseAdvancesToTheNext() {
        let runner = makeRunner()
        for _ in 0..<3 { runner.completeSet() }   // all of Back Squat
        XCTAssertEqual(runner.exerciseIndex, 1)
        XCTAssertTrue(runner.isComplete(exerciseAt: 0))
        XCTAssertEqual(runner.currentExercise?.name, "RDL")
    }

    func testBankingEverySetFinishesTheSession() {
        let runner = makeRunner()
        for _ in 0..<5 { runner.completeSet() }
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.setsDone, runner.totalSets)
        XCTAssertEqual(runner.fraction, 1.0, accuracy: 0.001)
    }

    func testASingleSetExerciseNeverOpensARestClock() {
        let runner = makeRunner(ruck)
        runner.completeSet()
        XCTAssertEqual(runner.phase, .finished, "One set, one exercise — that's the whole session")
        XCTAssertEqual(runner.restRemaining, 0)
    }

    // MARK: Rest controls

    func testSkipRestReturnsToWorkImmediately() {
        let runner = makeRunner()
        runner.completeSet()
        runner.skipRest()
        XCTAssertEqual(runner.phase, .working)
        XCTAssertEqual(runner.restRemaining, 0)
    }

    func testAddRestExtendsTheClock() {
        let runner = makeRunner()
        runner.completeSet()
        let before = runner.restRemaining
        runner.addRest(30)
        XCTAssertEqual(runner.restRemaining, before + 30)
    }

    func testAddRestDoesNothingWhileWorking() {
        let runner = makeRunner()
        runner.addRest(30)
        XCTAssertEqual(runner.restRemaining, 0)
        XCTAssertEqual(runner.phase, .working)
    }

    func testPauseFreezesBothClocks() {
        let runner = makeRunner()
        runner.completeSet()
        let rest = runner.restRemaining
        runner.togglePause()
        for _ in 0..<10 { runner.tick() }
        XCTAssertEqual(runner.restRemaining, rest, "Rest kept counting while paused")
        XCTAssertEqual(runner.elapsedSeconds, 0, "Paused time counted as time trained")

        runner.togglePause()
        runner.tick()
        XCTAssertEqual(runner.restRemaining, rest - 1)
    }

    func testElapsedCountsOnlyWhileRunning() {
        let runner = makeRunner()
        for _ in 0..<60 { runner.tick() }
        XCTAssertEqual(runner.elapsedSeconds, 60)
        runner.finish()
        for _ in 0..<60 { runner.tick() }
        XCTAssertEqual(runner.elapsedSeconds, 60, "A finished session kept accruing time")
    }

    // MARK: Corrections and navigation

    func testUndoGivesBackAMisTappedSet() {
        let runner = makeRunner()
        runner.completeSet()
        runner.undoSet()
        XCTAssertEqual(runner.currentSetsDone, 0)
        XCTAssertEqual(runner.phase, .working, "Undo should cancel the rest it opened")
    }

    func testUndoDoesNothingAtZero() {
        let runner = makeRunner()
        runner.undoSet()
        XCTAssertEqual(runner.setsDone, 0)
    }

    func testJumpingToAnExerciseMovesThereAndClearsRest() {
        let runner = makeRunner()
        runner.completeSet()
        runner.jump(to: 1)
        XCTAssertEqual(runner.exerciseIndex, 1)
        XCTAssertEqual(runner.phase, .working)
        XCTAssertEqual(runner.restRemaining, 0)
    }

    /// Skip the squat rack, finish the RDLs, and the session should send you
    /// back rather than declaring itself done.
    func testAdvanceWrapsBackToASkippedExercise() {
        let runner = makeRunner()
        runner.jump(to: 1)
        runner.completeSet()
        runner.completeSet()            // RDL done
        XCTAssertEqual(runner.exerciseIndex, 0, "Should wrap back to the unfinished squat")
        XCTAssertNotEqual(runner.phase, .finished)
    }

    func testFinishEarlyKeepsWhatWasBanked() {
        let runner = makeRunner()
        runner.completeSet()
        runner.completeSet()
        runner.finish()
        XCTAssertEqual(runner.phase, .finished)
        XCTAssertEqual(runner.setsDone, 2)
    }

    func testActionsAreInertOnceFinished() {
        let runner = makeRunner()
        runner.finish()
        runner.completeSet()
        XCTAssertEqual(runner.setsDone, 0)
        XCTAssertEqual(runner.phase, .finished)
    }

    // MARK: Resume

    func testProgressIsReportedOnEveryChange() {
        let runner = makeRunner()
        var latest: WorkoutProgress?
        runner.onProgress = { latest = $0 }
        runner.completeSet()
        XCTAssertEqual(latest?.completedSets, [1, 0])
        XCTAssertEqual(latest?.eventID, eventID)
        XCTAssertEqual(latest?.dayKey, dayKey)
    }

    func testResumingRestoresThePlaceInTheSession() {
        let saved = WorkoutProgress(eventID: eventID, dayKey: dayKey,
                                    completedSets: [3, 1], exerciseIndex: 1, elapsedSeconds: 400)
        let runner = makeRunner(resuming: saved)
        XCTAssertEqual(runner.setsDone, 4)
        XCTAssertEqual(runner.exerciseIndex, 1)
        XCTAssertEqual(runner.elapsedSeconds, 400)
        XCTAssertEqual(runner.phase, .working)
    }

    func testProgressFromAnotherEventIsIgnored() {
        let saved = WorkoutProgress(eventID: UUID(), dayKey: dayKey,
                                    completedSets: [3, 2], exerciseIndex: 1, elapsedSeconds: 900)
        XCTAssertEqual(makeRunner(resuming: saved).setsDone, 0)
    }

    func testProgressFromAnotherDayIsIgnored() {
        let saved = WorkoutProgress(eventID: eventID, dayKey: "2026-09-13",
                                    completedSets: [3, 2], exerciseIndex: 1, elapsedSeconds: 900)
        XCTAssertEqual(makeRunner(resuming: saved).setsDone, 0)
    }

    /// A schedule rebuild can change the exercise list under a saved record.
    func testProgressForADifferentSessionShapeIsIgnored() {
        let saved = WorkoutProgress(eventID: eventID, dayKey: dayKey,
                                    completedSets: [2, 2, 2], exerciseIndex: 2, elapsedSeconds: 300)
        XCTAssertEqual(makeRunner(resuming: saved).setsDone, 0)
    }

    func testResumedCountsAreClampedToThePrescription() {
        let saved = WorkoutProgress(eventID: eventID, dayKey: dayKey,
                                    completedSets: [99, -4], exerciseIndex: 0, elapsedSeconds: 10)
        let runner = makeRunner(resuming: saved)
        XCTAssertEqual(runner.completedSets, [3, 0])
        XCTAssertLessThanOrEqual(runner.fraction, 1.0)
    }

    func testResumingACompletedSessionOpensOnTheSummary() {
        let saved = WorkoutProgress(eventID: eventID, dayKey: dayKey,
                                    completedSets: [3, 2], exerciseIndex: 1, elapsedSeconds: 2000)
        XCTAssertEqual(makeRunner(resuming: saved).phase, .finished)
    }

    // MARK: Formatting

    func testClockFormatting() {
        XCTAssertEqual(0.asClock, "0:00")
        XCTAssertEqual(9.asClock, "0:09")
        XCTAssertEqual(150.asClock, "2:30")
        XCTAssertEqual(3725.asClock, "62:05")
        XCTAssertEqual((-5).asClock, "0:00")
    }
}

/// Every card the timeline can draw should either offer a way to actually do
/// the thing, or be honest that ticking it off is the whole interaction.
final class EventActionTests: XCTestCase {

    private func event(_ kind: EventKind) -> ScheduledEvent {
        ScheduledEvent(kind: kind, title: "T", detail: "", time: Date(),
                       durationMinutes: 10, isCritical: true)
    }

    func testActionableKindsHaveAPath() {
        XCTAssertEqual(EventAction.primary(for: event(.meal)), .logMeal)
        XCTAssertEqual(EventAction.primary(for: event(.workout)), .startWorkout)
        XCTAssertEqual(EventAction.primary(for: event(.weighIn)), .logWeight)
        XCTAssertEqual(EventAction.primary(for: event(.progressPhoto)), .takePhoto)
    }

    func testCheckOffOnlyKindsHaveNoAction() {
        for kind in [EventKind.wake, .caffeine, .mealPrep, .windDown, .sleep, .hydration, .custom] {
            XCTAssertNil(EventAction.primary(for: event(kind)), "\(kind) invented an action")
        }
    }

    func testStructuralBlocksHaveNoAction() {
        XCTAssertNil(EventAction.primary(for: event(.classSession)))
        XCTAssertNil(EventAction.primary(for: event(.commute)))
    }

    func testEveryActionHasLabelsAndAnIcon() {
        for action in [EventAction.logMeal, .startWorkout, .logWeight, .takePhoto] {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.shortTitle.isEmpty)
            XCTAssertFalse(action.systemImage.isEmpty)
        }
    }
}

/// The weigh-in path. Runs inside demo mode so nothing touches the real store —
/// the test bundle is hosted in the app and shares its UserDefaults.
final class WeighInTests: XCTestCase {

    private func demoState() -> AppState {
        let state = AppState()
        state.startDemo()
        return state
    }

    func testLoggingAWeightUpdatesTheLiveNumber() {
        let state = demoState()
        state.logWeight(213.5)
        XCTAssertEqual(state.profile.currentWeightLbs, 213.5)
        XCTAssertEqual(state.profile.weightHistory.last?.weightLbs, 213.5)
    }

    /// Macro targets are computed from `currentWeightLbs`, so a weigh-in has to
    /// move them — otherwise the whole point of weighing in is lost.
    func testMacroTargetsTrackTheNewWeight() {
        let state = demoState()
        let before = MetabolicEngine.dailyTargets(for: state.profile).calories
        state.logWeight(state.profile.currentWeightLbs - 25)
        let after = MetabolicEngine.dailyTargets(for: state.profile).calories
        XCTAssertLessThan(after, before)
    }

    /// Re-weighing after a number you didn't like must correct the day's entry,
    /// not stack a second point on the same date.
    func testReWeighingReplacesTodaysEntryRatherThanAppending() {
        let state = demoState()
        let before = state.profile.weightHistory.count
        state.logWeight(215)
        let afterFirst = state.profile.weightHistory.count
        state.logWeight(214)
        XCTAssertEqual(state.profile.weightHistory.count, afterFirst)
        XCTAssertGreaterThanOrEqual(afterFirst, before)
        XCTAssertEqual(state.profile.weightHistory.last?.weightLbs, 214)
    }

    func testPreviousEntryExcludesToday() {
        let state = demoState()
        state.logWeight(200)
        // The comparison number must be an earlier weigh-in, never the one just
        // entered — otherwise the sheet reads "0.0 lb level with 200.0".
        XCTAssertNotEqual(state.previousWeightEntry, 200)
    }
}

/// The workout event has to carry its prescription, or the Start button opens
/// a portal that doesn't match the plan it was launched from.
final class WorkoutEventWiringTests: XCTestCase {

    private func schedule(on date: Date) -> DaySchedule {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [], date: date)
        return ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                       busyBlocks: [], date: date)
    }

    func testWorkoutEventCarriesItsSession() {
        let monday = Fixture.date(2026, 9, 14)
        guard let workout = schedule(on: monday).events.first(where: { $0.kind == .workout }) else {
            return XCTFail("Expected a workout on a training day")
        }
        guard let session = workout.linkedWorkout else {
            return XCTFail("Workout event has no attached session — the portal has nothing to run")
        }
        XCTAssertEqual(session.focus.title, workout.title)
        XCTAssertFalse(session.exercises.isEmpty)
        XCTAssertGreaterThan(session.totalSets, 0)
    }

    func testNonWorkoutEventsCarryNoSession() {
        for event in schedule(on: Fixture.date(2026, 9, 14)).events where event.kind != .workout {
            XCTAssertNil(event.linkedWorkout, "\(event.title) carries a workout it shouldn't")
        }
    }

    /// The attached session must survive a save/load round trip, or resuming
    /// after a relaunch would find an empty portal.
    func testAScheduleWithAWorkoutRoundTripsThroughCoding() throws {
        let original = schedule(on: Fixture.date(2026, 9, 14))
        let decoded = try JSONDecoder().decode(
            DaySchedule.self, from: JSONEncoder().encode(original)
        )
        let session = decoded.events.first { $0.kind == .workout }?.linkedWorkout
        XCTAssertEqual(session?.exercises.count,
                       original.events.first { $0.kind == .workout }?.linkedWorkout?.exercises.count)
    }

    /// Schedules persisted before the portal shipped have no `linkedWorkout`.
    /// They must still decode, or the user loses their whole day on upgrade.
    func testAnEventEncodedWithoutAWorkoutStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"workout","title":"Lower Body Strength",
         "detail":"","time":0,"durationMinutes":60,"isCritical":true,"status":"pending"}
        """
        let event = try JSONDecoder().decode(ScheduledEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.linkedWorkout)
        XCTAssertEqual(event.kind, .workout)
    }

    func testRestLengthsAreSaneForEveryFocus() {
        for focus in [WorkoutFocus.lowerStrength, .upperPull, .rotationalPower, .sprintConditioning,
                      .ruckEndurance, .unilateralLegs, .core, .mobilityRecovery] {
            XCTAssertGreaterThanOrEqual(focus.restSeconds, 0)
            XCTAssertLessThanOrEqual(focus.restSeconds, 300, "\(focus) rests longer than anyone waits")
            XCTAssertFalse(focus.systemImage.isEmpty)
        }
    }
}
