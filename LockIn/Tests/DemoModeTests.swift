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
        let shoppingList: [ShoppingListItem]
    }

    private func snapshot() -> StoreSnapshot {
        StoreSnapshot(
            profile: store.loadProfile(),
            schedule: store.loadSchedule(),
            streak: store.loadStreak(),
            dayRecords: store.loadDayRecords(),
            loggedMeals: store.loadLoggedMeals(),
            shoppingList: store.loadShoppingList()
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

    /// Photo recognition is the flashiest route but the least accurate one. A
    /// tour that only showed it would sell the app on its weakest path.
    func testTourCoversBarcodeAndLabelScanning() {
        let bodies = DemoTourController().steps.map { $0.title + " " + $0.body }.joined().lowercased()

        XCTAssertTrue(bodies.contains("barcode"), "the tour should cover barcode scanning")
        XCTAssertTrue(bodies.contains("nutrition facts") || bodies.contains("nutrition label"),
                      "the tour should cover reading a nutrition label")
    }

    // MARK: - Practice data

    /// A mistyped digit would sail through review and then 404 in the middle of
    /// a demo, looking exactly like a broken lookup. The check digit catches it
    /// here instead, without a network call.
    func testEveryPracticeBarcodeIsAValidEAN13() {
        for practice in DemoMode.practiceBarcodes {
            let digits = practice.code.compactMap { $0.wholeNumberValue }
            XCTAssertEqual(digits.count, 13, "\(practice.name): EAN-13 codes have 13 digits")
            guard digits.count == 13 else { continue }

            let sum = (0..<12).reduce(0) { $0 + digits[$1] * ($1.isMultiple(of: 2) ? 1 : 3) }
            XCTAssertEqual((10 - sum % 10) % 10, digits[12],
                           "\(practice.name) (\(practice.code)) has a bad check digit")
        }
    }

    func testPracticeBarcodesAreDistinctAndCoverTheUnknownCase() {
        let codes = DemoMode.practiceBarcodes.map(\.code)

        XCTAssertGreaterThanOrEqual(codes.count, 3)
        XCTAssertEqual(Set(codes).count, codes.count, "a duplicated code wastes a practice slot")
        XCTAssertTrue(
            DemoMode.practiceBarcodes.contains { $0.name.localizedCaseInsensitiveContains("unknown") },
            "one code must be absent from the database, or the fallback can never be demonstrated"
        )
    }
}
