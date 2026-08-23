import Foundation

enum RuntimeEnvironment {
    /// True when the app is running only as a host for the unit-test bundle.
    ///
    /// Unit tests are hosted inside the app, so `RootView`'s startup task would
    /// otherwise run for real during a test pass — requesting Calendar and
    /// Health permissions (which block on a system dialog and hang the suite
    /// indefinitely) and firing live Spoonacular calls that burn quota and make
    /// results depend on the network. Startup side effects check this first.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
