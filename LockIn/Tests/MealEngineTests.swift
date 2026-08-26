import XCTest
@testable import LockIn

final class MealEngineTests: XCTestCase {

    // MARK: - Local fallback

    func testFallbackDayHitsCalorieTargetClosely() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.buildDay(macros: macros, profile: Fixture.rahil)
        let total = meals.reduce(0) { $0 + $1.totalMacros.calories }

        XCTAssertEqual(total, Double(macros.calories), accuracy: Double(macros.calories) * 0.02,
                       "Scaled fallback meals should land within 2% of the calorie target")
    }

    func testFallbackProducesRequestedNumberOfMeals() {
        var profile = Fixture.rahil
        for count in [3, 4, 5] {
            profile.mealsPerDay = count
            let macros = MetabolicEngine.dailyTargets(for: profile)
            XCTAssertEqual(MealEngine.buildDay(macros: macros, profile: profile).count, count)
        }
    }

    func testEveryMealCarriesAtLeastOneWeighableComponent() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        for meal in MealEngine.buildDay(macros: macros, profile: Fixture.rahil) {
            XCTAssertFalse(meal.components.isEmpty, "\(meal.name) has no components")
            XCTAssertTrue(meal.components.allSatisfy { $0.gramsToWeigh > 0 },
                          "\(meal.name) has a zero-gram component")
        }
    }

    func testVeganProfileNeverReceivesDairyOrWhey() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.vegan)
        let names = MealEngine.buildDay(macros: macros, profile: Fixture.vegan)
            .flatMap { $0.components.map { $0.food.name.lowercased() } }

        for banned in ["paneer", "yogurt", "whey", "egg"] {
            XCTAssertFalse(names.contains { $0.contains(banned) },
                           "Vegan plan contained \(banned): \(names)")
        }
    }

    func testVegetarianProfileStillGetsDairyProteins() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let names = MealEngine.buildDay(macros: macros, profile: Fixture.rahil)
            .flatMap { $0.components.map { $0.food.name.lowercased() } }
        XCTAssertTrue(names.contains { $0.contains("paneer") || $0.contains("yogurt") || $0.contains("whey") })
    }

    func testDislikedIngredientIsLeftOutOfTheLocalPlan() {
        var profile = Fixture.rahil
        profile.foodPreferences.dislikedIngredients = ["paneer"]
        let names = MealEngine.buildDay(macros: MetabolicEngine.dailyTargets(for: profile), profile: profile)
            .flatMap { $0.components.map { $0.food.name.lowercased() } }
        XCTAssertFalse(names.contains { $0.contains("paneer") })
        XCTAssertTrue(names.contains { $0.contains("tofu") }, "South-Asian lunch should fall back to tofu")
    }

    func testFavouriteIngredientBeatsAGenericTemplate() {
        var profile = Fixture.femaleCut
        profile.dietaryPattern = .omnivore
        profile.cuisinePreference = .american
        profile.foodPreferences.cuisines = [.american]
        profile.foodPreferences.favouriteIngredients = ["chicken"]
        let names = MealEngine.buildDay(macros: MetabolicEngine.dailyTargets(for: profile), profile: profile)
            .flatMap { $0.components.map { $0.food.name.lowercased() } }
        XCTAssertTrue(names.contains { $0.contains("chicken") })
    }

    func testFitCostPrefersAFavouriteTitleWhenMacrosAreClose() {
        var profile = Fixture.rahil
        profile.foodPreferences.favouriteIngredients = ["paneer"]
        let paneer = Fixture.recipe(id: 1, title: "Paneer Bowl", calories: 510, protein: 40)
        let generic = Fixture.recipe(id: 2, title: "Generic Bowl", calories: 500, protein: 40)
        let paneerCost = MealEngine.fitCost(paneer, targetCalories: 500, targetProtein: 40, profile: profile)
        let genericCost = MealEngine.fitCost(generic, targetCalories: 500, targetProtein: 40, profile: profile)
        XCTAssertLessThan(paneerCost, genericCost)
    }

    func testMealMacrosScaleLinearlyWithGrams() {
        let component = MealComponent(food: FoodDatabase.paneer, gramsToWeigh: 200)
        // Paneer is 265 kcal / 18 g protein per 100 g.
        XCTAssertEqual(component.macros.calories, 530, accuracy: 0.01)
        XCTAssertEqual(component.macros.proteinG, 36, accuracy: 0.01)
    }

    // MARK: - Live assembly from a recipe pool

    func testAssembledDayHitsCalorieTargetWithinTolerance() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                        profile: Fixture.rahil, date: Date())
        let total = meals.reduce(0) { $0 + $1.totalMacros.calories }

        XCTAssertEqual(total, Double(macros.calories), accuracy: Double(macros.calories) * 0.20,
                       "Assembled day drifted more than 20% from the calorie target")
    }

    /// The reason this whole path exists: Spoonacular's own meal planner hits
    /// calories while returning roughly half the protein we need.
    func testAssembledDayGetsMostOfTheProteinTarget() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                        profile: Fixture.rahil, date: Date())
        let protein = meals.reduce(0) { $0 + $1.totalMacros.proteinG }

        XCTAssertGreaterThan(protein, Double(macros.proteinGrams) * 0.6,
                             "Got \(Int(protein))g against a \(macros.proteinGrams)g target")
    }

    func testAssemblyProducesOneMealPerConfiguredSlot() {
        var profile = Fixture.rahil
        profile.mealsPerDay = 4
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let meals = MealEngine.assemble(from: Fixture.recipePool, macros: macros, profile: profile, date: Date())
        XCTAssertEqual(meals.count, 4)
    }

    func testAssemblyIsDeterministicForTheSameDay() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let day = Fixture.date(2026, 3, 14)
        let first = MealEngine.assemble(from: Fixture.recipePool, macros: macros, profile: Fixture.rahil, date: day)
        let second = MealEngine.assemble(from: Fixture.recipePool, macros: macros, profile: Fixture.rahil, date: day)

        XCTAssertEqual(first.map(\.name), second.map(\.name),
                       "Re-rendering the same day must not reshuffle the plan")
    }

    func testAssemblyVariesAcrossDays() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let monday = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                         profile: Fixture.rahil, date: Fixture.date(2026, 3, 16))
        let tuesday = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                          profile: Fixture.rahil, date: Fixture.date(2026, 3, 17))
        XCTAssertNotEqual(monday.map(\.name), tuesday.map(\.name),
                          "Consecutive days should rotate through the pool")
    }

    func testAssemblyAvoidsRepeatingTheSameRecipeWithinADay() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                        profile: Fixture.rahil, date: Date())
        let ids = meals.compactMap(\.spoonacularID)
        XCTAssertEqual(Set(ids).count, ids.count, "Same recipe served twice in one day")
    }

    func testServingsAreClampedToSaneRange() {
        // A pool of only tiny recipes must not prescribe ten servings.
        let tiny = [Fixture.recipe(id: 99, title: "Tiny", calories: 90, protein: 8)]
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: tiny, macros: macros, profile: Fixture.rahil, date: Date())

        // Only the recipe portions are servings-clamped. A protein top-up is a
        // weighed gram amount and is deliberately much smaller.
        for meal in meals {
            for component in meal.components where component.unit == .servings {
                XCTAssertLessThanOrEqual(component.gramsToWeigh, 300, "Servings exceeded the 3x clamp")
                XCTAssertGreaterThanOrEqual(component.gramsToWeigh, 50, "Servings fell below the 0.5x clamp")
            }
        }
    }

    func testAssemblyFallsBackWhenPoolHasUnusableNutrition() {
        let broken = [SpoonacularRecipe(id: 1, title: "Broken", readyInMinutes: nil,
                                        servings: nil, sourceUrl: nil, nutrition: nil)]
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: broken, macros: macros, profile: Fixture.rahil, date: Date())

        XCTAssertEqual(meals.count, Fixture.rahil.mealsPerDay)
        XCTAssertTrue(meals.allSatisfy { !$0.components.isEmpty },
                      "Zero-calorie recipes must fall back to the local database")
    }

    func testLongRecipesGetPrepAheadInstructions() {
        let slow = [Fixture.recipe(id: 5, title: "Slow Braise", calories: 600, protein: 40, minutes: 90)]
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: slow, macros: macros, profile: Fixture.rahil, date: Date())

        XCTAssertTrue(meals.contains { $0.maxPrepAheadMinutes != nil },
                      "A 90-minute recipe should schedule a prep reminder")
    }

    func testQuickRecipesDoNotGetPrepAheadInstructions() {
        let quick = [Fixture.recipe(id: 6, title: "Quick Bowl", calories: 600, protein: 40, minutes: 10)]
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: quick, macros: macros, profile: Fixture.rahil, date: Date())
        XCTAssertNil(meals.first?.maxPrepAheadMinutes)
    }

    // MARK: - Fit cost

    func testFitCostPrefersTheCloserMatch() {
        let onTarget = Fixture.recipe(id: 1, calories: 500, protein: 40)
        let wrongProtein = Fixture.recipe(id: 2, calories: 500, protein: 8)

        let good = MealEngine.fitCost(onTarget, targetCalories: 500, targetProtein: 40)
        let bad = MealEngine.fitCost(wrongProtein, targetCalories: 500, targetProtein: 40)
        XCTAssertLessThan(good, bad, "Protein mismatch must be penalised")
    }

    func testFitCostRejectsZeroCalorieRecipes() {
        let empty = Fixture.recipe(id: 3, calories: 0, protein: 0)
        XCTAssertEqual(MealEngine.fitCost(empty, targetCalories: 500, targetProtein: 40),
                       .greatestFiniteMagnitude)
    }
}
