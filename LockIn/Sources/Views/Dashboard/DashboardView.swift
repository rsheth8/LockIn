import SwiftUI

/// Three surfaces, in the order they matter: what to do now, the record that
/// proves you did it, and the controls. Tapping the "Progress photo" event on
/// Today jumps straight into the camera rather than just switching tabs.
/// DEBUG builds add a Lab tab for one-tap scenario testing.
struct DashboardView: View {
    @State private var selectedTab = 0
    @State private var pendingCameraLaunch = false

    init() {
        // The Ledger stays dark-forward and quiet — the system chrome shouldn't
        // introduce a second visual language on top of it.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.ground)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.ground)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.ink)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.ink)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(onOpenProgressPhoto: {
                pendingCameraLaunch = true
                selectedTab = 1
            })
            .tabItem { Label("Today", systemImage: "circle.righthalf.filled") }
            .tag(0)

            // No NavigationStack on these two: the system nav bar reserves a
            // large-title area the Ledger doesn't use, leaving dead space at the
            // top. Each screen draws its own in-content header instead, so all
            // three tabs share one header language.
            ProgressGalleryView(launchCameraOnAppear: $pendingCameraLaunch)
                .tabItem { Label("Record", systemImage: "square.grid.3x3.fill") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)

#if DEBUG
            DevLabView()
                .tabItem { Label("Lab", systemImage: "flask.fill") }
                .tag(3)
#endif
        }
        .tint(Theme.ink)
    }
}
