import Foundation

/// Which way the person is trying to move. Drives whether MetabolicEngine
/// applies a deficit, a surplus, or holds at maintenance.
enum GoalDirection: String, Codable, CaseIterable, Identifiable {
    case cut        // fat loss
    case maintain   // hold weight, improve performance/composition slowly
    case recomp     // maintenance calories, high protein, gain muscle while losing fat
    case gain       // deliberate muscle gain in a surplus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cut: return "Lose fat"
        case .maintain: return "Maintain"
        case .recomp: return "Recomp"
        case .gain: return "Build muscle"
        }
    }

    var blurb: String {
        switch self {
        case .cut: return "Sustained calorie deficit. Weight comes down."
        case .maintain: return "Hold your weight, train for performance."
        case .recomp: return "Eat at maintenance, high protein. Slow but you keep your weight."
        case .gain: return "Small surplus. Muscle comes with some fat."
        }
    }

    /// Fraction of TDEE to add (+) or remove (−). A 10% surplus is the
    /// evidence-supported range for lean gain — bigger surpluses mostly add fat
    /// without accelerating muscle accrual (Garthe et al. 2013; Slater et al. 2019).
    var calorieAdjustment: Double {
        switch self {
        case .cut: return -0.22
        case .maintain: return 0
        case .recomp: return 0
        case .gain: return 0.10
        }
    }
}
