import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.onboardingComplete {
                DashboardView()
                    .environmentObject(calendarManager)
                    .environmentObject(healthKitManager)
                    .environmentObject(screenTimeManager)
            } else {
                OnboardingFlowView()
            }
        }
        // Keyed on onboardingComplete so this also fires the moment onboarding
        // finishes, not just on RootView's first appearance.
        .task(id: appState.onboardingComplete) {
            guard appState.onboardingComplete else { return }
            appState.syncToneToMonitorExtension()
            appState.drainDistractionEvents()
            await calendarManager.requestAccess()
            await healthKitManager.requestAccess()
            await appState.syncWeightIfDue(healthKit: healthKitManager)
            appState.regenerateToday(calendarBusyBlocks: calendarManager.busyBlocks(for: Date()))
            scheduleWorkoutLockInBlock()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.drainDistractionEvents()
            }
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
        let block = LockInBlock(id: "workout-\(dayKey(workoutEvent.time))", label: workoutEvent.title, start: workoutEvent.time, end: end)
        screenTimeManager.scheduleLockInBlock(block)
    }

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
