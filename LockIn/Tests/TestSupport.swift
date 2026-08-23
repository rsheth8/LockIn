import Foundation
@testable import LockIn

/// Shared fixtures. Profiles are built from `.blank` and mutated so a new field
/// on UserProfile doesn't break every test file at once.
enum Fixture {

    /// Rahil: 5'10", 220 → 180, male, vegetarian, cutting.
    static var rahil: UserProfile {
        var p = UserProfile.blank
        p.name = "Rahil"
        p.age = 22
        p.sex = .male
        p.heightInches = 70
        p.currentWeightLbs = 220
        p.goalWeightLbs = 180
        p.goalDirection = .cut
        p.activityLevel = .lightlyActive
        p.dietaryPattern = .vegetarian
        p.cuisinePreference = .southAsian
        p.fitnessGoals = [.fatLoss, .fastBowling, .hikingBackpacking]
        p.mealsPerDay = 4
        return p
    }

    /// A second, materially different person — the case that broke the
    /// original one-person build.
    static var femaleCut: UserProfile {
        var p = UserProfile.blank
        p.name = "Priya"
        p.age = 25
        p.sex = .female
        p.heightInches = 66
        p.currentWeightLbs = 150
        p.goalWeightLbs = 135
        p.goalDirection = .cut
        p.activityLevel = .lightlyActive
        p.dietaryPattern = .omnivore
        return p
    }

    /// Small frame where an unclamped 22% deficit falls below the safe floor.
    static var smallFemale: UserProfile {
        var p = UserProfile.blank
        p.age = 30
        p.sex = .female
        p.heightInches = 62
        p.currentWeightLbs = 115
        p.goalWeightLbs = 105
        p.goalDirection = .cut
        p.activityLevel = .sedentary
        return p
    }

    static var maleGain: UserProfile {
        var p = UserProfile.blank
        p.age = 24
        p.sex = .male
        p.heightInches = 71
        p.currentWeightLbs = 160
        p.goalWeightLbs = 175
        p.goalDirection = .gain
        p.activityLevel = .moderatelyActive
        return p
    }

    static var vegan: UserProfile {
        var p = rahil
        p.dietaryPattern = .vegan
        return p
    }

    // MARK: - Dates

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    static func todayAt(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    static func busy(_ title: String, fromHour: Int, toHour: Int) -> BusyBlock {
        BusyBlock(title: title, start: todayAt(hour: fromHour), end: todayAt(hour: toHour))
    }

    // MARK: - Recipes

    static func recipe(id: Int, title: String = "Recipe", calories: Double, protein: Double,
                       fat: Double = 20, carbs: Double = 40, minutes: Int = 20) -> SpoonacularRecipe {
        SpoonacularRecipe(
            id: id,
            title: title,
            readyInMinutes: minutes,
            servings: 1,
            sourceUrl: nil,
            nutrition: .init(nutrients: [
                .init(name: "Calories", amount: calories, unit: "kcal"),
                .init(name: "Protein", amount: protein, unit: "g"),
                .init(name: "Fat", amount: fat, unit: "g"),
                .init(name: "Carbohydrates", amount: carbs, unit: "g")
            ])
        )
    }

    /// A pool spanning a realistic spread of calorie/protein combinations.
    static var recipePool: [SpoonacularRecipe] {
        [
            recipe(id: 1, title: "Paneer Bowl", calories: 520, protein: 42),
            recipe(id: 2, title: "Lentil Curry", calories: 430, protein: 28),
            recipe(id: 3, title: "Tofu Stir Fry", calories: 610, protein: 45),
            recipe(id: 4, title: "Chickpea Salad", calories: 380, protein: 22),
            recipe(id: 5, title: "Protein Oats", calories: 470, protein: 35),
            recipe(id: 6, title: "Big Thali", calories: 850, protein: 55, minutes: 60),
            recipe(id: 7, title: "Yogurt Parfait", calories: 260, protein: 24),
            recipe(id: 8, title: "Rajma Rice", calories: 700, protein: 30)
        ]
    }

    static func dayRecord(daysAgo: Int, total: Int = 9, confirmed: Int, missed: Int = 0,
                          distractions: Int = 0, weight: Double? = nil) -> DayRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
        return DayRecord(
            dayKey: DayRecord.key(for: date),
            date: date,
            criticalTotal: total,
            criticalConfirmed: confirmed,
            criticalMissed: missed,
            distractionEvents: distractions,
            weightLbs: weight
        )
    }
}
