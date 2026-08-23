import Foundation

/// Builds a rotating training split from the user's active FitnessGoals.
///
/// Rationale:
/// - Fast bowling: the biggest injury risk is lumbar bone stress (spondylolysis)
///   from repeated trunk hyperextension/rotation under high workload — the
///   evidence-based countermeasures are progressive workload management,
///   anti-rotation/anti-extension core work, posterior chain + lower body
///   strength to absorb front-foot landing forces, and rotational power
///   training to transfer force efficiently (Saw et al., cricket fast bowling
///   injury literature; ECB/Cricket Australia workload guidelines).
/// - Hiking/backpacking under load: aerobic base (zone 2) + rucking builds
///   the specific loaded-carry endurance; unilateral leg strength (step-ups,
///   split squats) builds the stability and eccentric control descents demand,
///   which is where most trail injuries happen.
/// - Fat loss: any of the above sessions plus daily step/NEAT target keeps
///   the deficit achievable without over-relying on food restriction alone.
enum WorkoutEngine {
    /// A 6-day rotation; ScheduleEngine indexes into this by day-of-week so the
    /// plan repeats weekly with one rest day implied wherever no calendar gap exists.
    static func weeklySplit(for goals: Set<FitnessGoal>) -> [WorkoutSession] {
        var split: [WorkoutSession] = []

        split.append(lowerStrengthSession(goals: goals))

        if goals.contains(.fastBowling) {
            split.append(rotationalPowerSession())
            split.append(sprintConditioningSession())
        }

        if goals.contains(.hikingBackpacking) {
            split.append(ruckEnduranceSession())
            split.append(unilateralLegSession())
        }

        split.append(upperPullSession(goals: goals))
        split.append(coreSession(goals: goals))
        split.append(mobilitySession(goals: goals))

        return split
    }

    static func session(for date: Date, goals: Set<FitnessGoal>) -> WorkoutSession {
        let split = weeklySplit(for: goals)
        let dayIndex = Calendar.current.component(.weekday, from: date) % split.count
        return split[dayIndex]
    }

    // MARK: - Sessions

    private static func lowerStrengthSession(goals: Set<FitnessGoal>) -> WorkoutSession {
        var exercises = [
            ExercisePrescription(name: "Barbell Back Squat", sets: 4, reps: "5-6", note: "Base strength for front-foot landing force absorption."),
            ExercisePrescription(name: "Romanian Deadlift", sets: 3, reps: "8", note: "Posterior chain — protects the lower back under bowling/rucking load."),
            ExercisePrescription(name: "Walking Lunge", sets: 3, reps: "12/leg")
        ]
        if goals.contains(.hikingBackpacking) {
            exercises.append(ExercisePrescription(name: "Weighted Step-Up", sets: 3, reps: "10/leg", note: "Direct carryover to steep trail ascents."))
        }
        return WorkoutSession(focus: .lowerStrength, goalTags: [.fatLoss, .fastBowling, .hikingBackpacking], exercises: exercises, equipmentNote: "Gym / heavy dumbbells if home.")
    }

    private static func rotationalPowerSession() -> WorkoutSession {
        WorkoutSession(
            focus: .rotationalPower,
            goalTags: [.fastBowling],
            exercises: [
                ExercisePrescription(name: "Rotational Med Ball Throw", sets: 4, reps: "6/side", note: "Trains hip-shoulder separation used in the bowling action."),
                ExercisePrescription(name: "Cable Woodchop", sets: 3, reps: "10/side"),
                ExercisePrescription(name: "Bowling-Action Shadow Reps (no ball)", sets: 3, reps: "8/side", note: "Groove the action pattern without run-up load.")
            ],
            equipmentNote: "Med ball + cable stack, or resistance band substitute."
        )
    }

    private static func sprintConditioningSession() -> WorkoutSession {
        WorkoutSession(
            focus: .sprintConditioning,
            goalTags: [.fastBowling, .fatLoss],
            exercises: [
                ExercisePrescription(name: "Run-up Length Sprints", sets: 6, reps: "20-30m", note: "Match your actual bowling run-up distance."),
                ExercisePrescription(name: "Repeat Sprint Sets", sets: 4, reps: "10x20m, 20s rest", note: "Mirrors repeat spell demands in a match."),
                ExercisePrescription(name: "Easy Jog Recovery", sets: 1, reps: "5 min")
            ],
            equipmentNote: "Track, field, or open road."
        )
    }

    private static func ruckEnduranceSession() -> WorkoutSession {
        WorkoutSession(
            focus: .ruckEndurance,
            goalTags: [.hikingBackpacking, .fatLoss],
            exercises: [
                ExercisePrescription(name: "Weighted Ruck Walk", sets: 1, reps: "45-60 min", note: "Start ~10-15% bodyweight in pack, add incline before adding weight."),
                ExercisePrescription(name: "Zone 2 Effort", sets: 1, reps: "conversational pace", note: "Builds the aerobic base multi-day trips actually run on.")
            ],
            equipmentNote: "Weighted pack or plate carrier, incline treadmill/hill/stairs."
        )
    }

    private static func unilateralLegSession() -> WorkoutSession {
        WorkoutSession(
            focus: .unilateralLegs,
            goalTags: [.hikingBackpacking],
            exercises: [
                ExercisePrescription(name: "Bulgarian Split Squat", sets: 3, reps: "8-10/leg"),
                ExercisePrescription(name: "Step-Down (eccentric focus)", sets: 3, reps: "10/leg", note: "Controls descent forces — where most trail knee issues start."),
                ExercisePrescription(name: "Single-Leg Calf Raise", sets: 3, reps: "15/leg", note: "Ankle stability on uneven terrain.")
            ],
            equipmentNote: "Dumbbells, a step or bench."
        )
    }

    private static func upperPullSession(goals: Set<FitnessGoal>) -> WorkoutSession {
        var exercises = [
            ExercisePrescription(name: "Pull-Up / Lat Pulldown", sets: 4, reps: "6-10"),
            ExercisePrescription(name: "Barbell Row", sets: 3, reps: "8"),
            ExercisePrescription(name: "Face Pull", sets: 3, reps: "15", note: "Rotator cuff durability — critical for repeated overhead bowling load.")
        ]
        if goals.contains(.hikingBackpacking) {
            exercises.append(ExercisePrescription(name: "Farmer's Carry", sets: 3, reps: "40m", note: "Grip + trap endurance for carrying a loaded pack."))
        }
        return WorkoutSession(focus: .upperPull, goalTags: [.fastBowling, .hikingBackpacking], exercises: exercises, equipmentNote: "Gym or bands + dumbbells.")
    }

    private static func coreSession(goals: Set<FitnessGoal>) -> WorkoutSession {
        WorkoutSession(
            focus: .core,
            goalTags: [.fastBowling, .fatLoss],
            exercises: [
                ExercisePrescription(name: "Pallof Press", sets: 3, reps: "12/side", note: "Anti-rotation — the core action most protective against fast-bowler lumbar stress."),
                ExercisePrescription(name: "Dead Bug", sets: 3, reps: "10/side"),
                ExercisePrescription(name: "Front Plank", sets: 3, reps: "45s")
            ],
            equipmentNote: "Band or cable for Pallof press, bodyweight otherwise."
        )
    }

    private static func mobilitySession(goals: Set<FitnessGoal>) -> WorkoutSession {
        WorkoutSession(
            focus: .mobilityRecovery,
            goalTags: [.fatLoss, .fastBowling, .hikingBackpacking],
            exercises: [
                ExercisePrescription(name: "Thoracic Spine Rotation Drill", sets: 2, reps: "10/side"),
                ExercisePrescription(name: "Hip Flexor + 90/90 Stretch", sets: 2, reps: "45s/side"),
                ExercisePrescription(name: "Ankle Dorsiflexion Drill", sets: 2, reps: "10/side", note: "Keeps ankles healthy for both bowling front-foot landing and trail terrain.")
            ],
            equipmentNote: "Just a mat."
        )
    }
}
