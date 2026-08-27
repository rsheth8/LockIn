import Foundation

/// Something you decided to buy.
///
/// A **snapshot, not a reference.** The score and macros are copied in at the
/// moment of adding rather than recomputed on read, for two reasons: the list
/// has to render in the shop with no signal and no round trip, and the number
/// shown should be the number you decided on. Re-scoring silently — because a
/// crowd-sourced record was edited, or because the ranking preset moved — would
/// change the reason an item is on the list without ever saying so.
struct ShoppingListItem: Codable, Equatable, Identifiable {
    /// The originating `GroceryItem.id`, so the same product can't be added
    /// twice and the detail screen can tell it's already on the list.
    let id: String
    var name: String
    var quantityText: String?
    /// What to hand a retailer's search box, carried so the list works without
    /// re-deriving it from a name that may have been trimmed.
    var searchTerm: String
    var scoreValue: Int
    var per100g: MacroTargetsLite
    var source: GrocerySource
    var addedAt: Date
    /// Ticked off in the shop. Kept rather than deleted so an accidental tap is
    /// recoverable and the list still reads as a record of the trip.
    var isChecked: Bool

    init(
        id: String,
        name: String,
        quantityText: String?,
        searchTerm: String,
        scoreValue: Int,
        per100g: MacroTargetsLite,
        source: GrocerySource,
        addedAt: Date = Date(),
        isChecked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quantityText = quantityText
        self.searchTerm = searchTerm
        self.scoreValue = scoreValue
        self.per100g = per100g
        self.source = source
        self.addedAt = addedAt
        self.isChecked = isChecked
    }

    init(from scored: ScoredGroceryItem, addedAt: Date = Date()) {
        self.init(
            id: scored.item.id,
            name: scored.item.name,
            quantityText: scored.item.quantityText,
            searchTerm: scored.item.searchTerm,
            scoreValue: scored.score.value,
            per100g: scored.item.per100g,
            source: scored.item.source,
            addedAt: addedAt
        )
    }
}

extension Array where Element == ShoppingListItem {
    /// Unticked first, then oldest-added first inside each group — so the list
    /// reads as "what's left to get", and ticking something moves it out of the
    /// way instead of leaving a gap you have to scan past.
    var shoppingOrder: [ShoppingListItem] {
        sorted { left, right in
            if left.isChecked != right.isChecked { return !left.isChecked }
            return left.addedAt < right.addedAt
        }
    }

    /// Plain text for sharing or pasting into notes. Ticked items are dropped —
    /// a list you hand to someone else is what still needs buying.
    var plainText: String {
        shoppingOrder
            .filter { !$0.isChecked }
            .map { item in
                guard let quantity = item.quantityText else { return "• \(item.name)" }
                return "• \(item.name) (\(quantity))"
            }
            .joined(separator: "\n")
    }
}
