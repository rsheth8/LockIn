import Foundation

/// Resolves a food name to macros, cheapest source first.
///
/// The local database always leads — it's instant, offline, free and
/// hand-checked. After that the order depends on *what kind of food it is*,
/// because the two online sources are good at opposite things:
///
/// - **Open Food Facts** is a label database: excellent for ingredients and
///   packaged goods ("greek yogurt", "almonds"), poor for cooked dishes, where
///   it returns whatever supermarket ready-meal shares the name. Free, keyless,
///   no practical rate limit.
/// - **Spoonacular `guessNutrition`** estimates from a dish name, which is
///   exactly the cooked-dish case. Costs quota, so it's never tried first for
///   something a label database would answer well.
///
/// Stress testing is what forced this split: routing everything to Open Food
/// Facts first returned "céréales et légumes, façon pad thaï, bio" at 122
/// kcal/100g for a plate of pad thai — a confidently wrong number.
///
/// Every step degrades gracefully. If all sources miss, the caller falls back
/// to manual entry rather than logging a zeroed-out meal.
enum NutritionLookup {

    static func facts(
        for name: String,
        isDish: Bool = true,
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
        let labelLookup: () async -> NutritionFacts? = {
            guard let facts = try? await openFoodFacts.nutrition(for: name),
                  facts.reference.calories > 0 else { return nil }
            return facts
        }
        let dishEstimate: () async -> NutritionFacts? = {
            try? await spoonacular.guessNutrition(title: name)
        }

        let ordered = isDish ? [dishEstimate, labelLookup] : [labelLookup, dishEstimate]
        for attempt in ordered {
            if let facts = await attempt() { return facts }
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
