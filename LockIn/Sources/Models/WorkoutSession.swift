import Foundation

enum WorkoutFocus: String, Codable {
    case push               // horizontal/vertical press + triceps — PPL
    case pull               // rows/pulldowns + rear delt — PPL
    case legs               // squat/hinge/unilateral — PPL
    case lowerStrength      // legacy alias kept for older saved schedules
    case upperPull          // legacy
    case rotationalPower    // bowling-specific power + sprint
    case sprintConditioning // legacy sprint day
    case ruckEndurance      // hike conditioning / zone 2
    case unilateralLegs     // legacy
    case core               // legacy
    case mobilityRecovery

    var title: String {
        switch self {
        case .push: return "Push (Chest / Shoulders / Tris)"
        case .pull: return "Pull (Back / Rear Delts)"
        case .legs: return "Legs (Squat / Hinge / Unilateral)"
        case .lowerStrength: return "Lower Body Strength"
        case .upperPull: return "Upper Pull + Shoulder Health"
        case .rotationalPower: return "Bowling Power + Sprint"
        case .sprintConditioning: return "Sprint Conditioning"
        case .ruckEndurance: return "Hike Conditioning / Zone 2"
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
    let reps: String
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
    let goalTags: [FitnessGoal]
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
