#if DEBUG
import Foundation

/// Powers the "Watch the demo" entry point on the sign-in screen: a fully
/// seeded, in-memory session (Rahil's preset profile, four months of promise
/// grid history, and today's schedule pre-populated with a realistic mix of
/// confirmed/pending/missed events) plus a scripted tour of every screen.
///
/// Deliberately isolated from `DebugSeed`: `DebugSeed` mutates the real,
/// persisted profile so a signed-in developer can eyeball realistic data.
/// Demo mode never touches `PersistenceStore` at all — it exists so someone
/// can click "Watch the demo" from the sign-in screen, look at everything,
/// and back out to a totally untouched app with their own account intact.
enum DemoMode {
    /// A realistic today: everything more than 90 minutes in the past is
    /// confirmed, the afternoon snack got missed regardless of the time (so
    /// the coach line and streak-reset copy are always visible), and
    /// whatever's left is still pending — one look shows every status color
    /// the app can render, no matter what time the demo is run.
    static func todaySchedule(profile: UserProfile) -> DaySchedule {
        let macros = MetabolicEngine.dailyTargets(for: profile)
        let sleep = SleepEngine.plan(for: profile, busyBlocks: [])
        var schedule = ScheduleEngine.buildDay(
            profile: profile, macros: macros, sleepPlan: sleep,
            busyBlocks: [], date: Date()
        )

        let now = Date()
        for index in schedule.events.indices {
            let event = schedule.events[index]
            if event.time < now.addingTimeInterval(-90 * 60) {
                schedule.events[index].status = .confirmed
            } else if event.kind == .meal, event.title.localizedCaseInsensitiveContains("snack") {
                schedule.events[index].status = .missed
            }
        }
        return schedule
    }

    /// Streak numbers consistent with the seeded history's rough patches —
    /// currently mid-run after the most recent slump, not a suspicious 118/118.
    static var streak: StreakStatus {
        StreakStatus(currentStreakDays: 12, longestStreakDays: 31, lastMissedEvent: "Afternoon snack", missedCheckInsThisWeek: 1)
    }

    /// One off-plan meal so the "Off plan" strip and the photo-logging tour
    /// step have something real to point at. Marked as photo-identified since
    /// that's the path worth showing off.
    static var loggedMeals: [LoggedMeal] {
        [
            LoggedMeal(
                name: "Chicken shawarma",
                portionDescription: "220 g",
                macros: MacroTargetsLite(calories: 449, proteinG: 48, fatG: 26, carbG: 6),
                loggedAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date()) ?? Date(),
                source: .openFoodFacts,
                identifiedFromPhoto: true
            )
        ]
    }
}

/// One stop on the guided tour. `tab` drives `DashboardView`'s selection via
/// `AppState.demoTabRequest`; nil leaves the tab wherever the last step put it.
struct DemoTourStep: Identifiable {
    let id = UUID()
    let tab: Int?
    let title: String
    let body: String
}

/// Drives the coach-mark overlay: which step is showing, and stepping
/// forward/back/out. Lives on `AppState` (`appState.demoTour`) so the overlay
/// and the tab bar can both react to it.
final class DemoTourController: ObservableObject {
    @Published var stepIndex: Int = 0
    let steps: [DemoTourStep] = [
        DemoTourStep(tab: 0, title: "Today", body: "The hero card always shows the next thing still pending, whatever time of day it is. Everything earlier today is already confirmed, and the missed snack below shows exactly what falling off looks like."),
        DemoTourStep(tab: 0, title: "Coach line", body: "Miss a critical event and the accountability engine speaks up in the tone you picked at onboarding — gentle, tough-love, or hardcore. It stays silent otherwise; constant chatter would make the real hits land softer."),
        DemoTourStep(tab: 0, title: "Meals & macros", body: "Every meal is weighed in grams to hit today's protein/fat/carb targets, pulled from the built-in food database or live Spoonacular recipes — swipe a meal to confirm or mark it missed."),
        DemoTourStep(tab: 0, title: "Ate something else?", body: "Real life happens. \"Log a meal\" up top works any time, and every planned meal has an \"Ate something else\" option. Snap or upload a photo and it's identified on-device against ~720 foods from every major cuisine — then you pick the portion, because no photo can measure grams. See the shawarma under Off Plan."),
        DemoTourStep(tab: 0, title: "Workout", body: "Today's session is slotted automatically into the largest open gap in your calendar, and rotates through a weekly split built from your active fitness goals — fat loss, fast bowling power work, rucking, whatever you picked."),
        DemoTourStep(tab: 1, title: "Promise grid", body: "Four months of history, one square per day. This is the Ledger's whole thesis: an unbroken wall of kept squares is worth more than any pep talk, and a slump is visible instantly instead of getting rationalized away."),
        DemoTourStep(tab: 1, title: "Streak & weight trend", body: "The current streak resets to zero the moment a critical event is missed — loss aversion, not gold stars. The weight line tracks real HealthKit syncs, rate-limited so a bad scale reading can't fake progress."),
        DemoTourStep(tab: 1, title: "Progress photos", body: "Daily photos live in the app's private sandbox — never the system Photos library, never iCloud backup. Day-1-vs-today compare is one tap away, and the Today tab can launch straight into the camera."),
        DemoTourStep(tab: 2, title: "Settings", body: "Tune the tone (gentle → hardcore), pick an accent color that repaints every surface instantly, and turn on Screen Time shielding — LockIn blocks the apps you pick for the duration of today's workout window automatically."),
        DemoTourStep(tab: 2, title: "That's the whole app", body: "Sign-in, a quiz-driven onboarding, and everything you just clicked through — all built on 177 tests covering the metabolic math, meal assembly, scheduling, and accountability copy. Tap Exit demo any time to get back to your own account.")
    ]

    var current: DemoTourStep { steps[stepIndex] }
    var isFirst: Bool { stepIndex == 0 }
    var isLast: Bool { stepIndex == steps.count - 1 }

    func advance() { if !isLast { stepIndex += 1 } }
    func back() { if !isFirst { stepIndex -= 1 } }
}
#endif
