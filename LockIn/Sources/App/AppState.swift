import Foundation
import Combine

/// Top-level app state: the single source of truth for the user's profile,
/// today's generated schedule, and streak/accountability status.
final class AppState: ObservableObject {
    @Published var profile: UserProfile
    @Published var todaySchedule: DaySchedule?
    @Published var streak: StreakStatus = StreakStatus()
    @Published var onboardingComplete: Bool

    private let store = PersistenceStore.shared

    init() {
        self.profile = store.loadProfile() ?? UserProfile.default
        self.onboardingComplete = store.loadProfile() != nil
        self.streak = store.loadStreak() ?? StreakStatus()
    }

    /// Pulls the latest HealthKit weight (if due — see WeightSyncEngine.shouldSync)
    /// and updates the profile before regenerating today's plan, so macro targets
    /// track actual weight loss instead of staying pinned to onboarding-day numbers.
    func syncWeightIfDue(healthKit: HealthKitManager) async {
        guard WeightSyncEngine.shouldSync(profile: profile) else { return }
        guard let updated = await WeightSyncEngine.sync(profile: profile, healthKit: healthKit) else { return }
        await MainActor.run {
            self.profile = updated
            store.saveProfile(updated)
        }
    }

    /// Regenerates today's plan from calendar + profile. Call on launch,
    /// on profile change, and at local midnight (see ScheduleRefreshTask).
    func regenerateToday(calendarBusyBlocks: [BusyBlock]) {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: calendarBusyBlocks)
        let schedule = ScheduleEngine.buildDay(
            profile: profile,
            macros: macros,
            sleepPlan: sleep,
            busyBlocks: calendarBusyBlocks,
            date: Date()
        )
        self.todaySchedule = schedule
        store.saveSchedule(schedule)
    }

    func saveProfile(_ profile: UserProfile) {
        self.profile = profile
        store.saveProfile(profile)
        onboardingComplete = true
        syncToneToMonitorExtension()
    }

    // MARK: - Screen Time distraction events

    /// The LockInMonitor extension writes here whenever you burn real time on
    /// a shielded app during a lock-in block. Drain the queue on launch/foreground
    /// so those events count against the streak just like a missed check-in.
    func drainDistractionEvents() {
        let events = AppGroup.pendingDistractionEvents()
        guard !events.isEmpty else { return }
        AppGroup.clearPendingDistractionEvents()

        for event in events {
            streak.currentStreakDays = 0
            streak.lastMissedEvent = "Distracted during \(event.blockLabel)"
            streak.missedCheckInsThisWeek += 1
        }
        store.saveStreak(streak)
    }

    /// The monitor extension can't read the main app's UserDefaults, so the
    /// tone has to be mirrored into the shared App Group container whenever
    /// it changes — call this after onboarding and after any settings change.
    func syncToneToMonitorExtension() {
        AppGroup.sharedDefaults.set(profile.toneIntensity.rawValue, forKey: AppGroup.Key.toneIntensity)
    }

    // MARK: - Check-ins

    /// User tapped "Done" on an event. Updates status, and — for critical events —
    /// rolls the daily streak forward once every critical event for today is confirmed.
    func confirm(_ event: ScheduledEvent) {
        setStatus(.confirmed, for: event)
    }

    /// User tapped "Missed" (or an escalation window closed with no confirmation).
    func markMissed(_ event: ScheduledEvent) {
        setStatus(.missed, for: event)
        if event.isCritical {
            streak.currentStreakDays = 0
            streak.lastMissedEvent = event.title
            streak.missedCheckInsThisWeek += 1
            store.saveStreak(streak)
        }
    }

    private func setStatus(_ status: EventStatus, for event: ScheduledEvent) {
        guard var schedule = todaySchedule,
              let index = schedule.events.firstIndex(where: { $0.id == event.id }) else { return }
        schedule.events[index].status = status
        todaySchedule = schedule
        store.saveSchedule(schedule)
        evaluateStreak(schedule: schedule)
    }

    /// A day counts toward the streak once every critical event in it is confirmed
    /// (not missed). Called after each confirmation so the streak ticks the moment
    /// the last critical box is checked, not just at midnight rollover.
    private func evaluateStreak(schedule: DaySchedule) {
        let criticalEvents = schedule.events.filter { $0.isCritical }
        let allConfirmed = !criticalEvents.isEmpty && criticalEvents.allSatisfy { $0.status == .confirmed }
        let anyMissed = criticalEvents.contains { $0.status == .missed }

        guard allConfirmed, !anyMissed else { return }
        let key = dayKey(schedule.date)
        guard streak.lastCountedDayKey != key else { return }

        streak.currentStreakDays += 1
        streak.longestStreakDays = max(streak.longestStreakDays, streak.currentStreakDays)
        streak.lastCountedDayKey = key
        store.saveStreak(streak)
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
