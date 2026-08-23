import Foundation

/// Mifflin-St Jeor BMR + activity multiplier for TDEE, evidence-based cut.
/// Refs: Mifflin et al. 1990 (BMR eq.); ISSN position stand on protein (1.6-2.2 g/kg,
/// we use ~1g/lb ≈ 2.2g/kg, high end, to preserve lean mass in a deficit);
/// Hall & Kahan 2018 on deficit sizing (~20-25% below maintenance is sustainable
/// without excessive lean mass loss for someone at this weight).
enum MetabolicEngine {
    static func bmr(for profile: UserProfile) -> Double {
        let weightKg = profile.currentWeightLbs * 0.453592
        let heightCm = profile.heightInches * 2.54
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    static func dailyTargets(for profile: UserProfile, deficitPercent: Double = 0.22) -> MacroTargets {
        let tdee = bmr(for: profile) * profile.activityLevel.multiplier
        let targetCalories = tdee * (1 - deficitPercent)

        // Protein: 1g per lb of current bodyweight (high end of ISSN range) to
        // maximize satiety and lean mass retention during the cut.
        let proteinG = profile.currentWeightLbs * 1.0
        let proteinCals = proteinG * 4

        // Fat: 25% of total calories (floor ~0.3g/lb for hormonal health).
        let fatG = max(profile.currentWeightLbs * 0.3, (targetCalories * 0.25) / 9)
        let fatCals = fatG * 9

        // Carbs: whatever calories remain, floor at 0 to avoid negative values on aggressive cuts.
        let remainingCals = max(targetCalories - proteinCals - fatCals, 0)
        let carbG = remainingCals / 4

        return MacroTargets(
            calories: Int(targetCalories.rounded()),
            proteinGrams: Int(proteinG.rounded()),
            fatGrams: Int(fatG.rounded()),
            carbGrams: Int(carbG.rounded()),
            tdeeMaintenance: Int(tdee.rounded()),
            deficitPercent: deficitPercent
        )
    }

    /// Rough weeks-to-goal estimate assuming ~3500 kcal ≈ 1 lb fat (a simplification,
    /// real rate slows as weight drops — recompute weekly off actual TDEE, not this estimate).
    static func estimatedWeeksToGoal(profile: UserProfile, targets: MacroTargets) -> Double {
        let poundsToLose = profile.currentWeightLbs - profile.goalWeightLbs
        let dailyDeficit = Double(targets.tdeeMaintenance - targets.calories)
        guard dailyDeficit > 0 else { return .infinity }
        let weeklyDeficit = dailyDeficit * 7
        return (poundsToLose * 3500) / weeklyDeficit
    }
}
