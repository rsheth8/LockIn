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
}

enum Equipment: String, Codable, CaseIterable { case fullGym, homeEquipment, bodyweightOnly }

enum DietaryPattern: String, Codable { case vegetarian }

struct UserProfile: Codable, Equatable {
    var name: String
    var age: Int
    var sex: Sex
    var heightInches: Double     // 5'10" = 70
    var currentWeightLbs: Double
    var goalWeightLbs: Double
    var activityLevel: ActivityLevel
    var equipment: [Equipment]
    var hasAppleWatch: Bool
    var dietaryPattern: DietaryPattern
    var southAsianVegetarian: Bool  // biases meal DB toward dal/paneer/roti/sabzi style meals
    var wakeConstraintEarliest: DateComponents?   // e.g. can't wake before class needs, optional
    var toneIntensity: ToneIntensity
    var accountabilityMode: Set<AccountabilityTrigger>
    var weightHistory: [WeightEntry]

    static let `default` = UserProfile(
        name: "",
        age: 22,
        sex: .male,
        heightInches: 70,
        currentWeightLbs: 220,
        goalWeightLbs: 180,
        activityLevel: .lightlyActive,
        equipment: [.fullGym, .homeEquipment],
        hasAppleWatch: true,
        dietaryPattern: .vegetarian,
        southAsianVegetarian: true,
        wakeConstraintEarliest: nil,
        toneIntensity: .toughLove,
        accountabilityMode: [.scheduledCheckIns, .screenTime],
        weightHistory: []
    )
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
}
