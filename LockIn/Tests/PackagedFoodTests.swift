import XCTest
@testable import LockIn

/// Barcode lookup against Open Food Facts.
final class BarcodeLookupTests: XCTestCase {

    private var client: OpenFoodFactsClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = OpenFoodFactsClient(session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    /// Shaped after the real response for the Kirkland Signature protein bar
    /// this feature was built against.
    private func kirklandBar(status: Int = 1) -> Data {
        Data("""
        {"status": \(status), "product": {
            "product_name": "Chewy Protein Bar Peanut Butter Chocolate",
            "brands": "Kirkland Signature",
            "serving_size": "1 bar (40 g)",
            "serving_quantity": 40,
            "nutriments": {"energy-kcal_100g": 475, "proteins_100g": 25, "fat_100g": 27.5, "carbohydrates_100g": 40}
        }}
        """.utf8)
    }

    func testResolvesAScannedProductWithBrandAndServing() async throws {
        MockURLProtocol.handler = { _ in (200, self.kirklandBar()) }

        let facts = try await client.product(barcode: "0096619160754")

        XCTAssertEqual(facts?.name, "Kirkland Signature Chewy Protein Bar Peanut Butter Chocolate")
        XCTAssertEqual(facts?.reference.calories, 475)
        XCTAssertEqual(facts?.basis, .per100g)
        XCTAssertEqual(facts?.source, .barcode, "a barcode is a stronger claim than a name search")
        XCTAssertEqual(facts?.servingGrams, 40)
    }

    /// The whole point of carrying the serving weight. A 40 g bar defaulted to
    /// the generic 200 g would log five bars — 950 kcal instead of 190.
    func testPortionStartsAtTheProductsOwnServing() async throws {
        MockURLProtocol.handler = { _ in (200, self.kirklandBar()) }

        let facts = try await client.product(barcode: "0096619160754")
        let unwrapped = try XCTUnwrap(facts)

        XCTAssertEqual(unwrapped.startingAmount, 40, "not the generic 200 g default")
        XCTAssertEqual(unwrapped.scaled(to: unwrapped.startingAmount).calories, 190, accuracy: 0.5)
        XCTAssertEqual(unwrapped.quickAmounts.first, 40, "one serving is the first quick pick")
        XCTAssertTrue(unwrapped.quickAmounts.contains(80), "two servings is the other realistic answer")
    }

    /// Open Food Facts is crowd-sourced; unknown codes are routine, not errors.
    func testUnknownBarcodeReturnsNilRatherThanThrowing() async throws {
        MockURLProtocol.handler = { _ in (200, Data(#"{"status": 0}"#.utf8)) }

        let facts = try await client.product(barcode: "1234567890123")

        XCTAssertNil(facts)
    }

    func testMissingProductIs404AndAlsoNotAnError() async throws {
        MockURLProtocol.handler = { _ in (404, Data()) }

        let facts = try await client.product(barcode: "1234567890123")

        XCTAssertNil(facts)
    }

    /// A record with calories but no macros at all is an incomplete entry, and
    /// logging it would quietly zero out the day's protein.
    func testRejectsProductsWithNoMacros() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"status":1,"product":{"product_name":"Mystery","nutriments":{"energy-kcal_100g":300}}}"#.utf8))
        }

        let facts = try await client.product(barcode: "0096619160754")

        XCTAssertNil(facts)
    }

    func testShortCodesAreRejectedWithoutHittingTheNetwork() async throws {
        MockURLProtocol.handler = { _ in (200, self.kirklandBar()) }

        let facts = try await client.product(barcode: "123")

        XCTAssertNil(facts)
        XCTAssertTrue(MockURLProtocol.requestedURLs.isEmpty, "a malformed code shouldn't cost a request")
    }

    /// Open Food Facts sends serving_quantity as a number on some records and
    /// a string on others.
    func testDecodesServingQuantitySentAsAString() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"status":1,"product":{"product_name":"Bar","serving_quantity":"45",
             "nutriments":{"energy-kcal_100g":400,"proteins_100g":20,"fat_100g":10,"carbohydrates_100g":40}}}
            """.utf8))
        }

        let facts = try await client.product(barcode: "0096619160754")

        XCTAssertEqual(facts?.servingGrams, 45)
    }

    /// Some records carry a stray 0 or an absurd serving weight, which would
    /// wreck the portion default if trusted.
    func testImplausibleServingWeightIsIgnored() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"status":1,"product":{"product_name":"Bar","serving_quantity":0,
             "nutriments":{"energy-kcal_100g":400,"proteins_100g":20,"fat_100g":10,"carbohydrates_100g":40}}}
            """.utf8))
        }

        let facts = try await client.product(barcode: "0096619160754")

        XCTAssertNil(facts?.servingGrams)
        XCTAssertEqual(facts?.startingAmount, 200, "falls back to the generic default")
    }

    /// Brand prefixing must not produce "Kirkland Kirkland Protein Bar".
    func testBrandIsNotRepeatedWhenAlreadyInTheProductName() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"status":1,"product":{"product_name":"Kirkland Signature Protein Bar","brands":"Kirkland Signature",
             "nutriments":{"energy-kcal_100g":400,"proteins_100g":20,"fat_100g":10,"carbohydrates_100g":40}}}
            """.utf8))
        }

        let facts = try await client.product(barcode: "0096619160754")

        XCTAssertEqual(facts?.name, "Kirkland Signature Protein Bar")
    }
}

/// Composed meals — the answer to a bowl the classifier can only give one
/// label for.
final class ComposedMealTests: XCTestCase {

    private func component(_ name: String, kcal: Double, protein: Double,
                           source: NutritionSource = .localDatabase) -> LoggedComponent {
        LoggedComponent(
            name: name, portionDescription: "1 serving",
            macros: MacroTargetsLite(calories: kcal, proteinG: protein, fatG: 0, carbG: 0),
            source: source
        )
    }

    /// The exact scenario this was built for: a yogurt bowl whose protein
    /// comes overwhelmingly from a scoop the camera cannot see.
    func testYogurtBowlSumsToItsParts() {
        let parts = [
            component("greek yogurt", kcal: 146, protein: 20),
            component("granola", kcal: 190, protein: 5),
            component("banana", kcal: 89, protein: 1),
            component("protein powder scoop", kcal: 120, protein: 25)
        ]

        let meal = LoggedMeal.composed(from: parts, name: "Yogurt bowl")

        XCTAssertEqual(meal.macros.calories, 545)
        XCTAssertEqual(meal.macros.proteinG, 51)
        XCTAssertEqual(meal.portionDescription, "4 items")
        XCTAssertTrue(meal.isComposed)
        XCTAssertEqual(meal.attribution, "4 items, added up")
    }

    /// A bowl is only as good as its weakest part — claiming otherwise would
    /// dress an estimate up as label data.
    func testSourceIsTheLeastTrustworthyComponent() {
        let meal = LoggedMeal.composed(from: [
            component("greek yogurt", kcal: 146, protein: 20, source: .barcode),
            component("leftover curry", kcal: 400, protein: 20, source: .spoonacularEstimate)
        ], name: "Bowl")

        XCTAssertEqual(meal.source, .spoonacularEstimate)
    }

    func testSingleComponentKeepsItsOwnPortionWording() {
        let meal = LoggedMeal.composed(from: [component("greek yogurt", kcal: 146, protein: 20)], name: "Yogurt")

        XCTAssertEqual(meal.portionDescription, "1 serving")
    }

    /// A hand-corrected number is the user's now. Attributing it to the lookup
    /// it replaced would be a lie the log can't defend.
    func testEditedMacrosAreAttributedToTheUser() {
        var meal = LoggedMeal(
            name: "Granola bowl", portionDescription: "1 serving",
            macros: MacroTargetsLite(calories: 287, proteinG: 6, fatG: 12, carbG: 42),
            source: .spoonacularEstimate
        )
        XCTAssertEqual(meal.attribution, "Estimated from the dish name")

        meal.macrosWereEdited = true
        XCTAssertEqual(meal.attribution, "Adjusted by hand")
    }

    /// Barcode and label figures are the manufacturer's own. Caveating them
    /// alongside a guess-from-the-name would make the warning meaningless.
    func testOnlyNameEstimatesCarryTheEstimateCaveat() {
        XCTAssertTrue(NutritionSource.spoonacularEstimate.isEstimate)
        XCTAssertFalse(NutritionSource.barcode.isEstimate)
        XCTAssertFalse(NutritionSource.nutritionLabel.isEstimate)
        XCTAssertFalse(NutritionSource.restaurantMenu.isEstimate)
    }

    /// Composition and hand-editing were added after meals were already being
    /// persisted. Decoding must tolerate their absence or the upgrade wipes
    /// the user's history.
    func testMealsSavedBeforeCompositionExistedStillDecode() throws {
        let legacy = Data("""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Chicken shawarma",
         "portionDescription":"220 g",
         "macros":{"calories":449,"proteinG":48,"fatG":26,"carbG":6},
         "loggedAt":767000000,"source":"openFoodFacts","identifiedFromPhoto":true}
        """.utf8)

        let meal = try JSONDecoder().decode(LoggedMeal.self, from: legacy)

        XCTAssertEqual(meal.name, "Chicken shawarma")
        XCTAssertEqual(meal.macros.calories, 449)
        XCTAssertTrue(meal.components.isEmpty)
        XCTAssertFalse(meal.macrosWereEdited)
        XCTAssertFalse(meal.isComposed)
    }

    /// And a round-trip through the new shape has to survive too.
    func testComposedMealRoundTripsThroughPersistence() throws {
        let meal = LoggedMeal.composed(from: [
            component("greek yogurt", kcal: 146, protein: 20),
            component("protein powder scoop", kcal: 120, protein: 25)
        ], name: "Yogurt bowl")

        let data = try JSONEncoder().encode(meal)
        let restored = try JSONDecoder().decode(LoggedMeal.self, from: data)

        XCTAssertEqual(restored, meal)
        XCTAssertEqual(restored.components.count, 2)
    }
}

/// Portion defaults for concentrated foods.
///
/// The generic 200 g default is fine for rice and wrong by an order of
/// magnitude for a scoop of whey. This is the difference between logging a
/// 114 kcal scoop and a 760 kcal one.
final class ConcentratedServingTests: XCTestCase {

    func testWheyOpensAtOneScoopNotTwoHundredGrams() throws {
        let facts = try XCTUnwrap(NutritionLookup.localMatch(for: "whey protein"))

        XCTAssertEqual(facts.startingAmount, 30, "one scoop, not the generic default")
        XCTAssertEqual(facts.scaled(to: facts.startingAmount).calories, 114, accuracy: 0.5)
        XCTAssertEqual(facts.servingLabel, "1 scoop")
    }

    func testOliveOilSliderCanReachATablespoon() throws {
        let facts = try XCTUnwrap(NutritionLookup.localMatch(for: "olive oil"))

        XCTAssertEqual(facts.startingAmount, 14)
        XCTAssertLessThanOrEqual(facts.amountRange.lowerBound, 14,
                                 "a 20 g floor can't express a tablespoon of oil")
        XCTAssertEqual(facts.amountStep, 1, "10 g steps are too coarse for oil")
    }

    /// Foods you genuinely eat a plateful of must keep the generic range.
    func testStapleFoodsKeepTheGenericDefaults() throws {
        let rice = try XCTUnwrap(NutritionLookup.localMatch(for: "basmati rice"))

        XCTAssertEqual(rice.startingAmount, 200)
        XCTAssertEqual(rice.amountRange.lowerBound, 20)
        XCTAssertEqual(rice.quickAmounts, [100, 150, 200, 300, 400])
    }
}

/// Editing a meal that's already in the log.
final class EditLoggedMealTests: XCTestCase {

    /// 1.5 g of fat renders in the field as "2". Opening the sheet and closing
    /// it must not round the stored value or claim the user edited anything.
    private let whey = LoggedMeal(
        name: "Whey Protein (powder)", portionDescription: "30 g",
        macros: MacroTargetsLite(calories: 114, proteinG: 24, fatG: 1.5, carbG: 2.4),
        source: .localDatabase
    )
    private let fields = ["114", "24", "2", "2"]

    func testOpeningAndClosingWithoutChangesIsNotAnEdit() {
        let result = EditLoggedMealView.apply(
            name: "Whey Protein (powder)", fields: fields, initialFields: fields, to: whey
        )

        XCTAssertNil(result, "Save must not appear, and the 1.5 g of fat must not round to 2")
    }

    func testChangingAMacroRecordsItAsHandAdjusted() {
        let result = EditLoggedMealView.apply(
            name: "Whey Protein (powder)", fields: ["114", "48", "2", "2"],
            initialFields: fields, to: whey
        )

        XCTAssertEqual(result?.macros.proteinG, 48)
        XCTAssertEqual(result?.macrosWereEdited, true)
        XCTAssertEqual(result?.attribution, "Adjusted by hand")
    }

    /// Renaming is a real edit, but it isn't a macro correction — the numbers
    /// still came from where they came from.
    func testRenamingAloneDoesNotMarkTheMacrosAsEdited() {
        let result = EditLoggedMealView.apply(
            name: "Post-workout shake", fields: fields, initialFields: fields, to: whey
        )

        XCTAssertEqual(result?.name, "Post-workout shake")
        XCTAssertEqual(result?.macrosWereEdited, false)
        XCTAssertEqual(result?.macros.fatG, 1.5, "untouched macros keep their precision")
    }

    /// An empty name or zero calories isn't a correction, it's a way to lose
    /// the entry.
    func testUnusableInputCannotBeSaved() {
        XCTAssertNil(EditLoggedMealView.apply(name: "  ", fields: fields, initialFields: fields, to: whey))
        XCTAssertNil(EditLoggedMealView.apply(name: "Whey", fields: ["0", "24", "2", "2"],
                                              initialFields: fields, to: whey))
    }

    /// Editing must not move the meal to the bottom of the day or un-swap the
    /// scheduled event it stood in for.
    func testIdentityAndTimingSurviveAnEdit() {
        let result = EditLoggedMealView.apply(
            name: "Whey", fields: ["200", "40", "3", "3"], initialFields: fields, to: whey
        )

        XCTAssertEqual(result?.id, whey.id)
        XCTAssertEqual(result?.loggedAt, whey.loggedAt)
        XCTAssertEqual(result?.replacedEventID, whey.replacedEventID)
        XCTAssertEqual(result?.portionDescription, "30 g")
    }
}
