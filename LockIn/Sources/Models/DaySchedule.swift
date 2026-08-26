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
    /// What this meal actually delivers. Held on the event rather than parsed
    /// back out of `detail`, so swapping a meal mid-day keeps the day's totals
    /// honest without anyone re-reading a display string.
    var mealMacros: MacroTargetsLite?

    init(id: UUID = UUID(), kind: EventKind, title: String, detail: String, time: Date, durationMinutes: Int, isCritical: Bool, linkedMealID: UUID? = nil, externalIdentifier: String? = nil, mealMacros: MacroTargetsLite? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.time = time
        self.durationMinutes = durationMinutes
        self.isCritical = isCritical
        self.linkedMealID = linkedMealID
        self.externalIdentifier = externalIdentifier
        self.mealMacros = mealMacros
    }

    var endTime: Date {
        time.addingTimeInterval(TimeInterval(max(durationMinutes, 0) * 60))
    }
}

enum EventStatus: String, Codable {
    case pending, confirmed, missed, snoozed
}

/// Where today's meals came from — surfaces on Today so a silent Spoonacular
/// fallback doesn't look like "live recipes" when it isn't.
enum MealSource: String, Codable, Equatable {
    case spoonacular
    case localDatabase

    var label: String {
        switch self {
        case .spoonacular: return "Live recipes"
        case .localDatabase: return "Built-in meals"
        }
    }
}

struct DaySchedule: Codable, Equatable {
    let date: Date
    var events: [ScheduledEvent]
    /// What the day is *supposed* to hit — computed by `MetabolicEngine`.
    var macros: MacroTargets
    var sleepPlan: SleepPlan
    var mealSource: MealSource

    init(date: Date, events: [ScheduledEvent], macros: MacroTargets, sleepPlan: SleepPlan,
         mealSource: MealSource = .localDatabase) {
        self.date = date
        self.events = events
        self.macros = macros
        self.sleepPlan = sleepPlan
        self.mealSource = mealSource
    }

    enum CodingKeys: String, CodingKey {
        case date, events, macros, sleepPlan, mealSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        events = try c.decode([ScheduledEvent].self, forKey: .events)
        macros = try c.decode(MacroTargets.self, forKey: .macros)
        sleepPlan = try c.decode(SleepPlan.self, forKey: .sleepPlan)
        mealSource = try c.decodeIfPresent(MealSource.self, forKey: .mealSource) ?? .localDatabase
    }

    /// What the meals on this schedule actually add up to, which is not the
    /// same as `macros` — that's the target. Derived from the events so a meal
    /// swap moves it automatically.
    var plannedMacros: MacroTargetsLite? {
        let macrosPerMeal = events.filter { $0.kind == .meal }.compactMap(\.mealMacros)
        guard !macrosPerMeal.isEmpty else { return nil }
        return macrosPerMeal.reduce(MacroTargetsLite(calories: 0, proteinG: 0, fatG: 0, carbG: 0)) { acc, m in
            MacroTargetsLite(
                calories: acc.calories + m.calories,
                proteinG: acc.proteinG + m.proteinG,
                fatG: acc.fatG + m.fatG,
                carbG: acc.carbG + m.carbG
            )
        }
    }

    /// How far the plan falls short of the protein target, in grams. Zero when
    /// it's on target, over, or built before macros were tracked per meal.
    var proteinShortfall: Int {
        guard let plannedMacros else { return 0 }
        return max(0, macros.proteinGrams - Int(plannedMacros.proteinG.rounded()))
    }
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
