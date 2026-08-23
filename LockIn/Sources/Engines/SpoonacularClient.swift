import Foundation

/// Live recipe + nutrition data from Spoonacular.
///
/// Designed around the free tier's 150 points/day quota, which is the binding
/// constraint: a meal-plan generation costs points, so we fetch a whole week in
/// one call and cache it rather than querying per meal. When quota is exhausted
/// or the network is down, `MealEngine` falls back to the built-in food
/// database — the day's plan must never fail to render because of an API.
actor SpoonacularClient {
    static let shared = SpoonacularClient()

    private let session = URLSession.shared
    private let host = "https://api.spoonacular.com"

    enum ClientError: Error {
        case missingKey
        case quotaExceeded
        case badResponse(status: Int)
    }

    // MARK: - Meal plan

    /// Generates a week of meals hitting the daily calorie target. One call,
    /// cached for the week — this is the quota-efficient path.
    func weekMealPlan(targetCalories: Int, profile: UserProfile) async throws -> SpoonacularWeekPlan {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }

        var components = URLComponents(string: "\(host)/mealplanner/generate")!
        var items: [URLQueryItem] = [
            .init(name: "apiKey", value: key),
            .init(name: "timeFrame", value: "week"),
            .init(name: "targetCalories", value: String(targetCalories))
        ]
        if let diet = profile.dietaryPattern.spoonacularDiet {
            items.append(.init(name: "diet", value: diet))
        }
        if !profile.allergies.isEmpty {
            items.append(.init(name: "exclude", value: profile.allergies.joined(separator: ",")))
        }
        components.queryItems = items

        let data = try await get(components.url!)
        return try JSONDecoder().decode(SpoonacularWeekPlan.self, from: data)
    }

    /// Full nutrition for a specific recipe. Used to get exact macros for a
    /// meal the plan proposed, since the plan endpoint returns only calories.
    func nutrition(recipeID: Int) async throws -> SpoonacularNutrition {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }
        let url = URL(string: "\(host)/recipes/\(recipeID)/nutritionWidget.json?apiKey=\(key)")!
        let data = try await get(url)
        return try JSONDecoder().decode(SpoonacularNutrition.self, from: data)
    }

    /// Recipe detail — ingredients with amounts, so the app can tell you what
    /// to weigh and what needs prepping ahead.
    func recipe(id: Int) async throws -> SpoonacularRecipe {
        guard let key = Secrets.spoonacularKey else { throw ClientError.missingKey }
        let url = URL(string: "\(host)/recipes/\(id)/information?includeNutrition=true&apiKey=\(key)")!
        let data = try await get(url)
        return try JSONDecoder().decode(SpoonacularRecipe.self, from: data)
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

struct SpoonacularWeekPlan: Codable, Equatable {
    let week: [String: DayPlan]

    struct DayPlan: Codable, Equatable {
        let meals: [PlanMeal]
        let nutrients: Nutrients
    }

    struct PlanMeal: Codable, Equatable {
        let id: Int
        let title: String
        let readyInMinutes: Int?
        let servings: Int?
        let imageType: String?
    }

    struct Nutrients: Codable, Equatable {
        let calories: Double
        let protein: Double
        let fat: Double
        let carbohydrates: Double
    }
}

struct SpoonacularNutrition: Codable, Equatable {
    let calories: String
    let carbs: String
    let fat: String
    let protein: String

    /// Values arrive as strings with units ("32g", "410k"). Strip to a number.
    private static func numeric(_ raw: String) -> Double {
        Double(raw.filter { $0.isNumber || $0 == "." }) ?? 0
    }

    var caloriesValue: Double { Self.numeric(calories) }
    var proteinGrams: Double { Self.numeric(protein) }
    var fatGrams: Double { Self.numeric(fat) }
    var carbGrams: Double { Self.numeric(carbs) }
}

struct SpoonacularRecipe: Codable, Equatable {
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
        /// Grams where Spoonacular provides a metric measure — that's what the
        /// food-scale flow needs.
        let measures: Measures?

        struct Measures: Codable, Equatable {
            let metric: Measure?
            struct Measure: Codable, Equatable {
                let amount: Double
                let unitShort: String
            }
        }

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
