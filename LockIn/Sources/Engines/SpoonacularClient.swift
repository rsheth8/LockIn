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

    /// A pool of recipes matching the person's diet, each carrying full
    /// nutrition so meals can be macro-matched without further calls.
    func recipePool(profile: UserProfile, minProteinPerServing: Int = 20, count: Int = 40) async throws -> [SpoonacularRecipe] {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }

        var components = URLComponents(string: "\(host)/recipes/complexSearch")!
        var items: [URLQueryItem] = [
            .init(name: "apiKey", value: key),
            .init(name: "number", value: String(count)),
            .init(name: "addRecipeNutrition", value: "true"),
            .init(name: "minProtein", value: String(minProteinPerServing)),
            .init(name: "sort", value: "random")
        ]
        if let diet = profile.dietaryPattern.spoonacularDiet {
            items.append(.init(name: "diet", value: diet))
        }
        if let cuisine = profile.cuisinePreference.spoonacularCuisine {
            items.append(.init(name: "cuisine", value: cuisine))
        }
        if !profile.allergies.isEmpty {
            items.append(.init(name: "intolerances", value: profile.allergies.joined(separator: ",")))
        }
        components.queryItems = items

        let data = try await get(components.url!)
        return try JSONDecoder().decode(SpoonacularSearchResponse.self, from: data).results
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
