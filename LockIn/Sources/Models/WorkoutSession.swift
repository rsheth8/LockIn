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
}
