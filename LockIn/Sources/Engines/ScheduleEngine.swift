import Foundation

/// Assembles the day's timeline around fixed anchors.
///
/// Order of operations: wake/bed come from `SleepPlan` (a fixed rhythm, not the
/// calendar). Classes from the term schedule are laid down as blocks, with a
/// "leave by" nudge before the first one. Meals are then fitted to the gaps —
/// lunch before an afternoon class, not on top of it — and the workout is
/// placed near its preferred time of day on training days only, never
/// overlapping a class or a calendar commitment. Weigh-in and progress photo
/// run weekly, on Mondays.
enum ScheduleEngine {
    /// `liveMeals` carries Spoonacular results when available; nil falls back to
    /// the built-in database so the day always builds.
    static func buildDay(profile: UserProfile, macros: MacroTargets, sleepPlan: SleepPlan,
                         busyBlocks: [BusyBlock], date: Date, liveMeals: [Meal]? = nil) -> DaySchedule {
        let calendar = Calendar.current
        var events: [ScheduledEvent] = []

        // MARK: Wake + coffee
        events.append(ScheduledEvent(kind: .wake, title: "Wake up",
            detail: "Get up, no snooze — hit the light.",
            time: sleepPlan.targetWakeTime, durationMinutes: 10, isCritical: true))

        events.append(ScheduledEvent(kind: .caffeine, title: "Coffee",
            detail: "Black or low-cal — nothing caffeinated after \(clock(sleepPlan.caffeineCutoff)).",
            time: calendar.date(byAdding: .minute, value: 30, to: sleepPlan.targetWakeTime)!,
            durationMinutes: 15, isCritical: false))

        // MARK: Classes + leave-by
        let sessions = profile.termSchedule?.sessions(on: date, calendar: calendar) ?? []
        for session in sessions {
            let minutes = Int(session.end.timeIntervalSince(session.start) / 60)
            events.append(ScheduledEvent(kind: .classSession, title: session.meeting.courseCode,
                detail: "\(session.meeting.title)\n\(session.meeting.location)",
                time: session.start, durationMinutes: minutes, isCritical: false))
        }
        if let first = sessions.first, let term = profile.termSchedule {
            let leaveBy = calendar.date(byAdding: .minute, value: -term.leadMinutes, to: first.start)!
            events.append(ScheduledEvent(kind: .commute, title: "Leave for campus",
                detail: "\(term.commuteMinutes) min there, \(term.prepMinutes) to get ready. First up: \(first.meeting.courseCode) at \(clock(first.start)).",
                time: leaveBy, durationMinutes: term.commuteMinutes, isCritical: false))
        }

        // MARK: Weigh-in + progress photo — Mondays only
        if calendar.component(.weekday, from: date) == 2 {
            events.append(ScheduledEvent(kind: .weighIn, title: "Weigh-in",
                detail: "Same time, same conditions — first thing, after the bathroom, before you eat. The trend is the signal.",
                time: calendar.date(byAdding: .minute, value: 5, to: sleepPlan.targetWakeTime)!,
                durationMinutes: 2, isCritical: true))
            events.append(ScheduledEvent(kind: .progressPhoto, title: "Progress photo",
                detail: "Same spot, same light, same pose as last week — open the Progress tab. Weekly, so the change is actually visible.",
                time: calendar.date(byAdding: .minute, value: 8, to: sleepPlan.targetWakeTime)!,
                durationMinutes: 2, isCritical: false))
        }

        // MARK: Meal times
        let meals = liveMeals ?? MealEngine.buildDay(macros: macros, profile: profile)
        let breakfast = calendar.date(byAdding: .minute, value: 45, to: sleepPlan.targetWakeTime)!
        let lunch = lunchTime(sessions: sessions, term: profile.termSchedule, date: date, calendar: calendar)
        let dinner = calendar.date(bySettingHour: 19, minute: 15, second: 0, of: date)!

        // Workout is placed before meals so the post-workout snack can hang off it.
        let classBusy = sessions.map { BusyBlock(title: $0.meeting.courseCode, start: $0.start, end: $0.end) }
        var workoutTime: Date?
        if profile.rhythm.trainsOn(date, calendar: calendar) {
            let target = workoutTarget(sessions: sessions, lunch: lunch, date: date, calendar: calendar)
            workoutTime = findWorkoutSlot(busyBlocks: busyBlocks + classBusy, date: date,
                                          target: target, calendar: calendar)
        }

        let snack: Date = workoutTime
            .map { calendar.date(byAdding: .minute, value: 75, to: $0)! }
            ?? calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)!

        let mealTimes: [MealSlot: Date] = [
            .breakfast: breakfast, .lunch: lunch, .snack: snack, .dinner: dinner
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
                    events.append(ScheduledEvent(kind: .mealPrep, title: "Prep for \(meal.name)",
                        detail: prepItems, time: prepTime, durationMinutes: 15,
                        isCritical: false, linkedMealID: meal.id))
                }
            }
        }

        // MARK: Workout content
        if let workoutTime {
            let session = WorkoutEngine.session(for: date, goals: profile.fitnessGoals)
            let goalTagLine = session.goalTags.filter { profile.fitnessGoals.contains($0) }
                .map { $0.displayName }.joined(separator: " · ")
            let detail = "\(session.summaryLine)\n\(session.equipmentNote)\nServes: \(goalTagLine)"
            events.append(ScheduledEvent(kind: .workout, title: session.focus.title,
                detail: detail, time: workoutTime, durationMinutes: 60, isCritical: true,
                linkedWorkout: session))
        }

        // MARK: Wind-down + sleep
        events.append(ScheduledEvent(kind: .windDown, title: "Wind down",
            detail: "Screens off, lights dim. Non-negotiable for sleep quality.",
            time: sleepPlan.windDownStart, durationMinutes: 45, isCritical: true))
        events.append(ScheduledEvent(kind: .sleep, title: "Sleep",
            detail: "Lights out. Tomorrow starts now.",
            time: sleepPlan.targetBedTime, durationMinutes: 0, isCritical: true))

        events.sort { $0.time < $1.time }
        return DaySchedule(date: date, events: events, macros: macros, sleepPlan: sleepPlan)
    }

    // MARK: - Helpers

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// Lunch lands before the first afternoon class on stacked days, just after
    /// a late-morning class on light days, else a plain midday slot.
    private static func lunchTime(sessions: [(meeting: ClassMeeting, start: Date, end: Date)],
                                  term: TermSchedule?, date: Date, calendar: Calendar) -> Date {
        let midday = calendar.date(bySettingHour: 12, minute: 45, second: 0, of: date)!
        guard !sessions.isEmpty, let term else { return midday }

        if let afternoon = sessions.first(where: { calendar.component(.hour, from: $0.start) >= 12 }) {
            let before = calendar.date(byAdding: .minute, value: -(term.leadMinutes + 25), to: afternoon.start)!
            return min(before, midday)
        }
        if let lastMorning = sessions.last {
            return calendar.date(byAdding: .minute, value: 20, to: lastMorning.end)!
        }
        return midday
    }

    /// Where the workout wants to land: right after the last class on days that
    /// run into the afternoon, otherwise just after lunch on lighter days.
    private static func workoutTarget(sessions: [(meeting: ClassMeeting, start: Date, end: Date)],
                                      lunch: Date, date: Date, calendar: Calendar) -> Date {
        if let lastClassEnd = sessions.map(\.end).max(),
           calendar.component(.hour, from: lastClassEnd) >= 15 {
            return calendar.date(byAdding: .minute, value: 30, to: lastClassEnd)!
        }
        return calendar.date(byAdding: .minute, value: 55, to: lunch)!
    }

    /// A ≥60-min free slot as close to `target` as possible, between noon and
    /// 21:00, never overlapping a busy block.
    private static func findWorkoutSlot(busyBlocks: [BusyBlock], date: Date, target: Date,
                                        calendar: Calendar) -> Date? {
        let windowStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let windowEnd = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!
        let need: TimeInterval = 60 * 60

        let relevant = busyBlocks
            .filter { $0.end > windowStart && $0.start < windowEnd }
            .sorted { $0.start < $1.start }

        var gaps: [(start: Date, end: Date)] = []
        var cursor = windowStart
        for block in relevant {
            if block.start > cursor { gaps.append((cursor, block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < windowEnd { gaps.append((cursor, windowEnd)) }

        let candidates: [Date] = gaps.compactMap { gap in
            guard gap.end.timeIntervalSince(gap.start) >= need else { return nil }
            let latestStart = gap.end.addingTimeInterval(-need)
            return min(max(target, gap.start), latestStart)
        }
        return candidates.min(by: {
            abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target))
        })
    }
}
