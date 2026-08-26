#if DEBUG
import Foundation
import Combine

/// DEBUG-only harness for exercising LockIn paths without hand-editing state.
/// Injected into RootView so schedule/meal overrides actually rebuild Today.
@MainActor
final class DevLabController: ObservableObject {
    static let shared = DevLabController()

    /// When non-nil, Today is built around these busy blocks instead of EventKit.
    @Published var overrideBusyBlocks: [BusyBlock]?
    /// Skip Spoonacular and always use the built-in food database.
    @Published var forceLocalMeals = false
    /// Bumped to ask RootView to rebuild the day.
    @Published private(set) var rebuildToken = UUID()
    @Published var lastAction: String?

    var hasScheduleOverride: Bool { overrideBusyBlocks != nil }

    func requestRebuild(note: String) {
        lastAction = note
        rebuildToken = UUID()
    }

    func clearScheduleOverride() {
        overrideBusyBlocks = nil
        requestRebuild(note: "Using live Calendar busy blocks")
    }

    /// Packed afternoon — no workout gap in the 2–9pm window.
    func applyPackedDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: today)!
        }
        overrideBusyBlocks = [
            BusyBlock(title: "Lecture", start: at(9, 0), end: at(11, 0)),
            BusyBlock(title: "Lab", start: at(12, 0), end: at(14, 0)),
            BusyBlock(title: "Seminar", start: at(14, 0), end: at(17, 0)),
            BusyBlock(title: "Study group", start: at(17, 0), end: at(21, 0))
        ]
        requestRebuild(note: "Packed day — workout should be missing")
    }

    /// One morning class, big afternoon gap for a workout.
    func applyLightDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: today)!
        }
        overrideBusyBlocks = [
            BusyBlock(title: "Morning class", start: at(9, 30), end: at(10, 45))
        ]
        requestRebuild(note: "Light day — workout should slot in")
    }

    /// Completely free calendar.
    func applyEmptyCalendar() {
        overrideBusyBlocks = []
        requestRebuild(note: "Empty calendar override")
    }
}

/// Named scenarios the Lab can one-tap apply.
enum DevPersona: String, CaseIterable, Identifiable {
    case rahilCut
    case rahilMaxCut
    case bodyweightOnly
    case homeGymGain
    case veganMaintain
    case gentleFemaleCut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rahilCut: return "Rahil · cut · gym"
        case .rahilMaxCut: return "Rahil · max pace"
        case .bodyweightOnly: return "Bodyweight only"
        case .homeGymGain: return "Home gym · gain"
        case .veganMaintain: return "Vegan · maintain"
        case .gentleFemaleCut: return "Gentle · female cut"
        }
    }

    var blurb: String {
        switch self {
        case .rahilCut: return "220→180, vegetarian, bowling + hiking, tough love"
        case .rahilMaxCut: return "Same body, maximum deficit intensity"
        case .bodyweightOnly: return "No barbells — exercises should swap"
        case .homeGymGain: return "Dumbbells/bands, surplus macros"
        case .veganMaintain: return "Maintenance calories, vegan meals"
        case .gentleFemaleCut: return "Softer tone, different body math"
        }
    }

    func makeProfile() -> UserProfile {
        switch self {
        case .rahilCut:
            return UserProfile.rahilPreset
        case .rahilMaxCut:
            var p = UserProfile.rahilPreset
            p.deficitIntensity = .maximum
            return p
        case .bodyweightOnly:
            var p = UserProfile.rahilPreset
            p.equipment = [.bodyweightOnly]
            p.gymAssets = [.stretchingMats]
            p.fitnessGoals = [.fatLoss, .fastBowling]
            return p
        case .homeGymGain:
            var p = UserProfile.blank
            p.name = "Dev Gain"
            p.age = 24
            p.sex = .male
            p.heightInches = 71
            p.currentWeightLbs = 160
            p.goalWeightLbs = 175
            p.goalDirection = .gain
            p.deficitIntensity = .aggressive
            p.activityLevel = .moderatelyActive
            p.equipment = [.homeEquipment]
            p.gymAssets = Equipment.homeEquipment.defaultAssets
            p.dietaryPattern = .omnivore
            p.cuisinePreference = .american
            p.foodPreferences.cuisines = [.american]
            p.fitnessGoals = [.fatLoss]
            p.toneIntensity = .toughLove
            p.mealsPerDay = 4
            return p
        case .veganMaintain:
            var p = UserProfile.rahilPreset
            p.goalDirection = .maintain
            p.goalWeightLbs = p.currentWeightLbs
            p.dietaryPattern = .vegan
            p.toneIntensity = .gentle
            return p
        case .gentleFemaleCut:
            var p = UserProfile.blank
            p.name = "Priya"
            p.age = 25
            p.sex = .female
            p.heightInches = 66
            p.currentWeightLbs = 150
            p.goalWeightLbs = 135
            p.goalDirection = .cut
            p.deficitIntensity = .standard
            p.activityLevel = .lightlyActive
            p.equipment = [.homeEquipment]
            p.gymAssets = Equipment.homeEquipment.defaultAssets
            p.dietaryPattern = .omnivore
            p.cuisinePreference = .mediterranean
            p.foodPreferences.cuisines = [.mediterranean]
            p.fitnessGoals = [.fatLoss, .hikingBackpacking]
            p.toneIntensity = .gentle
            p.mealsPerDay = 3
            return p
        }
    }
}
#endif
