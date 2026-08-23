import Foundation

struct MacroTargets: Codable, Equatable {
    let calories: Int
    let proteinGrams: Int
    let fatGrams: Int
    let carbGrams: Int
    let tdeeMaintenance: Int
    /// Magnitude of the adjustment from maintenance, as a fraction.
    let deficitPercent: Double
    let direction: GoalDirection
    /// True when the calculated target was raised to the safe minimum intake.
    let hitSafetyFloor: Bool

    /// How the adjustment reads in the UI: "22% deficit", "10% surplus", "maintenance".
    var adjustmentLabel: String {
        switch direction {
        case .cut: return "\(Int(deficitPercent * 100))% deficit"
        case .gain: return "\(Int(deficitPercent * 100))% surplus"
        case .maintain, .recomp: return "maintenance"
        }
    }
}
