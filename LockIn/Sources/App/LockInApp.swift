import SwiftUI

@main
struct LockInApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            // Under `xcodebuild test` this app is only a host for the test
            // bundle. Presenting the real UI makes XCTest stall for minutes
            // when an assertion fails — it enqueues failure reporting onto the
            // primary thread while SwiftUI is still driving the scene — so a
            // simple failing test looks like an infinite hang.
            if RuntimeEnvironment.isRunningUnitTests {
                Color.clear
            } else {
                RootView()
                    .environmentObject(appState)
                    // Google Sign-In completes by reopening the app through its
                    // redirect URL scheme; without this the sheet never resolves.
                    .onOpenURL { url in
                        AccountManager.handleRedirect(url)
                    }
            }
        }
    }
}
