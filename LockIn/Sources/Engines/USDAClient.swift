import Foundation

/// USDA FoodData Central — the answer to the hole Open Food Facts leaves.
///
/// Open Food Facts is a database of *packages*, so it's strong on branded goods
/// and thin on the things that don't come in one. Searching "chicken breast" or
/// "broccoli" there returns ready-meals and marinades. USDA's Foundation and
/// SR Legacy datasets are the opposite: laboratory-measured composition for
/// whole, generic foods, published by a government agency and updated on a
/// schedule rather than by whoever last held up their phone in a shop.
///
/// The two are complementary rather than competing, which is why
/// `CompositeGroceryProvider` asks both.
actor USDAClient {
    static let shared = USDAClient()

    private let session: URLSession
    private let host = "https://api.nal.usda.gov/fdc/v1"

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum ClientError: Error, Equatable {
        case badResponse(status: Int)
        case missingKey
    }

    /// Whole foods matching a query.
    ///
    /// Restricted to **Foundation** and **SR Legacy**. The third dataset,
    /// Branded, is manufacturer-submitted label data — the same territory Open
    /// Food Facts already covers, with worse coverage and no barcode, so
    /// including it would mostly produce duplicates of results the other
    /// provider returns better.
    ///
    /// Throws `missingKey` rather than silently returning nothing, so the
    /// composite can tell "no key configured" apart from "no results".
    func search(_ query: String, limit: Int = 12) async throws -> [GroceryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let key = Secrets.usdaKey else { throw ClientError.missingKey }

        var components = URLComponents(string: "\(host)/foods/search")!
        components.queryItems = [
            .init(name: "query", value: trimmed),
            .init(name: "api_key", value: key),
            .init(name: "pageSize", value: String(limit)),
            .init(name: "dataType", value: "Foundation,SR Legacy")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(status: http.statusCode)
        }

        return try JSONDecoder().decode(SearchResponse.self, from: data)
            .foods
            .compactMap(\.groceryItem)
    }

    // MARK: - Wire types

    struct SearchResponse: Decodable {
        let foods: [Food]
    }

    struct Food: Decodable {
        let fdcId: Int
        let description: String?
        let foodNutrients: [Nutrient]?

        /// USDA reports composition per 100 g, the same basis the rest of the
        /// app already works in, so nothing needs rescaling.
        struct Nutrient: Decodable {
            let nutrientId: Int?
            let value: Double?
            let unitName: String?
        }

        /// Nutrient numbers are stable USDA identifiers, not names — the names
        /// carry qualifiers ("Carbohydrate, by difference") and vary between
        /// datasets, while the ids don't.
        private enum ID {
            static let energyKcal = 1008
            static let protein = 1003
            static let fat = 1004
            static let carbs = 1005
            /// Foundation and SR Legacy disagree on which of these they use for
            /// total sugars, so both are accepted.
            static let sugars = 2000, sugarsAlternate = 1063
            static let saturatedFat = 1258
            static let sodiumMg = 1093
            static let fiber = 1079
        }

        private func value(_ id: Int) -> Double? {
            foodNutrients?.first { $0.nutrientId == id }?.value
        }

        var per100g: MacroTargetsLite {
            MacroTargetsLite(
                calories: value(ID.energyKcal) ?? 0,
                proteinG: value(ID.protein) ?? 0,
                fatG: value(ID.fat) ?? 0,
                carbG: value(ID.carbs) ?? 0
            )
        }

        /// Plenty of Foundation records carry only a partial panel — fatty acid
        /// breakdowns with no energy figure at all. Same bar as everywhere else:
        /// a food with no calories isn't worth recommending.
        var isUsable: Bool {
            let macros = per100g
            guard macros.calories > 0 else { return false }
            return macros.proteinG > 0 || macros.fatG > 0 || macros.carbG > 0
        }

        var groceryItem: GroceryItem? {
            guard isUsable,
                  let description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            else { return nil }

            return GroceryItem(
                // Namespaced so a USDA id can never collide with an Open Food
                // Facts barcode in a merged list.
                id: "usda-\(fdcId)",
                name: description,
                quantityText: nil,
                imageURL: nil,
                per100g: per100g,
                quality: GroceryQuality(
                    sugarsPer100g: value(ID.sugars) ?? value(ID.sugarsAlternate),
                    saturatedFatPer100g: value(ID.saturatedFat),
                    // Already milligrams here, unlike Open Food Facts' grams.
                    sodiumMgPer100g: value(ID.sodiumMg),
                    fiberPer100g: value(ID.fiber),
                    // USDA publishes composition, not marketing classifications.
                    // Leaving these nil is the honest answer — inventing a NOVA
                    // class for a raw ingredient would be a guess dressed as data.
                    nutriScoreGrade: nil,
                    novaGroup: nil,
                    additivesCount: nil,
                    ingredientCount: nil
                ),
                source: .usda
            )
        }
    }
}
