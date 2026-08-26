import Foundation
import Combine

/// Top-level app state: the single source of truth for the user's profile,
/// today's generated schedule, and streak/accountability status.
@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile
    @Published var todaySchedule: DaySchedule?
    @Published var streak: StreakStatus = StreakStatus()
    @Published var onboardingComplete: Bool
    /// Full adherence history, oldest first — backs the promise grid.
    @Published var dayRecords: [DayRecord] = []
    /// True while Spoonacular is still being fetched for today's meals.
    @Published var isRefreshingMeals = false

    private let store = PersistenceStore.shared

    init() {
        self.profile = store.loadProfile() ?? UserProfile.blank
        self.onboardingComplete = store.loadProfile() != nil
        self.streak = store.loadStreak() ?? StreakStatus()
        self.dayRecords = store.loadDayRecords()
    }

    /// Pulls an existing plan out of the signed-in user's private iCloud —
    /// the "new phone / reinstall" path, so they don't redo the quiz.
    /// Local-only accounts never hit this — otherwise a leftover iCloud profile
    /// would skip the quiz for someone who chose "Continue without an account."
    func restoreFromCloudIfAvailable(allowCloudRestore: Bool) async {
        guard allowCloudRestore else { return }
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
    ///
    /// Inert under `xcodebuild test`: the suite drives real check-ins through
    /// `AppState`, and every one of those would otherwise push a test fixture
    /// into the developer's own private CloudKit database. Since
    /// `fetchProfileForCurrentUser` restores the most recently updated profile,
    /// a test run could quietly become the profile a reinstall restores.
    func pushToCloud() {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        let profile = self.profile
        let records = self.dayRecords
        let streak = self.streak
        Task.detached {
            await CloudSyncEngine.shared.pushProfile(profile)
            await CloudSyncEngine.shared.pushDayRecords(records, profileID: profile.id)
            await CloudSyncEngine.shared.pushStreak(streak, profileID: profile.id)
        }
    }

    // MARK: - Derived state for the UI

    /// The event the hero card should be showing: the next thing still pending.
    /// Falls back to the last event of the day once everything is resolved, so
    /// the card never goes blank mid-evening.
    var currentEvent: ScheduledEvent? {
        guard let events = todaySchedule?.events else { return nil }
        let pending = events.filter {
            ($0.status == .pending || $0.status == .snoozed) && $0.kind.canLeadHero
        }
        return pending.min(by: { abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow) })
            ?? events.last(where: { $0.kind.canLeadHero })
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
            return AccountabilityEngine.message(
                for: missed, tier: 2, tone: profile.toneIntensity, streak: streak,
                currentWeightLbs: profile.currentWeightLbs, goalWeightLbs: profile.goalWeightLbs
            )
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
            store.saveProfile(updated)
            pushToCloud()
        }
    }

    /// Manual weigh-in from the Today check-in. Writes to HealthKit, updates
    /// the profile + history, and confirms the weigh-in event.
    func applyWeighIn(pounds: Double, event: ScheduledEvent, healthKit: HealthKitManager) {
        let clamped = max(80, min(pounds, 500))
        healthKit.logWeight(clamped)
        var updated = profile
        updated.currentWeightLbs = clamped
        updated.weightHistory.append(WeightEntry(date: Date(), weightLbs: clamped))
        profile = updated
        store.saveProfile(updated)
        setStatus(.confirmed, for: event)
        pushToCloud()
    }

    /// Regenerates today's plan from calendar + profile. Call on launch,
    /// on profile change, and at local midnight (see ScheduleRefreshTask).
    ///
    /// Check-ins survive a rebuild: the generated plan is structural, but the
    /// statuses on it are the user's actual work. Regenerating blind would wipe
    /// every confirmation made earlier in the day on the next app launch, which
    /// silently destroys the streak. Statuses are carried across by matching
    /// kind + title, which is stable for a given day's plan.
    func regenerateToday(calendarBusyBlocks: [BusyBlock], tasks: [DayTask] = [], liveMeals: [Meal]? = nil) {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: calendarBusyBlocks)
        var schedule = ScheduleEngine.buildDay(
            profile: profile,
            macros: macros,
            sleepPlan: sleep,
            busyBlocks: calendarBusyBlocks,
            date: Date(),
            liveMeals: liveMeals,
            tasks: tasks
        )

        if let saved = store.loadSchedule(), Calendar.current.isDateInToday(saved.date) {
            for index in schedule.events.indices {
                let event = schedule.events[index]
                if let previous = saved.events.first(where: { Self.sameEvent($0, event) }) {
                    schedule.events[index].status = previous.status
                }
            }
        }

        self.todaySchedule = schedule
        store.saveSchedule(schedule)
        recordToday(schedule: schedule)
    }

    /// Calendar items match by EventKit id so a renamed lecture still keeps
    /// its row; Lock In items still match on kind + title so a meal rebuild
    /// doesn't wipe a check-in.
    private static func sameEvent(_ lhs: ScheduledEvent, _ rhs: ScheduledEvent) -> Bool {
        if let id = lhs.externalIdentifier, id == rhs.externalIdentifier { return true }
        return lhs.kind == rhs.kind && lhs.title == rhs.title
    }

    func saveProfile(_ profile: UserProfile) {
        var synced = profile
        synced.syncLegacyFoodFields()
        self.profile = synced
        store.saveProfile(synced)
        onboardingComplete = true
        syncToneToMonitorExtension()
        pushToCloud()
    }

    /// Clears profile, schedule, streak, day records, and photo metadata.
    /// Progress JPEG files are left for `ProgressPhotoStore` to reclaim.
    func eraseAllLocalData() {
        store.clearAll()
        profile = .blank
        todaySchedule = nil
        streak = StreakStatus()
        dayRecords = []
        onboardingComplete = false
        isRefreshingMeals = false
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
        store.saveStreak(streak)
        store.saveDayRecords(dayRecords)
        pushToCloud()
    }

    /// The monitor extension can't read the main app's UserDefaults, so tone
    /// and goal weights have to be mirrored into the shared App Group container
    /// whenever they change — call this after onboarding and after any settings change.
    func syncToneToMonitorExtension() {
        AppGroup.sharedDefaults.set(profile.toneIntensity.rawValue, forKey: AppGroup.Key.toneIntensity)
        AppGroup.sharedDefaults.set(profile.currentWeightLbs, forKey: AppGroup.Key.currentWeightLbs)
        AppGroup.sharedDefaults.set(profile.goalWeightLbs, forKey: AppGroup.Key.goalWeightLbs)
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
            pushToCloud()
        }
    }

    private func setStatus(_ status: EventStatus, for event: ScheduledEvent) {
        guard var schedule = todaySchedule,
              let index = schedule.events.firstIndex(where: { $0.id == event.id }) else { return }
        schedule.events[index].status = status
        todaySchedule = schedule
        store.saveSchedule(schedule)
        NotificationManager.shared.cancelNotifications(for: event.id)
        recordToday(schedule: schedule)
        evaluateStreak(schedule: schedule)
        pushToCloud()
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
        store.saveDayRecords(dayRecords)
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

#if DEBUG
    /// Loads generated history so the record surfaces can be reviewed with
    /// realistic data. Triggered from the DEBUG-only Lab tab / Settings.
    func loadDemoHistory() {
        let seeded = DebugSeed.dayRecords()
        dayRecords = seeded
        profile.weightHistory = DebugSeed.weightHistory(from: seeded)
        if let latest = profile.weightHistory.last {
            profile.currentWeightLbs = latest.weightLbs
        }
        store.saveDayRecords(seeded)
        store.saveProfile(profile)
    }

    func clearDemoHistory() {
        dayRecords = []
        profile.weightHistory = []
        store.saveDayRecords([])
        store.saveProfile(profile)
    }

    /// Applies a Lab persona and marks onboarding complete.
    func applyDevPersona(_ persona: DevPersona) {
        saveProfile(persona.makeProfile())
        streak = StreakStatus()
        store.saveStreak(streak)
    }

    /// Sets streak to a live multi-day run (for coach / Record surfaces).
    func applyDevStreak(days: Int, longest: Int? = nil) {
        streak.currentStreakDays = max(0, days)
        streak.longestStreakDays = max(longest ?? days, days)
        streak.lastMissedEvent = nil
        streak.missedCheckInsThisWeek = 0
        streak.lastCountedDayKey = nil
        store.saveStreak(streak)
    }

    func confirmAllCriticalToday() {
        guard let schedule = todaySchedule else { return }
        for event in schedule.events where event.isCritical && event.status == .pending {
            confirm(event)
        }
    }

    func missNextCritical() {
        guard let event = todaySchedule?.events.first(where: {
            $0.isCritical && ($0.status == .pending || $0.status == .snoozed)
        }) else { return }
        markMissed(event)
    }

    func resetTodayStatuses() {
        guard var schedule = todaySchedule else { return }
        for i in schedule.events.indices {
            schedule.events[i].status = .pending
        }
        todaySchedule = schedule
        store.saveSchedule(schedule)
        recordToday(schedule: schedule)
    }

    /// Shifts every pending event 2 hours into the past so the hero shows Overdue.
    func makePendingEventsOverdue() {
        guard var schedule = todaySchedule else { return }
        let shift: TimeInterval = -2 * 3600
        for i in schedule.events.indices where schedule.events[i].status == .pending {
            schedule.events[i].time = schedule.events[i].time.addingTimeInterval(shift)
        }
        todaySchedule = schedule
        store.saveSchedule(schedule)
    }

    /// Marks the saved schedule as yesterday so the next rebuild path /
    /// staleness check can be exercised.
    func markScheduleAsYesterday() {
        guard var schedule = todaySchedule else { return }
        schedule = DaySchedule(
            date: Calendar.current.date(byAdding: .day, value: -1, to: schedule.date) ?? schedule.date,
            events: schedule.events,
            macros: schedule.macros,
            sleepPlan: schedule.sleepPlan,
            mealSource: schedule.mealSource
        )
        todaySchedule = schedule
        store.saveSchedule(schedule)
    }

    /// Queues a fake distraction so `drainDistractionEvents` can be tested.
    func injectDistractionEvent(label: String = "Lab focus block") {
        AppGroup.appendDistractionEvent(DistractionEvent(date: Date(), blockLabel: label))
        drainDistractionEvents()
    }

    /// Sends you back through the quiz without wiping food prefs history.
    func reopenOnboarding() {
        onboardingComplete = false
    }
#endif

    // MARK: - Meals: like + swap

    func likeCurrentMeal(for event: ScheduledEvent) {
        let liked = LikedRecipe(title: event.title, spoonacularID: nil)
        appendLiked(liked)
    }

    func appendLiked(_ recipe: LikedRecipe) {
        if profile.likedRecipes.contains(where: { $0.title.caseInsensitiveCompare(recipe.title) == .orderedSame }) {
            return
        }
        profile.likedRecipes.insert(recipe, at: 0)
        if profile.likedRecipes.count > 80 {
            profile.likedRecipes = Array(profile.likedRecipes.prefix(80))
        }
        store.saveProfile(profile)
        pushToCloud()
    }

    func removeLiked(id: String) {
        profile.likedRecipes.removeAll { $0.id == id }
        store.saveProfile(profile)
        pushToCloud()
    }

    /// Replaces a meal event with the next-best alternative from the local DB /
    /// liked menu, so the user isn't stuck with a suggestion they won't cook.
    @discardableResult
    func swapMeal(for event: ScheduledEvent) -> Bool {
        guard event.kind == .meal,
              var schedule = todaySchedule,
              let index = schedule.events.firstIndex(where: { $0.id == event.id }) else { return false }

        let macros = schedule.macros
        let alternatives = MealEngine.swapCandidates(
            excludingTitle: event.title,
            macros: macros,
            profile: profile,
            preferredTitles: Set(profile.likedRecipes.map(\.title))
        )
        guard let next = alternatives.first else { return false }

        schedule.events[index].title = next.name
        schedule.events[index].detail = next.detailLine
        schedule.events[index].linkedMealID = next.id
        schedule.events[index].status = .pending
        // The Fuel row sums mealMacros across the day's meal events, so moving
        // this one keeps the day's totals honest with no extra bookkeeping.
        schedule.events[index].mealMacros = next.totalMacros
        todaySchedule = schedule
        store.saveSchedule(schedule)
        return true
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
