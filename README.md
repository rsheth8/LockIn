# LockIn

A native iOS app that plans and enforces your daily routine — wake, caffeine,
weighed macro meals (with prep-ahead reminders), workouts slotted around your
real calendar, sleep schedule, and a tough-love accountability system —
targeting your 220→180 lb goal.

## Status: working MVP scaffold, builds clean

`LockIn/` is a full SwiftUI + XcodeGen project. Open it in Xcode:

```bash
cd LockIn && open LockIn.xcodeproj
```

Or regenerate the project after editing `project.yml`:

```bash
cd LockIn && xcodegen generate
```

Before running on a device, set `DEVELOPMENT_TEAM` in `LockIn/project.yml` to
your Apple Developer Team ID and re-run `xcodegen generate`.

## What's implemented

- **`MetabolicEngine`** — Mifflin-St Jeor BMR × activity factor TDEE, 22%
  deficit, 1g/lb protein, evidence-based macro split. Recalculate weekly as
  weight drops (call `MetabolicEngine.dailyTargets` again with updated profile).
- **`SleepEngine`** — wake time anchored to your first calendar commitment,
  8hr sleep target, 45-min wind-down, 9hr caffeine cutoff — standard
  sleep-hygiene science.
- **`MealEngine`** — builds 4 meals/day from a starter vegetarian South-Asian
  food database (`FoodDatabase.swift`), scaled in grams to hit your macro
  targets, with prep-ahead lead times (e.g. soaking dal) folded into the
  schedule.
- **`ScheduleEngine`** — assembles the full day timeline, slots your workout
  into the largest free gap between calendar busy blocks (2pm–9pm window).
- **`AccountabilityEngine`** — tiered tough-love messages (gentle/tough-love/
  hardcore) for missed critical events, loss-aversion streak framing.
- **`WorkoutEngine`** — rotating weekly split built from active `FitnessGoal`s
  (fat loss always on; fast bowling adds rotational power/sprint/anti-rotation
  core work for lumbar-stress prevention; hiking/backpacking adds weighted
  rucking + unilateral leg work for loaded trail durability).
- **`CalendarManager`** — EventKit read access for real busy blocks.
- **`HealthKitManager`** — weight/workout read+write, sleep/active-energy read.
- **`WeightSyncEngine`** — pulls latest HealthKit weight (rate-limited to once
  per ~20hrs, outlier-filtered) and updates the profile so `MetabolicEngine`
  targets track actual weight loss instead of staying pinned to day-1 numbers.
- **`ProgressPhotoStore`** — daily progress photos, JPEGs in the app's
  sandboxed Documents dir (excluded from iCloud/device backup), metadata only
  in `PersistenceStore`. Never touches the system Photos library.
- **`NotificationManager`** — schedules primary + escalating local
  notifications per critical event.
- **Screen Time distraction monitoring** (`LockInMonitor` — a second Xcode
  target, since DeviceActivityMonitor extensions run in their own process):
  pick distracting apps/categories in Settings, LockIn shields them for the
  duration of today's workout window automatically, and if you burn real time
  on them anyway (1-min cumulative threshold) the extension fires an
  immediate tough-love notification and logs it — draining that log resets
  your streak, same as a missed check-in. Main app and extension talk only
  through an App Group container (`group.com.rahilsheth.lockin`,
  `Sources/Shared/AppGroup.swift`); the extension never touches the network.
- Onboarding, Today (check-in), Progress (camera + gallery + day-1-vs-today
  compare), and Settings (Screen Time + tone) tabs.
- Check-in confirmation (swipe to confirm/miss on Today), streak tracking.

## Project structure note

`LockInMonitor` (`LockIn/MonitorExtension/`) is a separate app-extension
target — it needs the **Family Controls entitlement approved for your
specific Apple Developer account** before Screen Time monitoring works on a
real device (Settings → request from Apple; it's a manual review, not
instant). Without that approval, `requestAuthorization` in
`ScreenTimeManager` will fail gracefully and the rest of the app is
unaffected — Screen Time is opt-in, not a hard dependency.

## What's next (not yet built)

- Manual weigh-in entry UI that writes to HealthKit (currently weight only
  flows *in* from HealthKit — nothing logs a fresh reading from the app itself).
- Extending lock-in blocks beyond the workout window to manually-started study
  sessions (the `LockInBlock` model already supports arbitrary blocks —
  `ScreenTimeManager.scheduleLockInBlock` just isn't called for anything but
  today's workout yet).
- Expand `FoodDatabase` with verified USDA/label macro data and more variety.
- Apple Watch companion + widgets/Live Activities for the current event.
- Real persistence (SwiftData) once weight/meal logs need history and queries.
- Weekly progress review screen (adherence %, streak, weight trend chart).

## Design rationale (the science)

See doc comments at the top of each Engine file — TDEE formula, protein
target, deficit size, and sleep-timing rules are each cited to the specific
research/guideline they're based on.
