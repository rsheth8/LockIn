import XCTest
@testable import LockIn

// MARK: - Fixtures

private func item(
    id: String = "1",
    name: String = "Product",
    calories: Double = 200,
    protein: Double = 5,
    fat: Double = 5,
    carbs: Double = 20,
    sugars: Double? = nil,
    satFat: Double? = nil,
    sodiumMg: Double? = nil,
    fiber: Double? = nil,
    nutriScore: String? = nil,
    nova: Int? = nil,
    additives: Int? = nil,
    ingredients: Int? = nil
) -> GroceryItem {
    GroceryItem(
        id: id,
        name: name,
        quantityText: nil,
        imageURL: nil,
        per100g: MacroTargetsLite(calories: calories, proteinG: protein, fatG: fat, carbG: carbs),
        quality: GroceryQuality(
            sugarsPer100g: sugars,
            saturatedFatPer100g: satFat,
            sodiumMgPer100g: sodiumMg,
            fiberPer100g: fiber,
            nutriScoreGrade: nutriScore,
            novaGroup: nova,
            additivesCount: additives,
            ingredientCount: ingredients
        )
    )
}

/// Scoring a product from what its label says.
final class SmartChoiceEngineTests: XCTestCase {

    /// Nutri-Score is computed from the whole panel by a food agency; four
    /// numbers guessed at here shouldn't override it.
    func testNutriScoreLeadsWhenPresent() {
        let a = SmartChoiceEngine.score(item(nutriScore: "a"))
        let e = SmartChoiceEngine.score(item(nutriScore: "e"))

        XCTAssertEqual(a.value, 90)
        XCTAssertEqual(e.value, 20)
        XCTAssertEqual(a.band, .smart)
        XCTAssertEqual(e.band, .occasional)
    }

    /// A grade is a full panel's worth of judgement, so it stands on its own.
    func testNutriScoreAloneIsEnoughToBeConfident() {
        XCTAssertEqual(SmartChoiceEngine.score(item(nutriScore: "b")).confidence, .labelBacked)
    }

    /// Nutri-Score says nothing about processing, so NOVA still applies on top.
    func testProcessingPenaltyAppliesOverTheGrade() {
        let plain = SmartChoiceEngine.score(item(nutriScore: "a"))
        let ultra = SmartChoiceEngine.score(item(nutriScore: "a", nova: 4))

        XCTAssertEqual(ultra.value, plain.value - 15)
        XCTAssertTrue(ultra.cautions.contains { $0.contains("Ultra-processed") })
    }

    /// A long E-number list shouldn't be able to sink a product by itself.
    func testAdditivePenaltyIsCapped() {
        let few = SmartChoiceEngine.score(item(nutriScore: "c", additives: 3))
        let many = SmartChoiceEngine.score(item(nutriScore: "c", additives: 40))

        XCTAssertEqual(few.value, 55 - 6)
        XCTAssertEqual(many.value, 55 - 10, "capped at −10, not −80")
    }

    /// Without a grade, the FSA traffic lights have to carry it.
    func testFallsBackToTrafficLightsWithoutAGrade() {
        let good = SmartChoiceEngine.score(
            item(protein: 12, sugars: 4, satFat: 0.5, sodiumMg: 60, fiber: 7)
        )
        let bad = SmartChoiceEngine.score(
            item(protein: 2, sugars: 40, satFat: 12, sodiumMg: 900, fiber: 0.5)
        )

        XCTAssertGreaterThan(good.value, bad.value)
        XCTAssertEqual(good.band, .smart)
        XCTAssertEqual(bad.band, .occasional)
    }

    /// Thresholds are the published FSA boundaries; drifting off them would
    /// quietly change every score in the app.
    func testTrafficLightBoundaries() {
        // 22.5 g sugar is the top of amber, 22.6 is red.
        XCTAssertEqual(SmartChoiceEngine.score(item(protein: 0, sugars: 22.5)).value, 65 - 8)
        XCTAssertEqual(SmartChoiceEngine.score(item(protein: 0, sugars: 22.6)).value, 65 - 20)
        // 5 g sugar is the top of green — no penalty at all.
        XCTAssertEqual(SmartChoiceEngine.score(item(protein: 0, sugars: 5)).value, 65)
    }

    /// The number is only worth as much as the label behind it. A record with
    /// one stray field must not read as a confident verdict.
    func testSparseRecordsAreMarkedThin() {
        XCTAssertEqual(SmartChoiceEngine.score(item(nova: 1)).confidence, .thin)
        XCTAssertEqual(SmartChoiceEngine.score(item()).confidence, .thin)
        XCTAssertEqual(
            SmartChoiceEngine.score(item(sugars: 2, satFat: 1, sodiumMg: 50)).confidence,
            .labelBacked
        )
    }

    /// Missing data is not zero. A record with no sugar recorded must not be
    /// credited with being low in sugar.
    func testAbsentFieldsProduceNoClaims() {
        let score = SmartChoiceEngine.score(item(protein: 0))

        XCTAssertTrue(score.reasons.isEmpty)
        XCTAssertTrue(score.cautions.isEmpty)
        XCTAssertEqual(score.value, 65, "neutral, not perfect and not damned")
    }

    /// The sentences are the point — a bare number is a black box.
    func testExplanationsNameTheActualNumbers() {
        let score = SmartChoiceEngine.score(item(protein: 22, sugars: 40, sodiumMg: 900))

        XCTAssertTrue(score.reasons.contains { $0.contains("High in protein") && $0.contains("22 g") })
        XCTAssertTrue(score.cautions.contains { $0.contains("High in sugar") && $0.contains("40 g") })
        XCTAssertTrue(score.cautions.contains { $0.contains("High in sodium") && $0.contains("900 mg") })
    }

    func testScoreStaysWithinBounds() {
        let floor = SmartChoiceEngine.score(
            item(protein: 0, sugars: 90, satFat: 60, sodiumMg: 5000, nutriScore: "e", nova: 4, additives: 20)
        )
        let ceiling = SmartChoiceEngine.score(
            item(protein: 30, sugars: 0, satFat: 0, sodiumMg: 0, fiber: 20, nutriScore: "a", nova: 1)
        )

        XCTAssertEqual(floor.value, 0)
        XCTAssertLessThanOrEqual(ceiling.value, 100)
        XCTAssertGreaterThan(ceiling.value, 85)
    }
}

/// Ordering the shelf.
final class GroceryRankingTests: XCTestCase {

    func testHigherScoresComeFirst() {
        let ranked = GrocerySearchViewModel.rank([
            item(id: "1", name: "Sugary", sugars: 40, satFat: 10, sodiumMg: 700),
            item(id: "2", name: "Clean", protein: 12, sugars: 3, satFat: 0.5, sodiumMg: 50, fiber: 7)
        ])

        XCTAssertEqual(ranked.first?.item.name, "Clean")
    }

    /// A record carrying nothing but a NOVA 1 tag scores well by default. It
    /// must not outrank a product that was actually measured.
    func testThinlyDocumentedItemsSortBelowJudgedOnes() {
        let ranked = GrocerySearchViewModel.rank([
            item(id: "1", name: "Barely documented", nova: 1),
            item(id: "2", name: "Fully documented", sugars: 30, satFat: 8, sodiumMg: 800)
        ])

        XCTAssertEqual(ranked.first?.item.name, "Fully documented")
        XCTAssertEqual(ranked.last?.score.confidence, .thin)
        XCTAssertGreaterThan(ranked.last!.score.value, ranked.first!.score.value,
                             "and it does so despite scoring higher")
    }

    /// Open Food Facts holds a record per region and pack size, so one shelf
    /// item arrives several times under the same name.
    func testDuplicateNamesAreCollapsed() {
        let ranked = GrocerySearchViewModel.rank([
            item(id: "1", name: "Chobani Greek Yogurt", protein: 10),
            item(id: "2", name: "chobani greek yogurt", protein: 10),
            item(id: "3", name: "Fage Greek Yogurt", protein: 10)
        ])

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first(where: { $0.item.name.lowercased().contains("chobani") })?.id, "1",
                       "the first — and so most relevant — record wins")
    }

    /// Equal scores must not reshuffle between redraws.
    func testEqualScoresOrderStably() {
        let items = [
            item(id: "1", name: "Beta", sugars: 3, satFat: 1, sodiumMg: 50),
            item(id: "2", name: "Alpha", sugars: 3, satFat: 1, sodiumMg: 50)
        ]

        XCTAssertEqual(GrocerySearchViewModel.rank(items).map(\.item.name), ["Alpha", "Beta"])
        XCTAssertEqual(GrocerySearchViewModel.rank(items.reversed()).map(\.item.name), ["Alpha", "Beta"])
    }
}

/// Matching a query against the shelf.
final class CatalogMatchTests: XCTestCase {

    /// The rule that `isPlausibleMatch` gets deliberately backwards. Every real
    /// product name carries words the query didn't mention.
    func testABrandedProductMatchesABareCategoryQuery() {
        XCTAssertTrue(OpenFoodFactsClient.isCatalogMatch(
            productName: "Chobani Greek Yogurt Nonfat Plain", query: "yogurt"))
        XCTAssertFalse(OpenFoodFactsClient.isPlausibleMatch(
            productName: "Chobani Greek Yogurt Nonfat Plain", query: "yogurt"),
            "the strict logging rule would reject the entire shelf")
    }

    func testEveryQueryWordMustAppear() {
        XCTAssertTrue(OpenFoodFactsClient.isCatalogMatch(
            productName: "Chobani Greek Yogurt", query: "greek yogurt"))
        XCTAssertFalse(OpenFoodFactsClient.isCatalogMatch(
            productName: "Yoplait Strawberry Yogurt", query: "greek yogurt"))
    }

    /// Plurals and possessives shouldn't silently drop half the results.
    func testPrefixMatchingHandlesPlurals() {
        XCTAssertTrue(OpenFoodFactsClient.isCatalogMatch(productName: "Quaker Oats", query: "oat"))
        XCTAssertTrue(OpenFoodFactsClient.isCatalogMatch(productName: "Rolled Oat Cereal", query: "oats"))
    }

    func testUnnamedProductsAreRejected() {
        XCTAssertFalse(OpenFoodFactsClient.isCatalogMatch(productName: nil, query: "yogurt"))
        XCTAssertFalse(OpenFoodFactsClient.isCatalogMatch(productName: "", query: "yogurt"))
    }

    /// Nothing long enough to filter on — better to show what the server
    /// matched than to reject everything.
    func testQueriesWithNoUsableTokensDoNotFilter() {
        XCTAssertTrue(OpenFoodFactsClient.isCatalogMatch(productName: "Anything", query: "ok"))
    }
}

/// The hand-off to a retailer.
final class RetailerLinkTests: XCTestCase {

    func testBuildsSearchURLsForBothStores() {
        XCTAssertEqual(
            RetailerLink.searchURL(for: "greek yogurt", at: .walmart)?.absoluteString,
            "https://www.walmart.com/search?q=greek%20yogurt"
        )
        XCTAssertEqual(
            RetailerLink.searchURL(for: "greek yogurt", at: .target)?.absoluteString,
            "https://www.target.com/s?searchTerm=greek%20yogurt"
        )
    }

    /// Product names routinely contain ampersands ("M&M's"), which would
    /// truncate the query if they weren't encoded.
    func testSpecialCharactersAreEncoded() throws {
        let url = try XCTUnwrap(RetailerLink.searchURL(for: "M&M's peanut", at: .walmart))

        XCTAssertEqual(url.query, "q=M%26M's%20peanut")
    }

    func testEmptyTermProducesNoLink() {
        XCTAssertNil(RetailerLink.searchURL(for: "   ", at: .walmart))
    }

    /// Retailer search treats every token as a filter, so the full catalog name
    /// reliably returns nothing.
    func testSearchTermIsTrimmedToWhatRetailerSearchCanHandle() {
        let long = item(name: "Chobani Greek Yogurt Nonfat Plain Blended Vanilla Bean 5.3 oz Cup")

        XCTAssertEqual(long.searchTerm, "Chobani Greek Yogurt Nonfat Plain Blended Vanilla Bean")
    }
}

/// Decoding the catalog response.
final class CatalogSearchTests: XCTestCase {

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

    /// Shaped after a real search-a-licious response — note `hits` rather than
    /// `products`, and `brands` as an array.
    private let chobani = """
    {"hits":[{
      "code":"0894700010045",
      "product_name":"Greek Yogurt Nonfat Plain",
      "brands":["Chobani"],
      "quantity":"32 oz",
      "image_front_small_url":"https://images.openfoodfacts.org/front_small.jpg",
      "nutriscore_grade":"a",
      "nova_group":3,
      "additives_n":0,
      "ingredients_n":3,
      "nutriments":{"energy-kcal_100g":59,"proteins_100g":10.3,"fat_100g":0.4,
                    "carbohydrates_100g":3.6,"sugars_100g":3.6,"saturated-fat_100g":0.1,
                    "salt_100g":0.09,"fiber_100g":0}
    }]}
    """

    func testMapsAFullRecordOntoAGroceryItem() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.chobani.utf8)) }

        let items = try await client.catalogSearch("greek yogurt")
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(item.id, "0894700010045")
        XCTAssertEqual(item.name, "Chobani Greek Yogurt Nonfat Plain", "brand-prefixed for the shelf")
        XCTAssertEqual(item.quantityText, "32 oz")
        XCTAssertEqual(item.per100g.proteinG, 10.3)
        XCTAssertEqual(item.quality.nutriScoreGrade, "a")
        XCTAssertEqual(item.quality.novaGroup, 3)
        XCTAssertEqual(item.quality.additivesCount, 0)
        XCTAssertEqual(item.quality.ingredientCount, 3)
        XCTAssertNotNil(item.imageURL)
    }

    /// Search results are a different service from the barcode API, with a
    /// different envelope and a `brands` array rather than a joined string.
    func testHitsUseTheSearchServiceShapeNotTheProductAPIShape() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.chobani.utf8)) }

        _ = try await client.catalogSearch("greek yogurt")
        let url = try XCTUnwrap(MockURLProtocol.requestedURLs.first)

        XCTAssertEqual(url.host, "search.openfoodfacts.org",
                       "the legacy /cgi/search.pl on the main host now answers 503")
        XCTAssertTrue(try XCTUnwrap(url.query).contains("q=greek%20yogurt"))
    }

    /// Plenty of records leave `product_name` blank but carry the English one;
    /// dropping those loses real products off the shelf.
    func testFallsBackToTheEnglishName() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"hits":[{"code":"1","product_name":"","product_name_en":"Rolled Oats","brands":["Quaker"],
             "nutriments":{"energy-kcal_100g":380,"proteins_100g":13,"fat_100g":7,"carbohydrates_100g":67}}]}
            """.utf8))
        }

        let items = try await client.catalogSearch("oats")

        XCTAssertEqual(items.first?.name, "Quaker Rolled Oats")
    }

    /// Most records report salt, not sodium. Getting the 2.5 factor wrong would
    /// put ordinary food over the high-sodium line.
    func testSaltIsConvertedToSodium() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.chobani.utf8)) }

        let items = try await client.catalogSearch("greek yogurt")

        XCTAssertEqual(try XCTUnwrap(items.first?.quality.sodiumMgPer100g), 36, accuracy: 0.5)
    }

    func testSodiumIsPreferredWhenBothArePresent() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"hits":[{"code":"1","product_name":"Soup",
             "nutriments":{"energy-kcal_100g":50,"proteins_100g":2,"fat_100g":1,
                           "carbohydrates_100g":8,"sodium_100g":0.4,"salt_100g":1.0}}]}
            """.utf8))
        }

        let items = try await client.catalogSearch("soup")

        XCTAssertEqual(try XCTUnwrap(items.first?.quality.sodiumMgPer100g), 400, accuracy: 0.5)
    }

    /// Open Food Facts writes "unknown" and "not-applicable" into the grade
    /// field. Treating those as grades would score every one of them the same.
    func testNonGradeNutriScoreValuesReadAsAbsent() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"hits":[{"code":"1","product_name":"Mystery Bar","nutriscore_grade":"unknown",
             "nutriments":{"energy-kcal_100g":400,"proteins_100g":20,"fat_100g":10,"carbohydrates_100g":40}}]}
            """.utf8))
        }

        let items = try await client.catalogSearch("mystery bar")

        XCTAssertNil(items.first?.quality.nutriScoreGrade)
    }

    /// Same string-or-number inconsistency the barcode path already handles for
    /// serving weight.
    func testNovaGroupSentAsAStringStillDecodes() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"hits":[{"code":"1","product_name":"Cereal Bar","nova_group":"4",
             "nutriments":{"energy-kcal_100g":400,"proteins_100g":5,"fat_100g":10,"carbohydrates_100g":70}}]}
            """.utf8))
        }

        let items = try await client.catalogSearch("cereal bar")

        XCTAssertEqual(items.first?.quality.novaGroup, 4)
    }

    /// A record with no calories is no more worth recommending than logging.
    func testRecordsWithoutNutritionAreDropped() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"hits":[{"code":"1","product_name":"Empty Yogurt","nutriments":{}}]}"#.utf8))
        }

        let items = try await client.catalogSearch("yogurt")

        XCTAssertTrue(items.isEmpty)
    }

    /// Without a barcode there's no stable identity to key the list on.
    func testRecordsWithoutACodeAreDropped() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("""
            {"hits":[{"product_name":"Anonymous Yogurt",
             "nutriments":{"energy-kcal_100g":59,"proteins_100g":10,"fat_100g":0.4,"carbohydrates_100g":3.6}}]}
            """.utf8))
        }

        let items = try await client.catalogSearch("yogurt")

        XCTAssertTrue(items.isEmpty)
    }

    func testShortQueriesCostNoRequest() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.chobani.utf8)) }

        let items = try await client.catalogSearch("y")

        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(MockURLProtocol.requestedURLs.isEmpty)
    }

    /// Sorting by scan popularity was tried and is actively worse — it floats
    /// globally-popular products that barely match the words above the one the
    /// user asked for. Relevance order is the default and must stay that way.
    func testAsksForRelevanceOrderAndTheQualityFields() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.chobani.utf8)) }

        _ = try await client.catalogSearch("greek yogurt")
        let query = try XCTUnwrap(MockURLProtocol.requestedURLs.first?.query)

        XCTAssertFalse(query.contains("sort_by"), "popularity order returns the wrong products")
        XCTAssertTrue(query.contains("nutriscore_grade"))
        XCTAssertTrue(query.contains("nova_group"))
        XCTAssertTrue(query.contains("ingredients_n"))
    }

    func testServerErrorsSurfaceAsAThrow() async {
        MockURLProtocol.handler = { _ in (503, Data()) }

        do {
            _ = try await client.catalogSearch("yogurt")
            XCTFail("a 503 should not read as an empty shelf")
        } catch {
            XCTAssertEqual(error as? OpenFoodFactsClient.ClientError, .badResponse(status: 503))
        }
    }
}
