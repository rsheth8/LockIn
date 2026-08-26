import XCTest
@testable import LockIn

/// Covers the food-logging path: the bundled vocabulary, the abstain rule that
/// keeps non-food photos from producing confident guesses, the nutrition
/// lookup ladder, and the portion maths.
final class FoodVocabularyTests: XCTestCase {

    /// The vocabulary ships as two files that have to agree with each other —
    /// a mismatch between the name list and the embedding matrix would only
    /// show up as nonsense rankings at runtime, so it's asserted here.
    func testBundledVocabularyLoadsAndIsWellFormed() throws {
        let vocabulary = try FoodVocabulary.loadBundled()

        XCTAssertEqual(vocabulary.dimensions, 512, "MobileCLIP s0 emits 512-dim embeddings")
        XCTAssertGreaterThan(vocabulary.foodCount, 500, "vocabulary should cover a broad spread of dishes")
        XCTAssertGreaterThan(vocabulary.names.count, vocabulary.foodCount,
                             "non-food decoys must exist or the classifier can never abstain")
        XCTAssertEqual(Set(vocabulary.names).count, vocabulary.names.count, "names must be unique")
    }

    /// The whole cultural-breadth claim rests on the vocabulary actually
    /// spanning cuisines, so spot-check that it isn't quietly Western-only.
    func testVocabularySpansCuisines() throws {
        let vocabulary = try FoodVocabulary.loadBundled()
        let names = Set(vocabulary.foodNames)

        for dish in ["palak paneer", "masala dosa", "bibimbap", "pad thai", "jollof rice",
                     "injera with wot", "shakshuka", "tacos", "feijoada", "pierogi"] {
            XCTAssertTrue(names.contains(dish), "expected \(dish) in the vocabulary")
        }
    }

    func testSearchPrefersPrefixMatches() throws {
        let vocabulary = try FoodVocabulary.loadBundled()
        let results = vocabulary.search("chicken")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results[0].hasPrefix("chicken"),
                      "a prefix match should outrank a mid-string one, got \(results[0])")
        XCTAssertTrue(results.allSatisfy { $0.contains("chicken") })
    }

    func testSearchIgnoresBlankQueries() throws {
        let vocabulary = try FoodVocabulary.loadBundled()
        XCTAssertTrue(vocabulary.search("").isEmpty)
        XCTAssertTrue(vocabulary.search("   ").isEmpty)
    }

    // MARK: - Matching and abstention

    /// A synthetic vocabulary so match behaviour can be asserted exactly,
    /// rather than depending on what the real embeddings happen to do.
    private func makeVocabulary() -> FoodVocabulary {
        // Three orthogonal unit vectors: two foods, one non-food decoy.
        let embeddings: [Float] = [
            1, 0, 0,   // "rice"
            0, 1, 0,   // "curry"
            0, 0, 1    // "a person" (non-food)
        ]
        return FoodVocabulary(names: ["rice", "curry", "a person"],
                              foodCount: 2, dimensions: 3, embeddings: embeddings)
    }

    func testBestMatchesRanksBySimilarity() {
        let vocabulary = makeVocabulary()
        let matches = vocabulary.bestMatches(for: [0.9, 0.4, 0.0], limit: 5, minimumScore: 0.1)

        XCTAssertEqual(matches.map(\.name), ["rice", "curry"])
        XCTAssertEqual(matches[0].score, 0.9, accuracy: 0.001)
    }

    func testNonFoodDecoysAreNeverReturnedAsCandidates() {
        let vocabulary = makeVocabulary()
        // Points straight at the non-food vector.
        let matches = vocabulary.bestMatches(for: [0.1, 0.1, 0.95], limit: 5, minimumScore: 0.05)

        XCTAssertTrue(matches.isEmpty,
                      "a photo that looks like the non-food decoy must yield no food guesses")
    }

    func testWeakMatchesAreDroppedRatherThanGuessed() {
        let vocabulary = makeVocabulary()
        let matches = vocabulary.bestMatches(for: [0.05, 0.02, 0.0], limit: 5, minimumScore: 0.22)

        XCTAssertTrue(matches.isEmpty, "below-threshold scores should abstain, not guess")
    }

    func testMismatchedEmbeddingLengthIsRejected() {
        let vocabulary = makeVocabulary()
        XCTAssertTrue(vocabulary.bestMatches(for: [1, 0], limit: 5, minimumScore: 0).isEmpty)
    }
}

// MARK: - Nutrition lookup

final class NutritionLookupTests: XCTestCase {

    func testLocalMatchIgnoresParentheticalQualifiers() {
        // The local database calls it "Basmati Rice (cooked)"; the vocabulary
        // calls it "white rice". The qualifier shouldn't block the match.
        let facts = NutritionLookup.localMatch(for: "basmati rice")
        XCTAssertEqual(facts?.source, .localDatabase)
        XCTAssertEqual(facts?.basis, .per100g)
        XCTAssertEqual(facts?.reference.calories, 130)
    }

    func testLocalMatchIsCaseInsensitive() {
        XCTAssertNotNil(NutritionLookup.localMatch(for: "PANEER"))
    }

    func testLocalMatchReturnsNilForUnknownFood() {
        XCTAssertNil(NutritionLookup.localMatch(for: "beef wellington"))
    }

    func testLocalMatchRejectsEmptyQuery() {
        XCTAssertNil(NutritionLookup.localMatch(for: "   "))
    }
}

// MARK: - Portion maths

final class NutritionFactsTests: XCTestCase {

    private let per100g = NutritionFacts(
        name: "paneer",
        reference: MacroTargetsLite(calories: 265, proteinG: 18, fatG: 20, carbG: 4),
        basis: .per100g,
        source: .localDatabase
    )

    private let perServing = NutritionFacts(
        name: "chicken biryani",
        reference: MacroTargetsLite(calories: 480, proteinG: 26, fatG: 14, carbG: 62),
        basis: .perServing,
        source: .spoonacularEstimate
    )

    func testPer100gScalesByWeight() {
        let macros = per100g.scaled(to: 150)
        XCTAssertEqual(macros.calories, 397.5, accuracy: 0.01)
        XCTAssertEqual(macros.proteinG, 27, accuracy: 0.01)
    }

    /// Per-serving sources must not be silently divided by 100 — that bug
    /// would under-report a meal by ~100x and look plausible enough to miss.
    func testPerServingScalesByServings() {
        let macros = perServing.scaled(to: 2)
        XCTAssertEqual(macros.calories, 960, accuracy: 0.01)
        XCTAssertEqual(macros.carbG, 124, accuracy: 0.01)
    }

    func testHalfServingScalesDown() {
        XCTAssertEqual(perServing.scaled(to: 0.5).calories, 240, accuracy: 0.01)
    }

    func testPortionDescriptionsReadNaturally() {
        XCTAssertEqual(per100g.portionDescription(for: 180), "180 g")
        XCTAssertEqual(perServing.portionDescription(for: 1), "1 serving")
        XCTAssertEqual(perServing.portionDescription(for: 1.5), "1.5 servings")
        XCTAssertEqual(perServing.portionDescription(for: 2), "2 servings")
    }

    func testEstimateSourcesAreFlaggedForTheUI() {
        XCTAssertTrue(NutritionSource.spoonacularEstimate.isEstimate)
        XCTAssertFalse(NutritionSource.localDatabase.isEstimate)
        XCTAssertFalse(NutritionSource.openFoodFacts.isEstimate)
    }
}

// MARK: - Open Food Facts

final class OpenFoodFactsClientTests: XCTestCase {

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

    private func respond(_ json: String, status: Int = 200) {
        MockURLProtocol.handler = { _ in (status, Data(json.utf8)) }
    }

    func testDecodesNutrimentsPer100g() async throws {
        respond("""
        {"products":[{"product_name":"Greek Yogurt","nutriments":{
          "energy-kcal_100g":73,"proteins_100g":10,"fat_100g":2,"carbohydrates_100g":4}}]}
        """)

        let facts = try await client.nutrition(for: "greek yogurt")
        XCTAssertEqual(facts?.name, "Greek Yogurt")
        XCTAssertEqual(facts?.basis, .per100g)
        XCTAssertEqual(facts?.source, .openFoodFacts)
        XCTAssertEqual(facts?.reference.proteinG, 10)
    }

    /// Open Food Facts is crowd-sourced and returns numbers as strings often
    /// enough that strict decoding would drop otherwise-good entries.
    func testDecodesNumericStringsFromCrowdsourcedEntries() async throws {
        respond("""
        {"products":[{"product_name":"Lentils","nutriments":{
          "energy-kcal_100g":"116","proteins_100g":"9","fat_100g":"0.4","carbohydrates_100g":"20"}}]}
        """)

        let facts = try await client.nutrition(for: "lentils")
        XCTAssertEqual(facts?.reference.calories, 116)
        XCTAssertEqual(facts?.reference.proteinG, 9)
    }

    /// A product with no calories would otherwise log a 0 kcal meal that looks
    /// like a successful lookup.
    func testSkipsEntriesWithNoNutritionAndFallsThrough() async throws {
        respond("""
        {"products":[
          {"product_name":"Mystery Item","nutriments":{}},
          {"product_name":"Real Item","nutriments":{
            "energy-kcal_100g":200,"proteins_100g":8,"fat_100g":5,"carbohydrates_100g":30}}]}
        """)

        let facts = try await client.nutrition(for: "something")
        XCTAssertEqual(facts?.name, "Real Item", "the empty entry should be skipped, not returned")
    }

    func testRejectsEntriesWithCaloriesButNoMacros() async throws {
        respond("""
        {"products":[{"product_name":"Incomplete","nutriments":{"energy-kcal_100g":200}}]}
        """)

        let facts = try await client.nutrition(for: "incomplete")
        XCTAssertNil(facts)
    }

    func testEmptyResultsReturnNil() async throws {
        respond(#"{"products":[]}"#)
        let facts = try await client.nutrition(for: "nothing at all")
        XCTAssertNil(facts)
    }

    func testServerErrorSurfaces() async {
        respond(#"{"products":[]}"#, status: 503)
        do {
            _ = try await client.nutrition(for: "x")
            XCTFail("expected a thrown error")
        } catch {
            XCTAssertEqual(error as? OpenFoodFactsClient.ClientError, .badResponse(status: 503))
        }
    }

    func testIdentifiesItselfToTheAPI() async throws {
        respond(#"{"products":[]}"#)
        _ = try await client.nutrition(for: "rice")

        let url = try XCTUnwrap(MockURLProtocol.requestedURLs.first)
        XCTAssertTrue(url.absoluteString.contains("search_terms=rice"))
        XCTAssertTrue(url.absoluteString.contains("json=1"))
    }
}

// MARK: - Spoonacular nutrition guessing

final class SpoonacularGuessNutritionTests: XCTestCase {

    func testDecodesGuessResponse() throws {
        let json = """
        {"calories":{"value":480,"unit":"calories"},
         "carbs":{"value":62,"unit":"g"},
         "fat":{"value":14,"unit":"g"},
         "protein":{"value":26,"unit":"g"}}
        """
        let guess = try JSONDecoder().decode(SpoonacularNutritionGuess.self, from: Data(json.utf8))

        XCTAssertEqual(guess.calories.value, 480)
        XCTAssertEqual(guess.protein.value, 26)
    }

    /// Spoonacular has historically returned these values as unit-suffixed
    /// strings on some fields, which strict decoding would reject outright.
    func testDecodesUnitSuffixedStringValues() throws {
        let json = """
        {"calories":{"value":"480","unit":"calories"},
         "carbs":{"value":"62g","unit":"g"},
         "fat":{"value":"14g","unit":"g"},
         "protein":{"value":"26g","unit":"g"}}
        """
        let guess = try JSONDecoder().decode(SpoonacularNutritionGuess.self, from: Data(json.utf8))

        XCTAssertEqual(guess.calories.value, 480)
        XCTAssertEqual(guess.carbs.value, 62)
        XCTAssertEqual(guess.fat.value, 14)
    }
}

// MARK: - Logged meals

final class LoggedMealTests: XCTestCase {

    private func meal(_ calories: Double, protein: Double = 0, at date: Date = Date()) -> LoggedMeal {
        LoggedMeal(
            name: "test",
            portionDescription: "1 serving",
            macros: MacroTargetsLite(calories: calories, proteinG: protein, fatG: 0, carbG: 0),
            loggedAt: date,
            source: .manual
        )
    }

    func testTodaysMealsAreTotalled() {
        let state = AppState()
        state.loggedMeals = [meal(300, protein: 20), meal(450, protein: 30)]

        XCTAssertEqual(state.loggedMealsToday.count, 2)
        XCTAssertEqual(state.loggedMacrosToday.calories, 750)
        XCTAssertEqual(state.loggedMacrosToday.proteinG, 50)
    }

    /// The off-plan strip is a *today* readout — yesterday's kebab shouldn't
    /// still be counted against today's fuel.
    func testOlderMealsAreExcludedFromToday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let state = AppState()
        state.loggedMeals = [meal(300), meal(999, at: yesterday)]

        XCTAssertEqual(state.loggedMealsToday.count, 1)
        XCTAssertEqual(state.loggedMacrosToday.calories, 300)
    }

    func testEmptyLogTotalsToZero() {
        let state = AppState()
        state.loggedMeals = []
        XCTAssertEqual(state.loggedMacrosToday.calories, 0)
    }

    /// No image data may ever reach the persisted record — that's the whole
    /// storage guarantee for this feature.
    func testLoggedMealEncodesWithoutImageData() throws {
        let encoded = try JSONEncoder().encode(meal(300))
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.lowercased().contains("image"))
        XCTAssertFalse(json.lowercased().contains("photodata"))
        XCTAssertLessThan(encoded.count, 512, "a log entry should stay a few hundred bytes")
    }

    func testRoundTripsThroughCoding() throws {
        let original = LoggedMeal(
            name: "chicken shawarma",
            portionDescription: "1.5 servings",
            macros: MacroTargetsLite(calories: 600, proteinG: 40, fatG: 25, carbG: 45),
            source: .spoonacularEstimate,
            identifiedFromPhoto: true
        )
        let decoded = try JSONDecoder().decode(LoggedMeal.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.identifiedFromPhoto)
    }
}
