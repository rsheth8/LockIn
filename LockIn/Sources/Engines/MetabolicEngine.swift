import Foundation

/// Mifflin-St Jeor BMR + activity multiplier for TDEE, then a goal-directed
/// calorie adjustment with safety rails.
///
/// References:
/// - Mifflin et al. 1990 — BMR equation, still the best-validated predictive
///   equation for non-obese and obese adults.
/// - ISSN position stand (Jäger et al. 2017) and Helms et al. 2014 — protein
///   for physique athletes in a deficit: 2.3–3.1 g/kg of *lean* mass. We scale
///   to goal bodyweight rather than current, which approximates lean mass for
///   someone carrying fat to lose, is better supported than the popular
///   "1g per lb of current weight" heuristic, and is far more achievable on a
///   vegetarian diet.
/// - Garthe et al. 2013 / Slater et al. 2019 — a ~10% surplus captures most of
///   the muscle-gain benefit; larger surpluses add fat without adding muscle.
/// - Calorie floors: intakes below ~1200 kcal (female) / ~1500 kcal (male) are
///   considered very-low-calorie diets and are not appropriate without medical
///   supervision. The engine clamps to these floors and reports when it did.
enum MetabolicEngine {

    /// Hard lower bounds on daily intake for unsupervised dieting.
    private static func calorieFloor(for sex: Sex) -> Double {
        switch sex {
        case .female: return 1200
        case .male: return 1500
        }
    }

    static func bmr(for profile: UserProfile) -> Double {
        let weightKg = profile.currentWeightLbs * 0.453592
        let heightCm = profile.heightInches * 2.54
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    static func tdee(for profile: UserProfile) -> Double {
        bmr(for: profile) * profile.activityLevel.multiplier
    }

    static func dailyTargets(for profile: UserProfile) -> MacroTargets {
        let maintenance = tdee(for: profile)
        let direction = profile.goalDirection

        let unclamped = maintenance * (1 + direction.calorieAdjustment)
        let floor = calorieFloor(for: profile.sex)
        let targetCalories = max(unclamped, floor)
        let wasClamped = unclamped < floor

        // Protein reference: the bodyweight you're building toward, not the one
        // you're carrying. For a cut this approximates lean mass; for a gain it
        // scales with the target. Recomp gets the highest allocation since
        // protein is the whole mechanism there.
        let proteinReference = direction == .maintain ? profile.currentWeightLbs : profile.goalWeightLbs
        let proteinPerLb: Double = direction == .recomp ? 1.1 : 1.0
        let proteinG = proteinReference * proteinPerLb
        let proteinCals = proteinG * 4

        // Fat: 25% of intake, with a floor of ~0.3 g/lb for hormonal health.
        let fatG = max(profile.currentWeightLbs * 0.3, (targetCalories * 0.25) / 9)
        let fatCals = fatG * 9

        // Carbs take the remainder. On an aggressive cut for a small person the
        // remainder can go negative once protein and fat are covered — clamp at
        // zero rather than emitting a nonsense negative target.
        let remainingCals = max(targetCalories - proteinCals - fatCals, 0)
        let carbG = remainingCals / 4

        return MacroTargets(
            calories: Int(targetCalories.rounded()),
            proteinGrams: Int(proteinG.rounded()),
            fatGrams: Int(fatG.rounded()),
            carbGrams: Int(carbG.rounded()),
            tdeeMaintenance: Int(maintenance.rounded()),
            deficitPercent: abs(direction.calorieAdjustment),
            direction: direction,
            hitSafetyFloor: wasClamped
        )
    }

    /// Weeks to goal at the current rate. Uses ~3500 kcal ≈ 1 lb, which is a
    /// simplification — the real rate slows as you get lighter because TDEE
    /// falls with bodyweight, so treat this as an upper-bound estimate that the
    /// weekly weight re-sync will keep correcting.
    static func estimatedWeeksToGoal(profile: UserProfile, targets: MacroTargets) -> Double {
        let poundsToChange = abs(profile.currentWeightLbs - profile.goalWeightLbs)
        let dailyDelta = abs(Double(targets.tdeeMaintenance - targets.calories))
        guard dailyDelta > 0, poundsToChange > 0 else { return .infinity }
        return (poundsToChange * 3500) / (dailyDelta * 7)
    }

    /// Rate of change as a share of bodyweight per week. The sustainable
    /// evidence-based band is roughly 0.5–1.0 %/week for fat loss; faster than
    /// that increases lean-mass loss (Garthe et al. 2011). Surfaced in the UI so
    /// an over-aggressive goal is visible rather than silently applied.
    static func weeklyRatePercent(profile: UserProfile, targets: MacroTargets) -> Double {
        let dailyDelta = Double(targets.tdeeMaintenance - targets.calories)
        let poundsPerWeek = (dailyDelta * 7) / 3500
        guard profile.currentWeightLbs > 0 else { return 0 }
        return abs(poundsPerWeek / profile.currentWeightLbs) * 100
    }

    /// Non-blocking advisories shown after the quiz and in Settings. These are
    /// general evidence-based guidance, not medical advice — the copy says so.
    static func advisories(profile: UserProfile, targets: MacroTargets) -> [String] {
        var notes: [String] = []

        if targets.hitSafetyFloor {
            notes.append("Your target was raised to \(targets.calories) kcal — the calculated number fell below the floor considered safe without medical supervision.")
        }

        let rate = weeklyRatePercent(profile: profile, targets: targets)
        if profile.goalDirection == .cut && rate > 1.0 {
            notes.append("That's about \(String(format: "%.1f", rate))% of bodyweight per week. Above 1%/week tends to cost you muscle as well as fat — consider a smaller gap or a longer timeline.")
        }

        if profile.goalDirection == .cut && profile.goalWeightLbs >= profile.currentWeightLbs {
            notes.append("Your goal weight isn't below your current weight — check the numbers.")
        }

        return notes
    }
}
