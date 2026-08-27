import XCTest
@testable import LockIn

// MARK: - Fixtures

private func groceryItem(
    id: String = "1",
    name: String = "Product",
    calories: Double,
    protein: Double,
    sugars: Double? = nil,
    satFat: Double? = nil,
    sodiumMg: Double? = nil,
    nutriScore: String? = nil
) -> GroceryItem {
    GroceryItem(
        id: id,
        name: name,
        quantityText: nil,
        imageURL: nil,
        per100g: MacroTargetsLite(calories: calories, proteinG: protein, fatG: 0, carbG: 0),
        quality: GroceryQuality(
            sugarsPer100g: sugars, saturatedFatPer100g: satFat, sodiumMgPer100g: sodiumMg,
            fiberPer100g: nil, nutriScoreGrade: nutriScore, novaGroup: nil,
            additivesCount: nil, ingredientCount: nil
        )
    )
}

/// Rahil's real numbers: 2149 kcal, 180 g protein — 0.084 g/kcal, a demanding
/// ratio that most of the shelf fails.
private func cutting(priority: ShoppingPriority = .balanced) -> GoalContext {
    GoalContext(proteinPerCalorieTarget: 180.0 / 2149.0, direction: .cut, priority: priority)
}

private func logged(_ name: String, kcal: Double, protein: Double, daysAgo: Int = 1) -> LoggedMeal {
    LoggedMeal(
        name: name,
        portionDescription: "1 serving",
        macros: MacroTargetsLite(calories: kcal, proteinG: protein, fatG: 0, carbG: 0),
        loggedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
        source: .openFoodFacts
    )
}

/// Ranking against the user's own targets.
final class GoalFitTests: XCTestCase {

    /// The whole point of the ratio. Greek yogurt (9 g / 53 kcal) clears the
    /// target; granola (8 g / 450 kcal) does not, even though both have a
    /// respectable-looking protein number per 100 g.
    func testProteinPerCalorieSeparatesLookalikes() {
        let yogurt = SmartChoiceEngine.goalFit(
            groceryItem(calories: 53, protein: 9), context: cutting())
        let granola = SmartChoiceEngine.goalFit(
            groceryItem(calories: 450, protein: 8), context: cutting())

        XCTAssertEqual(yogurt.value, 100)
        XCTAssertLessThan(granola.value, 30)
        XCTAssertTrue(granola.cautions.contains { $0.contains("protein") })
    }

    /// Per-100 g protein alone would rank these the same. It's the calorie cost
    /// that tells them apart.
    func testEqualProteinPer100gStillRanksByCalorieCost() {
        let lean = SmartChoiceEngine.goalFit(
            groceryItem(calories: 120, protein: 20), context: cutting())
        let rich = SmartChoiceEngine.goalFit(
            groceryItem(calories: 600, protein: 20), context: cutting())

        XCTAssertGreaterThan(lean.value, rich.value)
    }

    /// The same calorie density is a problem in a deficit and the point in a
    /// surplus, so it cannot be a fixed penalty.
    func testCalorieDensityIsReadThroughTheGoal() {
        let dense = groceryItem(calories: 600, protein: 25)
        let cut = SmartChoiceEngine.goalFit(dense, context: cutting())
        let gain = SmartChoiceEngine.goalFit(
            dense,
            context: GoalContext(proteinPerCalorieTarget: 0.06, direction: .gain, priority: .balanced)
        )

        XCTAssertGreaterThan(gain.value, cut.value)
        XCTAssertTrue(cut.cautions.contains { $0.contains("Calorie-dense") })
        XCTAssertTrue(gain.reasons.contains { $0.contains("surplus") })
    }

    /// A bag of salad is not a win when you're trying to gain.
    func testVeryLightFoodsAreAWarningOnASurplus() {
        let result = SmartChoiceEngine.goalFit(
            groceryItem(calories: 25, protein: 2),
            context: GoalContext(proteinPerCalorieTarget: 0.06, direction: .gain, priority: .balanced)
        )

        XCTAssertTrue(result.cautions.contains { $0.contains("hard to hit a surplus") })
    }

    /// Zero-calorie records would divide by zero; they get a neutral read
    /// rather than a crash or a fake verdict.
    func testItemsWithNoCaloriesGetANeutralGoalRead() {
        let result = SmartChoiceEngine.goalFit(
            groceryItem(calories: 0, protein: 0), context: cutting())

        XCTAssertEqual(result.value, 50)
        XCTAssertTrue(result.reasons.isEmpty)
    }

    /// Explanations have to name the number so the user can disagree with it.
    func testGoalReasonsQuoteProteinPer100Kcal() {
        let result = SmartChoiceEngine.goalFit(
            groceryItem(calories: 53, protein: 9), context: cutting())

        XCTAssertTrue(result.reasons.contains { $0.contains("17 g per 100 kcal") },
                      "9 g over 53 kcal is 17 g per 100 kcal")
    }
}

/// Blending the label's read with the user's targets.
final class BlendedScoreTests: XCTestCase {

    /// A sugary drink with a clean-ish label should still lose to a plain
    /// yogurt once the targets are in play.
    private let yogurt = groceryItem(id: "1", name: "Plain Yogurt", calories: 53, protein: 9,
                                     sugars: 3.5, satFat: 0.1, sodiumMg: 38)
    private let juice = groceryItem(id: "2", name: "Orange Juice", calories: 45, protein: 0.7,
                                    sugars: 8.3, satFat: 0, sodiumMg: 1)

    /// Without a context the score must be exactly the label's read — that's
    /// what keeps health scoring meaningful on its own.
    func testNoContextIsPureHealthScore() {
        XCTAssertEqual(SmartChoiceEngine.score(yogurt), SmartChoiceEngine.healthScore(yogurt))
    }

    func testTargetsPullTheRankingTowardProtein() {
        let plainGap = SmartChoiceEngine.healthScore(yogurt).value
            - SmartChoiceEngine.healthScore(juice).value
        let goalGap = SmartChoiceEngine.score(yogurt, context: cutting(priority: .goals)).value
            - SmartChoiceEngine.score(juice, context: cutting(priority: .goals)).value

        XCTAssertGreaterThan(goalGap, plainGap,
                             "the protein-poor option should fall further once targets count")
    }

    /// The preset has to actually change the answer, in the direction it says.
    func testPriorityPresetsMoveTheScore() {
        let health = SmartChoiceEngine.score(yogurt, context: cutting(priority: .health)).value
        let balanced = SmartChoiceEngine.score(yogurt, context: cutting(priority: .balanced)).value
        let goals = SmartChoiceEngine.score(yogurt, context: cutting(priority: .goals)).value

        XCTAssertLessThan(health, balanced)
        XCTAssertLessThan(balanced, goals)
        XCTAssertEqual(ShoppingPriority.balanced.goalWeight, 0.5)
    }

    /// Goal reasons lead — they're the half the user can't read off the packet.
    func testGoalReasoningComesFirst() {
        let score = SmartChoiceEngine.score(yogurt, context: cutting())

        XCTAssertTrue(score.reasons.first?.contains("per 100 kcal") == true)
    }

    /// Confidence describes how complete the *label* is. Blending in a goal fit
    /// derived from macros must not dress up a sparse record as a solid one.
    func testConfidenceStillReflectsTheLabelOnly() {
        let sparse = groceryItem(calories: 53, protein: 9)

        XCTAssertEqual(SmartChoiceEngine.score(sparse, context: cutting()).confidence, .thin)
    }
}

/// Suggestions derived from the meal log.
final class GrocerySuggestionTests: XCTestCase {

    private var vegetarian: UserProfile { Fixture.rahil }

    func testFlagsLoggedFoodThatRunsLightOnProtein() {
        // Six meals averaging ~2 g protein per 100 kcal against a target of 8.
        let meals = (1...6).map { logged("pasta", kcal: 600, protein: 12, daysAgo: $0) }

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: meals, profile: vegetarian, goal: cutting())

        let protein = result.first { $0.id == "protein-mix" }
        XCTAssertNotNil(protein)
        XCTAssertTrue(protein!.detail.contains("2 g protein per 100 kcal"))
        XCTAssertTrue(protein!.detail.contains("6 meals"))
    }

    /// A suggestion that fires every time stops being read.
    func testStaysQuietWhenTheMixIsAlreadyFine() {
        let meals = (1...6).map { logged("yogurt bowl", kcal: 300, protein: 30, daysAgo: $0) }

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: meals, profile: vegetarian, goal: cutting())

        XCTAssertNil(result.first { $0.id == "protein-mix" })
    }

    /// One takeaway must not define the user's entire "pattern".
    func testWillNotGeneraliseFromTooFewMeals() {
        let meals = [logged("chips", kcal: 500, protein: 5)]

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: meals, profile: vegetarian, goal: cutting())

        XCTAssertNil(result.first { $0.id == "protein-mix" })
        XCTAssertFalse(result.isEmpty, "but the user still gets somewhere to go")
    }

    /// Twice is a coincidence; three times is a habit worth a better version.
    func testSurfacesARepeatedItem() throws {
        let meals = (1...3).map { logged("Granola Bar", kcal: 450, protein: 6, daysAgo: $0) }
            + [logged("salad", kcal: 200, protein: 4, daysAgo: 4)]

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: meals, profile: vegetarian, goal: cutting())

        let repeated = try XCTUnwrap(result.first { $0.id.hasPrefix("repeat-") })
        XCTAssertEqual(repeated.query, "granola bar")
        XCTAssertTrue(repeated.headline.contains("granola bar"))
    }

    /// Casing must not split a habit across spellings and then miss it.
    func testRepeatMatchingIgnoresCasingAndPadding() {
        let meals = [
            logged("Greek Yogurt", kcal: 150, protein: 15, daysAgo: 1),
            logged("greek yogurt", kcal: 150, protein: 15, daysAgo: 2),
            logged("  greek yogurt ", kcal: 150, protein: 15, daysAgo: 3)
        ]

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: meals, profile: vegetarian, goal: cutting())

        XCTAssertNotNil(result.first { $0.id == "repeat-greek yogurt" })
    }

    /// Old habits shouldn't keep being suggested after a diet change.
    func testIgnoresMealsOutsideTheWindow() {
        let stale = (1...6).map {
            logged("pasta", kcal: 600, protein: 12,
                   daysAgo: GrocerySuggestionEngine.windowDays + $0)
        }

        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: stale, profile: vegetarian, goal: cutting())

        XCTAssertNil(result.first { $0.id == "protein-mix" })
    }

    /// Offering a vegan Greek yogurt is the kind of mistake that costs trust in
    /// the whole feature.
    func testStaplesRespectTheDietaryPattern() {
        var vegan = Fixture.rahil
        vegan.dietaryPattern = .vegan

        let queries = GrocerySuggestionEngine
            .staples(profile: vegan, goal: cutting())
            .map(\.query)

        XCTAssertFalse(queries.contains { $0.contains("yogurt") || $0.contains("paneer") })
        XCTAssertTrue(queries.contains("tofu"))
    }

    func testOmnivoreAndVegetarianGetDifferentStaples() {
        var omnivore = Fixture.rahil
        omnivore.dietaryPattern = .omnivore

        let omni = GrocerySuggestionEngine.staples(profile: omnivore, goal: cutting()).map(\.query)
        let veg = GrocerySuggestionEngine.staples(profile: vegetarian, goal: cutting()).map(\.query)

        XCTAssertTrue(omni.contains("chicken breast"))
        XCTAssertFalse(veg.contains("chicken breast"))
    }

    /// A fresh install must not land on an empty screen.
    func testEmptyLogStillProducesStaples() {
        let result = GrocerySuggestionEngine.suggestions(
            loggedMeals: [], profile: vegetarian, goal: cutting())

        XCTAssertGreaterThanOrEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.query.isEmpty })
    }
}

/// The setting behind the ranking blend.
final class ShoppingPriorityTests: XCTestCase {

    /// UserProfile uses synthesised Codable, which throws on a missing key for
    /// a non-optional field — a profile saved before this shipped has to keep
    /// decoding, or the user is dropped back into the quiz with no plan.
    func testProfilesSavedBeforeThisSettingExistedStillDecode() throws {
        var profile = Fixture.rahil
        profile.shoppingPriorityRaw = nil
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(profile)) as! [String: Any]
        json.removeValue(forKey: "shoppingPriorityRaw")

        let restored = try JSONDecoder().decode(
            UserProfile.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(restored.shoppingPriority, .balanced, "defaults rather than failing")
    }

    func testRoundTripsWhenSet() throws {
        var profile = Fixture.rahil
        profile.shoppingPriority = .goals

        let restored = try JSONDecoder().decode(
            UserProfile.self, from: JSONEncoder().encode(profile))

        XCTAssertEqual(restored.shoppingPriority, .goals)
    }

    /// The context is what the ranking actually reads, so the profile setting
    /// has to reach it.
    func testContextCarriesTheProfilesPriorityAndTargetRatio() {
        var profile = Fixture.rahil
        profile.shoppingPriority = .goals
        let targets = MetabolicEngine.dailyTargets(for: profile)

        let context = GoalContext.build(profile: profile, targets: targets)

        XCTAssertEqual(context.priority, .goals)
        XCTAssertEqual(context.direction, .cut)
        XCTAssertEqual(context.proteinPerCalorieTarget,
                       Double(targets.proteinGrams) / Double(targets.calories), accuracy: 0.0001)
    }
}
