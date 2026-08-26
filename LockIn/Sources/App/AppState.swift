import Foundation
import Combine

/// Top-level app state: the single source of truth for the user's profile,
/// today's generated schedule, and streak/accountability status.
final class AppState: ObservableObject {
    @Published var profile: UserProfile
    @Published var todaySchedule: DaySchedule?
    @Published var streak: StreakStatus = StreakStatus()
    @Published var onboardingComplete: Bool
    /// Full adherence history, oldest first — backs the promise grid.
    @Published var dayRecords: [DayRecord] = []
    /// Meals eaten off-plan, either logged ad-hoc or swapped in for a
    /// scheduled meal. Kept separate from `todaySchedule` because the schedule
    /// is regenerated from the plan each launch and these are facts about what
    /// actually happened.
    @Published var loggedMeals: [LoggedMeal] = []

#if DEBUG
    /// True while "Watch the demo" is running. RootView checks this before
    /// the real sign-in/onboarding gates, so demo mode never touches — and
    /// never depends on — the signed-in user's actual account state.
    @Published var demoActive: Bool = false
    /// Non-nil while the tour wants DashboardView to jump to a specific tab.
    /// DashboardView consumes and clears it after switching.
    @Published var demoTabRequest: Int?
    let demoTour = DemoTourController()
#endif

    private let store = PersistenceStore.shared

    init() {
        self.profile = store.loadProfile() ?? UserProfile.blank
        self.onboardingComplete = store.loadProfile() != nil
        self.streak = store.loadStreak() ?? StreakStatus()
        self.dayRecords = store.loadDayRecords()
        self.loggedMeals = store.loadLoggedMeals()
    }

    /// Pulls an existing plan out of the signed-in user's private iCloud —
    /// the "new phone / reinstall" path, so they don't redo the quiz.
    func restoreFromCloudIfAvailable() async {
        guard !onboardingComplete else { return }
        guard let restored = await CloudSyncEngine.shared.fetchProfileForCurrentUser() else { return }
        let records = await CloudSyncEngine.shared.fetchDayRecords(profileID: restored.id)
        await MainActor.run {
            self.profile = restored
            self.dayRecords = records
            store.saveProfile(restored)
            store.saveDayRecords(records)
            self.onboardingComplete = true
        }
    }

    /// Mirrors local state up to private iCloud. Fire-and-forget: sync failures
    /// must never block the UI, and the local store stays authoritative.
    func pushToCloud() {
        let profile = self.profile
        let records = self.dayRecords
        Task.detached {
            await CloudSyncEngine.shared.pushProfile(profile)
            await CloudSyncEngine.shared.pushDayRecords(records, profileID: profile.id)
        }
    }

    // MARK: - Derived state for the UI

    /// The event the hero card should be showing: the next thing still pending.
    /// Falls back to the last event of the day once everything is resolved, so
    /// the card never goes blank mid-evening.
    var currentEvent: ScheduledEvent? {
        guard let events = todaySchedule?.events else { return nil }
        let pending = events.filter { $0.status == .pending || $0.status == .snoozed }
        return pending.min(by: { abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow) })
            ?? events.last
    }

    var criticalEventsToday: [ScheduledEvent] {
        todaySchedule?.events.filter { $0.isCritical } ?? []
    }

    var confirmedCriticalToday: Int {
        criticalEventsToday.filter { $0.status == .confirmed }.count
    }

    /// The coach line for the current moment — a callout if something's been
    /// blown off, a milestone win if one just landed, otherwise nothing (silence
    /// is better than filler; constant chatter makes the real hits land softer).
    var coachLine: String? {
        if let missed = todaySchedule?.events.first(where: { $0.status == .missed && $0.isCritical }) {
            return AccountabilityEngine.message(for: missed, tier: 2, tone: profile.toneIntensity, streak: streak)
        }
        if let win = AccountabilityEngine.winMessage(streak: streak) {
            return win
        }
        return nil
    }

    /// Pulls the latest HealthKit weight (if due — see WeightSyncEngine.shouldSync)
    /// and updates the profile before regenerating today's plan, so macro targets
    /// track actual weight loss instead of staying pinned to onboarding-day numbers.
    func syncWeightIfDue(healthKit: HealthKitManager) async {
        guard WeightSyncEngine.shouldSync(profile: profile) else { return }
        guard let updated = await WeightSyncEngine.sync(profile: profile, healthKit: healthKit) else { return }
        await MainActor.run {
            self.profile = updated
            persistProfile(updated)
        }
    }

    /// Regenerates today's plan from calendar + profile. Call on launch,
    /// on profile change, and at local midnight (see ScheduleRefreshTask).
    ///
    /// Check-ins survive a rebuild: the generated plan is structural, but the
    /// statuses on it are the user's actual work. Regenerating blind would wipe
    /// every confirmation made earlier in the day on the next app launch, which
    /// silently destroys the streak. Statuses are carried across by matching
    /// kind + title, which is stable for a given day's plan.
    func regenerateToday(calendarBusyBlocks: [BusyBlock], liveMeals: [Meal]? = nil) {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: calendarBusyBlocks)
        var schedule = ScheduleEngine.buildDay(
            profile: profile,
            macros: macros,
            sleepPlan: sleep,
            busyBlocks: calendarBusyBlocks,
            date: Date(),
            liveMeals: liveMeals
        )

        if let saved = store.loadSchedule(), Calendar.current.isDateInToday(saved.date) {
            for index in schedule.events.indices {
                let event = schedule.events[index]
                if let previous = saved.events.first(where: { $0.kind == event.kind && $0.title == event.title }) {
                    schedule.events[index].status = previous.status
                }
            }
        }

        self.todaySchedule = schedule
        persistSchedule(schedule)
        recordToday(schedule: schedule)
    }

    func saveProfile(_ profile: UserProfile) {
        self.profile = profile
        persistProfile(profile)
        onboardingComplete = true
        syncToneToMonitorExtension()
        pushToCloud()
    }

    // MARK: - Off-plan meals

    /// Today's off-plan entries, in the order they were logged.
    var loggedMealsToday: [LoggedMeal] {
        let key = DayRecord.key(for: Date())
        return loggedMeals.filter { $0.dayKey == key }
    }

    /// Calories and macros actually consumed today from off-plan meals, shown
    /// against the day's targets so the Fuel row reflects reality rather than
    /// just the plan.
    var loggedMacrosToday: MacroTargetsLite {
        loggedMealsToday.reduce(MacroTargetsLite(calories: 0, proteinG: 0, fatG: 0, carbG: 0)) { total, meal in
            MacroTargetsLite(
                calories: total.calories + meal.macros.calories,
                proteinG: total.proteinG + meal.macros.proteinG,
                fatG: total.fatG + meal.macros.fatG,
                carbG: total.carbG + meal.macros.carbG
            )
        }
    }

    /// Records an off-plan meal.
    ///
    /// When it replaces a scheduled meal, that event is marked **confirmed**,
    /// not missed. The streak tracks whether you followed through on eating a
    /// planned meal, not whether you hit the exact grams — swapping dal for a
    /// shawarma is a different meal, not a broken promise. Blowing the meal off
    /// entirely is still a miss, via Skip.
    func log(_ meal: LoggedMeal) {
        loggedMeals.append(meal)
        persistLoggedMeals()

        if let eventID = meal.replacedEventID,
           let event = todaySchedule?.events.first(where: { $0.id == eventID }) {
            confirm(event)
        }
    }

    func deleteLoggedMeal(_ meal: LoggedMeal) {
        loggedMeals.removeAll { $0.id == meal.id }
        persistLoggedMeals()
    }

    // MARK: - Persistence
    //
    // Every mutation writes through these rather than touching `store`
    // directly. Demo mode is a throwaway in-memory session shown from the
    // sign-in screen, and it must not leave anything behind in the real
    // store — not a check-in, not a streak bump, not a logged meal.

    private var shouldPersist: Bool {
#if DEBUG
        return !demoActive
#else
        return true
#endif
    }

    private func persistLoggedMeals() {
        guard shouldPersist else { return }
        store.saveLoggedMeals(loggedMeals)
    }

    private func persistProfile(_ profile: UserProfile) {
        guard shouldPersist else { return }
        store.saveProfile(profile)
    }

    private func persistSchedule(_ schedule: DaySchedule) {
        guard shouldPersist else { return }
        store.saveSchedule(schedule)
    }

    private func persistDayRecords() {
        guard shouldPersist else { return }
        store.saveDayRecords(dayRecords)
    }

    private func persistStreak() {
        guard shouldPersist else { return }
        store.saveStreak(streak)
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

            let key = DayRecord.key(for: event.date)
            if let index = dayRecords.firstIndex(where: { $0.dayKey == key }) {
                dayRecords[index].distractionEvents += 1
            }
        }
        persistStreak()
        persistDayRecords()
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
            persistStreak()
        }
    }

    private func setStatus(_ status: EventStatus, for event: ScheduledEvent) {
        guard var schedule = todaySchedule,
              let index = schedule.events.firstIndex(where: { $0.id == event.id }) else { return }
        schedule.events[index].status = status
        todaySchedule = schedule
        persistSchedule(schedule)
        recordToday(schedule: schedule)
        evaluateStreak(schedule: schedule)
    }

    /// Mirrors today's live schedule into the permanent adherence ledger after
    /// every change, so the promise grid stays accurate even if the app is
    /// killed before midnight.
    private func recordToday(schedule: DaySchedule) {
        let key = DayRecord.key(for: schedule.date)
        let critical = schedule.events.filter { $0.isCritical }
        let record = DayRecord(
            dayKey: key,
            date: schedule.date,
            criticalTotal: critical.count,
            criticalConfirmed: critical.filter { $0.status == .confirmed }.count,
            criticalMissed: critical.filter { $0.status == .missed }.count,
            distractionEvents: dayRecords.first(where: { $0.dayKey == key })?.distractionEvents ?? 0,
            weightLbs: profile.currentWeightLbs
        )

        if let existing = dayRecords.firstIndex(where: { $0.dayKey == key }) {
            dayRecords[existing] = record
        } else {
            dayRecords.append(record)
        }
        persistDayRecords()
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
        persistStreak()
    }

#if DEBUG
    /// Loads generated history so the record surfaces can be reviewed with
    /// realistic data. Triggered from the DEBUG-only row in Settings.
    func loadDemoHistory() {
        let seeded = DebugSeed.dayRecords()
        dayRecords = seeded
        profile.weightHistory = DebugSeed.weightHistory(from: seeded)
        if let latest = profile.weightHistory.last {
            profile.currentWeightLbs = latest.weightLbs
        }
        store.saveDayRecords(seeded)
        persistProfile(profile)
    }

    func clearDemoHistory() {
        dayRecords = []
        profile.weightHistory = []
        store.saveDayRecords([])
        persistProfile(profile)
    }

    /// Entry point for "Watch the demo" on the sign-in screen. Builds a
    /// fully-seeded session entirely in memory — nothing here touches
    /// `PersistenceStore`, so exiting the demo leaves the real account (if
    /// any) exactly as it was.
    func startDemo() {
        var demoProfile = UserProfile.rahilPreset
        let seeded = DebugSeed.dayRecords()
        demoProfile.weightHistory = DebugSeed.weightHistory(from: seeded)
        if let latest = demoProfile.weightHistory.last {
            demoProfile.currentWeightLbs = latest.weightLbs
        }

        profile = demoProfile
        dayRecords = seeded
        streak = DemoMode.streak
        loggedMeals = DemoMode.loggedMeals
        todaySchedule = DemoMode.todaySchedule(profile: demoProfile)
        onboardingComplete = true
        demoTour.stepIndex = 0
        demoTabRequest = 0
        demoActive = true
    }

    /// Backs out of the demo. Real persisted state was never touched, so the
    /// app falls straight back to whatever `RootView` would otherwise show.
    func exitDemo() {
        demoActive = false
        profile = store.loadProfile() ?? UserProfile.blank
        onboardingComplete = store.loadProfile() != nil
        streak = store.loadStreak() ?? StreakStatus()
        dayRecords = store.loadDayRecords()
        loggedMeals = store.loadLoggedMeals()
        todaySchedule = store.loadSchedule()
    }
#endif

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
