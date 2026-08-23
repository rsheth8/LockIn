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
    }
}
