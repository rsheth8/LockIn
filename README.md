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
- **`CalendarManager`** — EventKit read access for real busy blocks.
- **`HealthKitManager`** — weight/workout read+write, sleep/active-energy read.
- **`NotificationManager`** — schedules primary + escalating local
  notifications per critical event.
- Minimal onboarding + dashboard SwiftUI views.

## What's next (not yet built)

- Check-in confirmation UI (tap to confirm each event — currently only
  notifications fire, nothing writes back to `EventStatus`).
- Weekly weight re-sync from HealthKit → recompute `MetabolicEngine` targets.
- Screen Time / DeviceActivity monitoring for the "lock-in block" distraction
  nudges (needs Family Controls entitlement approval from Apple — entitlement
  is already declared in `project.yml`).
- Expand `FoodDatabase` with verified USDA/label macro data and more variety.
- Apple Watch companion + widgets/Live Activities for the current event.
- Real persistence (SwiftData) once weight/meal logs need history and queries.
- Weekly progress review screen (adherence %, streak, weight trend chart).

## Design rationale (the science)

See doc comments at the top of each Engine file — TDEE formula, protein
target, deficit size, and sleep-timing rules are each cited to the specific
research/guideline they're based on.
