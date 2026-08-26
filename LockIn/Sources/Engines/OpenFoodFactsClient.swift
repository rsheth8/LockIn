import Foundation

/// Nutrition lookup against Open Food Facts.
///
/// Chosen as the primary online source because it's free, needs no API key,
/// has no meaningful rate limit at this app's volume, and is crowd-sourced
/// worldwide — which matters when the vocabulary deliberately spans every
/// cuisine. Its weakness is the mirror image: coverage is strongest for
/// packaged products and thinner for home-cooked dishes, which is why
/// `NutritionLookup` keeps a fallback behind it.
actor OpenFoodFactsClient {
    static let shared = OpenFoodFactsClient()

    private let session: URLSession
    private let host = "https://world.openfoodfacts.org"

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum ClientError: Error, Equatable {
        case badResponse(status: Int)
        case noUsableResult
    }

    /// Best per-100g match for a food name, or nil if nothing usable came back.
    ///
    /// "Usable" is doing real work here: Open Food Facts entries are
    /// user-submitted and plenty have blank or zero nutrition. A product with
    /// no calories recorded would silently log a 0 kcal meal, so those are
    /// rejected rather than returned.
    func nutrition(for query: String) async throws -> NutritionFacts? {
        var components = URLComponents(string: "\(host)/cgi/search.pl")!
        components.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "12"),
            // Only pull the fields we use — the full product record is large
            // and this keeps the response small.
            .init(name: "fields", value: "product_name,nutriments")
        ]

        var request = URLRequest(url: components.url!)
        // Open Food Facts asks clients to identify themselves.
        request.setValue("LockIn/1.0 (iOS; personal nutrition tracking)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let best = decoded.products.first(where: {
            $0.isUsable && Self.isPlausibleMatch(productName: $0.product_name, query: query)
        }) else {
            return nil
        }
        return NutritionFacts(
            name: best.product_name?.isEmpty == false ? best.product_name! : query,
            reference: best.per100g,
            basis: .per100g,
            source: .openFoodFacts
        )
    }

    /// Rejects results that merely *mention* the query inside an unrelated
    /// product name.
    ///
    /// Open Food Facts matches loosely, so searching "pad thai" surfaces
    /// things like "céréales et légumes, façon pad thaï, bio" — a packaged
    /// side dish whose 122 kcal/100g has nothing to do with a plate of pad
    /// thai. Accepting it would log a confidently wrong number.
    ///
    /// The test is directional: most of the *product's* words should be words
    /// the user asked for. A good match ("Chicken Shawarma" for "chicken
    /// shawarma") is almost entirely query words; a ready-meal that happens to
    /// share a word is mostly other words.
    static func isPlausibleMatch(productName: String?, query: String) -> Bool {
        guard let productName, !productName.isEmpty else { return false }

        let queryTokens = Set(tokens(in: query))
        let productTokens = tokens(in: productName)
        guard !queryTokens.isEmpty, !productTokens.isEmpty else { return false }

        let overlap = productTokens.filter { queryTokens.contains($0) }.count
        return Double(overlap) / Double(productTokens.count) >= 0.5
    }

    /// Lowercased word tokens with diacritics folded, so "thaï" matches "thai".
    private static func tokens(in value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    // MARK: - Wire types

    struct SearchResponse: Decodable {
        let products: [Product]
    }

    struct Product: Decodable {
        let product_name: String?
        let nutriments: Nutriments?

        /// Open Food Facts stores nutriments as a flat bag of optional keys
        /// with inconsistent types (numbers sometimes arrive as strings), so
        /// each value is decoded leniently.
        struct Nutriments: Decodable {
            let energyKcal100g: Double?
            let proteins100g: Double?
            let fat100g: Double?
            let carbohydrates100g: Double?

            private enum CodingKeys: String, CodingKey {
                case energyKcal100g = "energy-kcal_100g"
                case proteins100g = "proteins_100g"
                case fat100g = "fat_100g"
                case carbohydrates100g = "carbohydrates_100g"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                energyKcal100g = Self.number(container, .energyKcal100g)
                proteins100g = Self.number(container, .proteins100g)
                fat100g = Self.number(container, .fat100g)
                carbohydrates100g = Self.number(container, .carbohydrates100g)
            }

            private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
                if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
                return nil
            }
        }

        var per100g: MacroTargetsLite {
            MacroTargetsLite(
                calories: nutriments?.energyKcal100g ?? 0,
                proteinG: nutriments?.proteins100g ?? 0,
                fatG: nutriments?.fat100g ?? 0,
                carbG: nutriments?.carbohydrates100g ?? 0
            )
        }

        /// Requires real calories and at least one macro — a record with
        /// calories but all-zero macros is almost always an incomplete entry.
        var isUsable: Bool {
            let macros = per100g
            guard macros.calories > 0 else { return false }
            return macros.proteinG > 0 || macros.fatG > 0 || macros.carbG > 0
        }
    }
}
