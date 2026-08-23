import Foundation

/// Caches the weekly Spoonacular plan on disk so the app makes roughly one
/// network call per week instead of one per meal. On the free tier (150
/// points/day) this is the difference between the feature working and the
/// feature running dry by Tuesday.
///
/// Also records quota exhaustion so we stop hammering an endpoint that's
/// already returning 402 for the rest of the day.
final class RecipeCache {
    static let shared = RecipeCache()

    private let defaults = UserDefaults.standard
    private let planKey = "spoonacular.weekPlan"
    private let planFetchedKey = "spoonacular.weekPlanFetchedAt"
    private let planSignatureKey = "spoonacular.weekPlanSignature"
    private let quotaBlockedKey = "spoonacular.quotaBlockedUntil"

    // MARK: - Week plan

    /// A cached plan is reusable while it's under a week old AND was generated
    /// for the same targets — changing your calorie goal should invalidate it,
    /// otherwise you'd keep eating last week's numbers.
    func cachedPlan(signature: String) -> SpoonacularWeekPlan? {
        guard let fetched = defaults.object(forKey: planFetchedKey) as? Date,
              Date().timeIntervalSince(fetched) < 7 * 24 * 3600,
              defaults.string(forKey: planSignatureKey) == signature,
              let data = defaults.data(forKey: planKey),
              let plan = try? JSONDecoder().decode(SpoonacularWeekPlan.self, from: data)
        else { return nil }
        return plan
    }

    func store(plan: SpoonacularWeekPlan, signature: String) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: planKey)
        defaults.set(Date(), forKey: planFetchedKey)
        defaults.set(signature, forKey: planSignatureKey)
    }

    /// Identifies what a cached plan was generated for.
    static func signature(calories: Int, profile: UserProfile) -> String {
        "\(calories)|\(profile.dietaryPattern.rawValue)|\(profile.cuisinePreference.rawValue)|\(profile.allergies.sorted().joined(separator: ","))"
    }

    // MARK: - Quota

    /// After a 402 we back off until tomorrow rather than retrying all day.
    func markQuotaExceeded() {
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 3600))
        defaults.set(tomorrow, forKey: quotaBlockedKey)
    }

    var isQuotaBlocked: Bool {
        guard let until = defaults.object(forKey: quotaBlockedKey) as? Date else { return false }
        return Date() < until
    }

    func clear() {
        [planKey, planFetchedKey, planSignatureKey, quotaBlockedKey].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}
