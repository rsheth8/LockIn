import Foundation

enum EventKind: String, Codable {
    case wake, caffeine, meal, mealPrep, workout, windDown, sleep, weighIn, hydration, custom
}

struct ScheduledEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: EventKind
    var title: String
    var detail: String          // e.g. "180g paneer, 150g rice, 100g spinach"
    var time: Date
    var durationMinutes: Int
    var isCritical: Bool        // critical events trigger guilt-trip escalation if missed
    var status: EventStatus = .pending
    var linkedMealID: UUID?

    init(id: UUID = UUID(), kind: EventKind, title: String, detail: String, time: Date, durationMinutes: Int, isCritical: Bool, linkedMealID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.time = time
        self.durationMinutes = durationMinutes
        self.isCritical = isCritical
        self.linkedMealID = linkedMealID
    }
}

enum EventStatus: String, Codable {
    case pending, confirmed, missed, snoozed
}

struct DaySchedule: Codable, Equatable {
    let date: Date
    var events: [ScheduledEvent]
    var macros: MacroTargets
    var sleepPlan: SleepPlan
}

struct BusyBlock: Codable, Equatable {
    let title: String
    let start: Date
    let end: Date
}
