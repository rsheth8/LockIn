import Foundation

enum Sex: String, Codable, CaseIterable { case male, female }

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary, lightlyActive, moderatelyActive, veryActive

    /// Multiplier applied to BMR to get maintenance TDEE (standard Mifflin-St Jeor activity factors).
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        }
    }

    var displayName: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    var blurb: String {
        switch self {
        case .sedentary: return "Desk and lectures, little walking"
        case .lightlyActive: return "Some walking, 1–3 sessions a week"
        case .moderatelyActive: return "On your feet daily, 3–5 sessions"
        case .veryActive: return "Training most days, physical job or sport"
        }
    }
}

enum Equipment: String, Codable, CaseIterable {
    case fullGym, homeEquipment, bodyweightOnly

    var displayName: String {
        switch self {
        case .fullGym: return "Full gym"
        case .homeEquipment: return "Home equipment"
        case .bodyweightOnly: return "Bodyweight only"
        }
    }

    var blurb: String {
        switch self {
        case .fullGym: return "Barbells, machines, cables"
        case .homeEquipment: return "Dumbbells, bands, a bench"
        case .bodyweightOnly: return "No equipment — calisthenics and cardio"
        }
    }
}

/// Dietary pattern drives both the local food database and the Spoonacular
/// query, so it has to cover more than one person's diet.
enum DietaryPattern: String, Codable, CaseIterable, Identifiable {
    case vegetarian, vegan, pescatarian, omnivore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .omnivore: return "Eats everything"
        }
    }

    /// Spoonacular's `diet` query parameter. Omnivore sends nothing.
    var spoonacularDiet: String? {
        switch self {
        case .vegetarian: return "vegetarian"
        case .vegan: return "vegan"
        case .pescatarian: return "pescetarian"
        case .omnivore: return nil
        }
    }
}

/// Cuisine leaning, used to bias recipe search so the meal plan feels like food
/// the person actually eats rather than generic diet fare.
enum CuisinePreference: String, Codable, CaseIterable, Identifiable {
    case southAsian, mediterranean, eastAsian, latin, american, noPreference

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .southAsian: return "South Asian"
        case .mediterranean: return "Mediterranean"
        case .eastAsian: return "East Asian"
        case .latin: return "Latin"
        case .american: return "American"
        case .noPreference: return "No preference"
        }
    }

    /// Spoonacular `cuisine` parameter.
    var spoonacularCuisine: String? {
        switch self {
        case .southAsian: return "Indian"
        case .mediterranean: return "Mediterranean"
        case .eastAsian: return "Asian"
        case .latin: return "Latin American"
        case .american: return "American"
        case .noPreference: return nil
        }
    }
}

struct UserProfile: Codable, Equatable, Identifiable {
    /// Stable local identity. When signed in with Apple this is paired with
    /// `appleUserIdentifier` so the same person's data follows them across
    /// devices via their private CloudKit database.
    var id: UUID
    /// Apple's stable, app-scoped user ID from Sign in with Apple. Never an
    /// email — Apple may relay those, and we don't need one.
    var appleUserIdentifier: String?

    var name: String
    var age: Int
    var sex: Sex
    var heightInches: Double     // 5'10" = 70
    var currentWeightLbs: Double
    var goalWeightLbs: Double
    var goalDirection: GoalDirection
    var activityLevel: ActivityLevel
    var equipment: [Equipment]
    var hasAppleWatch: Bool
    var fitnessGoals: Set<FitnessGoal>
    var dietaryPattern: DietaryPattern
    var cuisinePreference: CuisinePreference
    var allergies: [String]
    var mealsPerDay: Int
    var wakeConstraintEarliest: DateComponents?   // e.g. can't wake before class needs, optional
    var toneIntensity: ToneIntensity
    var accentColor: AppAccent
    var accountabilityMode: Set<AccountabilityTrigger>
    var weightHistory: [WeightEntry]

    /// A blank profile for someone starting the quiz — intentionally neutral
    /// rather than pre-filled with one person's situation.
    static var blank: UserProfile {
        UserProfile(
            id: UUID(),
            appleUserIdentifier: nil,
            name: "",
            age: 25,
            sex: .male,
            heightInches: 68,
            currentWeightLbs: 170,
            goalWeightLbs: 160,
            goalDirection: .cut,
            activityLevel: .lightlyActive,
            equipment: [.homeEquipment],
            hasAppleWatch: false,
            fitnessGoals: [.fatLoss],
            dietaryPattern: .omnivore,
            cuisinePreference: .noPreference,
            allergies: [],
            mealsPerDay: 4,
            wakeConstraintEarliest: nil,
            toneIntensity: .toughLove,
            accentColor: .ember,
            accountabilityMode: [.scheduledCheckIns],
            weightHistory: []
        )
    }

    /// Rahil's preset — used by the "start from a preset" path so an existing
    /// setup can be handed to someone without re-running the whole quiz.
    static var rahilPreset: UserProfile {
        var profile = blank
        profile.name = "Rahil"
        profile.age = 22
        profile.sex = .male
        profile.heightInches = 70
        profile.currentWeightLbs = 220
        profile.goalWeightLbs = 180
        profile.goalDirection = .cut
        profile.activityLevel = .lightlyActive
        profile.equipment = [.fullGym, .homeEquipment]
        profile.hasAppleWatch = true
        profile.fitnessGoals = [.fatLoss, .fastBowling, .hikingBackpacking]
        profile.dietaryPattern = .vegetarian
        profile.cuisinePreference = .southAsian
        profile.toneIntensity = .toughLove
        profile.accountabilityMode = [.scheduledCheckIns, .screenTime]
        return profile
    }
}

struct WeightEntry: Codable, Equatable {
    let date: Date
    let weightLbs: Double
}

enum ToneIntensity: String, Codable, CaseIterable { case gentle, toughLove, hardcore }

enum AccountabilityTrigger: String, Codable, CaseIterable {
    case scheduledCheckIns, screenTime
}

struct StreakStatus: Codable, Equatable {
    var currentStreakDays: Int = 0
    var longestStreakDays: Int = 0
    var lastMissedEvent: String?
    var missedCheckInsThisWeek: Int = 0
    /// "yyyy-MM-dd" of the last day already counted toward currentStreakDays,
    /// so evaluateStreak doesn't double-increment on repeat confirmations.
    var lastCountedDayKey: String?
}
