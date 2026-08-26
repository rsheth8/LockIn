# LockIn

A native iOS app that plans and enforces your daily routine — wake, caffeine,
weighed macro meals (with prep-ahead reminders), workouts slotted around your
real calendar, sleep schedule, and a tough-love accountability system.

## Status: daily-driver ready

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

- **`MetabolicEngine`** — Mifflin-St Jeor BMR × activity factor TDEE, rate-based
  deficit/surplus, 1g/lb protein, evidence-based macro split. Recalculates as
  weight changes.
- **`SleepEngine`** — wake time anchored to your first calendar commitment,
  8hr sleep target, 45-min wind-down, 9hr caffeine cutoff.
- **`MealEngine`** — Spoonacular live recipes when keyed, otherwise the built-in
  food database. Today shows which source is active. Recipe portions are stated
  in *servings* and database foods in *grams* — a recipe has no per-gram truth,
  so labelling one "141g" would be a number you can't weigh. Where the pool
  lands under the protein target, portions are scaled and a weighed protein
  top-up added to close the gap; whatever gap remains is printed on the Fuel
  row rather than hidden behind the target.
- **`ScheduleEngine` + `ScheduleSlotter`** — full day timeline; meals and workout
  slot into free gaps around Calendar busy blocks.
- **`ScheduleRefreshTask`** — midnight timer + foreground staleness check so
  yesterday's plan never sticks after rollover.
- **`AccountabilityEngine`** — tiered messages using *your* goal weights (not
  hardcoded copy); escalations cancel when you tap Done/Skip.
- **`WorkoutEngine`** — weekly split from `FitnessGoal`s, adapted to quiz
  equipment (full gym / home / bodyweight).
- **`CalendarManager`** — EventKit read + Lock In calendar write-back.
- **`HealthKitManager` + weigh-in** — pull weight from Health; confirming the
  morning weigh-in writes back and updates macros.
- **`WeightSyncEngine`** — rate-limited HealthKit pull with outlier filter.
- **`ProgressPhotoStore`** — on-device JPEGs only (never Photos library / iCloud).
- **`NotificationManager`** — primary + 15/45m escalations; cancel-on-confirm.
- **`PersistenceStore`** — SwiftData keyed blobs (migrates prior UserDefaults).
- **`CloudSyncEngine`** — private iCloud profile + day records + streak on
  every check-in (photos stay local).
- **Screen Time** (`LockInMonitor` extension) — shields during workout *and*
  manually started focus blocks; auth status restored on launch.
- Accounts (Apple / Google / local), quiz onboarding, Settings for body/diet/
  equipment/permissions, sign-out confirm + erase-all.

## Setup: API keys & signing

```bash
cp LockIn/Sources/Resources/Secrets.example.plist LockIn/Sources/Resources/Secrets.plist
# Xcode packs secrets from BundleResources — keep the symlink (or copy):
ln -sf ../Sources/Resources/Secrets.plist LockIn/BundleResources/Secrets.plist
```

- **Spoonacular** — optional. Without it, built-in meals still work. For App
  Store distribution, proxy the API so the key is not on-device; a personal
  build may keep the key in `Secrets.plist` (gitignored).
- **Google** — `GoogleClientID` in Secrets + `GOOGLE_REVERSED_CLIENT_ID` in
  `project.yml` (or a gitignored `Local.xcconfig`). Button stays hidden until set.
- **Claude** (`ClaudeAPIKey`) — optional. Powers the quiz “what do you want to
  get good at?” brief via Haiku, rate-limited on device (20s gap, 15/day).
  Without it the free-text field still saves; presets still work.
- **`DEVELOPMENT_TEAM`** — required for device / TestFlight / Store.
- **Family Controls** — request Apple approval for your team before Screen Time
  works on a real device (opt-in; app runs without it).

Re-run `xcodegen generate` after editing `project.yml`.

## Privacy

`PrivacyInfo.xcprivacy` declares Health/fitness + user-content use for app
functionality only (no tracking). Usage strings match what the app actually
does (weigh-in write, no unused Face ID / background-fetch modes).

## Tests

```bash
cd LockIn && xcodebuild -project LockIn.xcodeproj -scheme LockIn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Unit coverage includes metabolic math, meals, sleep/schedule, Spoonacular
filter ladder (mocked), persistence, accountability goal copy, equipment
adaptation, midnight staleness, and AppState check-in / weigh-in / streak paths.

Notes:

- The test bundle is **hosted in the app**. `RuntimeEnvironment.isRunningUnitTests`
  keeps launch UI/permissions inert so the suite doesn't hang on system dialogs.
- **DEBUG Lab tab** — a fourth tab (flask icon) with one-tap personas, calendar
  fixtures, overdue/streak/distraction injectors, meal-source forcing, and jumps
  back to quiz / sign-in. Overrides show a banner on Today. Stripped from Release.
- Settings still has DEBUG shortcuts to seed/clear history.

## Still later (nice-to-have)

- Expand `FoodDatabase` with verified USDA/label macros.
- Apple Watch companion + widgets / Live Activities.
- Dedicated weekly progress review screen.
- Server-side Spoonacular proxy for public App Store builds.

## Design rationale (the science)

See doc comments at the top of each Engine file — TDEE formula, protein
target, deficit size, and sleep-timing rules are each cited to the specific
research/guideline they're based on.
