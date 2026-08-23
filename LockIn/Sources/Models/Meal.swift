import Foundation

enum MealSlot: String, Codable, CaseIterable { case breakfast, lunch, dinner, snack }

struct FoodItem: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    /// Macro values PER 100g, so the app can scale to any weighed portion.
    let per100g: MacroTargetsLite
    let prepAheadMinutes: Int?   // if non-nil, needs prep this many minutes before the meal (soak/marinate/cook)
    let prepInstructions: String?

    init(id: UUID = UUID(), name: String, per100g: MacroTargetsLite, prepAheadMinutes: Int? = nil, prepInstructions: String? = nil) {
        self.id = id
        self.name = name
        self.per100g = per100g
        self.prepAheadMinutes = prepAheadMinutes
        self.prepInstructions = prepInstructions
    }
}

struct MacroTargetsLite: Codable, Equatable {
    let calories: Double
    let proteinG: Double
    let fatG: Double
    let carbG: Double
}

struct MealComponent: Codable, Equatable, Identifiable {
    let id: UUID
    let food: FoodItem
    let gramsToWeigh: Double

    init(id: UUID = UUID(), food: FoodItem, gramsToWeigh: Double) {
        self.id = id
        self.food = food
        self.gramsToWeigh = gramsToWeigh
    }

    var macros: MacroTargetsLite {
        let f = gramsToWeigh / 100.0
        return MacroTargetsLite(
            calories: food.per100g.calories * f,
            proteinG: food.per100g.proteinG * f,
            fatG: food.per100g.fatG * f,
            carbG: food.per100g.carbG * f
        )
    }
}

struct Meal: Codable, Equatable, Identifiable {
    let id: UUID
    let slot: MealSlot
    let name: String
    var components: [MealComponent]

    init(id: UUID = UUID(), slot: MealSlot, name: String, components: [MealComponent]) {
        self.id = id
        self.slot = slot
        self.name = name
        self.components = components
    }

    var totalMacros: MacroTargetsLite {
        components.reduce(MacroTargetsLite(calories: 0, proteinG: 0, fatG: 0, carbG: 0)) { acc, c in
            MacroTargetsLite(
                calories: acc.calories + c.macros.calories,
                proteinG: acc.proteinG + c.macros.proteinG,
                fatG: acc.fatG + c.macros.fatG,
                carbG: acc.carbG + c.macros.carbG
            )
        }
    }

    /// Latest prep-ahead lead time among components, used to schedule a "prep now" reminder.
    var maxPrepAheadMinutes: Int? {
        components.compactMap { $0.food.prepAheadMinutes }.max()
    }
}
