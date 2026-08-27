import Foundation

/// How much the shelf ranking should care about *your* targets versus the
/// label's own merits.
///
/// Three presets rather than two sliders. The weights interact — nudging one
/// implicitly moves the other — so a slider pair invites fiddling without ever
/// making it clear what changed. A named choice says what you get.
enum ShoppingPriority: String, Codable, CaseIterable, Identifiable {
    case health, balanced, goals

    var id: String { rawValue }

    /// Share of the blended score that comes from goal fit; the rest is the
    /// label's health read.
    var goalWeight: Double {
        switch self {
        case .health: return 0.25
        case .balanced: return 0.5
        case .goals: return 0.75
        }
    }

    var displayName: String {
        switch self {
        case .health: return "Healthiest"
        case .balanced: return "Balanced"
        case .goals: return "My targets"
        }
    }

    var blurb: String {
        switch self {
        case .health: return "Rank mostly on the label — sugar, sodium, fibre, processing."
        case .balanced: return "Even weight between a clean label and hitting your macros."
        case .goals: return "Rank mostly on protein-per-calorie against your daily targets."
        }
    }
}

/// What the ranking needs to know about the person, reduced to the few numbers
/// that actually change the answer.
///
/// `proteinPerCalorieTarget` is the load-bearing one. A 2,149 kcal day with a
/// 180 g protein target is 0.084 g/kcal — a demanding ratio that most of the
/// shelf fails. Expressing the goal as a *ratio* rather than a daily total is
/// what makes it usable while shopping, where there's no "today" to budget
/// against: it asks whether this food moves you toward that mix or away from it,
/// which is true whenever you eat it.
struct GoalContext: Equatable {
    let proteinPerCalorieTarget: Double
    let direction: GoalDirection
    let priority: ShoppingPriority

    static func build(profile: UserProfile, targets: MacroTargets) -> GoalContext {
        GoalContext(
            proteinPerCalorieTarget: targets.calories > 0
                ? Double(targets.proteinGrams) / Double(targets.calories)
                : 0,
            direction: targets.direction,
            priority: profile.shoppingPriority
        )
    }
}

/// A prompt on the Shop Smart landing screen, derived from what the person has
/// actually been logging.
///
/// Carries a query rather than results: firing six searches on screen open
/// would spend six round trips to fill a screen the user may scroll straight
/// past. The reasoning is the personalised part and it's free — the products
/// arrive when they tap.
struct GrocerySuggestion: Equatable, Identifiable, Hashable {
    let id: String
    /// The claim — "You're running lean on protein".
    let headline: String
    /// What in their data supports it. Kept concrete and checkable.
    let detail: String
    /// What tapping it searches for.
    let query: String
}
