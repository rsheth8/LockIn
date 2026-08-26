import Foundation

/// One item inside a composed meal — a single yogurt, a scoop of whey, the
/// granola on top. Already resolved to the portion actually eaten, so the sum
/// is a plain addition and never needs to re-derive a basis.
struct LoggedComponent: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var portionDescription: String
    var macros: MacroTargetsLite
    var source: NutritionSource

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String,
        macros: MacroTargetsLite,
        source: NutritionSource
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.macros = macros
        self.source = source
    }
}

/// A meal that wasn't on the generated plan — either logged ad-hoc, or eaten
/// in place of a scheduled meal.
///
/// Deliberately holds **no image data**. The photo that may have helped
/// identify the food is used for recognition in memory and discarded; what's
/// worth keeping is the identification and the macros, which are a few hundred
/// bytes rather than a few megabytes per meal.
///
/// `macros` is always the authoritative total. When `components` is non-empty
/// it's their sum, and when `macrosWereEdited` is set the user has overridden
/// whatever a lookup produced. Both are recorded rather than inferred, because
/// how much to trust a number is exactly what the log is for.
struct LoggedMeal: Codable, Equatable, Identifiable {
    let id: UUID
    /// What the food was decided to be — either a vocabulary match the user
    /// confirmed, or free text they typed.
    var name: String
    /// How much was eaten, already resolved to a human-readable string
    /// ("180 g", "1.5 servings", "4 items") so the log doesn't need the basis
    /// to render.
    var portionDescription: String
    /// Macros for the portion actually eaten.
    var macros: MacroTargetsLite
    var loggedAt: Date
    /// Where the nutrition numbers came from, so the UI can be honest about
    /// how precise they are.
    var source: NutritionSource
    /// Set when this replaced a scheduled meal, so the day's plan can show what
    /// was actually eaten in that slot instead of what was planned.
    var replacedEventID: UUID?
    /// True when a photo was used to identify the food. Records that a photo
    /// happened, not the photo itself.
    var identifiedFromPhoto: Bool
    /// The items this meal was built from, empty for a plain single-food log.
    ///
    /// This is the honest answer to a bowl of yogurt, fruit, granola and a
    /// scoop of whey: photo recognition returns exactly one label, so a
    /// composed meal can only be represented by naming its parts.
    var components: [LoggedComponent]
    /// True once the user has hand-corrected the macros, so the UI can stop
    /// attributing the numbers to a lookup that no longer produced them.
    var macrosWereEdited: Bool

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String,
        macros: MacroTargetsLite,
        loggedAt: Date = Date(),
        source: NutritionSource,
        replacedEventID: UUID? = nil,
        identifiedFromPhoto: Bool = false,
        components: [LoggedComponent] = [],
        macrosWereEdited: Bool = false
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.macros = macros
        self.loggedAt = loggedAt
        self.source = source
        self.replacedEventID = replacedEventID
        self.identifiedFromPhoto = identifiedFromPhoto
        self.components = components
        self.macrosWereEdited = macrosWereEdited
    }

    /// Hand-decoded so meals logged before composition existed still load.
    /// The synthesised initialiser would reject them outright on the missing
    /// keys, which would silently wipe the user's history on upgrade.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        portionDescription = try container.decode(String.self, forKey: .portionDescription)
        macros = try container.decode(MacroTargetsLite.self, forKey: .macros)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        source = try container.decode(NutritionSource.self, forKey: .source)
        replacedEventID = try container.decodeIfPresent(UUID.self, forKey: .replacedEventID)
        identifiedFromPhoto = try container.decodeIfPresent(Bool.self, forKey: .identifiedFromPhoto) ?? false
        components = try container.decodeIfPresent([LoggedComponent].self, forKey: .components) ?? []
        macrosWereEdited = try container.decodeIfPresent(Bool.self, forKey: .macrosWereEdited) ?? false
    }

    var dayKey: String { DayRecord.key(for: loggedAt) }

    /// True when this is a bowl rather than a single food.
    var isComposed: Bool { !components.isEmpty }

    /// What to attribute the numbers to. A hand-corrected meal is the user's
    /// number now, whatever the lookup said, and a bowl is only as good as its
    /// parts — claiming either came from Open Food Facts would be a lie.
    var attribution: String {
        if macrosWereEdited { return "Adjusted by hand" }
        if isComposed { return "\(components.count) items, added up" }
        return source.label
    }

    /// Rebuilds name-independent fields from the current components. Used
    /// after adding or removing an item so the total can never drift from the
    /// parts it claims to be made of.
    static func composed(
        from components: [LoggedComponent],
        name: String,
        loggedAt: Date = Date(),
        replacedEventID: UUID? = nil,
        identifiedFromPhoto: Bool = false
    ) -> LoggedMeal {
        LoggedMeal(
            name: name,
            portionDescription: components.count == 1 ? components[0].portionDescription : "\(components.count) items",
            macros: .sum(components.map(\.macros)),
            loggedAt: loggedAt,
            // A bowl is exactly as trustworthy as its least trustworthy part,
            // so the weakest source is what gets recorded for the whole.
            source: components.map(\.source).min { $0.trust < $1.trust } ?? .manual,
            replacedEventID: replacedEventID,
            identifiedFromPhoto: identifiedFromPhoto,
            components: components
        )
    }
}

extension MacroTargetsLite {
    static let zero = MacroTargetsLite(calories: 0, proteinG: 0, fatG: 0, carbG: 0)

    static func sum(_ values: [MacroTargetsLite]) -> MacroTargetsLite {
        values.reduce(.zero) { total, next in
            MacroTargetsLite(
                calories: total.calories + next.calories,
                proteinG: total.proteinG + next.proteinG,
                fatG: total.fatG + next.fatG,
                carbG: total.carbG + next.carbG
            )
        }
    }
}

/// Which lookup supplied the macros. Ordered loosely by how much to trust it:
/// the local database is hand-curated, Open Food Facts is crowd-sourced label
/// data, and a Spoonacular guess is an estimate from a dish name alone.
enum NutritionSource: String, Codable, Equatable {
    case localDatabase
    case openFoodFacts
    case barcode
    case nutritionLabel
    case restaurantMenu
    case spoonacularEstimate
    case manual

    var label: String {
        switch self {
        case .localDatabase: return "Built-in food data"
        case .openFoodFacts: return "Open Food Facts"
        case .barcode: return "Scanned barcode"
        case .nutritionLabel: return "Read off the label"
        case .restaurantMenu: return "Published by the restaurant"
        case .spoonacularEstimate: return "Estimated from the dish name"
        case .manual: return "Entered by hand"
        }
    }

    /// Whether the numbers deserve a visible "this is an estimate" caveat.
    ///
    /// Deliberately narrow. A barcode or a photographed label is the
    /// manufacturer's own figure for a specific product — caveating those
    /// alongside a guess-from-the-name would make the warning meaningless
    /// exactly where it matters.
    var isEstimate: Bool { self == .spoonacularEstimate }

    /// How much the number can be relied on, higher is better.
    ///
    /// A barcode identifies one exact product, so it tops the order; a
    /// photographed label is the same figure with OCR risk in front of it. A
    /// hand-typed number sits mid-table — the user may know exactly, or may be
    /// guessing — and a name-only estimate is last because it knows nothing
    /// about what was actually on the plate.
    var trust: Int {
        switch self {
        case .barcode: return 6
        case .nutritionLabel: return 5
        case .localDatabase: return 4
        case .restaurantMenu: return 4
        case .openFoodFacts: return 3
        case .manual: return 2
        case .spoonacularEstimate: return 1
        }
    }
}

/// How a source expresses its numbers, and therefore what portion question to
/// ask.
///
/// This distinction is load-bearing rather than pedantic: label data (local
/// database, Open Food Facts) is per 100 g and wants a weight, while
/// Spoonacular's `guessNutrition` estimates a whole serving of a dish and
/// gives no weight at all. Forcing the latter into grams would mean inventing
/// a serving weight, which is exactly the kind of fake precision this app
/// avoids elsewhere.
enum PortionBasis: Equatable {
    case per100g
    case perServing

    var unitLabel: String {
        switch self {
        case .per100g: return "g"
        case .perServing: return "servings"
        }
    }

    /// Sensible starting amount when the sheet opens.
    var defaultAmount: Double {
        switch self {
        case .per100g: return 200
        case .perServing: return 1
        }
    }

    /// Steps offered as quick-tap buttons, so the common cases don't need the
    /// keyboard.
    var quickAmounts: [Double] {
        switch self {
        case .per100g: return [100, 150, 200, 300, 400]
        case .perServing: return [0.5, 1, 1.5, 2]
        }
    }
}

/// Nutrition for a candidate food, before a portion is chosen.
struct NutritionFacts: Equatable {
    let name: String
    /// Macros for one unit of `basis` — either 100 g, or one serving.
    let reference: MacroTargetsLite
    let basis: PortionBasis
    let source: NutritionSource
    /// What the package calls one serving, in grams, when the source knows.
    ///
    /// Barcode results carry this ("1 bar (40 g)"), and it matters: defaulting
    /// a 40 g protein bar to the generic 200 g would log five bars. Only
    /// meaningful for `.per100g`, where the amount is a weight.
    var servingGrams: Double?
    /// The package's own wording for a serving, shown on the quick-pick button
    /// so it reads "1 bar" rather than "40g".
    var servingLabel: String?

    init(
        name: String,
        reference: MacroTargetsLite,
        basis: PortionBasis,
        source: NutritionSource,
        servingGrams: Double? = nil,
        servingLabel: String? = nil
    ) {
        self.name = name
        self.reference = reference
        self.basis = basis
        self.source = source
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
    }

    /// Where the portion picker starts. A known serving weight beats the
    /// generic default every time — it's the number on the box.
    var startingAmount: Double {
        if basis == .per100g, let servingGrams, servingGrams > 0 { return servingGrams }
        return basis.defaultAmount
    }

    /// Quick-tap amounts, with the known serving inserted first.
    var quickAmounts: [Double] {
        guard basis == .per100g, let servingGrams, servingGrams > 0 else { return basis.quickAmounts }
        // One and two servings are the realistic answers; the generic weights
        // stay available behind them.
        let servings = [servingGrams, servingGrams * 2].map { ($0 * 10).rounded() / 10 }
        return servings + basis.quickAmounts.filter { !servings.contains($0) }.prefix(3)
    }

    /// Slider bounds and granularity.
    ///
    /// A fixed 20–800 g range in 10 g steps can't express a 14 g glug of olive
    /// oil at all, so small-serving foods get a finer, lower range. Servings
    /// are always 0.25–4.
    var amountRange: ClosedRange<Double> {
        guard basis == .per100g else { return 0.25...4 }
        guard let servingGrams, servingGrams > 0, servingGrams < 60 else { return 20...800 }
        return 5...300
    }

    var amountStep: Double {
        guard basis == .per100g else { return 0.25 }
        return amountRange.lowerBound < 20 ? 1 : 10
    }

    func scaled(to amount: Double) -> MacroTargetsLite {
        let factor: Double
        switch basis {
        case .per100g: factor = amount / 100.0
        case .perServing: factor = amount
        }
        return MacroTargetsLite(
            calories: reference.calories * factor,
            proteinG: reference.proteinG * factor,
            fatG: reference.fatG * factor,
            carbG: reference.carbG * factor
        )
    }

    /// "180 g" / "1.5 servings" — what gets stored on the log entry.
    func portionDescription(for amount: Double) -> String {
        switch basis {
        case .per100g:
            return "\(Int(amount.rounded())) g"
        case .perServing:
            let trimmed = amount == amount.rounded()
                ? String(Int(amount))
                : String(format: "%.1f", amount)
            return "\(trimmed) \(amount == 1 ? "serving" : "servings")"
        }
    }
}
