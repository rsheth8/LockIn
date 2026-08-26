import Foundation

/// Resolves a food name to macros, cheapest source first.
///
/// The ladder is ordered by cost and reliability, not preference:
///
/// 1. **Local database** — instant, offline, free, hand-checked. Only covers
///    the app's staples, but when it hits it's the best answer available.
/// 2. **Open Food Facts** — free, keyless, global, no practical rate limit.
///    Strong on packaged products, thin on home-cooked dishes.
/// 3. **Spoonacular `guessNutrition`** — the only source that handles cooked
///    dishes by name, but it costs quota, so it's last.
///
/// Every step degrades gracefully: if all three miss, the caller is expected
/// to fall back to manual entry rather than logging a zeroed-out meal.
enum NutritionLookup {

    static func facts(
        for name: String,
        localDatabase: [FoodItem] = FoodDatabase.all,
        openFoodFacts: OpenFoodFactsClient = .shared,
        spoonacular: SpoonacularClient = .shared
    ) async -> NutritionFacts? {
        if let local = localMatch(for: name, in: localDatabase) {
            return local
        }

        // Network sources are best-effort: a lookup failure should leave the
        // user on manual entry, never surface as an error they have to dismiss
        // before they can log their lunch.
        if let remote = try? await openFoodFacts.nutrition(for: name), remote.reference.calories > 0 {
            return remote
        }

        if let guess = try? await spoonacular.guessNutrition(title: name) {
            return guess
        }

        return nil
    }

    /// Matches a vocabulary name against the built-in database.
    ///
    /// Deliberately conservative — it only accepts a match when one name
    /// contains the other, because the local database is small and a fuzzy
    /// match here would confidently return the wrong macros rather than
    /// falling through to a source that actually knows the dish.
    static func localMatch(for name: String, in database: [FoodItem] = FoodDatabase.all) -> NutritionFacts? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }

        let match = database.first { item in
            let candidate = normalize(item.name)
            return candidate == needle
                || candidate.contains(needle)
                || needle.contains(candidate)
        }

        guard let match else { return nil }
        return NutritionFacts(name: match.name, reference: match.per100g,
                              basis: .per100g, source: .localDatabase)
    }

    /// Strips the parenthetical qualifiers the local database uses ("Basmati
    /// Rice (cooked)") so they don't block an otherwise clean match.
    private static func normalize(_ value: String) -> String {
        var result = value.lowercased()
        while let open = result.firstIndex(of: "("), let close = result[open...].firstIndex(of: ")") {
            result.removeSubrange(open...close)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
