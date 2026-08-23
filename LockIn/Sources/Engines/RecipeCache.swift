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

    private let defaults: UserDefaults
    private let poolKey = "spoonacular.recipePool"
    private let poolFetchedKey = "spoonacular.recipePoolFetchedAt"
    private let poolSignatureKey = "spoonacular.recipePoolSignature"
    private let quotaBlockedKey = "spoonacular.quotaBlockedUntil"

    /// Injectable so tests can run against an isolated suite instead of the
    /// real user defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Recipe pool

    /// A cached pool is reusable while it's under a week old AND was fetched
    /// for the same targets — changing your calorie goal or diet should
    /// invalidate it, otherwise you'd keep eating last week's numbers.
    func cachedPool(signature: String) -> [SpoonacularRecipe]? {
        guard let fetched = defaults.object(forKey: poolFetchedKey) as? Date,
              Date().timeIntervalSince(fetched) < 7 * 24 * 3600,
              defaults.string(forKey: poolSignatureKey) == signature,
              let data = defaults.data(forKey: poolKey),
              let pool = try? JSONDecoder().decode([SpoonacularRecipe].self, from: data)
        else { return nil }
        return pool
    }

    func store(pool: [SpoonacularRecipe], signature: String) {
        guard let data = try? JSONEncoder().encode(pool) else { return }
        defaults.set(data, forKey: poolKey)
        defaults.set(Date(), forKey: poolFetchedKey)
        defaults.set(signature, forKey: poolSignatureKey)
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
        [poolKey, poolFetchedKey, poolSignatureKey, quotaBlockedKey].forEach {
            defaults.removeObject(forKey: $0)
        }
    }
}
