# LockIn — Handoff

Last updated: 2026-08-25, on branch `food-preferences-and-pacing`.

## Status

230 tests passing. Builds clean. Verified end-to-end in the iOS Simulator
(iPhone 17 Pro) — onboarding, Today's timeline, live Spoonacular meals,
Workout Mode with stick-figure guidance, Record/promise grid, Settings, and
the DEBUG Lab tab all run.

## What changed this session

Session started from a full status review of the app (see conversation for
the original audit), then fixed everything that was found broken or
misleading. In order of impact:

### 1. Fake gram labels on recipe meals
`MealComponent` had one `gramsToWeigh` field used for two different things:
real grams for database foods, and `servings × 100` for Spoonacular recipes —
both rendered with a "g" suffix. A 1.4-serving portion of stew read as
"141g", which looks weighable and isn't.

Fix: added `PortionUnit` (`.grams` / `.servings`) to `MealComponent`.
`portionLabel` / `portionDescription` render correctly per unit ("180g
Paneer" vs. "1.4 servings of Mushroom Tofu Stew"). Old persisted schedules
decode as `.grams`, which is what those numbers always were.
— `Sources/Models/Meal.swift`, `Sources/Engines/MealEngine.swift`

### 2. Fuel row showed the target, not what the plan delivered
The header printed `MetabolicEngine`'s target macros regardless of whether
the day's actual meals hit them. A day landing at P130 against a P180 target
looked identical to a day that hit P180.

Fix: `ScheduledEvent` now carries `mealMacros` per meal; `DaySchedule
.plannedMacros` sums them; the Fuel row shows the real total and, when short,
an explicit red line ("71g under your 225g protein target — today's recipes
couldn't reach it").
— `Sources/Models/DaySchedule.swift`, `Sources/Views/Dashboard/TodayView.swift`

### 3. Recipe pools routinely missed the protein target
Spoonacular pools scaled to a calorie share landed 40-60g under a 1g/lb
protein target with no correction.

Fix: `MealEngine.reconcileProtein` solves portion-scale and a weighed
protein-powder top-up jointly so calories hold while protein rises (capped at
~100g powder / 40% portion cut — past that it's a pool problem, reported via
#2 rather than hidden). Vegan profiles get pea protein, never whey. Top-up is
split across all meals, not backloaded into one.
— `Sources/Engines/MealEngine.swift` (`reconcileProtein`, `proteinTopUp`)
— new `FoodDatabase.peaProtein`

### 4. Dips/sauces served as "lunch"
`type=main course` alone wasn't enough — Spoonacular tags plenty of dips and
sauces as main courses (lived bug: "Jalapeno Queso With Goat Cheese" as
lunch).

Fix: `SpoonacularClient.MealType.accepts(_:)` screens both `dishTypes` and
title keywords (dip/sauce/queso/hummus/etc.) before a recipe is used for a
slot. `RecipeCache.filterVersion` bumped so pools cached under the old,
unscreened rules are discarded rather than served for another week.
— `Sources/Engines/SpoonacularClient.swift`, `Sources/Engines/RecipeCache.swift`

### 5. Tests wrote to the developer's real CloudKit / wiped the real store
`AppState.pushToCloud()` had no test guard, and `PersistenceStore` used the
on-disk SwiftData store even under `xcodebuild test`, so running the suite
could push test fixtures into your private iCloud and `clearAll()` could
delete your real profile/streak/history.

Fix: `pushToCloud()` no-ops under `RuntimeEnvironment.isRunningUnitTests`;
`PersistenceStore` uses `isStoredInMemoryOnly: true` under tests and skips
UserDefaults migration/clearing there too.
— `Sources/App/AppState.swift`, `Sources/Engines/PersistenceStore.swift`

### 6. Prep reminders could land before wake time
A meal needing a 12-hour soak scheduled its prep reminder by simple
subtraction from meal time, which could land in the middle of the night.

Fix: clamped to `wake + 10min` minimum in `ScheduleEngine.buildDay`.

### 7. Status bar / Dynamic Island overlap on every tab
`PinnedHeader.swift` (a `safeAreaInset`-based header pinner) existed but was
never actually called anywhere — every tab's header just scrolled up under
the system chrome.

Fix: applied `.pinnedHeader { ScreenHeader(...) }` to Today, Record, Settings,
and the DEBUG Lab tab.
— `Sources/Views/Dashboard/TodayView.swift`,
  `Sources/Views/Progress/ProgressGalleryView.swift`,
  `Sources/Views/Settings/SettingsView.swift`, `Sources/Views/Dev/DevLabView.swift`

### 8. Stick-figure pull-up was unreadable
Knees folded to ~80° collapsed the lower body to a stub; arms reaching
straight up sat exactly on the spine/head so the near arm visually vanished
into the skull.

Fix: knee fold moved to the hip (thigh forward, shin back — a real tucked
hang), reach carried ~10-20° off the spine, head tilts back (`head: -22` →
`-8` across the four keyframes) to clear the skull. Only `pullVertical`'s
signature drifted in `StickFigureBaseline.swift`; the other 32 clips are
byte-identical. Contact sheets regenerate via
`StickFigureTests.testContactSheetRendererProducesImagesForEveryPattern` /
`writeAllContactSheets` → `LockIn/StickFigureSheets/*.png`.
— `Sources/Models/StickFigureFrames.swift`

### 9. Workout Mode silently credited the workout on exit
Closing the X button after 20 seconds elapsed called `onFinish()` regardless
of whether any work happened — open the screen, do nothing, close it, streak
stays alive. The one thing an accountability app must never do quietly.

Fix: `WorkoutModeController.completedSets` / `hasCreditableWork` (≥1 logged
set). Closing with no sets just dismisses; closing with sets logged shows a
confirm dialog ("N sets logged so far — Mark workout done / Leave without
credit / Keep going").
— `Sources/Engines/WorkoutModeController.swift`,
  `Sources/Views/Workout/WorkoutModeView.swift`

### 10. Smaller fixes
- `ClaudeClient`: model id `claude-haiku-4-5` (was date-suffixed
  `-20251001`); rate limiter now reserves its slot *before* the request goes
  out (was recording after response returned, so concurrent calls could slip
  the 20s/day-cap gate).
- `CalendarManager`: `sync(_:)` now fingerprints the day's writable events
  and no-ops on an unchanged rebuild instead of delete-and-recreate on every
  launch pass; removed the dead `isWriting` flag (EventKit change
  notifications arrive too late for it to do anything — documented why);
  `preferredSource()` prefers the account you already write to over "first
  CalDAV source found."
- Promise grid month labels: were anchored to the *first column's* month
  (produced "MAY JUN" crammed together at the left edge when the leading
  column was June's tail labelled as May). Now anchored to whichever column
  contains each month's actual 1st.
- `PersistenceStore` / `AppState` / `ProgressPhotoStore` marked `@MainActor`
  — they share one non-thread-safe `ModelContext`; this was previously true
  by convention only.

## Test additions

`Tests/PortionsAndPlanTruthTests.swift` (new, 20 tests) — one test per bug
above: portion units, protein reconciliation (including the "already good day
is left alone" and "vegan never gets whey" cases), course screening, Fuel-row
truthfulness, prep-before-wake.

`Tests/WorkoutModeControllerTests.swift` — added `WorkoutModeCreditTests` (4
tests) for the exit-credit fix.

## Known remaining gaps (not touched this session)

- Fat/carb macros can still drift from target even after protein
  reconciliation — only calories and protein are jointly solved. The Fuel row
  now *shows* this honestly but doesn't correct it.
- No Apple Watch companion, no widgets/Live Activities.
- Spoonacular key lives in `Secrets.plist` on-device; README notes a
  server-side proxy is needed before public App Store distribution.
- `FoodDatabase` is still approximate USDA-style values, not verified
  label/FDC data.

## Repo state

Everything above is committed on `food-preferences-and-pacing`. This file
lives at the repo root (`HANDOFF.md`), not inside `LockIn/`, so it survives
independently of the Xcode project structure.
