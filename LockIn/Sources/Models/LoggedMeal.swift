import Foundation

/// A meal that wasn't on the generated plan — either logged ad-hoc, or eaten
/// in place of a scheduled meal.
///
/// Deliberately holds **no image data**. The photo that may have helped
/// identify the food is used for recognition in memory and discarded; what's
/// worth keeping is the identification and the macros, which are a few hundred
/// bytes rather than a few megabytes per meal.
struct LoggedMeal: Codable, Equatable, Identifiable {
    let id: UUID
    /// What the food was decided to be — either a vocabulary match the user
    /// confirmed, or free text they typed.
    var name: String
    /// How much was eaten, already resolved to a human-readable string
    /// ("180 g", "1.5 servings") so the log doesn't need the basis to render.
    var portionDescription: String
    /// Macros for the portion actually eaten.
    var macros: MacroTargetsLite
    var loggedAt: Date
    /// Where the nutrition numbers came from, so the UI can be honest about
    /// how precise they are.
    var source: NutritionSource
    /// Set when this replaced a scheduled meal, so the day's plan can show what
    /// was actually eaten in that slot instead of what was planned.
    var replacedEventID: UUID?
    /// True when a photo was used to identify the food. Records that a photo
    /// happened, not the photo itself.
    var identifiedFromPhoto: Bool

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String,
        macros: MacroTargetsLite,
        loggedAt: Date = Date(),
        source: NutritionSource,
        replacedEventID: UUID? = nil,
        identifiedFromPhoto: Bool = false
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.macros = macros
        self.loggedAt = loggedAt
        self.source = source
        self.replacedEventID = replacedEventID
        self.identifiedFromPhoto = identifiedFromPhoto
    }

    var dayKey: String { DayRecord.key(for: loggedAt) }
}

/// Which lookup supplied the macros. Ordered loosely by how much to trust it:
/// the local database is hand-curated, Open Food Facts is crowd-sourced label
/// data, and a Spoonacular guess is an estimate from a dish name alone.
enum NutritionSource: String, Codable, Equatable {
    case localDatabase
    case openFoodFacts
    case spoonacularEstimate
    case manual

    var label: String {
        switch self {
        case .localDatabase: return "Built-in food data"
        case .openFoodFacts: return "Open Food Facts"
        case .spoonacularEstimate: return "Estimated from the dish name"
        case .manual: return "Entered by hand"
        }
    }

    /// Whether the numbers deserve a visible "this is an estimate" caveat.
    var isEstimate: Bool { self == .spoonacularEstimate }
}

/// How a source expresses its numbers, and therefore what portion question to
/// ask.
///
/// This distinction is load-bearing rather than pedantic: label data (local
/// database, Open Food Facts) is per 100 g and wants a weight, while
/// Spoonacular's `guessNutrition` estimates a whole serving of a dish and
/// gives no weight at all. Forcing the latter into grams would mean inventing
/// a serving weight, which is exactly the kind of fake precision this app
/// avoids elsewhere.
enum PortionBasis: Equatable {
    case per100g
    case perServing

    var unitLabel: String {
        switch self {
        case .per100g: return "g"
        case .perServing: return "servings"
        }
    }

    /// Sensible starting amount when the sheet opens.
    var defaultAmount: Double {
        switch self {
        case .per100g: return 200
        case .perServing: return 1
        }
    }

    /// Steps offered as quick-tap buttons, so the common cases don't need the
    /// keyboard.
    var quickAmounts: [Double] {
        switch self {
        case .per100g: return [100, 150, 200, 300, 400]
        case .perServing: return [0.5, 1, 1.5, 2]
        }
    }
}

/// Nutrition for a candidate food, before a portion is chosen.
struct NutritionFacts: Equatable {
    let name: String
    /// Macros for one unit of `basis` — either 100 g, or one serving.
    let reference: MacroTargetsLite
    let basis: PortionBasis
    let source: NutritionSource

    func scaled(to amount: Double) -> MacroTargetsLite {
        let factor: Double
        switch basis {
        case .per100g: factor = amount / 100.0
        case .perServing: factor = amount
        }
        return MacroTargetsLite(
            calories: reference.calories * factor,
            proteinG: reference.proteinG * factor,
            fatG: reference.fatG * factor,
            carbG: reference.carbG * factor
        )
    }

    /// "180 g" / "1.5 servings" — what gets stored on the log entry.
    func portionDescription(for amount: Double) -> String {
        switch basis {
        case .per100g:
            return "\(Int(amount.rounded())) g"
        case .perServing:
            let trimmed = amount == amount.rounded()
                ? String(Int(amount))
                : String(format: "%.1f", amount)
            return "\(trimmed) \(amount == 1 ? "serving" : "servings")"
        }
    }
}
