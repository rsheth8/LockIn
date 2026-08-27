import Foundation

enum EventKind: String, Codable {
    case wake, caffeine, meal, mealPrep, workout, windDown, sleep, weighIn, progressPhoto, hydration, custom
    case classSession   // a scheduled class, drawn from the term schedule
    case commute        // "leave by" nudge before the first class of the day
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
    /// The full prescription behind a `.workout` event. The timeline only shows
    /// its summary line, but the workout portal needs the sets/reps structure —
    /// carrying it here means the portal runs exactly the session that was
    /// planned rather than re-deriving one and risking a mismatch. Optional so
    /// schedules persisted before the portal shipped still decode.
    var linkedWorkout: WorkoutSession?

    init(id: UUID = UUID(), kind: EventKind, title: String, detail: String, time: Date, durationMinutes: Int, isCritical: Bool, linkedMealID: UUID? = nil, linkedWorkout: WorkoutSession? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.time = time
        self.durationMinutes = durationMinutes
        self.isCritical = isCritical
        self.linkedMealID = linkedMealID
        self.linkedWorkout = linkedWorkout
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
