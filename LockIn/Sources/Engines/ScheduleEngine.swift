import Foundation

/// Assembles the full day's timeline: wake routine, real Calendar commitments,
/// meals and a workout slotted into free gaps, Reminders due today, then
/// wind-down and sleep. Adding something to Calendar moves the Lock In pieces
/// — the day is one timeline, not a template with a calendar glance.
enum ScheduleEngine {
    /// `liveMeals` carries Spoonacular results when they're available; passing
    /// nil falls back to the built-in database so the day always builds.
    static func buildDay(profile: UserProfile, macros: MacroTargets, sleepPlan: SleepPlan,
                         busyBlocks: [BusyBlock], date: Date, liveMeals: [Meal]? = nil,
                         tasks: [DayTask] = []) -> DaySchedule {
        let calendar = Calendar.current
        var events: [ScheduledEvent] = []
        var occupied: [ScheduleSlotter.Interval] = busyBlocks.map {
            ScheduleSlotter.Interval(start: $0.start, end: $0.end)
        }

        events.append(ScheduledEvent(kind: .wake, title: "Wake up", detail: "Get up, no snooze — hit the light.", time: sleepPlan.targetWakeTime, durationMinutes: 10, isCritical: true))
        occupy(&occupied, start: sleepPlan.targetWakeTime, minutes: 10)

        let weighIn = calendar.date(byAdding: .minute, value: 5, to: sleepPlan.targetWakeTime)!
        events.append(ScheduledEvent(kind: .weighIn, title: "Weigh-in", detail: "Same time, same conditions, every day — trend matters more than one reading.", time: weighIn, durationMinutes: 2, isCritical: true))

        events.append(ScheduledEvent(kind: .progressPhoto, title: "Progress photo", detail: "Same spot, same lighting, same pose as yesterday — open Progress tab. This is the evidence, not the scale.", time: calendar.date(byAdding: .minute, value: 8, to: sleepPlan.targetWakeTime)!, durationMinutes: 2, isCritical: false))

        let caffeineTime = calendar.date(byAdding: .minute, value: 30, to: sleepPlan.targetWakeTime)!
        events.append(ScheduledEvent(kind: .caffeine, title: "Coffee", detail: "Black or low-cal — mind the caffeine cutoff tonight.", time: caffeineTime, durationMinutes: 15, isCritical: false))

        for block in busyBlocks.sorted(by: { $0.start < $1.start }) {
            let minutes = max(Int(block.end.timeIntervalSince(block.start) / 60), 1)
            var detail = timeRange(start: block.start, end: block.end)
            if let location = block.location, !location.isEmpty {
                detail += " · \(location)"
            }
            detail += " · Calendar"
            events.append(ScheduledEvent(
                kind: .commitment,
                title: block.title,
                detail: detail,
                time: block.start,
                durationMinutes: minutes,
                isCritical: false,
                externalIdentifier: block.calendarItemIdentifier
            ))
        }

        occupy(&occupied, start: sleepPlan.windDownStart, minutes: 45)
        occupy(&occupied, start: sleepPlan.targetBedTime, minutes: Int(sleepPlan.sleepDurationHours * 60))

        if let workoutTime = findWorkoutSlot(busyBlocks: busyBlocks, date: date) {
            let session = WorkoutEngine.session(for: date, goals: profile.fitnessGoals)
            let goalTagLine = session.goalTags.filter { profile.fitnessGoals.contains($0) }.map { $0.displayName }.joined(separator: " · ")
            let detail = "\(session.summaryLine)\n\(session.equipmentNote)\nServes: \(goalTagLine)"
            events.append(ScheduledEvent(kind: .workout, title: session.focus.title, detail: detail, time: workoutTime, durationMinutes: 60, isCritical: true))
            occupy(&occupied, start: workoutTime, minutes: 60)
        }

        let meals = liveMeals ?? MealEngine.buildDay(macros: macros, profile: profile)
        let mealWindows = mealWindows(for: date, wake: sleepPlan.targetWakeTime, windDown: sleepPlan.windDownStart)
        let mealDuration = 25

        for meal in meals {
            guard let window = mealWindows[meal.slot] else { continue }
            let start = ScheduleSlotter.firstFit(
                duration: TimeInterval(mealDuration * 60),
                preferred: window.preferred,
                window: window.bounds,
                occupied: occupied
            )
            let macroLine = "\(Int(meal.totalMacros.calories))kcal · P\(Int(meal.totalMacros.proteinG)) F\(Int(meal.totalMacros.fatG)) C\(Int(meal.totalMacros.carbG))"
            let componentLines = meal.components.map { "\(Int($0.gramsToWeigh))g \($0.food.name)" }.joined(separator: ", ")
            events.append(ScheduledEvent(
                kind: .meal, title: meal.name, detail: "\(componentLines) — \(macroLine)",
                time: start, durationMinutes: mealDuration, isCritical: true, linkedMealID: meal.id
            ))
            occupy(&occupied, start: start, minutes: mealDuration)

            if let prepAhead = meal.maxPrepAheadMinutes, prepAhead > 15 {
                let prepTime = calendar.date(byAdding: .minute, value: -prepAhead, to: start)!
                let prepItems = meal.components.compactMap { c -> String? in
                    guard let instr = c.food.prepInstructions else { return nil }
                    return "\(c.food.name): \(instr)"
                }.joined(separator: "\n")
                if !prepItems.isEmpty {
                    events.append(ScheduledEvent(kind: .mealPrep, title: "Prep for \(meal.name)", detail: prepItems, time: prepTime, durationMinutes: 15, isCritical: false, linkedMealID: meal.id))
                }
            }
        }

        for task in tasks {
            var detail = "Reminders"
            if let notes = task.notes, !notes.isEmpty { detail = "\(notes) · Reminders" }
            events.append(ScheduledEvent(
                kind: .task,
                title: task.title,
                detail: detail,
                time: task.due,
                durationMinutes: 15,
                isCritical: false,
                externalIdentifier: task.id
            ))
        }

        events.append(ScheduledEvent(kind: .windDown, title: "Wind down", detail: "Screens off, lights dim. This is non-negotiable for sleep quality.", time: sleepPlan.windDownStart, durationMinutes: 45, isCritical: true))
        events.append(ScheduledEvent(kind: .sleep, title: "Sleep", detail: "Lights out. Tomorrow starts now.", time: sleepPlan.targetBedTime, durationMinutes: Int(sleepPlan.sleepDurationHours * 60), isCritical: true))

        events.sort { $0.time < $1.time }
        return DaySchedule(date: date, events: events, macros: macros, sleepPlan: sleepPlan)
    }

    // MARK: - Meal windows

    private struct MealWindow {
        let preferred: Date
        let bounds: ScheduleSlotter.Interval
    }

    private static func mealWindows(for date: Date, wake: Date, windDown: Date) -> [MealSlot: MealWindow] {
        let calendar = Calendar.current
        func clock(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        }

        let breakfastPreferred = calendar.date(byAdding: .minute, value: 45, to: wake)!
        let breakfastEnd = min(clock(10, 30), windDown)
        let lunchPreferred = clock(13, 0)
        let snackPreferred = clock(16, 30)
        let dinnerPreferred = clock(19, 30)

        return [
            .breakfast: MealWindow(
                preferred: breakfastPreferred,
                bounds: ScheduleSlotter.Interval(
                    start: calendar.date(byAdding: .minute, value: 30, to: wake)!,
                    end: max(breakfastEnd, calendar.date(byAdding: .minute, value: 90, to: wake)!)
                )
            ),
            .lunch: MealWindow(
                preferred: lunchPreferred,
                bounds: ScheduleSlotter.Interval(start: clock(11, 30), end: min(clock(14, 30), windDown))
            ),
            .snack: MealWindow(
                preferred: snackPreferred,
                bounds: ScheduleSlotter.Interval(start: clock(15, 0), end: min(clock(17, 30), windDown))
            ),
            .dinner: MealWindow(
                preferred: dinnerPreferred,
                bounds: ScheduleSlotter.Interval(start: clock(18, 0), end: min(clock(20, 30), windDown))
            )
        ]
    }

    // MARK: - Workout

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

    // MARK: - Helpers

    private static func occupy(_ occupied: inout [ScheduleSlotter.Interval], start: Date, minutes: Int) {
        occupied.append(ScheduleSlotter.Interval(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60))))
    }

    private static func timeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
