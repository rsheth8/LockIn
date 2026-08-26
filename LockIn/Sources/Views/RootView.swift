import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @StateObject private var accountManager = AccountManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
#if DEBUG
            if appState.demoActive {
                DashboardView()
                    .environmentObject(calendarManager)
                    .environmentObject(healthKitManager)
                    .environmentObject(screenTimeManager)
                    .overlay(alignment: .bottom) { DemoTourOverlay(tour: appState.demoTour) }
            } else {
                mainFlow
            }
#else
            mainFlow
#endif
        }
        .environmentObject(accountManager)
        // The whole tree reads the accent from the environment, so a change in
        // Settings repaints every surface without any view caching its own copy.
        .environment(\.accent, appState.profile.accentColor)
        .task(id: taskKey) {
            // The unit-test bundle is hosted in this app, so without this guard
            // a test run would trigger real permission prompts and network calls.
            guard !RuntimeEnvironment.isRunningUnitTests else { return }
            guard accountManager.state != .signedOut else { return }
#if DEBUG
            // The demo is a self-contained, in-memory session — it must never
            // fire real permission prompts, network calls, or overwrite the
            // seeded schedule with a freshly generated one.
            guard !appState.demoActive else { return }
#endif

            if !appState.onboardingComplete {
                await appState.restoreFromCloudIfAvailable()
                return
            }

            appState.syncToneToMonitorExtension()
            appState.drainDistractionEvents()
            await calendarManager.requestAccess()
            await healthKitManager.requestAccess()
            await appState.syncWeightIfDue(healthKit: healthKitManager)

            let busy = calendarManager.busyBlocks(for: Date())
            // Render immediately off the local database, then upgrade in place
            // if Spoonacular returns — the day's plan should never wait on a
            // network round trip.
            appState.regenerateToday(calendarBusyBlocks: busy)

            let macros = MetabolicEngine.dailyTargets(for: appState.profile)
            if let live = await MealEngine.liveMealsForToday(macros: macros, profile: appState.profile) {
                appState.regenerateToday(calendarBusyBlocks: busy, liveMeals: live)
            }

            scheduleWorkoutLockInBlock()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.drainDistractionEvents()
            }
        }
    }

    /// Re-runs setup when the account changes or onboarding finishes.
    private var taskKey: String {
        "\(accountManager.state)-\(appState.onboardingComplete)"
    }

    @ViewBuilder
    private var mainFlow: some View {
        switch (accountManager.state, appState.onboardingComplete) {
        case (.signedOut, _):
            SignInView()
        case (_, false):
            QuizFlowView()
        case (_, true):
            DashboardView()
                .environmentObject(calendarManager)
                .environmentObject(healthKitManager)
                .environmentObject(screenTimeManager)
        }
    }

    /// Registers today's workout window as a guarded lock-in block, if Screen
    /// Time is authorized and distracting apps have been picked in Settings.
    /// No-ops silently otherwise — Screen Time monitoring is opt-in, not a
    /// blocker for the rest of the app.
    private func scheduleWorkoutLockInBlock() {
        guard screenTimeManager.isAuthorized,
              let workoutEvent = appState.todaySchedule?.events.first(where: { $0.kind == .workout }) else { return }
        let end = workoutEvent.time.addingTimeInterval(TimeInterval(workoutEvent.durationMinutes * 60))
        let block = LockInBlock(id: "workout-\(DayRecord.key(for: workoutEvent.time))", label: workoutEvent.title, start: workoutEvent.time, end: end)
        screenTimeManager.scheduleLockInBlock(block)
    }
}
