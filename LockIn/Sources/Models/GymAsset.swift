import Foundation

/// Specific kit available in an apartment / hotel / home gym. Finer than the
/// coarse `Equipment` tier — drives which variations `WorkoutEngine` picks
/// (Smith vs free bar, cable woodchop vs band, Peloton vs outdoor run, etc.).
enum GymAsset: String, Codable, CaseIterable, Identifiable, Hashable {
    case cablePulley
    case smithMachine
    case dumbbells
    case medicineBall
    case treadmill
    case peloton
    case rower
    case stretchingMats
    case barbellRack
    case resistanceBands
    case pullUpBar
    case bench

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cablePulley: return "Cable / pulley stack"
        case .smithMachine: return "Smith machine"
        case .dumbbells: return "Dumbbells"
        case .medicineBall: return "Medicine balls"
        case .treadmill: return "Treadmill"
        case .peloton: return "Peloton / bike"
        case .rower: return "Rowing machine"
        case .stretchingMats: return "Stretching mats"
        case .barbellRack: return "Barbell + rack"
        case .resistanceBands: return "Resistance bands"
        case .pullUpBar: return "Pull-up bar"
        case .bench: return "Bench"
        }
    }

    /// Sensible default for a typical apartment gym like Rahil's.
    static var apartmentDefault: Set<GymAsset> {
        [.cablePulley, .smithMachine, .dumbbells, .medicineBall, .treadmill, .peloton, .rower, .stretchingMats, .bench]
    }
}

extension Equipment {
    /// When the user picks apartment gym and hasn't customized assets yet,
    /// seed the apartment default kit.
    var defaultAssets: Set<GymAsset> {
        switch self {
        case .fullGym:
            return Set(GymAsset.allCases)
        case .homeEquipment:
            return [.dumbbells, .resistanceBands, .bench, .stretchingMats, .pullUpBar]
        case .apartmentGym:
            return GymAsset.apartmentDefault
        case .bodyweightOnly:
            return [.stretchingMats]
        }
    }
}
