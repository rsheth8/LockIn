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
