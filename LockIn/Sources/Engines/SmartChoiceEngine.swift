import Foundation

/// Turns a product's label into a 0–100 read and the sentences explaining it.
///
/// Two paths, in order of how much they know:
///
/// - **Nutri-Score**, when the record has one. It's computed by the French food
///   agency from the *full* nutrition panel — energy density, sugars, sat fat,
///   salt, fibre, protein, fruit/veg content — which is strictly more than the
///   four numbers this app can see. Deferring to it is the same instinct as
///   preferring a barcode over a name search.
/// - **A traffic-light approximation**, otherwise, using the UK FSA's
///   front-of-pack per-100 g thresholds. Public, defensible cutoffs rather than
///   numbers invented here.
///
/// Processing is layered on top of both, because neither Nutri-Score nor the
/// FSA lights account for it: NOVA class and additive count are what separate a
/// reconstituted protein snack from the same macros made of food.
///
/// The output is a *rough guide from public label data* and is labelled that
/// way in the UI. Crowd-sourced label data with gaps in it doesn't support
/// more certainty than that.
enum SmartChoiceEngine {

    // MARK: - Thresholds
    //
    // UK FSA front-of-pack criteria, per 100 g of solid food. "High" is the
    // red-light boundary, "low" the green.

    private enum Limit {
        static let sugarsHigh = 22.5, sugarsLow = 5.0
        static let satFatHigh = 5.0, satFatLow = 1.5
        /// 1.5 g / 0.3 g of *salt* expressed as sodium.
        static let sodiumHigh = 600.0, sodiumLow = 120.0
        static let fiberHigh = 6.0, fiberSome = 3.0
        static let proteinHigh = 10.0, proteinSome = 5.0
        static let shortIngredientList = 5
    }

    /// Nutri-Score grade to a starting score. Spread wide enough that the grade
    /// dominates the processing adjustment rather than being erased by it.
    private static func base(forGrade grade: String) -> Int? {
        switch grade.lowercased() {
        case "a": return 90
        case "b": return 75
        case "c": return 55
        case "d": return 35
        case "e": return 20
        default: return nil
        }
    }

    // MARK: - Scoring

    static func score(_ item: GroceryItem) -> SmartScore {
        let quality = item.quality
        let protein = item.per100g.proteinG

        var value = quality.nutriScoreGrade.flatMap(base(forGrade:))
            ?? approximate(quality: quality, proteinPer100g: protein)

        // Processing, applied to both paths. Capped at −10 for additives so a
        // long E-number list can't sink an otherwise sound product on its own.
        if let nova = quality.novaGroup {
            if nova >= 4 { value -= 15 } else if nova == 3 { value -= 5 }
        }
        if let additives = quality.additivesCount, additives > 0 {
            value -= min(additives * 2, 10)
        }
        // A five-ingredient product is a different kind of thing from a
        // thirty-ingredient one even at identical macros. Small bonus only —
        // it's a proxy, and a short list of bad ingredients is still bad.
        if let ingredients = quality.ingredientCount, ingredients > 0, ingredients <= Limit.shortIngredientList {
            value += 5
        }

        return SmartScore(
            value: min(max(value, 0), 100),
            reasons: reasons(quality: quality, proteinPer100g: protein),
            cautions: cautions(quality: quality),
            // One number is an anecdote. Three, or a Nutri-Score, is a read.
            confidence: (quality.nutriScoreGrade != nil || quality.signalCount >= 3)
                ? .labelBacked : .thin
        )
    }

    /// FSA traffic lights, summed around a neutral midpoint.
    ///
    /// Starts at 65 rather than 50 because the penalties are heavier than the
    /// bonuses by design — this is a screen for what to avoid more than a
    /// ranking of virtues, and a plain unremarkable food should land in the
    /// middling band rather than be punished for having no fibre to brag about.
    private static func approximate(quality: GroceryQuality, proteinPer100g: Double) -> Int {
        var value = 65

        if let sugars = quality.sugarsPer100g {
            if sugars > Limit.sugarsHigh { value -= 20 } else if sugars > Limit.sugarsLow { value -= 8 }
        }
        if let satFat = quality.saturatedFatPer100g {
            if satFat > Limit.satFatHigh { value -= 15 } else if satFat > Limit.satFatLow { value -= 6 }
        }
        if let sodium = quality.sodiumMgPer100g {
            if sodium > Limit.sodiumHigh { value -= 18 } else if sodium > Limit.sodiumLow { value -= 7 }
        }
        if let fiber = quality.fiberPer100g {
            if fiber > Limit.fiberHigh { value += 10 } else if fiber > Limit.fiberSome { value += 5 }
        }
        if proteinPer100g >= Limit.proteinHigh {
            value += 8
        } else if proteinPer100g >= Limit.proteinSome {
            value += 4
        }

        return value
    }

    // MARK: - Explanation
    //
    // Derived from the raw label rather than from the score, so they stay true
    // whichever path produced the number — and so a Nutri-Score A product still
    // says *why* it's an A.

    private static func reasons(quality: GroceryQuality, proteinPer100g: Double) -> [String] {
        var result: [String] = []

        if proteinPer100g >= Limit.proteinHigh {
            result.append("High in protein — \(grams(proteinPer100g)) per 100 g")
        }
        if let fiber = quality.fiberPer100g, fiber > Limit.fiberSome {
            result.append(fiber > Limit.fiberHigh
                ? "High in fibre — \(grams(fiber)) per 100 g"
                : "Some fibre — \(grams(fiber)) per 100 g")
        }
        if let sugars = quality.sugarsPer100g, sugars <= Limit.sugarsLow {
            result.append("Low in sugar — \(grams(sugars)) per 100 g")
        }
        if let satFat = quality.saturatedFatPer100g, satFat <= Limit.satFatLow {
            result.append("Low in saturated fat")
        }
        if let sodium = quality.sodiumMgPer100g, sodium <= Limit.sodiumLow {
            result.append("Low in sodium")
        }
        if let nova = quality.novaGroup, nova == 1 {
            result.append("Minimally processed")
        }
        if let ingredients = quality.ingredientCount, ingredients > 0, ingredients <= Limit.shortIngredientList {
            result.append("Short ingredient list — \(ingredients)")
        }
        if let grade = quality.nutriScoreGrade?.uppercased(), grade == "A" || grade == "B" {
            result.append("Nutri-Score \(grade)")
        }
        return result
    }

    private static func cautions(quality: GroceryQuality) -> [String] {
        var result: [String] = []

        if let sugars = quality.sugarsPer100g, sugars > Limit.sugarsHigh {
            result.append("High in sugar — \(grams(sugars)) per 100 g")
        }
        if let satFat = quality.saturatedFatPer100g, satFat > Limit.satFatHigh {
            result.append("High in saturated fat — \(grams(satFat)) per 100 g")
        }
        if let sodium = quality.sodiumMgPer100g, sodium > Limit.sodiumHigh {
            result.append("High in sodium — \(Int(sodium.rounded())) mg per 100 g")
        }
        if let nova = quality.novaGroup, nova >= 4 {
            result.append("Ultra-processed (NOVA 4)")
        }
        if let additives = quality.additivesCount, additives >= 5 {
            result.append("\(additives) additives listed")
        }
        return result
    }

    /// "12 g" / "1.5 g" — trailing zeros dropped, because "22.0 g" reads like a
    /// measurement it isn't.
    private static func grams(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) g"
            : String(format: "%.1f g", rounded)
    }
}
