import SwiftUI

/// Top-level tab shell: today's schedule/check-ins, and the progress-photo
/// gallery. Tapping the "Progress photo" event on Today jumps straight to the
/// camera on the Progress tab instead of just switching tabs and stopping.
struct DashboardView: View {
    @State private var selectedTab = 0
    @State private var pendingCameraLaunch = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(onOpenProgressPhoto: {
                pendingCameraLaunch = true
                selectedTab = 1
            })
            .tabItem { Label("Today", systemImage: "checklist") }
            .tag(0)

            NavigationStack {
                ProgressGalleryView(launchCameraOnAppear: $pendingCameraLaunch)
            }
            .tabItem { Label("Progress", systemImage: "camera.fill") }
            .tag(1)
        }
    }
}
