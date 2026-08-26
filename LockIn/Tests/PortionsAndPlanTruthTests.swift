import XCTest
@testable import LockIn

/// Guards the promises the Today screen makes about food.
///
/// Every test here corresponds to something the app used to state as fact and
/// get wrong: a serving labelled as a weighed gram amount, a protein target
/// printed over a plan that missed it by 50g, a dip served as lunch, and a
/// soak reminder scheduled for the middle of the night.
final class PortionUnitTests: XCTestCase {

    func testRecipePortionsAreServingsNotGrams() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.assemble(from: Fixture.recipePool, macros: macros,
                                        profile: Fixture.rahil, date: Date())

        let recipeComponents = meals.flatMap(\.components).filter { $0.food.name != "Whey Protein (powder)" }
        XCTAssertFalse(recipeComponents.isEmpty, "Expected the live pool to supply the meals")
        for component in recipeComponents {
            XCTAssertEqual(component.unit, .servings, "\(component.food.name) claimed to be weighable")
            XCTAssertFalse(component.portionLabel.hasSuffix("g"),
                           "\(component.portionLabel) reads as grams for a recipe portion")
            XCTAssertTrue(component.portionLabel.contains("serving"), component.portionLabel)
        }
    }

    func testDatabaseFoodsStayInGrams() {
        let macros = MetabolicEngine.dailyTargets(for: Fixture.rahil)
        let meals = MealEngine.buildDay(macros: macros, profile: Fixture.rahil)

        for component in meals.flatMap(\.components) {
            XCTAssertEqual(component.unit, .grams, "\(component.food.name) lost its weighed portion")
            XCTAssertTrue(component.portionLabel.hasSuffix("g"), component.portionLabel)
        }
    }

    func testWholeServingsReadNaturally() {
        let food = FoodDatabase.paneer
        XCTAssertEqual(MealComponent(food: food, gramsToWeigh: 100, unit: .servings).portionLabel, "1 serving")
        XCTAssertEqual(MealComponent(food: food, gramsToWeigh: 200, unit: .servings).portionLabel, "2 servings")
        XCTAssertEqual(MealComponent(food: food, gramsToWeigh: 141, unit: .servings).portionLabel, "1.4 servings")
        XCTAssertEqual(MealComponent(food: food, gramsToWeigh: 180, unit: .grams).portionLabel, "180g")
    }

    /// A schedule written before portion units existed must still decode, and
    /// must decode as grams — which is what those numbers were.
    func testLegacyComponentsDecodeAsGrams() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)",
         "gramsToWeigh":180,
         "food":{"id":"\(UUID().uuidString)","name":"Paneer",
                 "per100g":{"calories":265,"proteinG":18,"fatG":20,"carbG":4}}}
        """
        let component = try JSONDecoder().decode(MealComponent.self, from: Data(legacy.utf8))
        XCTAssertEqual(component.unit, .grams)
        XCTAssertEqual(component.portionLabel, "180g")
    }
}

final class ProteinReconciliationTests: XCTestCase {

    /// The live bug: a pool of ordinary recipes scaled to a calorie share lands
    /// tens of grams under a 1g/lb protein target, and the app printed the
    /// target anyway.
    func testAModestlyShortPoolIsBroughtAllTheWayToTarget() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let pool = (1...8).map {
            Fixture.recipe(id: $0, title: "Bowl \($0)", calories: 600, protein: 45, fat: 20, carbs: 60)
        }

        let meals = MealEngine.assemble(from: pool, macros: macros, profile: profile, date: Date())
        let delivered = meals.reduce(0.0) { $0 + $1.totalMacros.proteinG }

        XCTAssertGreaterThanOrEqual(
            delivered, Double(macros.proteinGrams) - MealEngine.proteinTolerance,
            "Day delivered \(Int(delivered))g against a \(macros.proteinGrams)g target"
        )
    }

    /// A pool this protein-poor cannot be rescued without prescribing absurd
    /// amounts of powder, so the cap binds. The contract is that the day gets
    /// much closer *and* that the remaining gap is reported rather than papered
    /// over — which is what `DaySchedule.proteinShortfall` exists for.
    func testAHopelessPoolGetsCloserAndStillReportsTheGap() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let pool = (1...8).map {
            Fixture.recipe(id: $0, title: "Pasta \($0)", calories: 600, protein: 18, fat: 20, carbs: 90)
        }

        let reconciled = MealEngine.assemble(from: pool, macros: macros, profile: profile, date: Date())
        let delivered = reconciled.reduce(0.0) { $0 + $1.totalMacros.proteinG }

        // Before reconciliation this pool lands around 60g.
        XCTAssertGreaterThan(delivered, 110, "Reconciliation barely moved the needle")
        XCTAssertLessThan(delivered, Double(macros.proteinGrams),
                          "This pool should not be able to reach target — check the cap")

        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros, sleepPlan: sleep,
                                               busyBlocks: [], date: Date(), liveMeals: reconciled)
        XCTAssertGreaterThan(schedule.proteinShortfall, 0,
                             "The remaining gap must surface on the day, not be hidden")
    }

    func testReconciliationHoldsTheCalorieBudget() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let pool = (1...8).map {
            Fixture.recipe(id: $0, title: "Pasta \($0)", calories: 600, protein: 18, fat: 20, carbs: 90)
        }

        let meals = MealEngine.assemble(from: pool, macros: macros, profile: profile, date: Date())
        let calories = meals.reduce(0.0) { $0 + $1.totalMacros.calories }

        // Adding protein must not blow the deficit open. 10% either way covers
        // the portion-scale clamp without letting a 300kcal overshoot through.
        XCTAssertEqual(calories, Double(macros.calories), accuracy: Double(macros.calories) * 0.1)
    }

    func testAnAlreadyGoodDayIsLeftAlone() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)

        // A day built to land exactly on both targets.
        let perMeal = MacroTargetsLite(
            calories: Double(macros.calories) / 4,
            proteinG: Double(macros.proteinGrams) / 4,
            fatG: Double(macros.fatGrams) / 4,
            carbG: Double(macros.carbGrams) / 4
        )
        let onTarget: [Meal] = [MealSlot.breakfast, .lunch, .snack, .dinner].map { slot in
            Meal(slot: slot, name: "On target",
                 components: [MealComponent(food: FoodItem(name: "Plate", per100g: perMeal),
                                            gramsToWeigh: 100, unit: .servings)])
        }

        let after = MealEngine.reconcileProtein(onTarget, macros: macros, profile: profile)
        XCTAssertEqual(after, onTarget, "A day that already hits its target must be left untouched")
    }

    func testVeganDaysNeverGetWhey() {
        var profile = Fixture.rahil
        profile.dietaryPattern = .vegan
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let pool = (1...8).map {
            Fixture.recipe(id: $0, title: "Rice bowl \($0)", calories: 600, protein: 14, fat: 18, carbs: 95)
        }

        let meals = MealEngine.assemble(from: pool, macros: macros, profile: profile, date: Date())
        let names = meals.flatMap(\.components).map(\.food.name)
        XCTAssertFalse(names.contains(FoodDatabase.whey.name), "A vegan plan was handed whey")
    }

    func testTopUpIsSplitAcrossMealsRatherThanDumpedInOne() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let pool = (1...8).map {
            Fixture.recipe(id: $0, title: "Pasta \($0)", calories: 600, protein: 18, fat: 20, carbs: 90)
        }

        let meals = MealEngine.assemble(from: pool, macros: macros, profile: profile, date: Date())
        let mealsWithPowder = meals.filter { meal in
            meal.components.contains { $0.food.name.contains("Protein (powder)") }
        }
        XCTAssertEqual(mealsWithPowder.count, meals.count,
                       "Protein should be spread across the day's feedings, not backloaded")
    }
}

final class CourseScreeningTests: XCTestCase {

    /// The live bug: `type=main course` alone let "Jalapeno Queso With Goat
    /// Cheese" through as lunch.
    func testDipsAndSaucesAreNeverAMainCourse() {
        let rejects = [
            Fixture.recipe(id: 1, title: "Jalapeno Queso With Goat Cheese", calories: 400, protein: 20),
            Fixture.recipe(id: 2, title: "Oven-Baked Feta Cheese Dip", calories: 300, protein: 12),
            Fixture.recipe(id: 3, title: "Creamy Ranch Dressing", calories: 200, protein: 4),
            Fixture.recipe(id: 4, title: "Mango Smoothie", calories: 250, protein: 6),
            Fixture.recipe(id: 5, title: "Roasted Red Pepper Hummus", calories: 320, protein: 14)
        ]
        for recipe in rejects {
            XCTAssertFalse(SpoonacularClient.MealType.mainCourse.accepts(recipe),
                           "\(recipe.title) was accepted as a main course")
        }
    }

    func testDishTypesAreScreenedEvenWhenTheTitleLooksFine() {
        let sneaky = Fixture.recipe(id: 6, title: "Roasted Garlic Delight", calories: 300,
                                    protein: 10, dishTypes: ["dip", "appetizer"])
        XCTAssertFalse(SpoonacularClient.MealType.mainCourse.accepts(sneaky))
    }

    func testRealMealsStillPass() {
        let keepers = [
            Fixture.recipe(id: 7, title: "Paneer Butter Masala", calories: 620, protein: 38,
                           dishTypes: ["main course", "lunch", "dinner"]),
            Fixture.recipe(id: 8, title: "Mushroom Tofu Stew", calories: 540, protein: 44,
                           dishTypes: ["main course"]),
            // dishTypes is often missing from search results; that must not
            // empty the pool.
            Fixture.recipe(id: 9, title: "Chickpea Curry", calories: 500, protein: 30)
        ]
        for recipe in keepers {
            XCTAssertTrue(SpoonacularClient.MealType.mainCourse.accepts(recipe),
                          "\(recipe.title) was rejected as a main course")
        }
    }

    func testSidesAreRejectedButSnacksAccepted() {
        let side = Fixture.recipe(id: 10, title: "Garlic Green Beans", calories: 120, protein: 4,
                                  dishTypes: ["side dish"])
        XCTAssertFalse(SpoonacularClient.MealType.mainCourse.accepts(side))
        XCTAssertTrue(SpoonacularClient.MealType.snack.accepts(side))
    }

    /// A pool cached under the old, unscreened query must not be reused.
    func testCacheSignatureChangedWithTheFilterRules() {
        let signature = RecipeCache.signature(calories: 2000, profile: Fixture.rahil)
        XCTAssertTrue(signature.hasPrefix(RecipeCache.filterVersion),
                      "Signature does not carry the filter version: \(signature)")
    }
}

final class PlanTruthTests: XCTestCase {

    func testFuelTotalsComeFromTheMealsNotTheTarget() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())

        guard let planned = schedule.plannedMacros else {
            return XCTFail("Schedule carried no planned macros")
        }
        let mealSum = schedule.events.filter { $0.kind == .meal }
            .compactMap(\.mealMacros)
            .reduce(0.0) { $0 + $1.calories }
        XCTAssertEqual(planned.calories, mealSum, accuracy: 0.01)
        XCTAssertGreaterThan(planned.calories, 0)
    }

    func testLocalPlanLandsWithinToleranceOfItsProteinTarget() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())
        XCTAssertLessThanOrEqual(
            schedule.proteinShortfall, Int(MealEngine.proteinTolerance),
            "Local database plan drifted further than the reconciliation tolerance"
        )
    }

    func testShortfallIsReportedRatherThanHidden() {
        let profile = Fixture.rahil
        var macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        var schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())
        // Raise the bar past what the plan delivers and confirm the gap surfaces.
        macros = MacroTargets(calories: macros.calories, proteinGrams: macros.proteinGrams + 60,
                              fatGrams: macros.fatGrams, carbGrams: macros.carbGrams,
                              tdeeMaintenance: macros.tdeeMaintenance,
                              deficitPercent: macros.deficitPercent,
                              direction: macros.direction, hitSafetyFloor: macros.hitSafetyFloor)
        schedule.macros = macros
        XCTAssertGreaterThan(schedule.proteinShortfall, 0)
    }

    /// A schedule from before macros were carried per meal must not crash or
    /// claim a shortfall it can't know about.
    func testSchedulesWithoutPerMealMacrosReportNoShortfall() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        var schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())
        for index in schedule.events.indices { schedule.events[index].mealMacros = nil }

        XCTAssertNil(schedule.plannedMacros)
        XCTAssertEqual(schedule.proteinShortfall, 0)
    }
}

final class PrepTimingTests: XCTestCase {

    /// The live bug: an overnight soak scheduled the prep reminder for the
    /// small hours, so the day opened with a promise already broken.
    func testPrepIsNeverScheduledBeforeYouAreAwake() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())

        let preps = schedule.events.filter { $0.kind == .mealPrep }
        XCTAssertFalse(preps.isEmpty, "Expected at least one prep-ahead reminder to check")
        for prep in preps {
            XCTAssertGreaterThanOrEqual(
                prep.time, sleep.targetWakeTime,
                "\(prep.title) was scheduled before wake at \(sleep.targetWakeTime)"
            )
        }
    }

    func testPrepStillLeadsItsMeal() {
        let profile = Fixture.rahil
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        let schedule = ScheduleEngine.buildDay(profile: profile, macros: macros,
                                               sleepPlan: sleep, busyBlocks: [], date: Date())

        for prep in schedule.events where prep.kind == .mealPrep {
            guard let meal = schedule.events.first(where: {
                $0.kind == .meal && $0.linkedMealID == prep.linkedMealID
            }) else { continue }
            XCTAssertLessThan(prep.time, meal.time, "\(prep.title) does not precede its meal")
        }
    }
}
