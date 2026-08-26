import XCTest
@testable import LockIn

/// Demo mode is shown from the sign-in screen to people who may already have
/// their own account on the device. Its entire safety story is that it's a
/// throwaway in-memory session — so these assert that nothing it does reaches
/// the real store.
final class DemoModeTests: XCTestCase {

    private let store = PersistenceStore.shared

    /// Snapshot of everything demo mode could plausibly clobber.
    private struct StoreSnapshot: Equatable {
        let profile: UserProfile?
        let schedule: DaySchedule?
        let streak: StreakStatus?
        let dayRecords: [DayRecord]
        let loggedMeals: [LoggedMeal]
    }

    private func snapshot() -> StoreSnapshot {
        StoreSnapshot(
            profile: store.loadProfile(),
            schedule: store.loadSchedule(),
            streak: store.loadStreak(),
            dayRecords: store.loadDayRecords(),
            loggedMeals: store.loadLoggedMeals()
        )
    }

    func testStartingDemoWritesNothingToTheStore() {
        let before = snapshot()

        let state = AppState()
        state.startDemo()

        XCTAssertEqual(snapshot(), before, "startDemo() must not touch persisted state")
    }

    /// The riskiest path: demo mode seeds a plausible day, and confirming an
    /// event is the most natural thing to try while showing the app off.
    func testConfirmingEventsInDemoDoesNotPersist() throws {
        let before = snapshot()

        let state = AppState()
        state.startDemo()
        let event = try XCTUnwrap(state.todaySchedule?.events.first { $0.status == .pending })
        state.confirm(event)

        XCTAssertEqual(snapshot(), before, "check-ins made during the demo must not persist")
    }

    func testMissingEventsInDemoDoesNotPersist() throws {
        let before = snapshot()

        let state = AppState()
        state.startDemo()
        let event = try XCTUnwrap(state.todaySchedule?.events.first { $0.isCritical })
        state.markMissed(event)

        XCTAssertEqual(snapshot(), before, "a missed event during the demo must not reset the real streak")
    }

    func testLoggingAMealInDemoDoesNotPersist() {
        let before = snapshot()

        let state = AppState()
        state.startDemo()
        state.log(LoggedMeal(
            name: "demo meal",
            portionDescription: "1 serving",
            macros: MacroTargetsLite(calories: 500, proteinG: 30, fatG: 20, carbG: 40),
            source: .manual
        ))

        XCTAssertEqual(snapshot(), before, "meals logged during the demo must not persist")
    }

    func testExitingDemoRestoresRealState() {
        let state = AppState()
        let realMealCount = state.loggedMeals.count

        state.startDemo()
        XCTAssertTrue(state.demoActive)
        XCTAssertFalse(state.loggedMeals.isEmpty, "demo should seed an off-plan meal to show the feature")

        state.exitDemo()

        XCTAssertFalse(state.demoActive)
        XCTAssertEqual(state.loggedMeals.count, realMealCount,
                       "exiting the demo should drop seeded meals and restore the real log")
    }

    // MARK: - Tour

    func testTourCoversEveryTabAndEndsCleanly() {
        let tour = DemoTourController()

        XCTAssertTrue(tour.isFirst)
        XCTAssertFalse(tour.isLast)

        let tabs = Set(tour.steps.compactMap(\.tab))
        XCTAssertEqual(tabs, [0, 1, 2], "the tour should visit all three tabs")

        for _ in tour.steps { tour.advance() }
        XCTAssertTrue(tour.isLast, "advancing past the end should clamp, not overflow")
        XCTAssertEqual(tour.stepIndex, tour.steps.count - 1)

        for _ in tour.steps { tour.back() }
        XCTAssertTrue(tour.isFirst)
        XCTAssertEqual(tour.stepIndex, 0)
    }

    /// The tour is the pitch for the app; a step with no body is a visibly
    /// broken card.
    func testEveryTourStepHasContent() {
        for step in DemoTourController().steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertGreaterThan(step.body.count, 40, "step \(step.title) reads as a stub")
        }
    }

    func testTourMentionsPhotoMealLogging() {
        let bodies = DemoTourController().steps.map { $0.title + " " + $0.body }.joined().lowercased()
        XCTAssertTrue(bodies.contains("photo"), "the tour should cover photo meal logging")
    }
}
