import Foundation

enum WorkoutFocus: String, Codable {
    case lowerStrength      // squat/hinge patterns — base strength for bowling power + rucking durability
    case upperPull          // pull/row/rotator-cuff — shoulder durability for bowling, pack-carrying posture
    case rotationalPower    // med ball throws, cable rotations — bowling-specific power transfer
    case sprintConditioning // repeat sprints/intervals — bowling run-up speed + match-day repeat efforts
    case ruckEndurance      // weighted incline walking / stairs — direct backpacking specificity
    case unilateralLegs     // step-ups, lunges, single-leg — trail stability, injury-proofing on descents
    case core               // anti-rotation/anti-extension — lumbar stress protection for fast bowlers
    case mobilityRecovery   // hips/shoulders/ankles/thoracic spine

    var title: String {
        switch self {
        case .lowerStrength: return "Lower Body Strength"
        case .upperPull: return "Upper Pull + Shoulder Health"
        case .rotationalPower: return "Rotational Power"
        case .sprintConditioning: return "Sprint Conditioning"
        case .ruckEndurance: return "Rucking / Loaded Cardio"
        case .unilateralLegs: return "Unilateral Leg Strength"
        case .core: return "Core & Anti-Rotation"
        case .mobilityRecovery: return "Mobility & Recovery"
        }
    }

    /// Default rest between sets, in seconds.
    ///
    /// Heavy compound strength work needs full phosphocreatine recovery or the
    /// later sets stop training strength and start training fatigue (~2–3 min).
    /// Power work rests long for the same reason — a slow med ball throw is a
    /// wasted rep. Conditioning, core and mobility rest short by design, because
    /// the incomplete recovery *is* the stimulus.
    var restSeconds: Int {
        switch self {
        case .lowerStrength, .upperPull: return 150
        case .rotationalPower, .unilateralLegs: return 120
        case .sprintConditioning: return 90
        case .core: return 60
        case .mobilityRecovery: return 30
        case .ruckEndurance: return 0   // one continuous effort, nothing to rest between
        }
    }

    var systemImage: String {
        switch self {
        case .lowerStrength: return "figure.strengthtraining.traditional"
        case .upperPull: return "figure.play"
        case .rotationalPower: return "figure.cricket"
        case .sprintConditioning: return "figure.run"
        case .ruckEndurance: return "figure.hiking"
        case .unilateralLegs: return "figure.step.training"
        case .core: return "figure.core.training"
        case .mobilityRecovery: return "figure.flexibility"
        }
    }
}

struct ExercisePrescription: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: String        // string to allow "8-10", "30s", "400m" etc.
    let note: String?

    init(id: UUID = UUID(), name: String, sets: Int, reps: String, note: String? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.note = note
    }
}

struct WorkoutSession: Codable, Equatable, Identifiable {
    let id: UUID
    let focus: WorkoutFocus
    let goalTags: [FitnessGoal]     // which goals this session serves, shown so the "why" is visible
    let exercises: [ExercisePrescription]
    let equipmentNote: String

    init(id: UUID = UUID(), focus: WorkoutFocus, goalTags: [FitnessGoal], exercises: [ExercisePrescription], equipmentNote: String) {
        self.id = id
        self.focus = focus
        self.goalTags = goalTags
        self.exercises = exercises
        self.equipmentNote = equipmentNote
    }

    var summaryLine: String {
        exercises.map { "\($0.name) \($0.sets)x\($0.reps)" }.joined(separator: ", ")
    }

    /// Every set in the session — the denominator the portal counts against.
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }

    /// Rest owed after a set of `exercise`. A single-set prescription (a ruck, a
    /// 5-minute jog) has nothing to rest *between*, so it goes straight on.
    func restSeconds(after exercise: ExercisePrescription) -> Int {
        exercise.sets <= 1 ? 0 : focus.restSeconds
    }
}

/// A workout left half-finished. Persisted so walking out of the portal —
/// deliberately, or because the phone locked and something else grabbed focus —
/// doesn't cost you your place in the session.
struct WorkoutProgress: Codable, Equatable {
    /// The `ScheduledEvent` this belongs to. Progress from a different event, or
    /// a different day, is stale and must not be resumed into.
    var eventID: UUID
    var dayKey: String
    /// Sets completed, parallel to `WorkoutSession.exercises`.
    var completedSets: [Int]
    var exerciseIndex: Int
    var elapsedSeconds: Int
}
