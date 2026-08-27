import Foundation

/// Sleep scheduling anchored to the user's chosen rhythm, not to the calendar.
///
/// - Wake is fixed from `RhythmPreference` (a later slot on weekends) and only
///   pulled earlier when a class or calendar block starts too soon after it.
/// - Bedtime is the rhythm's target clock time; wind-down sits 45 min before it.
/// - Caffeine cutoff is a fixed hour, clamped to always precede wind-down.
///
/// This deliberately does *not* float the whole schedule off the first
/// commitment of the day — a consistent wake time is what keeps energy stable
/// across a week whose class times vary.
enum SleepEngine {
    /// When a class forces an early start, minutes to leave between waking and
    /// heading out: quick routine + coffee + something to eat.
    private static let earlyStartRoutineMinutes = 30

    /// Fallback lead time (commute + prep) when there's no term schedule to read it from.
    private static let defaultLeadMinutes = 45

    static func plan(for profile: UserProfile, busyBlocks: [BusyBlock], date: Date = Date()) -> SleepPlan {
        let calendar = Calendar.current
        let rhythm = profile.rhythm

        var wake = rhythm.wake(on: date, calendar: calendar)

        // Earliest hard obligation on this date — a class from the term
        // schedule, or a timed calendar block.
        let lead = profile.termSchedule?.leadMinutes ?? defaultLeadMinutes
        let classStart = profile.termSchedule?.sessions(on: date, calendar: calendar).first?.start
        let blockStart = busyBlocks
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .min(by: { $0.start < $1.start })?.start

        if let earliest = [classStart, blockStart].compactMap({ $0 }).min() {
            let mustWakeBy = calendar.date(byAdding: .minute,
                                           value: -(lead + earlyStartRoutineMinutes),
                                           to: earliest)!
            if mustWakeBy < wake { wake = mustWakeBy }
        }

        let bed = rhythm.bedtime(after: date, calendar: calendar)
        let windDown = calendar.date(byAdding: .minute, value: -45, to: bed)!

        var caffeineCutoff = rhythm.caffeineCutoff(on: date, calendar: calendar)
        if caffeineCutoff >= windDown {
            caffeineCutoff = calendar.date(byAdding: .hour, value: -1, to: windDown)!
        }

        // Duration: tonight's bedtime → tomorrow's wake.
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
        let nextWake = rhythm.wake(on: nextDay, calendar: calendar)
        let duration = max(0, nextWake.timeIntervalSince(bed)) / 3600

        return SleepPlan(
            targetWakeTime: wake,
            targetBedTime: bed,
            windDownStart: windDown,
            caffeineCutoff: caffeineCutoff,
            sleepDurationHours: duration
        )
    }
}
