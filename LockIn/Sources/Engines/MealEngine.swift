import Foundation

/// Builds the day's meals. Prefers real Spoonacular recipes (cached weekly);
/// falls back to the built-in scaled food database whenever live data isn't
/// available — no key, no network, or quota exhausted. The fallback is a first
/// class path, not an error state: the day's plan must always render.
enum MealEngine {

    /// Calorie split across the day. Protein is spread roughly evenly regardless,
    /// since 3–4 servings/day supports muscle protein synthesis better than
    /// backloading it all into dinner (Areta et al. 2013; Mamerow et al. 2014).
    private static func splits(mealsPerDay: Int) -> [(MealSlot, Double)] {
        switch mealsPerDay {
        case ...3: return [(.breakfast, 0.30), (.lunch, 0.38), (.dinner, 0.32)]
        case 5: return [(.breakfast, 0.22), (.snack, 0.10), (.lunch, 0.30), (.snack, 0.10), (.dinner, 0.28)]
        default: return [(.breakfast, 0.25), (.lunch, 0.35), (.snack, 0.10), (.dinner, 0.30)]
        }
    }

    // MARK: - Live path

    /// Fetches (or reuses) the week's recipe pool and assembles today's meals
    /// from it. Returns nil whenever live data isn't usable, which tells the
    /// caller to fall back rather than surfacing an error to the user.
    static func liveMealsForToday(macros: MacroTargets, profile: UserProfile) async -> [Meal]? {
        guard Secrets.hasSpoonacular, !RecipeCache.shared.isQuotaBlocked else { return nil }

        let signature = RecipeCache.signature(calories: macros.calories, profile: profile)
        // Floor the per-serving protein requirement at the day's average
        // protein-per-meal so the pool can actually hit target.
        let perMeal = max(Int(Double(macros.proteinGrams) / Double(max(profile.mealsPerDay, 1)) * 0.7), 15)

        // Separate pools per meal type — a single untyped search returns dips
        // and sauces, which are fine on macros but wrong as a lunch. Both are
        // cached for the week, so this is two calls per week, not per day.
        let neededTypes = Set(splits(mealsPerDay: profile.mealsPerDay)
            .map { SpoonacularClient.MealType.forSlot($0.0) })

        var pools: [SpoonacularClient.MealType: [SpoonacularRecipe]] = [:]
        for type in neededTypes {
            if let cached = RecipeCache.shared.cachedPool(signature: signature, bucket: type.rawValue) {
                pools[type] = cached
                continue
            }
            do {
                let fetched = try await SpoonacularClient.shared.recipePool(
                    profile: profile, mealType: type, minProteinPerServing: perMeal
                )
                guard fetched.count >= SpoonacularClient.minimumUsablePool else { continue }
                RecipeCache.shared.store(pool: fetched, signature: signature, bucket: type.rawValue)
                pools[type] = fetched
            } catch SpoonacularClient.ClientError.quotaExceeded {
                RecipeCache.shared.markQuotaExceeded()
                return nil
            } catch {
                continue
            }
        }

        // Any slot without a usable pool falls back to the local database for
        // that meal only, rather than discarding the whole day's live plan.
        guard !pools.isEmpty else { return nil }
        return assemble(from: pools, macros: macros, profile: profile, date: Date())
    }

    /// Picks the best-fitting recipe for each slot and scales servings to hit
    /// that slot's calorie and protein share.
    ///
    /// Deterministic for a given day: the rotation offset comes from the date,
    /// so the plan doesn't reshuffle every time the view redraws, but does
    /// vary across the week.
    /// Convenience for a single undifferentiated pool (used by tests).
    static func assemble(from pool: [SpoonacularRecipe], macros: MacroTargets,
                         profile: UserProfile, date: Date) -> [Meal] {
        let mapped = Dictionary(uniqueKeysWithValues:
            Set(splits(mealsPerDay: profile.mealsPerDay).map { SpoonacularClient.MealType.forSlot($0.0) })
                .map { ($0, pool) })
        return assemble(from: mapped, macros: macros, profile: profile, date: date)
    }

    static func assemble(from pools: [SpoonacularClient.MealType: [SpoonacularRecipe]],
                         macros: MacroTargets, profile: UserProfile, date: Date) -> [Meal] {
        let splits = splits(mealsPerDay: profile.mealsPerDay)
        let dayOffset = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        var used = Set<Int>()

        return splits.enumerated().map { index, entry in
            let (slot, fraction) = entry
            let targetCalories = Double(macros.calories) * fraction
            let targetProtein = Double(macros.proteinGrams) * fraction

            let pool = pools[SpoonacularClient.MealType.forSlot(slot)] ?? []
            let available = pool.filter { !used.contains($0.id) }
            let searchSpace = available.isEmpty ? pool : available

            // Rank by fit, then rotate *within the shortlist* by day. Rotating
            // the whole pool before a `min` does nothing — the global best fit
            // wins regardless of array order, so every day served identical
            // meals. Choosing among the closest few keeps macros honest while
            // actually varying the week.
            let shortlist = searchSpace
                .filter { $0.macrosPerServing.calories > 0 }
                .sorted {
                    fitCost($0, targetCalories: targetCalories, targetProtein: targetProtein)
                        < fitCost($1, targetCalories: targetCalories, targetProtein: targetProtein)
                }
                .prefix(4)

            let best = shortlist.isEmpty
                ? nil
                : Array(shortlist)[((dayOffset + index) % shortlist.count + shortlist.count) % shortlist.count]

            guard let recipe = best, recipe.macrosPerServing.calories > 0 else {
                return buildMeal(slot: slot, calorieShare: targetCalories, profile: profile)
            }
            used.insert(recipe.id)

            // Scale servings to close the calorie gap, clamped so the app never
            // tells you to eat a sixth of a muffin or four whole dinners.
            let rawServings = targetCalories / recipe.macrosPerServing.calories
            let servings = min(max(rawServings, 0.5), 3)

            let per = recipe.macrosPerServing
            let component = MealComponent(
                food: FoodItem(
                    name: recipe.title,
                    // per100g here carries one serving's macros; gramsToWeigh
                    // is servings×100 so MealComponent's /100 scaling yields
                    // exactly `servings` portions.
                    per100g: per,
                    prepAheadMinutes: recipe.needsPrepAhead ? recipe.readyInMinutes : nil,
                    prepInstructions: recipe.needsPrepAhead
                        ? "Takes about \(recipe.readyInMinutes ?? 0) min — start early or batch it the night before."
                        : nil
                ),
                gramsToWeigh: (servings * 100).rounded()
            )
            return Meal(slot: slot, name: recipe.title, components: [component], spoonacularID: recipe.id)
        }
    }

    /// Squared relative error on calories and protein, protein weighted double
    /// because it's the macro that actually drives lean-mass retention and the
    /// one Spoonacular's own planner gets wrong.
    static func fitCost(_ recipe: SpoonacularRecipe, targetCalories: Double, targetProtein: Double) -> Double {
        let macros = recipe.macrosPerServing
        guard macros.calories > 0 else { return .greatestFiniteMagnitude }

        // Compare at the scaled serving size we'd actually prescribe.
        let servings = min(max(targetCalories / macros.calories, 0.5), 3)
        let calorieError = (macros.calories * servings - targetCalories) / max(targetCalories, 1)
        let proteinError = (macros.proteinG * servings - targetProtein) / max(targetProtein, 1)
        return calorieError * calorieError + 2 * proteinError * proteinError
    }


    // MARK: - Fallback path

    /// Built-in database, scaled in grams to hit the day's targets. Always
    /// available, works offline, no quota.
    static func buildDay(macros: MacroTargets, profile: UserProfile) -> [Meal] {
        splits(mealsPerDay: profile.mealsPerDay).map { slot, fraction in
            buildMeal(
                slot: slot,
                calorieShare: Double(macros.calories) * fraction,
                profile: profile
            )
        }
    }

    private static func buildMeal(slot: MealSlot, calorieShare: Double, profile: UserProfile) -> Meal {
        let (name, template) = template(for: slot, profile: profile)
        let baseCalories = template.reduce(0.0) { $0 + ($1.0.per100g.calories / 100.0) * $1.1 }
        let scale = baseCalories > 0 ? calorieShare / baseCalories : 1
        let components = template.map { food, grams in
            MealComponent(food: food, gramsToWeigh: (grams * scale).rounded())
        }
        return Meal(slot: slot, name: name, components: components)
    }

    /// Templates respect the dietary pattern — a vegan profile must never be
    /// handed paneer or yogurt.
    private static func template(for slot: MealSlot, profile: UserProfile) -> (String, [(FoodItem, Double)]) {
        let vegan = profile.dietaryPattern == .vegan

        switch slot {
        case .breakfast:
            if vegan {
                return ("Oats + Peanut Butter", [(FoodDatabase.oats, 60), (FoodDatabase.banana, 100), (FoodDatabase.peanutButter, 20)])
            }
            return ("Protein Oats + Yogurt", [(FoodDatabase.oats, 60), (FoodDatabase.greekYogurt, 200), (FoodDatabase.banana, 100), (FoodDatabase.peanutButter, 15)])
        case .lunch:
            if vegan {
                return ("Tofu Sabzi + Rice", [(FoodDatabase.tofuFirm, 180), (FoodDatabase.basmatiRice, 200), (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)])
            }
            return ("Paneer Sabzi + Rice", [(FoodDatabase.paneer, 150), (FoodDatabase.basmatiRice, 200), (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)])
        case .dinner:
            return ("Moong Dal + Roti + Spinach", [(FoodDatabase.moongDal, 250), (FoodDatabase.roti, 90), (FoodDatabase.spinach, 100)])
        case .snack:
            if vegan {
                return ("Chickpeas + Almonds", [(FoodDatabase.chana, 120), (FoodDatabase.almonds, 20)])
            }
            return ("Whey Shake + Almonds", [(FoodDatabase.whey, 30), (FoodDatabase.almonds, 20)])
        }
    }
}
