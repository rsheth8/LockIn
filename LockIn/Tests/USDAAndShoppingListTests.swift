import XCTest
@testable import LockIn

// MARK: - Fixtures

private func scored(
    id: String = "1",
    name: String = "Product",
    quantity: String? = nil,
    calories: Double = 100,
    protein: Double = 10,
    source: GrocerySource = .openFoodFacts,
    value: Int = 70
) -> ScoredGroceryItem {
    ScoredGroceryItem(
        item: GroceryItem(
            id: id, name: name, quantityText: quantity, imageURL: nil,
            per100g: MacroTargetsLite(calories: calories, proteinG: protein, fatG: 0, carbG: 0),
            quality: .unknown,
            source: source
        ),
        score: SmartScore(value: value, reasons: [], cautions: [], confidence: .labelBacked)
    )
}

/// Decoding USDA FoodData Central.
///
/// The mapping is exercised directly on the wire types rather than through
/// `search()`, so these run whether or not a `USDAAPIKey` is configured — the
/// decoding is what's worth guarding, and gating it behind a key would mean the
/// tests that matter silently stop running on a fresh checkout.
final class USDAClientTests: XCTestCase {

    private var client: USDAClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = USDAClient(session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func items(from json: String) throws -> [GroceryItem] {
        try JSONDecoder()
            .decode(USDAClient.SearchResponse.self, from: Data(json.utf8))
            .foods
            .compactMap(\.groceryItem)
    }

    /// Shaped after a real SR Legacy record.
    private let chickenBreast = """
    {"foods":[{
      "fdcId": 171077,
      "description": "Chicken, broilers or fryers, breast, meat only, raw",
      "dataType": "SR Legacy",
      "foodNutrients": [
        {"nutrientId": 1008, "nutrientName": "Energy", "value": 120, "unitName": "KCAL"},
        {"nutrientId": 1003, "nutrientName": "Protein", "value": 22.5, "unitName": "G"},
        {"nutrientId": 1004, "nutrientName": "Total lipid (fat)", "value": 2.62, "unitName": "G"},
        {"nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "value": 0, "unitName": "G"},
        {"nutrientId": 2000, "nutrientName": "Sugars, total", "value": 0, "unitName": "G"},
        {"nutrientId": 1258, "nutrientName": "Fatty acids, total saturated", "value": 0.56, "unitName": "G"},
        {"nutrientId": 1093, "nutrientName": "Sodium, Na", "value": 45, "unitName": "MG"},
        {"nutrientId": 1079, "nutrientName": "Fiber, total dietary", "value": 0, "unitName": "G"}
      ]}]}
    """

    func testMapsAWholeFoodOntoAGroceryItem() throws {
        let item = try XCTUnwrap(items(from: chickenBreast).first)

        XCTAssertEqual(item.id, "usda-171077", "namespaced so it can't collide with a barcode")
        XCTAssertEqual(item.name, "Chicken, broilers or fryers, breast, meat only, raw")
        XCTAssertEqual(item.per100g.calories, 120)
        XCTAssertEqual(item.per100g.proteinG, 22.5)
        XCTAssertEqual(item.source, .usda)
    }

    /// USDA reports sodium in milligrams already, unlike Open Food Facts' grams
    /// — converting again would be wrong by a factor of a thousand.
    func testSodiumIsTakenAsMilligramsWithoutConversion() throws {
        let item = try XCTUnwrap(items(from: chickenBreast).first)

        XCTAssertEqual(item.quality.sodiumMgPer100g, 45)
        XCTAssertEqual(item.quality.saturatedFatPer100g, 0.56)
    }

    /// Foundation and SR Legacy disagree on which nutrient number carries total
    /// sugars, so both have to be accepted.
    func testAcceptsEitherSugarsNutrientNumber() throws {
        let item = try XCTUnwrap(items(from: """
        {"foods":[{"fdcId":1,"description":"Apple","foodNutrients":[
          {"nutrientId":1008,"value":52},{"nutrientId":1003,"value":0.3},
          {"nutrientId":1004,"value":0.2},{"nutrientId":1005,"value":14},
          {"nutrientId":1063,"value":10.4}]}]}
        """).first)

        XCTAssertEqual(item.quality.sugarsPer100g, 10.4)
    }

    /// Plenty of Foundation records carry a fatty-acid breakdown and no energy
    /// figure at all. Same bar as everywhere else.
    func testRecordsWithoutEnergyAreDropped() throws {
        let mapped = try items(
            from: #"{"foods":[{"fdcId":1,"description":"Partial","foodNutrients":[{"nutrientId":1258,"value":0.7}]}]}"#)

        XCTAssertTrue(mapped.isEmpty)
    }

    /// USDA publishes composition, not marketing classifications. Inventing a
    /// NOVA class for raw chicken would be a guess dressed as data.
    func testLeavesProcessingFieldsUnsetRatherThanGuessing() throws {
        let quality = try XCTUnwrap(items(from: chickenBreast).first?.quality)

        XCTAssertNil(quality.novaGroup)
        XCTAssertNil(quality.nutriScoreGrade)
        XCTAssertNil(quality.additivesCount)
        XCTAssertNotNil(quality.sodiumMgPer100g, "but the measured panel is there")
    }

    /// Four measured values is a real panel — a USDA assay shouldn't be
    /// dismissed as thin just because it carries no marketing grade.
    func testMeasuredPanelCountsAsLabelBacked() throws {
        let item = try XCTUnwrap(items(from: chickenBreast).first)

        XCTAssertEqual(SmartChoiceEngine.score(item).confidence, .labelBacked)
    }

    /// The composite has to tell "no key" apart from "no results", or a missing
    /// key would look like an empty shelf forever.
    func testMissingKeyThrowsWithoutSpendingARequest() async throws {
        try XCTSkipIf(Secrets.hasUSDA, "only meaningful without a key configured")
        MockURLProtocol.handler = { _ in (200, Data(self.chickenBreast.utf8)) }

        do {
            _ = try await client.search("chicken breast")
            XCTFail("expected missingKey")
        } catch {
            XCTAssertEqual(error as? USDAClient.ClientError, .missingKey)
            XCTAssertTrue(MockURLProtocol.requestedURLs.isEmpty)
        }
    }

    /// Short queries shouldn't reach the network whether or not a key is set.
    func testShortQueriesReturnNothingWithoutARequest() async throws {
        let result = try? await client.search("c")

        XCTAssertEqual(result ?? [], [])
        XCTAssertTrue(MockURLProtocol.requestedURLs.isEmpty)
    }

    /// USDA names foods in inverted form; a retailer search takes the commas
    /// literally and returns nothing.
    func testSearchTermStripsTheInvertedNaming() {
        let item = GroceryItem(
            id: "usda-1", name: "Chicken, broilers or fryers, breast, meat only, raw",
            quantityText: nil, imageURL: nil,
            per100g: MacroTargetsLite(calories: 120, proteinG: 22, fatG: 3, carbG: 0),
            quality: .unknown, source: .usda
        )

        XCTAssertEqual(item.searchTerm, "Chicken broilers or fryers breast meat only raw")
        XCTAssertFalse(item.searchTerm.contains(","))
    }
}

// MARK: - Composite provider

private struct StubProvider: GroceryProvider {
    let items: [GroceryItem]
    let error: Error?

    init(items: [GroceryItem] = [], error: Error? = nil) {
        self.items = items
        self.error = error
    }

    func search(_ query: String) async throws -> [GroceryItem] {
        if let error { throw error }
        return items
    }
}

private struct StubError: Error, Equatable {}

/// Pooling two catalogs.
final class CompositeProviderTests: XCTestCase {

    private let branded = scored(id: "off-1", name: "Chobani Yogurt").item
    private let whole = scored(id: "usda-1", name: "Yogurt, plain", source: .usda).item

    func testPoolsResultsFromEveryProvider() async throws {
        let composite = CompositeGroceryProvider(providers: [
            StubProvider(items: [branded]), StubProvider(items: [whole])
        ])

        let items = try await composite.search("yogurt")

        XCTAssertEqual(items.map(\.id), ["off-1", "usda-1"])
    }

    /// One service being down is not a failed search — a shorter shelf beats an
    /// error screen. This is also the everyday path: no USDA key means that
    /// provider never contributes.
    func testOneFailingProviderStillReturnsTheOther() async throws {
        let composite = CompositeGroceryProvider(providers: [
            StubProvider(error: StubError()), StubProvider(items: [whole])
        ])

        let items = try await composite.search("yogurt")

        XCTAssertEqual(items.map(\.id), ["usda-1"])
    }

    /// But if everything failed there is genuinely nothing to show, and saying
    /// "no results" would blame the query for a network problem.
    func testAllProvidersFailingSurfacesTheError() async {
        let composite = CompositeGroceryProvider(providers: [
            StubProvider(error: StubError()), StubProvider(error: StubError())
        ])

        do {
            _ = try await composite.search("yogurt")
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue(error is StubError)
        }
    }

    /// An empty shelf from a working service is a real answer, not an error.
    func testEmptyResultsFromWorkingProvidersIsNotAnError() async throws {
        let composite = CompositeGroceryProvider(providers: [StubProvider(), StubProvider()])

        let items = try await composite.search("nothing at all")

        XCTAssertTrue(items.isEmpty)
    }

    /// Results must not reshuffle with whichever service happened to answer
    /// first, or the same search would reorder between runs.
    func testOrderFollowsProviderDeclarationNotResponseSpeed() async throws {
        for _ in 0..<8 {
            let composite = CompositeGroceryProvider(providers: [
                StubProvider(items: [branded]), StubProvider(items: [whole])
            ])
            let items = try await composite.search("yogurt")
            XCTAssertEqual(items.map(\.id), ["off-1", "usda-1"])
        }
    }
}

// MARK: - Shopping list

/// The list itself — ordering, text export, and the snapshot rule.
final class ShoppingListTests: XCTestCase {

    private func item(_ id: String, checked: Bool = false, minutesAgo: Int = 0,
                      name: String = "Thing", quantity: String? = nil) -> ShoppingListItem {
        ShoppingListItem(
            id: id, name: name, quantityText: quantity, searchTerm: name,
            scoreValue: 80,
            per100g: MacroTargetsLite(calories: 100, proteinG: 10, fatG: 1, carbG: 5),
            source: .openFoodFacts,
            addedAt: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            isChecked: checked
        )
    }

    /// Ticking something off should move it out of the way, not leave a gap to
    /// scan past.
    func testUncheckedComesFirstThenOldestAdded() {
        let ordered = [
            item("a", checked: true, minutesAgo: 30),
            item("b", minutesAgo: 5),
            item("c", minutesAgo: 20)
        ].shoppingOrder

        XCTAssertEqual(ordered.map(\.id), ["c", "b", "a"])
    }

    /// A list you hand to someone is what still needs buying.
    func testPlainTextDropsTickedItemsAndKeepsSizes() {
        let text = [
            item("a", name: "Greek yogurt", quantity: "32 oz"),
            item("b", checked: true, name: "Oats"),
            item("c", name: "Tofu")
        ].plainText

        XCTAssertTrue(text.contains("• Greek yogurt (32 oz)"))
        XCTAssertTrue(text.contains("• Tofu"))
        XCTAssertFalse(text.contains("Oats"))
    }

    /// The score is copied in at the moment of deciding, not recomputed later.
    func testCapturesTheScoreAtTheMomentOfAdding() {
        let listItem = ShoppingListItem(from: scored(id: "x", name: "Yogurt", value: 93))

        XCTAssertEqual(listItem.scoreValue, 93)
        XCTAssertEqual(listItem.id, "x")
        XCTAssertFalse(listItem.isChecked)
    }

    func testRoundTripsThroughPersistence() throws {
        let items = [item("a", quantity: "500 g"), item("b", checked: true)]

        let restored = try JSONDecoder().decode(
            [ShoppingListItem].self, from: JSONEncoder().encode(items))

        XCTAssertEqual(restored, items)
    }
}

/// The list operations on AppState.
///
/// These mutate through to the real store, because `AppState` persists every
/// change and the test bundle is hosted in the app — so the user's own list is
/// snapshotted and put back. Without this the fixtures leak into the running
/// app, which is exactly how the "Product" entry once appeared on a real list.
@MainActor
final class ShoppingListStateTests: XCTestCase {

    private let store = PersistenceStore.shared
    private var savedList: [ShoppingListItem] = []

    override func setUp() {
        super.setUp()
        savedList = store.loadShoppingList()
        store.saveShoppingList([])
    }

    override func tearDown() {
        store.saveShoppingList(savedList)
        super.tearDown()
    }

    private func freshState() -> AppState {
        AppState()
    }

    /// Tapping Add twice is a slip, not a request for two tubs.
    func testAddingTheSameItemTwiceIsANoOp() {
        let state = freshState()
        let entry = scored(id: "x")

        state.addToShoppingList(entry)
        state.addToShoppingList(entry)

        XCTAssertEqual(state.shoppingList.count, 1)
        XCTAssertTrue(state.isOnShoppingList("x"))
    }

    func testTogglingFlipsCheckedState() {
        let state = freshState()
        state.addToShoppingList(scored(id: "x"))

        state.toggleShoppingItem("x")
        XCTAssertTrue(state.shoppingList[0].isChecked)

        state.toggleShoppingItem("x")
        XCTAssertFalse(state.shoppingList[0].isChecked)
    }

    /// The end-of-trip action. Deliberately not "clear all" — that would take
    /// the things you couldn't find with it.
    func testClearingCheckedLeavesWhatYouStillNeed() {
        let state = freshState()
        state.addToShoppingList(scored(id: "got"))
        state.addToShoppingList(scored(id: "missing"))
        state.toggleShoppingItem("got")

        state.clearCheckedShoppingItems()

        XCTAssertEqual(state.shoppingList.map(\.id), ["missing"])
    }

    func testRemovingTakesItOffTheList() {
        let state = freshState()
        state.addToShoppingList(scored(id: "x"))

        state.removeFromShoppingList("x")

        XCTAssertFalse(state.isOnShoppingList("x"))
    }

    /// Operations on an id that isn't there must not crash or corrupt the list.
    func testUnknownIdsAreIgnored() {
        let state = freshState()
        state.addToShoppingList(scored(id: "x"))

        state.toggleShoppingItem("nope")
        state.removeFromShoppingList("nope")

        XCTAssertEqual(state.shoppingList.map(\.id), ["x"])
        XCTAssertFalse(state.shoppingList[0].isChecked)
    }
}
