import Foundation

/// Performance goals layered on top of the fat-loss cut. Each maps to specific
/// training emphases in WorkoutEngine — these are additive, not exclusive.
enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case fatLoss           // always on implicitly, kept explicit for display
    case fastBowling       // cricket fast bowling: rotational power, sprint speed, shoulder/lumbar durability
    case hikingBackpacking // extreme backpacking: loaded aerobic capacity, unilateral leg strength, durability under load

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fatLoss: return "Fat Loss"
        case .fastBowling: return "Fast Bowling (Cricket)"
        case .hikingBackpacking: return "Hiking / Backpacking"
        }
    }
}
