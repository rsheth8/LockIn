import SwiftUI

@main
struct LockInApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
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
