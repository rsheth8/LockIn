import Foundation

/// How hard to push the calorie gap, expressed as a target rate of bodyweight
/// change per week rather than a percentage off maintenance.
///
/// Rate is the better control because it self-corrects: 1%/week of 220 lb is a
/// 1100 kcal daily gap, but 1%/week of 190 lb is only 950 — so the deficit
/// shrinks automatically as you get lighter, instead of staying punishing.
///
/// The evidence-based band for fat loss is roughly 0.5–1.0 %BW/week (Garthe et
/// al. 2011): below that progress is slow enough that adherence suffers, above
/// it a growing share of the loss comes from lean mass. `maximum` deliberately
/// sits past the top of that band and is labelled as the trade-off it is —
/// it's still bounded by the absolute calorie floors in MetabolicEngine.
enum DeficitIntensity: String, Codable, CaseIterable, Identifiable {
    case steady
    case standard
    case aggressive
    case maximum

    var id: String { rawValue }

    /// Target percent of bodyweight per week.
    var weeklyRatePercent: Double {
        switch self {
        case .steady: return 0.5
        case .standard: return 0.75
        case .aggressive: return 1.0
        case .maximum: return 1.5
        }
    }

    var displayName: String {
        switch self {
        case .steady: return "Steady"
        case .standard: return "Standard"
        case .aggressive: return "Aggressive"
        case .maximum: return "Maximum"
        }
    }

    /// Honest trade-offs. Faster is a real option — it just isn't free.
    var blurb: String {
        switch self {
        case .steady:
            return "Easiest to live with. Training and energy stay normal."
        case .standard:
            return "The usual recommendation. Noticeable progress, manageable hunger."
        case .aggressive:
            return "Top of the evidence-based band. Expect real hunger and flatter workouts."
        case .maximum:
            return "Hardest legal push — often hits the calorie floor. Fastest scale movement, but more of the loss comes from muscle and hard sessions will suffer."
        }
    }

    /// Protein rises with the deficit — the larger the gap, the more protein
    /// does the work of protecting lean mass (Helms et al. 2014).
    var proteinPerLbOfGoalWeight: Double {
        switch self {
        case .steady, .standard: return 1.0
        case .aggressive: return 1.1
        case .maximum: return 1.25
        }
    }

    /// Whether the UI should warn before applying this level.
    var isBeyondRecommendedBand: Bool { self == .maximum }
}
