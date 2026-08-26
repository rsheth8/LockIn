import Foundation

/// Live recipe + nutrition data from Spoonacular.
///
/// Why a recipe *pool* rather than `/mealplanner/generate`: the meal-planner
/// endpoint only targets calories. Asked for a 2149 kcal vegetarian week it
/// returns ~87 g protein — less than half the 180 g target this app computes.
/// Since every macro number here is the point, we instead pull one pool of
/// protein-filtered recipes with full nutrition attached, cache it for the
/// week, and let `MealEngine` assemble days locally to actually hit the
/// targets. That's one network call per week, which also fits the free tier's
/// 150 points/day.
actor SpoonacularClient {
    static let shared = SpoonacularClient()

    private let session: URLSession
    private let host = "https://api.spoonacular.com"

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum ClientError: Error, Equatable {
        case missingKey
        case quotaExceeded
        case badResponse(status: Int)
    }

    /// Minimum pool size worth using. Below this the day can't be varied and
    /// the local database is the better answer.
    static let minimumUsablePool = 8

    /// A pool of recipes matching the person's diet, each carrying full
    /// nutrition so meals can be macro-matched without further calls.
    ///
    /// Filters are relaxed progressively because stacking them yields nothing:
    /// `diet=vegetarian&cuisine=Indian&minProtein=31` returns *zero* results
    /// against the live API, which silently sent every South-Asian vegetarian
    /// user to the offline fallback forever. Cuisine is only a preference, so
    /// it's dropped first; the protein floor is dropped last because macro
    /// matching can partly compensate but an empty pool can't.
    func recipePool(profile: UserProfile, mealType: MealType? = nil,
                    minProteinPerServing: Int = 20, count: Int = 40) async throws -> [SpoonacularRecipe] {
        guard Secrets.spoonacularKey != nil else { throw ClientError.missingKey }

        let attempts: [(cuisine: Bool, minProtein: Int?)] = [
            (cuisine: true, minProtein: minProteinPerServing),
            (cuisine: false, minProtein: minProteinPerServing),
            (cuisine: true, minProtein: nil),
            (cuisine: false, minProtein: nil)
        ]

        var best: [SpoonacularRecipe] = []
        for attempt in attempts {
            let results = try await search(profile: profile, count: count, mealType: mealType,
                                           includeCuisine: attempt.cuisine,
                                           minProtein: attempt.minProtein)
            if results.count > best.count { best = results }
            if best.count >= Self.minimumUsablePool { break }
        }
        return best
    }

    /// Spoonacular's `type` parameter. Without it the search happily returns
    /// dips, sauces and drinks, so lunch came back as "Herbed Goat Cheese
    /// Yogurt Dip" — technically on-macro, obviously not a meal.
    enum MealType: String {
        case mainCourse = "main course"
        case breakfast
        case snack

        /// Which slots each pool serves.
        static func forSlot(_ slot: MealSlot) -> MealType {
            switch slot {
            case .breakfast: return .breakfast
            case .lunch, .dinner: return .mainCourse
            case .snack: return .snack
            }
        }
    }

    private func search(profile: UserProfile, count: Int, mealType: MealType?,
                        includeCuisine: Bool, minProtein: Int?) async throws -> [SpoonacularRecipe] {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }

        var components = URLComponents(string: "\(host)/recipes/complexSearch")!
        var items: [URLQueryItem] = [
            .init(name: "apiKey", value: key),
            .init(name: "number", value: String(count)),
            .init(name: "addRecipeNutrition", value: "true"),
            .init(name: "sort", value: "random")
        ]
        if let mealType {
            items.append(.init(name: "type", value: mealType.rawValue))
        }
        if let minProtein {
            items.append(.init(name: "minProtein", value: String(minProtein)))
        }
        if let diet = profile.dietaryPattern.spoonacularDiet {
            items.append(.init(name: "diet", value: diet))
        }
        if includeCuisine, let cuisine = profile.cuisinePreference.spoonacularCuisine {
            items.append(.init(name: "cuisine", value: cuisine))
        }
        if !profile.allergies.isEmpty {
            items.append(.init(name: "intolerances", value: profile.allergies.joined(separator: ",")))
        }
        components.queryItems = items

        let data = try await get(components.url!)
        return try JSONDecoder().decode(SpoonacularSearchResponse.self, from: data).results
    }

    /// Estimated nutrition for a dish given only its name.
    ///
    /// This is the one source that handles *cooked dishes* well — label
    /// databases are built around packaged products, so "chicken biryani"
    /// finds nothing useful there while this returns a plausible estimate.
    /// Values are per serving, not per 100g, and Spoonacular gives no serving
    /// weight, which is why `NutritionFacts` carries an explicit basis.
    ///
    /// Costs one quota point per call, so `NutritionLookup` only reaches it
    /// after the free sources have missed.
    func guessNutrition(title: String) async throws -> NutritionFacts? {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }
        var components = URLComponents(string: "\(host)/recipes/guessNutrition")!
        components.queryItems = [
            .init(name: "title", value: title),
            .init(name: "apiKey", value: key)
        ]

        let data = try await get(components.url!)
        let guess = try JSONDecoder().decode(SpoonacularNutritionGuess.self, from: data)
        guard guess.calories.value > 0 else { return nil }

        return NutritionFacts(
            name: title,
            reference: MacroTargetsLite(
                calories: guess.calories.value,
                proteinG: guess.protein.value,
                fatG: guess.fat.value,
                carbG: guess.carbs.value
            ),
            basis: .perServing,
            source: .spoonacularEstimate
        )
    }

    /// Full detail including ingredient amounts, for the recipe sheet.
    func recipe(id: Int) async throws -> SpoonacularRecipeDetail {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }
        let url = URL(string: "\(host)/recipes/\(id)/information?includeNutrition=true&apiKey=\(key)")!
        let data = try await get(url)
        return try JSONDecoder().decode(SpoonacularRecipeDetail.self, from: data)
    }

    // MARK: - Transport

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(status: -1)
        }
        // 402 is Spoonacular's "daily quota used up".
        if http.statusCode == 402 { throw ClientError.quotaExceeded }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(status: http.statusCode)
        }
        return data
    }
}

// MARK: - Wire types

struct SpoonacularSearchResponse: Codable, Equatable {
    let results: [SpoonacularRecipe]
    let totalResults: Int?
}

/// A recipe with its nutrition, as returned by complexSearch when
/// `addRecipeNutrition=true`.
struct SpoonacularRecipe: Codable, Equatable, Identifiable {
    let id: Int
    let title: String
    let readyInMinutes: Int?
    let servings: Int?
    let sourceUrl: String?
    let nutrition: Nutrition?

    struct Nutrition: Codable, Equatable {
        let nutrients: [Nutrient]

        struct Nutrient: Codable, Equatable {
            let name: String
            let amount: Double
            let unit: String
        }

        /// Spoonacular returns nutrients as a flat named array, so values are
        /// looked up by name rather than by a fixed schema.
        func amount(of name: String) -> Double {
            nutrients.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.amount ?? 0
        }
    }

    /// Per-serving macros. Nutrition from complexSearch is already per serving.
    var macrosPerServing: MacroTargetsLite {
        guard let nutrition else { return MacroTargetsLite(calories: 0, proteinG: 0, fatG: 0, carbG: 0) }
        return MacroTargetsLite(
            calories: nutrition.amount(of: "Calories"),
            proteinG: nutrition.amount(of: "Protein"),
            fatG: nutrition.amount(of: "Fat"),
            carbG: nutrition.amount(of: "Carbohydrates")
        )
    }

    /// Anything that takes real time gets a prep-ahead reminder scheduled.
    var needsPrepAhead: Bool { (readyInMinutes ?? 0) > 30 }
}

/// Response from `guessNutrition` — each macro arrives as its own object with
/// a value and confidence range.
struct SpoonacularNutritionGuess: Codable, Equatable {
    let calories: Amount
    let carbs: Amount
    let fat: Amount
    let protein: Amount

    /// Spoonacular returns these as `{"value": 350, "unit": "calories"}` for
    /// calories but `{"value": "12g", "unit": "g"}` shapes vary by field, so
    /// the value is decoded leniently from either a number or a string with a
    /// trailing unit.
    struct Amount: Codable, Equatable {
        let value: Double

        private enum CodingKeys: String, CodingKey { case value }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Double.self, forKey: .value) {
                value = number
            } else if let text = try? container.decode(String.self, forKey: .value) {
                value = Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.").inverted)) ?? 0
            } else {
                value = 0
            }
        }

        init(value: Double) { self.value = value }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
        }
    }
}

struct SpoonacularRecipeDetail: Codable, Equatable {
    let id: Int
    let title: String
    let readyInMinutes: Int?
    let servings: Int?
    let sourceUrl: String?
    let extendedIngredients: [Ingredient]?

    struct Ingredient: Codable, Equatable {
        let id: Int?
        let name: String
        let amount: Double
        let unit: String
        let measures: Measures?

        struct Measures: Codable, Equatable {
            let metric: Measure?
            struct Measure: Codable, Equatable {
                let amount: Double
                let unitShort: String
            }
        }

        /// Grams where Spoonacular provides a metric measure — that's what the
        /// food-scale flow needs.
        var grams: Double? {
            guard let metric = measures?.metric else { return nil }
            switch metric.unitShort.lowercased() {
            case "g", "gram", "grams": return metric.amount
            case "kg": return metric.amount * 1000
            case "ml": return metric.amount   // close enough for most liquids
            default: return nil
            }
        }
    }
}
