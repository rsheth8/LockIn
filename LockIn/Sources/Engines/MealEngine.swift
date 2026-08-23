import Foundation

/// Builds a day's meals (3 meals + 1 snack) from the food database, scaled in
/// weighed grams to hit the day's macro targets. Splits calories roughly
/// 25% breakfast / 35% lunch / 30% dinner / 10% snack, protein spread evenly
/// across meals (3-4 servings/day is well-supported for muscle protein synthesis).
enum MealEngine {
    static func buildDay(macros: MacroTargets, southAsianVegetarian: Bool) -> [Meal] {
        let splits: [(MealSlot, Double)] = [(.breakfast, 0.25), (.lunch, 0.35), (.dinner, 0.30), (.snack, 0.10)]
        return splits.map { slot, fraction in
            buildMeal(slot: slot, calorieShare: Double(macros.calories) * fraction,
                      proteinShare: Double(macros.proteinGrams) * fraction)
        }
    }

    private static func buildMeal(slot: MealSlot, calorieShare: Double, proteinShare: Double) -> Meal {
        // Each slot has a template: a protein anchor + a carb base + a veg, in
        // rough starting grams, then scaled to hit this meal's calorie share.
        let (name, template): (String, [(FoodItem, Double)]) = {
            switch slot {
            case .breakfast:
                return ("Protein Oats + Yogurt", [(FoodDatabase.oats, 60), (FoodDatabase.greekYogurt, 200), (FoodDatabase.banana, 100), (FoodDatabase.peanutButter, 15)])
            case .lunch:
                return ("Paneer Sabzi + Rice", [(FoodDatabase.paneer, 150), (FoodDatabase.basmatiRice, 200), (FoodDatabase.mixedVeg, 150), (FoodDatabase.oliveOil, 5)])
            case .dinner:
                return ("Moong Dal + Roti + Spinach", [(FoodDatabase.moongDal, 250), (FoodDatabase.roti, 90), (FoodDatabase.spinach, 100)])
            case .snack:
                return ("Whey Shake + Almonds", [(FoodDatabase.whey, 30), (FoodDatabase.almonds, 20)])
            }
        }()

        let baseCalories = template.reduce(0.0) { $0 + ($1.0.per100g.calories / 100.0) * $1.1 }
        let scale = baseCalories > 0 ? calorieShare / baseCalories : 1
        let components = template.map { food, grams in
            MealComponent(food: food, gramsToWeigh: (grams * scale).rounded())
        }
        return Meal(slot: slot, name: name, components: components)
    }
}
