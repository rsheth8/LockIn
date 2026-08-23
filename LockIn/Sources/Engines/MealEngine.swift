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

    /// Fetches (or reuses) the week's Spoonacular plan and maps today's meals.
    /// Returns nil whenever live data isn't usable, which tells the caller to
    /// fall back rather than surfacing an error to the user.
    static func liveMealsForToday(macros: MacroTargets, profile: UserProfile) async -> [Meal]? {
        guard Secrets.hasSpoonacular, !RecipeCache.shared.isQuotaBlocked else { return nil }

        let signature = RecipeCache.signature(calories: macros.calories, profile: profile)
        var plan = RecipeCache.shared.cachedPlan(signature: signature)

        if plan == nil {
            do {
                let fetched = try await SpoonacularClient.shared.weekMealPlan(
                    targetCalories: macros.calories, profile: profile
                )
                RecipeCache.shared.store(plan: fetched, signature: signature)
                plan = fetched
            } catch SpoonacularClient.ClientError.quotaExceeded {
                RecipeCache.shared.markQuotaExceeded()
                return nil
            } catch {
                return nil
            }
        }

        guard let dayPlan = plan?.week[weekdayKey(for: Date())], !dayPlan.meals.isEmpty else { return nil }

        let slots: [MealSlot] = [.breakfast, .lunch, .dinner]
        return dayPlan.meals.enumerated().map { index, planMeal in
            let slot = index < slots.count ? slots[index] : .snack
            // The plan endpoint gives per-day totals, not per-meal macros. Split
            // the day's nutrients across meals by the configured calorie share
            // so numbers stay coherent without spending a quota call per recipe.
            let share = shareForSlot(slot, mealsPerDay: profile.mealsPerDay)
            let component = MealComponent(
                food: FoodItem(
                    name: planMeal.title,
                    per100g: MacroTargetsLite(
                        calories: dayPlan.nutrients.calories * share,
                        proteinG: dayPlan.nutrients.protein * share,
                        fatG: dayPlan.nutrients.fat * share,
                        carbG: dayPlan.nutrients.carbohydrates * share
                    ),
                    prepAheadMinutes: (planMeal.readyInMinutes ?? 0) > 30 ? planMeal.readyInMinutes : nil,
                    prepInstructions: (planMeal.readyInMinutes ?? 0) > 30
                        ? "Takes about \(planMeal.readyInMinutes ?? 0) min — start it early or batch it the night before."
                        : nil
                ),
                gramsToWeigh: 100   // one serving; per100g already carries the serving's macros
            )
            return Meal(slot: slot, name: planMeal.title, components: [component], spoonacularID: planMeal.id)
        }
    }

    private static func shareForSlot(_ slot: MealSlot, mealsPerDay: Int) -> Double {
        splits(mealsPerDay: mealsPerDay).first { $0.0 == slot }?.1 ?? 0.25
    }

    private static func weekdayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date).lowercased()
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
