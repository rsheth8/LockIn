import Foundation

/// A source of shoppable products.
///
/// A protocol rather than a direct call to Open Food Facts because the catalog
/// question is the part of this feature most likely to change: a Walmart
/// affiliate key, a USDA lookup for loose produce, or a cached backend all slot
/// in behind this without the search screen knowing. It also lets the view model
/// be tested without a network.
protocol GroceryProvider: Sendable {
    func search(_ query: String) async throws -> [GroceryItem]
}

/// The free, keyless default — the same crowd-sourced label database the meal
/// logger already scans barcodes against.
///
/// Its bias is worth stating: coverage is strong for packaged goods and thin for
/// loose produce, so "chicken breast" or "broccoli" will look sparse next to
/// "greek yogurt". That's the trade for needing no key, no account and no
/// backend.
struct OpenFoodFactsGroceryProvider: GroceryProvider {
    private let client: OpenFoodFactsClient

    init(client: OpenFoodFactsClient = .shared) {
        self.client = client
    }

    func search(_ query: String) async throws -> [GroceryItem] {
        try await client.catalogSearch(query)
    }
}

/// Whole foods — the half Open Food Facts is worst at. Inert without a key.
struct USDAGroceryProvider: GroceryProvider {
    private let client: USDAClient

    init(client: USDAClient = .shared) {
        self.client = client
    }

    func search(_ query: String) async throws -> [GroceryItem] {
        try await client.search(query)
    }
}

/// Asks every provider at once and pools the results.
///
/// Concurrent rather than sequential: the two services are unrelated, so
/// waiting for one before starting the other would double the time the user
/// spends looking at a spinner for no benefit.
///
/// **A failing provider is not a failed search.** If Open Food Facts is down
/// but USDA answers, the user gets a shorter shelf rather than an error — and
/// the reverse holds when no USDA key is configured, which is the default. The
/// search only reports failure when every provider failed, since that's the
/// only case where there's genuinely nothing to show.
struct CompositeGroceryProvider: GroceryProvider {
    private let providers: [GroceryProvider]

    init(providers: [GroceryProvider]) {
        self.providers = providers
    }

    /// The shipping configuration: Open Food Facts always, USDA when a key is
    /// present. Assembled here so no caller has to know about that condition.
    static var standard: CompositeGroceryProvider {
        var providers: [GroceryProvider] = [OpenFoodFactsGroceryProvider()]
        if Secrets.hasUSDA {
            providers.append(USDAGroceryProvider())
        }
        return CompositeGroceryProvider(providers: providers)
    }

    func search(_ query: String) async throws -> [GroceryItem] {
        guard !providers.isEmpty else { return [] }

        let results: [Result<[GroceryItem], Error>] = await withTaskGroup(
            of: (Int, Result<[GroceryItem], Error>).self
        ) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do { return (index, .success(try await provider.search(query))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<[GroceryItem], Error>)] = []
            for await result in group { collected.append(result) }
            // Restored to declaration order so results don't reshuffle with
            // whichever service happened to answer first.
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let items = results.flatMap { (try? $0.get()) ?? [] }
        if items.isEmpty, let firstFailure = results.compactMap({ $0.failureError }).first,
           results.allSatisfy({ $0.isFailure }) {
            throw firstFailure
        }
        return items
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    var failureError: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
