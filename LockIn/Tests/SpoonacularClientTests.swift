import XCTest
@testable import LockIn

/// Intercepts requests so the filter-relaxation ladder can be tested without
/// network or quota.
final class MockURLProtocol: URLProtocol {
    /// Returns (status, body) for a given request. Set per test.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    /// Every URL the client requested, in order.
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    static func reset() {
        handler = nil
        requestedURLs = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        let (status, body) = Self.handler?(request) ?? (200, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SpoonacularClientTests: XCTestCase {

    private var client: SpoonacularClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = SpoonacularClient(session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func body(count: Int) -> Data {
        let results = (0..<count).map { index in
            """
            { "id": \(index), "title": "Recipe \(index)", "readyInMinutes": 20, "servings": 1,
              "sourceUrl": null,
              "nutrition": { "nutrients": [
                { "name": "Calories", "amount": 500, "unit": "kcal" },
                { "name": "Protein", "amount": 35, "unit": "g" },
                { "name": "Fat", "amount": 18, "unit": "g" },
                { "name": "Carbohydrates", "amount": 45, "unit": "g" } ] } }
            """
        }.joined(separator: ",")
        return #"{"results":[\#(results)],"totalResults":\#(count)}"#.data(using: .utf8)!
    }

    // MARK: - Relaxation ladder

    /// The live bug this guards: vegetarian + Indian + minProtein=31 returns
    /// zero results, which silently routed every South-Asian vegetarian user to
    /// the offline fallback forever.
    func testDropsCuisineWhenTheNarrowQueryReturnsNothing() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            // Only the cuisine-constrained query comes back empty.
            return (200, url.contains("cuisine=Indian") ? self.body(count: 0) : self.body(count: 20))
        }

        let pool = try await client.recipePool(profile: Fixture.rahil, minProteinPerServing: 31)

        XCTAssertEqual(pool.count, 20, "Should have retried without the cuisine filter")
        XCTAssertGreaterThanOrEqual(MockURLProtocol.requestedURLs.count, 2)
        XCTAssertTrue(MockURLProtocol.requestedURLs[0].absoluteString.contains("cuisine=Indian"),
                      "First attempt should still honour the cuisine preference")
    }

    func testStopsAtTheFirstAttemptWhenItAlreadyReturnsEnough() async throws {
        MockURLProtocol.handler = { _ in (200, self.body(count: 25)) }
        let pool = try await client.recipePool(profile: Fixture.rahil, minProteinPerServing: 31)

        XCTAssertEqual(pool.count, 25)
        XCTAssertEqual(MockURLProtocol.requestedURLs.count, 1, "Shouldn't waste quota on extra attempts")
    }

    func testDropsProteinFloorWhenCuisineRelaxationIsStillNotEnough() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            // Anything with a protein floor stays thin.
            return (200, url.contains("minProtein") ? self.body(count: 2) : self.body(count: 30))
        }

        let pool = try await client.recipePool(profile: Fixture.rahil, minProteinPerServing: 31)
        XCTAssertEqual(pool.count, 30)
        XCTAssertTrue(MockURLProtocol.requestedURLs.contains { !$0.absoluteString.contains("minProtein") })
    }

    func testReturnsTheLargestPoolFoundWhenNoAttemptClearsTheBar() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            return (200, self.body(count: url.contains("cuisine=Indian") ? 1 : 4))
        }

        let pool = try await client.recipePool(profile: Fixture.rahil, minProteinPerServing: 31)
        XCTAssertEqual(pool.count, 4, "Should keep the best attempt rather than the last")
        XCTAssertEqual(MockURLProtocol.requestedURLs.count, 4, "All four attempts should be tried")
    }

    // MARK: - Query construction

    func testQueryCarriesDietNutritionAndProteinFloor() async throws {
        MockURLProtocol.handler = { _ in (200, self.body(count: 20)) }
        _ = try await client.recipePool(profile: Fixture.rahil, minProteinPerServing: 31)

        let url = MockURLProtocol.requestedURLs[0].absoluteString
        XCTAssertTrue(url.contains("diet=vegetarian"))
        XCTAssertTrue(url.contains("addRecipeNutrition=true"), "Without nutrition every macro would be zero")
        XCTAssertTrue(url.contains("minProtein=31"))
    }

    func testOmnivoreProfileSendsNoDietConstraint() async throws {
        MockURLProtocol.handler = { _ in (200, self.body(count: 20)) }
        _ = try await client.recipePool(profile: Fixture.femaleCut, minProteinPerServing: 25)
        XCTAssertFalse(MockURLProtocol.requestedURLs[0].absoluteString.contains("diet="))
    }

    func testAllergiesBecomeIntolerances() async throws {
        var profile = Fixture.rahil
        profile.allergies = ["peanut", "soy"]
        MockURLProtocol.handler = { _ in (200, self.body(count: 20)) }
        _ = try await client.recipePool(profile: profile, minProteinPerServing: 20)

        let url = MockURLProtocol.requestedURLs[0].absoluteString
        XCTAssertTrue(url.contains("intolerances=peanut,soy") || url.contains("intolerances=peanut%2Csoy"),
                      "Allergies must reach the query: \(url)")
    }

    // MARK: - Error handling

    func testQuotaExhaustionSurfacesAsQuotaExceeded() async {
        MockURLProtocol.handler = { _ in (402, Data()) }
        do {
            _ = try await client.recipePool(profile: Fixture.rahil)
            XCTFail("Expected a quota error")
        } catch {
            XCTAssertEqual(error as? SpoonacularClient.ClientError, .quotaExceeded)
        }
    }

    func testServerErrorSurfacesStatusCode() async {
        MockURLProtocol.handler = { _ in (500, Data()) }
        do {
            _ = try await client.recipePool(profile: Fixture.rahil)
            XCTFail("Expected a server error")
        } catch {
            XCTAssertEqual(error as? SpoonacularClient.ClientError, .badResponse(status: 500))
        }
    }

    func testMalformedBodyThrowsRatherThanReturningEmptyMacros() async {
        MockURLProtocol.handler = { _ in (200, "not json".data(using: .utf8)!) }
        do {
            _ = try await client.recipePool(profile: Fixture.rahil)
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertFalse(error is SpoonacularClient.ClientError)
        }
    }
}
