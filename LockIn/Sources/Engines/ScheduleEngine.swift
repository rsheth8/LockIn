import Foundation

/// Assembles the full day's timeline: wake -> caffeine -> meals (+ prep reminders,
/// scheduled earlier when a food needs soak/marinate/cook lead time) -> workout
/// slotted into the largest open gap between calendar busy blocks -> wind-down -> sleep.
enum ScheduleEngine {
    static func buildDay(profile: UserProfile, macros: MacroTargets, sleepPlan: SleepPlan, busyBlocks: [BusyBlock], date: Date) -> DaySchedule {
        let calendar = Calendar.current
        var events: [ScheduledEvent] = []

        events.append(ScheduledEvent(kind: .wake, title: "Wake up", detail: "Get up, no snooze — hit the light.", time: sleepPlan.targetWakeTime, durationMinutes: 10, isCritical: true))

        let caffeineTime = calendar.date(byAdding: .minute, value: 30, to: sleepPlan.targetWakeTime)!
        events.append(ScheduledEvent(kind: .caffeine, title: "Coffee", detail: "Black or low-cal — mind the caffeine cutoff tonight.", time: caffeineTime, durationMinutes: 15, isCritical: false))

        events.append(ScheduledEvent(kind: .weighIn, title: "Weigh-in", detail: "Same time, same conditions, every day — trend matters more than one reading.", time: calendar.date(byAdding: .minute, value: 5, to: sleepPlan.targetWakeTime)!, durationMinutes: 2, isCritical: true))

        let meals = MealEngine.buildDay(macros: macros, southAsianVegetarian: profile.southAsianVegetarian)
        let mealTimes: [MealSlot: Date] = [
            .breakfast: calendar.date(byAdding: .minute, value: 45, to: sleepPlan.targetWakeTime)!,
            .lunch: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: date)!,
            .snack: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: date)!,
            .dinner: calendar.date(bySettingHour: 19, minute: 30, second: 0, of: date)!
        ]

        for meal in meals {
            guard let mealTime = mealTimes[meal.slot] else { continue }
            let macroLine = "\(Int(meal.totalMacros.calories))kcal · P\(Int(meal.totalMacros.proteinG)) F\(Int(meal.totalMacros.fatG)) C\(Int(meal.totalMacros.carbG))"
            let componentLines = meal.components.map { "\(Int($0.gramsToWeigh))g \($0.food.name)" }.joined(separator: ", ")
            events.append(ScheduledEvent(
                kind: .meal, title: meal.name, detail: "\(componentLines) — \(macroLine)",
                time: mealTime, durationMinutes: 25, isCritical: true, linkedMealID: meal.id
            ))

            if let prepAhead = meal.maxPrepAheadMinutes, prepAhead > 15 {
                let prepTime = calendar.date(byAdding: .minute, value: -prepAhead, to: mealTime)!
                let prepItems = meal.components.compactMap { c -> String? in
                    guard let instr = c.food.prepInstructions else { return nil }
                    return "\(c.food.name): \(instr)"
                }.joined(separator: "\n")
                if !prepItems.isEmpty {
                    events.append(ScheduledEvent(kind: .mealPrep, title: "Prep for \(meal.name)", detail: prepItems, time: prepTime, durationMinutes: 15, isCritical: false, linkedMealID: meal.id))
                }
            }
        }

        // Workout: find the largest free gap between 2pm-9pm that fits 60 min, avoiding busy blocks.
        if let workoutTime = findWorkoutSlot(busyBlocks: busyBlocks, date: date) {
            let equipmentNote = profile.equipment.contains(.fullGym) ? "Gym session — follow this week's program." : "Home session — dumbbells/bodyweight circuit."
            events.append(ScheduledEvent(kind: .workout, title: "Workout", detail: equipmentNote, time: workoutTime, durationMinutes: 60, isCritical: true))
        }

        events.append(ScheduledEvent(kind: .windDown, title: "Wind down", detail: "Screens off, lights dim. This is non-negotiable for sleep quality.", time: sleepPlan.windDownStart, durationMinutes: 45, isCritical: true))
        events.append(ScheduledEvent(kind: .sleep, title: "Sleep", detail: "Lights out. Tomorrow starts now.", time: sleepPlan.targetBedTime, durationMinutes: 0, isCritical: true))

        events.sort { $0.time < $1.time }
        return DaySchedule(date: date, events: events, macros: macros, sleepPlan: sleepPlan)
    }

    private static func findWorkoutSlot(busyBlocks: [BusyBlock], date: Date) -> Date? {
        let calendar = Calendar.current
        let windowStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date)!
        let windowEnd = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!
        let relevant = busyBlocks.filter { $0.end > windowStart && $0.start < windowEnd }.sorted { $0.start < $1.start }

        var cursor = windowStart
        var bestGapStart: Date?
        var bestGapLength: TimeInterval = 0

        func considerGap(_ start: Date, _ end: Date) {
            let length = end.timeIntervalSince(start)
            if length >= 60 * 60 && length > bestGapLength {
                bestGapLength = length
                bestGapStart = start
            }
        }

        for block in relevant {
            if block.start > cursor { considerGap(cursor, block.start) }
            cursor = max(cursor, block.end)
        }
        if cursor < windowEnd { considerGap(cursor, windowEnd) }

        return bestGapStart
    }
}
