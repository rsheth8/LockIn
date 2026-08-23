import Foundation

struct SleepPlan: Codable, Equatable {
    let targetWakeTime: Date
    let targetBedTime: Date
    let windDownStart: Date       // screens off / dim lights, ~30-60 min before bed
    let caffeineCutoff: Date      // last acceptable caffeine time
    let sleepDurationHours: Double
}
