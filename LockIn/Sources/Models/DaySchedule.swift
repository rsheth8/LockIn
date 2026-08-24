import Foundation

enum EventKind: String, Codable {
    case wake, caffeine, meal, mealPrep, workout, windDown, sleep, weighIn, progressPhoto, hydration, custom
    /// A real Calendar.app event — shown on the timeline, never a streak promise.
    case commitment
    /// An incomplete Reminders item due today.
    case task

    /// Calendar blocks occupy time; Lock In meals and workouts must move around them.
    var occupiesTime: Bool {
        switch self {
        case .commitment, .workout, .meal, .windDown, .sleep, .wake: return true
        default: return false
        }
    }

    /// Hero card + streak only care about things Lock In asked you to do.
    var canLeadHero: Bool { self != .commitment }

    var writesToCalendar: Bool {
        switch self {
        case .wake, .meal, .mealPrep, .workout, .windDown, .sleep: return true
        default: return false
        }
    }

    var sourceLabel: String? {
        switch self {
        case .commitment: return "Calendar"
        case .task: return "Reminders"
        default: return nil
        }
    }
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
    /// EventKit calendar item / reminder identifier, used to match across rebuilds
    /// and to complete a reminder in the Reminders app.
    var externalIdentifier: String?

    init(id: UUID = UUID(), kind: EventKind, title: String, detail: String, time: Date, durationMinutes: Int, isCritical: Bool, linkedMealID: UUID? = nil, externalIdentifier: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.time = time
        self.durationMinutes = durationMinutes
        self.isCritical = isCritical
        self.linkedMealID = linkedMealID
        self.externalIdentifier = externalIdentifier
    }

    var endTime: Date {
        time.addingTimeInterval(TimeInterval(max(durationMinutes, 0) * 60))
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
    var calendarItemIdentifier: String? = nil
    var location: String? = nil
}

/// An incomplete Reminders item due today, pulled onto the day timeline.
struct DayTask: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let due: Date
    var notes: String?
}
