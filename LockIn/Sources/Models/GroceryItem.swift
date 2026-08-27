import Foundation

/// A shoppable product, normalised away from whatever catalog it came out of.
///
/// Deliberately carries **no price**. Neither Walmart nor Target offers a
/// sanctioned way to read their prices, and inventing one from a scraper would
/// mean showing a number the app can't stand behind — the same reason meal
/// logging refuses to log a 0 kcal product rather than guess. What the app can
/// honestly offer is *which* item to reach for; where to buy it is a hand-off.
struct GroceryItem: Equatable, Identifiable {
    /// The catalog's own identifier — an Open Food Facts barcode today.
    let id: String
    /// Brand-prefixed product name, e.g. "Chobani Greek Yogurt Nonfat Plain".
    let name: String
    /// Pack size as the catalog words it ("500 g", "12 x 330 ml"). Shown rather
    /// than parsed: it's for the human deciding which tub to pick up.
    let quantityText: String?
    let imageURL: URL?
    let per100g: MacroTargetsLite
    let quality: GroceryQuality

    /// What to type into a retailer's search box.
    ///
    /// Capped at eight words because retailer search treats every token as a
    /// filter — the full catalog name ("Chobani Greek Yogurt Nonfat Plain
    /// Blended Vanilla 5.3 oz") reliably returns nothing, while the first few
    /// words find the shelf.
    var searchTerm: String {
        name.split(separator: " ").prefix(8).joined(separator: " ")
    }
}

extension String {
    /// A blank string is the same as no string for display purposes, and Open
    /// Food Facts records carry plenty of empty-string fields.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The label signals a health judgement can be made from, all per 100 g.
///
/// Every field is optional and frequently nil — Open Food Facts is
/// crowd-sourced, and a product someone added in thirty seconds has a name and
/// little else. `SmartChoiceEngine` treats missing data as missing rather than
/// as zero, which is why a mostly-empty record scores as thin rather than
/// perfect.
struct GroceryQuality: Equatable {
    let sugarsPer100g: Double?
    let saturatedFatPer100g: Double?
    /// Milligrams. Open Food Facts reports grams of sodium or grams of salt
    /// depending on the record; both are converted on the way in.
    let sodiumMgPer100g: Double?
    let fiberPer100g: Double?
    /// Nutri-Score, lowercased "a" through "e". A composite the EU already
    /// computes from the full label, so when it's present it beats anything
    /// this app would derive from four numbers.
    let nutriScoreGrade: String?
    /// NOVA processing class, 1 (unprocessed) through 4 (ultra-processed).
    let novaGroup: Int?
    let additivesCount: Int?
    /// How many ingredients are listed. A short list is the oldest and bluntest
    /// heuristic there is for real food, and the one signal here a shopper can
    /// check against the box in their hand.
    let ingredientCount: Int?

    static let unknown = GroceryQuality(
        sugarsPer100g: nil, saturatedFatPer100g: nil, sodiumMgPer100g: nil,
        fiberPer100g: nil, nutriScoreGrade: nil, novaGroup: nil,
        additivesCount: nil, ingredientCount: nil
    )

    /// How many of the eight signals the record actually carries. Drives
    /// `SmartScore.confidence` — a score built on one number isn't a score.
    var signalCount: Int {
        var count = 0
        if sugarsPer100g != nil { count += 1 }
        if saturatedFatPer100g != nil { count += 1 }
        if sodiumMgPer100g != nil { count += 1 }
        if fiberPer100g != nil { count += 1 }
        if nutriScoreGrade != nil { count += 1 }
        if novaGroup != nil { count += 1 }
        if additivesCount != nil { count += 1 }
        if ingredientCount != nil { count += 1 }
        return count
    }
}

/// A 0–100 read on whether an item is worth reaching for, with the reasoning
/// shown rather than hidden.
///
/// The reasons matter more than the number. A bare score is a black box the
/// user has to take on faith; "low in sugar, high in protein, ultra-processed"
/// is something they can disagree with, which is the honest version.
struct SmartScore: Equatable {
    let value: Int
    /// What's good about it, strongest first.
    let reasons: [String]
    /// What to know before buying it.
    let cautions: [String]
    let confidence: Confidence

    /// Whether there was enough label data to judge on.
    ///
    /// Kept separate from the score rather than folded into it: a product with
    /// no sugar recorded isn't sugar-free, it's unmeasured, and scoring it 90
    /// would be exactly the confident-wrong-number failure this app avoids.
    enum Confidence: Equatable {
        case labelBacked
        case thin
    }

    enum Band: Equatable {
        case smart, middling, occasional

        var label: String {
            switch self {
            case .smart: return "Smart pick"
            case .middling: return "Middling"
            case .occasional: return "Occasional"
            }
        }
    }

    var band: Band {
        switch value {
        case 70...: return .smart
        case 45..<70: return .middling
        default: return .occasional
        }
    }
}

/// An item paired with its verdict, which is what the list actually renders.
///
/// `Hashable` on the barcode alone so it can be a `navigationDestination`
/// value — two records sharing a barcode are the same shelf item however their
/// scores came out.
struct ScoredGroceryItem: Equatable, Identifiable, Hashable {
    let item: GroceryItem
    let score: SmartScore

    var id: String { item.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}
