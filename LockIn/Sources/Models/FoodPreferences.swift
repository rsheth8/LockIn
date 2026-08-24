import Foundation

/// Everything that makes the meal plan feel like *your* food rather than
/// generic diet fare. Adherence is the single biggest predictor of whether a
/// cut works, and people stick to food they actually want to eat — so this is
/// a performance feature, not a nicety.
struct FoodPreferences: Codable, Equatable {
    /// Cuisines to bias recipe search toward. Multi-select: constraining to one
    /// cuisine plus a protein floor returns almost nothing from the API.
    var cuisines: Set<CuisinePreference>

    /// Ingredients to steer meals toward — the things you'd happily eat daily.
    var favouriteIngredients: [String]

    /// Hard exclusions. Anything here never appears in a plan.
    var dislikedIngredients: [String]

    /// Medical intolerances, kept separate from dislikes because they map to a
    /// different (stricter) API parameter and must never be relaxed.
    var intolerances: [String]

    /// What's in the kitchen right now. Used to prefer recipes you can cook
    /// without another shop.
    var pantry: [PantryItem]

    static var empty: FoodPreferences {
        FoodPreferences(cuisines: [], favouriteIngredients: [],
                        dislikedIngredients: [], intolerances: [], pantry: [])
    }

    /// Pantry names only, for the search query.
    var pantryIngredientNames: [String] {
        pantry.filter { !$0.isRunningOut }.map(\.name)
    }

    /// Ingredients the search should try to include: pantry first (use what you
    /// have), then favourites. Capped — Spoonacular returns nothing if this list
    /// is long.
    var preferredIngredients: [String] {
        Array((pantryIngredientNames + favouriteIngredients).reduced())
    }

    /// The include-ingredients query: pantry first, then favourites, max three
    /// so the pool doesn't collapse to zero.
    var searchIncludeIngredients: [String] {
        Array(preferredIngredients.prefix(3))
    }

    /// Single cuisine for the legacy `UserProfile.cuisinePreference` field.
    var primaryCuisine: CuisinePreference {
        let selected = cuisines.subtracting([.noPreference])
        return selected.sorted { $0.rawValue < $1.rawValue }.first ?? .noPreference
    }
}

struct PantryItem: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Marked when you're nearly out, so the planner stops leaning on it.
    var isRunningOut: Bool
    var addedAt: Date

    init(id: UUID = UUID(), name: String, isRunningOut: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isRunningOut = isRunningOut
        self.addedAt = addedAt
    }
}

extension Sequence where Element == String {
    /// De-duplicates case-insensitively while preserving order, so "Paneer"
    /// and "paneer" don't both end up in the query.
    func reduced() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in self {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}

/// Common starting points so the pantry screen isn't an empty text field.
enum PantrySuggestions {
    static func forCuisines(_ cuisines: Set<CuisinePreference>, pattern: DietaryPattern) -> [String] {
        var items = ["eggs", "olive oil", "onion", "garlic", "rice"]

        if pattern == .vegetarian || pattern == .vegan {
            items += ["lentils", "chickpeas", "tofu", "black beans"]
        }
        if pattern == .vegetarian { items += ["paneer", "greek yogurt"] }
        if pattern == .omnivore || pattern == .pescatarian { items += ["chicken breast", "salmon"] }

        if cuisines.contains(.southAsian) { items += ["basmati rice", "moong dal", "spinach", "cumin", "turmeric"] }
        if cuisines.contains(.mediterranean) { items += ["feta", "tomatoes", "cucumber", "hummus"] }
        if cuisines.contains(.eastAsian) { items += ["soy sauce", "ginger", "sesame oil", "bok choy"] }
        if cuisines.contains(.latin) { items += ["black beans", "avocado", "lime", "tortillas"] }
        if cuisines.contains(.american) { items += ["potatoes", "cheddar", "broccoli"] }

        return items.reduced()
    }
}
