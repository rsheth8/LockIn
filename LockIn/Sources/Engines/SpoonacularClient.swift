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
    private let apiKeyOverride: String?
    private let host = "https://api.spoonacular.com"

    init(session: URLSession = .shared, apiKey: String? = nil) {
        self.session = session
        self.apiKeyOverride = apiKey
    }

    private var resolvedAPIKey: String? {
        apiKeyOverride ?? Secrets.spoonacularKey
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
    /// user to the offline fallback forever.
    ///
    /// Preferences (cuisine, include-ingredients) drop first. Hard exclusions
    /// — diet, disliked ingredients, medical intolerances — are never relaxed.
    /// The protein floor is dropped last because macro matching can partly
    /// compensate but an empty pool can't.
    func recipePool(profile: UserProfile, mealType: MealType? = nil,
                    minProteinPerServing: Int = 20, count: Int = 40) async throws -> [SpoonacularRecipe] {
        guard resolvedAPIKey != nil else { throw ClientError.missingKey }

        let hasCuisine = !profile.resolvedCuisines.isEmpty
        let hasInclude = !profile.foodPreferences.searchIncludeIngredients.isEmpty

        var attempts: [(include: Bool, cuisine: Bool, minProtein: Int?)] = [
            (include: hasInclude, cuisine: hasCuisine, minProtein: minProteinPerServing),
            (include: false, cuisine: hasCuisine, minProtein: minProteinPerServing),
            (include: false, cuisine: false, minProtein: minProteinPerServing),
            (include: false, cuisine: false, minProtein: nil)
        ]
        // Drop duplicate attempts when a preference isn't set, so we don't
        // spend quota on identical queries.
        var seen = Set<String>()
        attempts = attempts.filter { attempt in
            let key = "\(attempt.include)|\(attempt.cuisine)|\(attempt.minProtein ?? -1)"
            return seen.insert(key).inserted
        }

        var best: [SpoonacularRecipe] = []
        for attempt in attempts {
            let results = try await search(profile: profile, count: count, mealType: mealType,
                                           includeIngredients: attempt.include,
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

        /// Things that are never a meal on their own, whatever their macros say.
        /// `type=main course` alone does not hold: Spoonacular tags plenty of
        /// dips and sauces as main courses, which is how "Jalapeno Queso With
        /// Goat Cheese" was served as lunch. Screening the returned dish types
        /// and titles is the second gate.
        static let condimentDishTypes: Set<String> = [
            "dip", "sauce", "condiment", "spread", "dressing", "marinade",
            "beverage", "drink", "frosting"
        ]

        static let condimentTitleWords: [String] = [
            "dip", "sauce", "queso", "salsa", "hummus", "spread", "dressing",
            "marinade", "chutney", "relish", "pesto", "aioli", "syrup", "jam",
            "glaze", "frosting", "seasoning", "rub", "smoothie", "cocktail",
            "margarita", "latte", "juice"
        ]

        /// True when this recipe is a plausible dish for the slot.
        func accepts(_ recipe: SpoonacularRecipe) -> Bool {
            let types = Set((recipe.dishTypes ?? []).map { $0.lowercased() })
            if !types.isDisjoint(with: Self.condimentDishTypes) { return false }

            let title = recipe.title.lowercased()
            let words = title.split { !$0.isLetter }.map(String.init)
            if words.contains(where: { Self.condimentTitleWords.contains($0) }) { return false }

            switch self {
            case .mainCourse:
                // A side or an appetiser isn't lunch either — but only reject
                // when Spoonacular actually said so, since dishTypes is often
                // missing and an empty set must not empty the pool.
                if types.isEmpty { return true }
                if !types.isDisjoint(with: ["main course", "main dish", "lunch", "dinner"]) { return true }
                return types.isDisjoint(with: ["side dish", "appetizer", "antipasti", "fingerfood", "dessert"])
            case .breakfast:
                if types.isEmpty { return true }
                return !types.contains("dessert")
            case .snack:
                return true
            }
        }
    }

    private func search(profile: UserProfile, count: Int, mealType: MealType?,
                        includeIngredients: Bool, includeCuisine: Bool,
                        minProtein: Int?) async throws -> [SpoonacularRecipe] {
        guard let key = resolvedAPIKey else { throw ClientError.missingKey }

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
        if includeCuisine {
            let cuisines = profile.resolvedCuisines.compactMap(\.spoonacularCuisine)
            if !cuisines.isEmpty {
                items.append(.init(name: "cuisine", value: cuisines.joined(separator: ",")))
            }
        }
        if includeIngredients {
            let include = profile.foodPreferences.searchIncludeIngredients
            if !include.isEmpty {
                items.append(.init(name: "includeIngredients", value: include.joined(separator: ",")))
            }
        }
        let excluded = profile.foodPreferences.dislikedIngredients.reduced()
        if !excluded.isEmpty {
            items.append(.init(name: "excludeIngredients", value: excluded.joined(separator: ",")))
        }
        let intolerances = profile.effectiveIntolerances
        if !intolerances.isEmpty {
            items.append(.init(name: "intolerances", value: intolerances.joined(separator: ",")))
        }
        components.queryItems = items

        let data = try await get(components.url!)
        let results = try JSONDecoder().decode(SpoonacularSearchResponse.self, from: data).results
        guard let mealType else { return results }
        return results.filter { mealType.accepts($0) }
    }

    /// Full detail including ingredient amounts, for the recipe sheet.
    func recipe(id: Int) async throws -> SpoonacularRecipeDetail {
        guard let key = resolvedAPIKey else { throw ClientError.missingKey }
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
    /// Spoonacular's own categorisation ("main course", "dip", "sauce", …).
    /// Absent on some results, which is why `MealType.accepts` also screens
    /// the title.
    let dishTypes: [String]?

    init(id: Int, title: String, readyInMinutes: Int? = nil, servings: Int? = nil,
         sourceUrl: String? = nil, dishTypes: [String]? = nil, nutrition: Nutrition? = nil) {
        self.id = id
        self.title = title
        self.readyInMinutes = readyInMinutes
        self.servings = servings
        self.sourceUrl = sourceUrl
        self.nutrition = nutrition
        self.dishTypes = dishTypes
    }

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
