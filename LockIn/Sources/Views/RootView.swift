import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var healthKitManager = HealthKitManager()

    var body: some View {
        Group {
            if appState.onboardingComplete {
                DashboardView()
                    .environmentObject(calendarManager)
                    .environmentObject(healthKitManager)
            } else {
                OnboardingFlowView()
            }
        }
        // Keyed on onboardingComplete so this also fires the moment onboarding
        // finishes, not just on RootView's first appearance.
        .task(id: appState.onboardingComplete) {
            if appState.onboardingComplete {
                await calendarManager.requestAccess()
                await healthKitManager.requestAccess()
                await appState.syncWeightIfDue(healthKit: healthKitManager)
                appState.regenerateToday(calendarBusyBlocks: calendarManager.busyBlocks(for: Date()))
            }
        }
    }
}
