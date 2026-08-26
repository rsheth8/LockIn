import Foundation

/// Structured coaching brief produced by Claude from the user's free-text
/// "what I want to get good at" answer. Stored on the profile so WorkoutEngine
/// and the review screen can show it without re-calling the API.
struct TrainingBrief: Codable, Equatable {
    var summary: String
    var priorities: [String]
    var sessionEmphases: [String]
    var mappedGoalHints: [String]
    var cautions: [String]
    var generatedAt: Date

    static var empty: TrainingBrief {
        TrainingBrief(summary: "", priorities: [], sessionEmphases: [], mappedGoalHints: [], cautions: [], generatedAt: .distantPast)
    }

    var isEmpty: Bool { summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// A recipe the user liked enough to keep on their personal menu.
struct LikedRecipe: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var slot: MealSlot?
    var spoonacularID: Int?
    var calories: Double?
    var proteinG: Double?
    var sourceURL: String?
    var savedAt: Date

    init(id: String = UUID().uuidString, title: String, slot: MealSlot? = nil,
         spoonacularID: Int? = nil, calories: Double? = nil, proteinG: Double? = nil,
         sourceURL: String? = nil, savedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.slot = slot
        self.spoonacularID = spoonacularID
        self.calories = calories
        self.proteinG = proteinG
        self.sourceURL = sourceURL
        self.savedAt = savedAt
    }

    static func from(meal: Meal) -> LikedRecipe {
        LikedRecipe(
            title: meal.name,
            slot: meal.slot,
            spoonacularID: meal.spoonacularID,
            calories: meal.totalMacros.calories,
            proteinG: meal.totalMacros.proteinG
        )
    }
}
