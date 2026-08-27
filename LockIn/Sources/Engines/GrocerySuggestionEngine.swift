import Foundation

/// Everything the grocery screens need about the user, assembled once at the
/// call site.
///
/// Passed in rather than read from `AppState` inside the views: those screens
/// are two sheets deep, and threading the values explicitly keeps them
/// previewable, testable, and honest about what they depend on.
///
/// Lives here rather than beside `GoalContext` in Models because it reaches for
/// the engines, and the Screen Time extension compiles Models without them.
struct ShopSmartContext: Equatable {
    let goal: GoalContext
    let suggestions: [GrocerySuggestion]

    static func build(profile: UserProfile, loggedMeals: [LoggedMeal], now: Date = Date()) -> ShopSmartContext {
        let goal = GoalContext.build(
            profile: profile, targets: MetabolicEngine.dailyTargets(for: profile)
        )
        return ShopSmartContext(
            goal: goal,
            suggestions: GrocerySuggestionEngine.suggestions(
                loggedMeals: loggedMeals, profile: profile, goal: goal, now: now
            )
        )
    }
}

/// Turns the meal log into a few things worth buying.
///
/// **What this deliberately does not claim.** `loggedMeals` holds meals eaten
/// *off-plan* — it is not a record of everything the user ate, because meals
/// they followed from the plan never land here. So this engine says nothing
/// about daily totals or deficits: "you're 30 g under protein" would be a
/// confident lie on a day the user ate exactly as planned and logged nothing.
///
/// What the log genuinely supports is a claim about *composition* — the mix of
/// the food they reach for when they go off-plan. That's a real, checkable
/// signal, and it's the one that maps onto what to put in the trolley.
enum GrocerySuggestionEngine {

    /// Meals needed before the log is worth generalising from. Below this, one
    /// takeaway would define the user's entire "pattern".
    static let minimumMealsForAPattern = 4

    /// How far back to look. Long enough to smooth out a bad week, short enough
    /// that a diet change from two months ago stops counting.
    static let windowDays = 21

    static func suggestions(
        loggedMeals: [LoggedMeal],
        profile: UserProfile,
        goal: GoalContext,
        now: Date = Date()
    ) -> [GrocerySuggestion] {
        let recent = withinWindow(loggedMeals, now: now)
        var result: [GrocerySuggestion] = []

        if let protein = proteinSuggestion(recent, profile: profile, goal: goal) {
            result.append(protein)
        }
        if let repeated = repeatSuggestion(recent) {
            result.append(repeated)
        }
        // Always leaves the user with somewhere to go. On a fresh install the
        // staples are all there is, and they're still matched to the goal and
        // the diet rather than being generic filler.
        if result.count < 2 {
            result.append(contentsOf: staples(profile: profile, goal: goal)
                .prefix(3 - result.count))
        }
        return result
    }

    // MARK: - Rules

    /// The protein-per-calorie mix of what they choose off-plan, against what
    /// their targets ask for.
    private static func proteinSuggestion(
        _ meals: [LoggedMeal], profile: UserProfile, goal: GoalContext
    ) -> GrocerySuggestion? {
        guard meals.count >= minimumMealsForAPattern, goal.proteinPerCalorieTarget > 0 else { return nil }

        let calories = meals.reduce(0.0) { $0 + $1.macros.calories }
        let protein = meals.reduce(0.0) { $0 + $1.macros.proteinG }
        guard calories > 0 else { return nil }

        let ratio = protein / calories
        // Only speaks up when the gap is worth acting on. Within 15% of target
        // is noise, and a suggestion that fires every time stops being read.
        guard ratio < goal.proteinPerCalorieTarget * 0.85 else { return nil }

        let actual = Int((ratio * 100).rounded())
        let target = Int((goal.proteinPerCalorieTarget * 100).rounded())
        guard let pick = staples(profile: profile, goal: goal).first else { return nil }

        return GrocerySuggestion(
            id: "protein-mix",
            headline: "Your off-plan food runs light on protein",
            detail: "\(meals.count) meals logged in the last \(windowDays) days average \(actual) g protein per 100 kcal. Your targets want \(target).",
            query: pick.query
        )
    }

    /// The thing they buy again and again — the highest-leverage single swap,
    /// because it's the one that repeats.
    private static func repeatSuggestion(_ meals: [LoggedMeal]) -> GrocerySuggestion? {
        let counts = Dictionary(grouping: meals) { normalise($0.name) }
            .filter { !$0.key.isEmpty }
            .mapValues(\.count)

        // Twice is a coincidence; three times is a habit worth a better version.
        guard let (name, count) = counts.max(by: { $0.value < $1.value }), count >= 3 else { return nil }

        return GrocerySuggestion(
            id: "repeat-\(name)",
            headline: "You log \(name) a lot",
            detail: "\(count) times in the last \(windowDays) days. Worth seeing how the shelf compares.",
            query: name
        )
    }

    /// Protein staples that fit the diet, in rough order of how much protein
    /// they carry per calorie.
    ///
    /// Diet-gated rather than filtered afterwards: offering a vegan Greek
    /// yogurt is the kind of mistake that makes someone stop trusting the whole
    /// feature.
    static func staples(profile: UserProfile, goal: GoalContext) -> [GrocerySuggestion] {
        let queries: [(String, String)]
        switch profile.dietaryPattern {
        case .vegan:
            queries = [
                ("tofu", "Firm tofu is most of a day's protein for very few calories."),
                ("tempeh", "Fermented, high protein, and it holds up to actual cooking."),
                ("red lentils", "Cheap, filling, and the protein comes with fibre.")
            ]
        case .vegetarian:
            queries = [
                ("greek yogurt", "Plain Greek yogurt runs about twice the protein of regular."),
                ("cottage cheese", "One of the densest protein-per-calorie things on the shelf."),
                ("paneer", "Works in the food you already eat and carries real protein.")
            ]
        case .pescatarian:
            queries = [
                ("greek yogurt", "Plain Greek yogurt runs about twice the protein of regular."),
                ("canned tuna", "Almost pure protein per calorie, and it keeps."),
                ("cottage cheese", "One of the densest protein-per-calorie things on the shelf.")
            ]
        case .omnivore:
            queries = [
                ("greek yogurt", "Plain Greek yogurt runs about twice the protein of regular."),
                ("chicken breast", "The benchmark for protein per calorie."),
                ("cottage cheese", "One of the densest protein-per-calorie things on the shelf.")
            ]
        }

        let framing = goal.direction == .gain
            ? "Worth having in for a surplus."
            : "Worth having in."

        return queries.map { query, blurb in
            GrocerySuggestion(
                id: "staple-\(query)",
                headline: query.capitalisedFirst,
                detail: "\(blurb) \(framing)",
                query: query
            )
        }
    }

    // MARK: - Helpers

    private static func withinWindow(_ meals: [LoggedMeal], now: Date) -> [LoggedMeal] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) else { return meals }
        return meals.filter { $0.loggedAt >= cutoff }
    }

    /// Groups "Greek Yogurt" with "greek yogurt " so a habit isn't split across
    /// spellings and then missed.
    private static func normalise(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    var capitalisedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
