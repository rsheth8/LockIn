import Foundation

/// Sleep scheduling based on standard sleep-hygiene science:
/// - Consistent wake time anchors circadian rhythm (Walker, "Why We Sleep"; AASM guidance).
/// - 7-9 hours for young adults (National Sleep Foundation).
/// - Caffeine has a ~5-6hr half-life; cutoff ~8-10hrs before bed avoids sleep-onset/quality disruption.
/// - Wind-down window (screens/bright light off) ~30-60 min pre-bed improves sleep onset latency.
enum SleepEngine {
    static func plan(for profile: UserProfile, busyBlocks: [BusyBlock], targetSleepHours: Double = 8.0) -> SleepPlan {
        let calendar = Calendar.current

        // Wake time: earliest busy block start today minus prep buffer, else default 7:00 AM.
        let earliestBlock = busyBlocks
            .filter { calendar.isDateInToday($0.start) }
            .min(by: { $0.start < $1.start })

        let defaultWake = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let wake: Date
        if let earliest = earliestBlock {
            // Leave 90 min before first commitment for wake routine, coffee, breakfast.
            wake = calendar.date(byAdding: .minute, value: -90, to: earliest.start) ?? defaultWake
        } else {
            wake = defaultWake
        }

        let bed = calendar.date(byAdding: .hour, value: -Int(targetSleepHours), to: calendar.date(byAdding: .day, value: 1, to: wake)!)
            ?? calendar.date(byAdding: .hour, value: Int(24 - targetSleepHours), to: wake)!

        let windDown = calendar.date(byAdding: .minute, value: -45, to: bed)!
        let caffeineCutoff = calendar.date(byAdding: .hour, value: -9, to: bed)!

        return SleepPlan(
            targetWakeTime: wake,
            targetBedTime: bed,
            windDownStart: windDown,
            caffeineCutoff: caffeineCutoff,
            sleepDurationHours: targetSleepHours
        )
    }
}
