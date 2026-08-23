import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = CalendarManager()

    var body: some View {
        Group {
            if appState.onboardingComplete {
                DashboardView()
                    .environmentObject(calendarManager)
            } else {
                OnboardingFlowView()
            }
        }
        .task {
            if appState.onboardingComplete {
                await calendarManager.requestAccess()
                appState.regenerateToday(calendarBusyBlocks: calendarManager.busyBlocks(for: Date()))
            }
        }
    }
}
