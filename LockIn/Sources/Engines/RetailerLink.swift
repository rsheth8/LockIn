import Foundation

/// Where to go buy the thing.
///
/// This is a *search* hand-off, not a product link, and that's a ceiling rather
/// than a shortcut: Walmart's catalog API is affiliate-gated and Target retired
/// its public one entirely, so no third-party app can address a specific SKU at
/// either. Handing over the product name is the honest version of what's
/// possible without scraping.
enum Retailer: String, CaseIterable, Identifiable {
    case walmart
    case target

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .walmart: return "Walmart"
        case .target: return "Target"
        }
    }
}

enum RetailerLink {

    /// An https URL, deliberately — **not** a `walmart://` custom scheme.
    ///
    /// Both retailers register their domains as universal links, so iOS opens
    /// the installed app and falls back to Safari when it isn't there. A custom
    /// scheme would need `LSApplicationQueriesSchemes` entries and would dead-end
    /// on a device without the app.
    static func searchURL(for term: String, at retailer: Retailer) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components: URLComponents
        switch retailer {
        case .walmart:
            components = URLComponents(string: "https://www.walmart.com/search")!
            components.queryItems = [.init(name: "q", value: trimmed)]
        case .target:
            components = URLComponents(string: "https://www.target.com/s")!
            components.queryItems = [.init(name: "searchTerm", value: trimmed)]
        }
        return components.url
    }
}
