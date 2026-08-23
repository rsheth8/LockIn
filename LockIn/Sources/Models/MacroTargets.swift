import Foundation

struct MacroTargets: Codable, Equatable {
    let calories: Int
    let proteinGrams: Int
    let fatGrams: Int
    let carbGrams: Int
    let tdeeMaintenance: Int
    let deficitPercent: Double
}
