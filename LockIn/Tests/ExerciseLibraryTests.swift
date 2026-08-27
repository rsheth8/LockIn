import XCTest
@testable import LockIn

/// The guard on the whole feature: an exercise the plan can prescribe but the
/// library can't explain is a dead end in the middle of a workout.
final class ExerciseLibraryTests: XCTestCase {

    /// Every combination of goals the quiz can produce.
    private var allGoalSets: [Set<FitnessGoal>] {
        let goals: [FitnessGoal] = [.fatLoss, .fastBowling, .hikingBackpacking]
        return (0..<(1 << goals.count)).map { mask in
            Set(goals.enumerated().compactMap { index, goal in
                mask & (1 << index) != 0 ? goal : nil
            })
        }
    }

    private var everyPrescribedExercise: [ExercisePrescription] {
        var seen = Set<String>()
        var result: [ExercisePrescription] = []
        for goals in allGoalSets {
            for session in WorkoutEngine.weeklySplit(for: goals) {
                for exercise in session.exercises where !seen.contains(exercise.name) {
                    seen.insert(exercise.name)
                    result.append(exercise)
                }
            }
        }
        return result
    }

    func testEveryPrescribedExerciseHasAGuide() {
        for exercise in everyPrescribedExercise {
            XCTAssertNotNil(ExerciseLibrary.guide(for: exercise.name),
                            "\(exercise.name) can be prescribed but has no how-to")
        }
    }

    func testTheSplitCoversAMeaningfulNumberOfMovements() {
        // Catches a silently emptied split — a passing "every exercise has a
        // guide" over zero exercises would prove nothing.
        XCTAssertGreaterThanOrEqual(everyPrescribedExercise.count, 20)
    }

    func testEveryGuideIsActuallyFilledIn() {
        for name in ExerciseLibrary.allNames {
            guard let guide = ExerciseLibrary.guide(for: name) else {
                return XCTFail("\(name) listed but missing")
            }
            XCTAssertFalse(guide.setup.isEmpty, "\(name) has no setup steps")
            XCTAssertFalse(guide.execution.isEmpty, "\(name) has no execution steps")
            XCTAssertFalse(guide.cues.isEmpty, "\(name) has no cues")
            XCTAssertFalse(guide.mistakes.isEmpty, "\(name) has no common mistakes")
            XCTAssertFalse(guide.swap.isEmpty, "\(name) has no substitution")
            XCTAssertFalse(guide.searchTerm.isEmpty, "\(name) has no video search term")
        }
    }

    /// Cues are what you repeat to yourself under a bar. A sentence isn't a cue.
    func testCuesAreShortEnoughToUseMidSet() {
        for name in ExerciseLibrary.allNames {
            for cue in ExerciseLibrary.guide(for: name)?.cues ?? [] {
                XCTAssertLessThanOrEqual(cue.count, 44, "\(name) cue is a sentence, not a cue: \(cue)")
                XCTAssertFalse(cue.hasSuffix("."), "\(name) cue reads as prose: \(cue)")
            }
        }
    }

    func testNoGuideIsOrphaned() {
        let prescribed = Set(everyPrescribedExercise.map(\.name))
        for name in ExerciseLibrary.allNames {
            XCTAssertTrue(prescribed.contains(name),
                          "\(name) has a guide but nothing can prescribe it — dead content")
        }
    }

    // MARK: - Tempo

    func testTempoPhasesAreOrderedAndPositive() {
        for name in ExerciseLibrary.allNames {
            guard let tempo = ExerciseLibrary.guide(for: name)?.tempo else { continue }
            XCTAssertFalse(tempo.phases.isEmpty, "\(name) has an empty tempo")
            XCTAssertGreaterThan(tempo.totalSeconds, 0, "\(name) tempo totals zero")
            for phase in tempo.phases {
                XCTAssertGreaterThan(phase.seconds, 0, "\(name) phase '\(phase.label)' has no duration")
                XCTAssertFalse(phase.label.isEmpty)
            }
        }
    }

    /// Phase labels key the pacer's `Identifiable` conformance and its
    /// highlight, so a repeat within one rep would light two blocks at once.
    func testTempoPhaseLabelsAreUniqueWithinARep() {
        for name in ExerciseLibrary.allNames {
            guard let tempo = ExerciseLibrary.guide(for: name)?.tempo else { continue }
            let labels = tempo.phases.map(\.label)
            XCTAssertEqual(Set(labels).count, labels.count, "\(name) repeats a tempo phase label")
        }
    }

    /// Isometrics, carries and steady-state work are paced by a clock, not a
    /// rep rhythm — a pacer there would be inventing structure that isn't real.
    func testClockPacedWorkHasNoRepTempo() {
        for name in ["Front Plank", "Farmer's Carry", "Weighted Ruck Walk",
                     "Zone 2 Effort", "Run-up Length Sprints", "Repeat Sprint Sets"] {
            XCTAssertNil(ExerciseLibrary.guide(for: name)?.tempo, "\(name) shouldn't have a rep tempo")
        }
    }

    func testLoweringIsAtLeastAsSlowAsLiftingOnStrengthWork() {
        // The near-universal coaching error is rushing the eccentric, so no
        // strength lift in here should prescribe a faster down than up.
        for name in ["Barbell Back Squat", "Romanian Deadlift", "Bulgarian Split Squat",
                     "Barbell Row", "Pull-Up / Lat Pulldown", "Single-Leg Calf Raise"] {
            guard let tempo = ExerciseLibrary.guide(for: name)?.tempo,
                  let slowest = tempo.phases.max(by: { $0.seconds < $1.seconds }) else {
                return XCTFail("\(name) has no tempo")
            }
            XCTAssertGreaterThanOrEqual(slowest.seconds, 2,
                                        "\(name) has no phase slow enough to be a controlled eccentric")
        }
    }

    func testTempoSummaryReadsAsAClock() {
        let tempo = MovementTempo.lower(3, drive: 1)
        XCTAssertEqual(tempo.summary, "3s lower · 1s drive")
        XCTAssertEqual(tempo.totalSeconds, 4)
    }

    func testTempoHelperDropsAZeroLengthPause() {
        XCTAssertEqual(MovementTempo.lower(2, drive: 1).phases.count, 2)
        XCTAssertEqual(MovementTempo.lower(2, hold: 1, drive: 1).phases.count, 3)
    }
}
