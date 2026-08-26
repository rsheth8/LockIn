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

/// How a component's portion should be read out loud.
///
/// Built-in database foods are genuinely weighed, so `per100g` means what it
/// says and the portion is grams on a scale. A Spoonacular recipe has no
/// per-gram truth — its nutrition is per *serving* — so those components store
/// `servings x 100` in `amount` (which keeps the /100 macro scaling correct)
/// and must never be labelled "g". Printing "141g" for 1.41 servings of stew
/// is worse than printing nothing: it looks weighable and isn't.
enum PortionUnit: String, Codable, Equatable {
    case grams
    case servings
}

struct MealComponent: Codable, Equatable, Identifiable {
    let id: UUID
    let food: FoodItem
    /// Grams when `unit == .grams`; servings x 100 when `unit == .servings`.
    /// Either way `amount / 100` is the multiplier for `food.per100g`.
    let gramsToWeigh: Double
    let unit: PortionUnit

    init(id: UUID = UUID(), food: FoodItem, gramsToWeigh: Double, unit: PortionUnit = .grams) {
        self.id = id
        self.food = food
        self.gramsToWeigh = gramsToWeigh
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey {
        case id, food, gramsToWeigh, unit
    }

    /// Schedules persisted before portion units existed decode as grams, which
    /// is what they were.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        food = try c.decode(FoodItem.self, forKey: .food)
        gramsToWeigh = try c.decode(Double.self, forKey: .gramsToWeigh)
        unit = try c.decodeIfPresent(PortionUnit.self, forKey: .unit) ?? .grams
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

    var servings: Double { gramsToWeigh / 100.0 }

    /// "180g" for weighed food, "1.4 servings" for a recipe portion.
    var portionLabel: String {
        switch unit {
        case .grams:
            return "\(Int(gramsToWeigh.rounded()))g"
        case .servings:
            let s = servings
            if abs(s - s.rounded()) < 0.05 {
                let whole = Int(s.rounded())
                return whole == 1 ? "1 serving" : "\(whole) servings"
            }
            return String(format: "%.1f servings", s)
        }
    }

    /// "180g Paneer" / "1.4 servings of Mushroom Tofu Stew".
    var portionDescription: String {
        switch unit {
        case .grams: return "\(portionLabel) \(food.name)"
        case .servings: return "\(portionLabel) of \(food.name)"
        }
    }
}

struct Meal: Codable, Equatable, Identifiable {
    let id: UUID
    let slot: MealSlot
    let name: String
    var components: [MealComponent]
    /// Set when this meal came from Spoonacular, so the UI can offer the full
    /// recipe and ingredient list on demand.
    var spoonacularID: Int?

    init(id: UUID = UUID(), slot: MealSlot, name: String, components: [MealComponent], spoonacularID: Int? = nil) {
        self.id = id
        self.slot = slot
        self.name = name
        self.components = components
        self.spoonacularID = spoonacularID
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

    /// "180g Paneer, 200g Basmati Rice" — the portion line shown on the timeline.
    /// Single source of truth so the schedule and a mid-day meal swap can never
    /// disagree about how a portion is phrased.
    var componentSummary: String {
        components.map(\.portionDescription).joined(separator: ", ")
    }

    var macroSummary: String {
        let m = totalMacros
        return "\(Int(m.calories))kcal · P\(Int(m.proteinG)) F\(Int(m.fatG)) C\(Int(m.carbG))"
    }

    /// The full timeline detail string for this meal.
    var detailLine: String {
        "\(componentSummary) — \(macroSummary)"
    }
}
