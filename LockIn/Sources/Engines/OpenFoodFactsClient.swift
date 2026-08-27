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
        let hits = try await searchHits(query, fields: "product_name,product_name_en,nutriments", limit: 12)
        guard let best = hits.first(where: {
            $0.isUsable && Self.isPlausibleMatch(productName: $0.displayName, query: query)
        }) else {
            return nil
        }
        return NutritionFacts(
            name: best.displayName ?? query,
            reference: best.per100g,
            basis: .per100g,
            source: .openFoodFacts
        )
    }

    /// Products matching a shopping query, for the Shop Smart browser.
    ///
    /// Distinct from `nutrition(for:)` in what it optimises for. That one wants
    /// *the* answer for a food the user already ate, so it returns a single
    /// tightly-matched result. This one is a shelf to look along, so it returns
    /// many and leans on the caller to rank them — and it pulls the extra label
    /// fields (Nutri-Score, NOVA, sugars, sodium, fibre) that a health judgement
    /// needs and macro logging doesn't.
    ///
    /// Comes back in the service's relevance order; ranking by health score is
    /// the caller's job, so the two concerns stay separable.
    func catalogSearch(_ query: String, limit: Int = 24) async throws -> [GroceryItem] {
        // A one-character query matches most of the database and is always a
        // half-typed word. Only the browsing path takes this shortcut — a name
        // lookup is given whatever the caller asked for.
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }

        let hits = try await searchHits(query, fields: [
            "code", "product_name", "product_name_en", "brands", "quantity", "nutriments",
            "image_front_small_url", "image_url",
            "nutriscore_grade", "nova_group", "additives_n", "ingredients_n"
        ].joined(separator: ","), limit: limit)

        return hits
            .filter { $0.isUsable && Self.isCatalogMatch(productName: $0.displayName, query: query) }
            .compactMap(\.groceryItem)
    }

    /// One request against Open Food Facts' full-text search.
    ///
    /// Points at `search.openfoodfacts.org` rather than the older
    /// `/cgi/search.pl` on the main host, which now answers 503 — that legacy
    /// endpoint is being retired in favour of this one. The barcode lookup is
    /// unaffected: it uses `/api/v2/product`, which is still live.
    ///
    /// Note there's no `sort_by`. Sorting by scan popularity was tried and is
    /// actively worse: for "greek yogurt" it returns globally-popular products
    /// that barely match the words ("Vanille au Soja") ahead of the Chobani
    /// tub, because popularity is global rather than relative to the query.
    /// Default relevance order puts the right thing first.
    private func searchHits(_ query: String, fields: String, limit: Int) async throws -> [CatalogHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            .init(name: "q", value: trimmed),
            .init(name: "page_size", value: String(limit)),
            .init(name: "fields", value: fields)
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

        return try JSONDecoder().decode(CatalogResponse.self, from: data).hits
    }

    /// Exact product for a scanned barcode.
    ///
    /// This is the highest-confidence lookup the app has and the reason
    /// scanning is worth the camera: a barcode identifies one specific
    /// manufactured product, so there's no name matching, no plausibility
    /// gate, and no estimate. The Costco protein bar in the cupboard is that
    /// exact bar, with the manufacturer's own numbers.
    ///
    /// Returns nil for an unknown code — Open Food Facts is crowd-sourced and
    /// answers `status: 0` for products nobody has added yet, which is a normal
    /// outcome rather than an error.
    func product(barcode: String) async throws -> NutritionFacts? {
        let digits = barcode.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }

        var components = URLComponents(string: "\(host)/api/v2/product/\(digits).json")!
        components.queryItems = [
            .init(name: "fields", value: "product_name,brands,nutriments,serving_size,serving_quantity")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("LockIn/1.0 (iOS; personal nutrition tracking)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(status: -1)
        }
        // A code nobody has catalogued comes back 404, which isn't a failure
        // worth surfacing — the caller falls through to label scanning.
        guard http.statusCode != 404 else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product, product.isUsable else { return nil }

        return NutritionFacts(
            name: product.displayName ?? "Scanned product",
            reference: product.per100g,
            basis: .per100g,
            source: .barcode,
            servingGrams: product.servingGrams,
            servingLabel: product.serving_size
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

    /// Match test for browsing a shelf, rather than for pinning down one food.
    ///
    /// `isPlausibleMatch` is deliberately strict — most of the *product's* words
    /// have to be words the user asked for — because logging the wrong macros is
    /// worse than logging none. That rule is exactly wrong here: searching
    /// "yogurt" would reject "Chobani Greek Yogurt Nonfat Plain" for having four
    /// words the query didn't mention, which is every real product on the shelf.
    ///
    /// So the direction flips. Every word the user typed must appear in the
    /// product name; the product may say as much else as it likes. "greek
    /// yogurt" keeps the Chobani and drops Yoplait Strawberry, while "yogurt"
    /// keeps both — which is what browsing should do.
    ///
    /// Prefix rather than exact comparison so plurals and possessives don't
    /// silently drop half the shelf ("oat" matching "oats").
    static func isCatalogMatch(productName: String?, query: String) -> Bool {
        guard let productName, !productName.isEmpty else { return false }

        let queryTokens = tokens(in: query)
        // Nothing long enough to filter on — better to show the results the
        // server already matched than to reject everything.
        guard !queryTokens.isEmpty else { return true }

        let productTokens = tokens(in: productName)
        guard !productTokens.isEmpty else { return false }

        return queryTokens.allSatisfy { queryToken in
            productTokens.contains { $0.hasPrefix(queryToken) || queryToken.hasPrefix($0) }
        }
    }

    /// Lowercased word tokens with diacritics folded, so "thaï" matches "thai".
    private static func tokens(in value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    // MARK: - Wire types

    /// The v2 single-product envelope. `status` is 1 for a hit, 0 for a code
    /// that isn't in the database.
    struct ProductResponse: Decodable {
        let status: Int
        let product: Product?
    }

    /// A record from `/api/v2/product` — the barcode path.
    struct Product: Decodable, NutrimentCarrying {
        let product_name: String?
        let brands: String?
        let serving_size: String?
        let serving_quantity: Double?
        let nutriments: Nutriments?

        private enum CodingKeys: String, CodingKey {
            case product_name, brands, serving_size, serving_quantity, nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            product_name = try container.decodeIfPresent(String.self, forKey: .product_name)
            brands = try container.decodeIfPresent(String.self, forKey: .brands)
            serving_size = try container.decodeIfPresent(String.self, forKey: .serving_size)
            // Open Food Facts sends this as a number on some records and a
            // string on others.
            if let value = try? container.decodeIfPresent(Double.self, forKey: .serving_quantity) {
                serving_quantity = value
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .serving_quantity) {
                serving_quantity = Double(text)
            } else {
                serving_quantity = nil
            }
            nutriments = try container.decodeIfPresent(Nutriments.self, forKey: .nutriments)
        }

        /// "Kirkland Signature Chewy Protein Bar" — the brand matters for a
        /// scanned product in a way it doesn't for a search result, because
        /// it's what's printed on the thing in the user's hand.
        var displayName: String? {
            let name = product_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            guard let brand = brands?.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty,
                !name.localizedCaseInsensitiveContains(brand) else { return name }
            return "\(brand) \(name)"
        }

        /// A serving weight only when it's a sane one — some records carry a
        /// stray 0 or an absurd value that would wreck the portion default.
        var servingGrams: Double? {
            guard let serving_quantity, serving_quantity >= 1, serving_quantity <= 1500 else { return nil }
            return serving_quantity
        }
    }

    /// The search-a-licious envelope. Note `hits`, not `products` — a different
    /// service from the main API, with its own response shape.
    struct CatalogResponse: Decodable {
        let hits: [CatalogHit]
    }

    /// One search result.
    ///
    /// Shaped differently enough from `Product` to be worth its own type rather
    /// than a pile of optionals on that one: `brands` arrives as an array here
    /// and a comma-joined string there, and the fields a shopper needs
    /// (Nutri-Score, NOVA, pack size) are ones the barcode path never asks for.
    struct CatalogHit: Decodable, NutrimentCarrying {
        let code: String?
        let product_name: String?
        /// Plenty of records leave `product_name` empty but carry the English
        /// one, and dropping those loses real products off the shelf.
        let product_name_en: String?
        let brands: [String]?
        let quantity: String?
        let image_front_small_url: String?
        let image_url: String?
        let nutriscore_grade: String?
        let nova_group: Int?
        let additives_n: Int?
        let ingredients_n: Int?
        let nutriments: Nutriments?

        private enum CodingKeys: String, CodingKey {
            case code, product_name, product_name_en, brands, quantity
            case image_front_small_url, image_url
            case nutriscore_grade, nova_group, additives_n, ingredients_n, nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try? container.decodeIfPresent(String.self, forKey: .code)
            product_name = try? container.decodeIfPresent(String.self, forKey: .product_name)
            product_name_en = try? container.decodeIfPresent(String.self, forKey: .product_name_en)
            // Tolerates the string form too, so a shape change on the service
            // side degrades to a missing brand rather than a decode failure
            // that empties the whole shelf.
            if let list = try? container.decodeIfPresent([String].self, forKey: .brands) {
                brands = list
            } else if let single = try? container.decodeIfPresent(String.self, forKey: .brands) {
                brands = [single]
            } else {
                brands = nil
            }
            quantity = try? container.decodeIfPresent(String.self, forKey: .quantity)
            image_front_small_url = try? container.decodeIfPresent(String.self, forKey: .image_front_small_url)
            image_url = try? container.decodeIfPresent(String.self, forKey: .image_url)
            nutriscore_grade = try? container.decodeIfPresent(String.self, forKey: .nutriscore_grade)
            // Same string-or-number inconsistency as serving_quantity.
            nova_group = Self.integer(container, .nova_group)
            additives_n = Self.integer(container, .additives_n)
            ingredients_n = Self.integer(container, .ingredients_n)
            nutriments = try? container.decodeIfPresent(Nutriments.self, forKey: .nutriments)
        }

        private static func integer(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Int(text) }
            return nil
        }

        /// Brand-prefixed, so the shelf reads the way the packaging does.
        var displayName: String? {
            let raw = (product_name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
                ?? product_name_en?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            guard let name = raw else { return nil }
            guard let brand = brands?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !brand.isEmpty,
                  !name.localizedCaseInsensitiveContains(brand) else { return name }
            return "\(brand) \(name)"
        }

        /// The shoppable view of this record, or nil when it has no barcode to
        /// be identified by.
        ///
        /// Reuses `isUsable` and `displayName` rather than relaxing them: a
        /// product with no calories is no more worth *recommending* than it is
        /// worth logging.
        var groceryItem: GroceryItem? {
            guard let code, !code.isEmpty, let name = displayName else { return nil }
            return GroceryItem(
                id: code,
                name: name,
                quantityText: quantity?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                imageURL: (image_front_small_url ?? image_url).flatMap(URL.init(string:)),
                per100g: per100g,
                quality: GroceryQuality(
                    sugarsPer100g: nutriments?.sugars100g,
                    saturatedFatPer100g: nutriments?.saturatedFat100g,
                    sodiumMgPer100g: nutriments?.sodiumMg,
                    fiberPer100g: nutriments?.fiber100g,
                    // Open Food Facts writes "unknown" and "not-applicable" into
                    // this field as well as grades; both must read as absent, or
                    // the score silently falls through to a default grade.
                    nutriScoreGrade: nutriscore_grade
                        .map { $0.lowercased() }
                        .flatMap { ["a", "b", "c", "d", "e"].contains($0) ? $0 : nil },
                    novaGroup: nova_group,
                    additivesCount: additives_n,
                    ingredientCount: ingredients_n
                )
            )
        }
    }

    /// Open Food Facts stores nutriments as a flat bag of optional keys
    /// with inconsistent types (numbers sometimes arrive as strings), so
    /// each value is decoded leniently. Shared by both endpoints.
    struct Nutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let fat100g: Double?
        let carbohydrates100g: Double?
        // Quality signals — only requested by `catalogSearch`.
        let sugars100g: Double?
        let saturatedFat100g: Double?
        let fiber100g: Double?
        /// Grams of sodium. Most records carry salt instead; see `sodiumMg`.
        let sodium100g: Double?
        /// Grams of salt (sodium chloride).
        let salt100g: Double?

        private enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case fat100g = "fat_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case sugars100g = "sugars_100g"
            case saturatedFat100g = "saturated-fat_100g"
            case fiber100g = "fiber_100g"
            case sodium100g = "sodium_100g"
            case salt100g = "salt_100g"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            energyKcal100g = Self.number(container, .energyKcal100g)
            proteins100g = Self.number(container, .proteins100g)
            fat100g = Self.number(container, .fat100g)
            carbohydrates100g = Self.number(container, .carbohydrates100g)
            sugars100g = Self.number(container, .sugars100g)
            saturatedFat100g = Self.number(container, .saturatedFat100g)
            fiber100g = Self.number(container, .fiber100g)
            sodium100g = Self.number(container, .sodium100g)
            salt100g = Self.number(container, .salt100g)
        }

        /// Sodium in milligrams, from whichever of the two the record has.
        ///
        /// Salt is converted at the standard 2.5 factor (sodium chloride is
        /// ~40% sodium by mass). Getting this wrong by that factor would put
        /// ordinary bread over the high-sodium line, so it's worth stating.
        var sodiumMg: Double? {
            if let sodium100g { return sodium100g * 1000 }
            if let salt100g { return salt100g / 2.5 * 1000 }
            return nil
        }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }
    }
}

/// Shared by both wire types so the "is this record worth using" rule has one
/// definition. A product with no calories is no more worth recommending on a
/// shelf than it is worth writing into the day's log.
protocol NutrimentCarrying {
    var nutriments: OpenFoodFactsClient.Nutriments? { get }
}

extension NutrimentCarrying {
    var per100g: MacroTargetsLite {
        MacroTargetsLite(
            calories: nutriments?.energyKcal100g ?? 0,
            proteinG: nutriments?.proteins100g ?? 0,
            fatG: nutriments?.fat100g ?? 0,
            carbG: nutriments?.carbohydrates100g ?? 0
        )
    }

    /// Requires real calories and at least one macro — a record with calories
    /// but all-zero macros is almost always an incomplete entry.
    var isUsable: Bool {
        let macros = per100g
        guard macros.calories > 0 else { return false }
        return macros.proteinG > 0 || macros.fatG > 0 || macros.carbG > 0
    }
}
