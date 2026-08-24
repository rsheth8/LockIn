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
                    fitCost($0, targetCalories: targetCalories, targetProtein: targetProtein, profile: profile)
                        < fitCost($1, targetCalories: targetCalories, targetProtein: targetProtein, profile: profile)
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
    static func fitCost(_ recipe: SpoonacularRecipe, targetCalories: Double, targetProtein: Double,
                        profile: UserProfile? = nil) -> Double {
        let macros = recipe.macrosPerServing
        guard macros.calories > 0 else { return .greatestFiniteMagnitude }

        // Compare at the scaled serving size we'd actually prescribe.
        let servings = min(max(targetCalories / macros.calories, 0.5), 3)
        let calorieError = (macros.calories * servings - targetCalories) / max(targetCalories, 1)
        let proteinError = (macros.proteinG * servings - targetProtein) / max(targetProtein, 1)
        var cost = calorieError * calorieError + 2 * proteinError * proteinError
        if let profile {
            cost += preferencePenalty(title: recipe.title, profile: profile)
        }
        return cost
    }

    /// Soft ranking on top of macros: favourites and pantry items in the title
    /// pull a recipe forward, disliked ingredients push it back. Dislikes are
    /// also sent as `excludeIngredients`, so this is a second line of defence
    /// for the local pool and for titles the API still returned.
    static func preferencePenalty(title: String, profile: UserProfile) -> Double {
        let haystack = title.lowercased()
        var penalty = 0.0
        for dislike in profile.foodPreferences.dislikedIngredients {
            if matches(haystack, query: dislike) { penalty += 2.0 }
        }
        for favourite in profile.foodPreferences.favouriteIngredients {
            if matches(haystack, query: favourite) { penalty -= 0.20 }
        }
        for pantry in profile.foodPreferences.pantryIngredientNames {
            if matches(haystack, query: pantry) { penalty -= 0.12 }
        }
        return penalty
    }

    static func matches(_ haystack: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return haystack.contains(needle)
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

    /// Picks the highest-scoring template that the person's diet allows and
    /// their dislikes don't veto. Cuisine, favourites and pantry are soft
    /// bonuses so the fallback still feels like their food when the API is down.
    private static func template(for slot: MealSlot, profile: UserProfile) -> (String, [(FoodItem, Double)]) {
        let candidates = MealTemplate.all.filter { $0.slot == slot && $0.isAllowed(for: profile) }
        let ranked = candidates.max { lhs, rhs in
            lhs.score(for: profile) < rhs.score(for: profile)
        }
        guard let best = ranked else {
            return ("Mixed Plate", [(FoodDatabase.oats, 80), (FoodDatabase.banana, 100)])
        }
        return (best.name, best.foods)
    }
}

/// Offline meal options. First matching template used to be hardcoded South
/// Asian vegetarian; scoring now picks among these using the person's tastes.
private struct MealTemplate {
    let name: String
    let slot: MealSlot
    let foods: [(FoodItem, Double)]
    let cuisines: Set<CuisinePreference>
    let diets: Set<DietaryPattern>

    func isAllowed(for profile: UserProfile) -> Bool {
        guard diets.contains(profile.dietaryPattern) else { return false }
        for dislike in profile.foodPreferences.dislikedIngredients {
            if foods.contains(where: { MealEngine.matches($0.0.name.lowercased(), query: dislike) }) {
                return false
            }
        }
        return true
    }

    func score(for profile: UserProfile) -> Int {
        var score = 0
        let resolved = profile.resolvedCuisines
        if !resolved.isEmpty, !cuisines.isDisjoint(with: resolved) {
            score += 5
        }
        for favourite in profile.foodPreferences.favouriteIngredients {
            if foods.contains(where: { MealEngine.matches($0.0.name.lowercased(), query: favourite) }) {
                score += 3
            }
        }
        for pantry in profile.foodPreferences.pantryIngredientNames {
            if foods.contains(where: { MealEngine.matches($0.0.name.lowercased(), query: pantry) }) {
                score += 2
            }
        }
        return score
    }

    static let all: [MealTemplate] = {
        let veg: Set<DietaryPattern> = [.vegetarian, .omnivore, .pescatarian]
        let vegan: Set<DietaryPattern> = [.vegan, .vegetarian, .omnivore, .pescatarian]
        let pesc: Set<DietaryPattern> = [.pescatarian, .omnivore]
        let omni: Set<DietaryPattern> = [.omnivore]
        let anyCuisine: Set<CuisinePreference> = []

        return [
            MealTemplate(name: "Protein Oats + Yogurt", slot: .breakfast, foods: [
                (FoodDatabase.oats, 60), (FoodDatabase.greekYogurt, 200),
                (FoodDatabase.banana, 100), (FoodDatabase.peanutButter, 15)
            ], cuisines: anyCuisine, diets: veg),
            MealTemplate(name: "Oats + Peanut Butter", slot: .breakfast, foods: [
                (FoodDatabase.oats, 60), (FoodDatabase.banana, 100), (FoodDatabase.peanutButter, 20)
            ], cuisines: anyCuisine, diets: vegan),
            MealTemplate(name: "Eggs + Roti", slot: .breakfast, foods: [
                (FoodDatabase.egg, 120), (FoodDatabase.roti, 60), (FoodDatabase.spinach, 80)
            ], cuisines: [.southAsian], diets: veg),
            MealTemplate(name: "Yogurt + Feta Bowl", slot: .breakfast, foods: [
                (FoodDatabase.greekYogurt, 200), (FoodDatabase.feta, 40), (FoodDatabase.banana, 80)
            ], cuisines: [.mediterranean], diets: veg),

            MealTemplate(name: "Paneer Sabzi + Rice", slot: .lunch, foods: [
                (FoodDatabase.paneer, 150), (FoodDatabase.basmatiRice, 200),
                (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)
            ], cuisines: [.southAsian], diets: veg),
            MealTemplate(name: "Tofu Sabzi + Rice", slot: .lunch, foods: [
                (FoodDatabase.tofuFirm, 180), (FoodDatabase.basmatiRice, 200),
                (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)
            ], cuisines: [.southAsian, .eastAsian], diets: vegan),
            MealTemplate(name: "Chickpea Salad", slot: .lunch, foods: [
                (FoodDatabase.chana, 180), (FoodDatabase.feta, 40),
                (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 8)
            ], cuisines: [.mediterranean], diets: veg),
            MealTemplate(name: "Chicken + Rice", slot: .lunch, foods: [
                (FoodDatabase.chickenBreast, 160), (FoodDatabase.basmatiRice, 200),
                (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)
            ], cuisines: [.american, .southAsian], diets: omni),
            MealTemplate(name: "Salmon + Potatoes", slot: .lunch, foods: [
                (FoodDatabase.salmon, 150), (FoodDatabase.potatoes, 200), (FoodDatabase.mixedVeg, 120)
            ], cuisines: [.american, .mediterranean], diets: pesc),
            MealTemplate(name: "Black Bean Bowl", slot: .lunch, foods: [
                (FoodDatabase.blackBeans, 200), (FoodDatabase.basmatiRice, 160),
                (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 8)
            ], cuisines: [.latin, .american], diets: vegan),

            MealTemplate(name: "Moong Dal + Roti + Spinach", slot: .dinner, foods: [
                (FoodDatabase.moongDal, 250), (FoodDatabase.roti, 90), (FoodDatabase.spinach, 100)
            ], cuisines: [.southAsian], diets: vegan),
            MealTemplate(name: "Tofu + Veg", slot: .dinner, foods: [
                (FoodDatabase.tofuFirm, 180), (FoodDatabase.mixedVeg, 180),
                (FoodDatabase.basmatiRice, 150), (FoodDatabase.oliveOil, 5)
            ], cuisines: [.eastAsian], diets: vegan),
            MealTemplate(name: "Chicken + Potatoes", slot: .dinner, foods: [
                (FoodDatabase.chickenBreast, 170), (FoodDatabase.potatoes, 220), (FoodDatabase.mixedVeg, 140)
            ], cuisines: [.american], diets: omni),
            MealTemplate(name: "Salmon + Veg", slot: .dinner, foods: [
                (FoodDatabase.salmon, 160), (FoodDatabase.mixedVeg, 180), (FoodDatabase.oliveOil, 5)
            ], cuisines: [.mediterranean, .american], diets: pesc),

            MealTemplate(name: "Whey Shake + Almonds", slot: .snack, foods: [
                (FoodDatabase.whey, 30), (FoodDatabase.almonds, 20)
            ], cuisines: anyCuisine, diets: veg),
            MealTemplate(name: "Chickpeas + Almonds", slot: .snack, foods: [
                (FoodDatabase.chana, 120), (FoodDatabase.almonds, 20)
            ], cuisines: anyCuisine, diets: vegan),
            MealTemplate(name: "Yogurt + Almonds", slot: .snack, foods: [
                (FoodDatabase.greekYogurt, 180), (FoodDatabase.almonds, 15)
            ], cuisines: anyCuisine, diets: veg)
        ]
    }()
}
