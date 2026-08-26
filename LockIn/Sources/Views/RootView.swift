import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @StateObject private var accountManager = AccountManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var scheduleRefresh = ScheduleRefreshTask()
#if DEBUG
    @ObservedObject private var lab = DevLabController.shared
#endif

    var body: some View {
        Group {
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
        .environmentObject(accountManager)
        // The whole tree reads the accent from the environment, so a change in
        // Settings repaints every surface without any view caching its own copy.
        .environment(\.accent, appState.profile.accentColor)
        .task(id: taskKey) {
            // The unit-test bundle is hosted in this app, so without this guard
            // a test run would trigger real permission prompts and network calls.
            guard !RuntimeEnvironment.isRunningUnitTests else { return }
            guard accountManager.state != .signedOut else { return }

            if !appState.onboardingComplete {
                // Only signed-in accounts restore from iCloud — local-only users
                // must not skip the quiz because of a leftover cloud profile.
                let allowCloud = accountManager.isSignedIn
                await appState.restoreFromCloudIfAvailable(allowCloudRestore: allowCloud)
                return
            }

            accountManager.restoreGoogleSessionIfNeeded()
            appState.syncToneToMonitorExtension()
            appState.drainDistractionEvents()
            await calendarManager.requestAccess()
            await healthKitManager.requestAccess()
            await appState.syncWeightIfDue(healthKit: healthKitManager)

            rebuildToday()
            armMidnightRefresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.drainDistractionEvents()
                calendarManager.refreshIfNeeded()
                if appState.onboardingComplete, accountManager.state != .signedOut {
                    if ScheduleRefreshTask.isStale(appState.todaySchedule) {
                        rebuildToday()
                    }
                    armMidnightRefresh()
                }
            }
        }
        .onChange(of: planFingerprint) { _, _ in
            guard !RuntimeEnvironment.isRunningUnitTests else { return }
            guard appState.onboardingComplete, accountManager.state != .signedOut else { return }
            rebuildToday()
        }
        .onChange(of: calendarManager.revision) { _, _ in
            guard !RuntimeEnvironment.isRunningUnitTests else { return }
            guard appState.onboardingComplete, accountManager.state != .signedOut else { return }
            rebuildToday()
        }
#if DEBUG
        .onChange(of: lab.rebuildToken) { _, _ in
            guard !RuntimeEnvironment.isRunningUnitTests else { return }
            guard appState.onboardingComplete, accountManager.state != .signedOut else { return }
            rebuildToday()
        }
#endif
        .onDisappear {
            scheduleRefresh.cancel()
        }
    }

    /// Re-runs setup when the account changes or onboarding finishes.
    private var taskKey: String {
        "\(accountManager.state)-\(appState.onboardingComplete)"
    }

    /// Fields that change the day's plan. Accent/tone changes must not
    /// spend Spoonacular quota on a rebuild.
    private var planFingerprint: String {
        let profile = appState.profile
        return [
            profile.goalDirection.rawValue,
            profile.deficitIntensity.rawValue,
            String(Int(profile.currentWeightLbs)),
            String(Int(profile.goalWeightLbs)),
            profile.activityLevel.rawValue,
            profile.dietaryPattern.rawValue,
            String(profile.mealsPerDay),
            profile.equipment.map(\.rawValue).sorted().joined(),
            profile.gymAssets.map(\.rawValue).sorted().joined(),
            profile.fitnessGoals.map(\.rawValue).sorted().joined(),
            RecipeCache.signature(calories: 0, profile: profile)
        ].joined(separator: "/")
    }

    private func armMidnightRefresh() {
        scheduleRefresh.onMidnight = {
            rebuildToday()
        }
        scheduleRefresh.arm()
    }

    private func rebuildToday() {
#if DEBUG
        let busy = lab.overrideBusyBlocks ?? calendarManager.busyBlocks(for: Date())
        let forceLocal = lab.forceLocalMeals
#else
        let busy = calendarManager.busyBlocks(for: Date())
        let forceLocal = false
#endif
        let tasks = calendarManager.todayTasks
        appState.regenerateToday(calendarBusyBlocks: busy, tasks: tasks)
        publishSchedule()
        appState.isRefreshingMeals = Secrets.hasSpoonacular && !forceLocal
        Task {
            guard !forceLocal else {
                await MainActor.run { appState.isRefreshingMeals = false }
                return
            }
            let macros = MetabolicEngine.dailyTargets(for: appState.profile)
            if let live = await MealEngine.liveMealsForToday(macros: macros, profile: appState.profile) {
                appState.regenerateToday(calendarBusyBlocks: busy, tasks: tasks, liveMeals: live)
                publishSchedule()
            }
            await MainActor.run { appState.isRefreshingMeals = false }
        }
    }

    /// Notifications + the Lock In calendar + the workout shield. The generated
    /// schedule is the source of truth; these just project it outward.
    private func publishSchedule() {
        guard let schedule = appState.todaySchedule else { return }
        NotificationManager.shared.scheduleDay(
            schedule,
            tone: appState.profile.toneIntensity,
            streak: appState.streak,
            currentWeightLbs: appState.profile.currentWeightLbs,
            goalWeightLbs: appState.profile.goalWeightLbs
        )
        calendarManager.sync(schedule)
        scheduleWorkoutLockInBlock()
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
