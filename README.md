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
- **Photo meal logging** (`FoodVisionClassifier`, `FoodVocabulary`,
  `NutritionLookup`) — snap a photo of anything you're eating and get macros.
  Recognition runs fully on-device via Apple's MobileCLIP against a bundled
  vocabulary of ~700 dishes spanning every major cuisine. See
  [Photo meal logging](#photo-meal-logging) below.
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

## Setup: API keys

Copy the example secrets file and fill in your keys — `Secrets.plist` is
gitignored and never committed:

```bash
cp LockIn/Sources/Resources/Secrets.example.plist LockIn/Sources/Resources/Secrets.plist
```

- **Spoonacular** (`SpoonacularAPIKey`) — real recipes and macros. Without it
  the app runs entirely on the built-in food database; nothing breaks.
- **Google** (`GoogleClientID`) — enables the Google sign-in button. Also paste
  your `REVERSED_CLIENT_ID` into `GOOGLE_REVERSED_CLIENT_ID` in `project.yml`
  so the OAuth redirect resolves. Without it the button stays hidden and Apple
  sign-in still works.

Re-run `xcodegen generate` after editing `project.yml`.

## Tests

```bash
cd LockIn && xcodebuild -project LockIn.xcodeproj -scheme LockIn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

164 tests covering the metabolic engine (BMR pinned to hand-computed
Mifflin-St Jeor values, safety floors swept across ~300 body/sex combinations,
macros proven never negative), meal assembly and macro fitting, sleep and
schedule construction, streak/adherence logic, accountability copy, cache
invalidation, and Spoonacular decoding + the filter-relaxation ladder against
a mocked `URLProtocol` (no network, no quota), plus the food-recognition path:
vocabulary integrity, the non-food abstain rule, the nutrition-lookup ladder,
portion maths across both bases, and Open Food Facts decoding.

The image preprocessing is pinned against a reference embedding computed
offline by the same model (`Tools/reference_embedding.py`). That test exists
because the simulator has no camera and the failure it guards — handing the
model its colour channels in the wrong order — is completely silent. A
companion test feeds a deliberately channel-swapped image and asserts the check
*fails*, so a check that passes on everything can't masquerade as a working one.

Two things worth knowing if you add tests:

- The test bundle is **hosted in the app**, so anything the app does at launch
  runs during a test pass. `RuntimeEnvironment.isRunningUnitTests` keeps
  startup and UI inert — without it, `RootView` requests Calendar/Health
  permissions and the suite hangs on a system dialog forever.
- Settings has a DEBUG-only "Seed history" button that generates ~4 months of
  realistic adherence data, for reviewing the grid and charts against
  something other than an empty state.

## Photo meal logging

Two ways in, both landing in the same flow:

- **"Log a meal"** in the Today header — always available, for anything eaten
  off-plan.
- **"Ate something else"** on any scheduled *meal* — swaps what you actually
  had into that slot. The event is then marked **confirmed**, not missed: the
  streak tracks whether you followed through on eating, not whether you hit
  the exact grams. Blowing a meal off entirely is still a miss, via Skip.

Inside, you can take a photo, search the vocabulary, or type free text.

### How recognition works

`FoodImageEncoder.mlpackage` is Apple's **MobileCLIP-S0** image encoder (~22 MB,
compiled to `.mlmodelc` by Xcode at build time). CLIP matches an image against
*arbitrary text* rather than a fixed set of trained classes, so coverage is
bounded by the vocabulary we ship — not by what the model was trained to
classify. Adding a cuisine is a data change, never a retrain.

The ~700 dish names and their text embeddings live in `FoodVocabulary.json` /
`FoodVocabulary.bin` (~700 KB of float16). Those are precomputed at build time
by `LockIn/Tools/` — the app never runs a text encoder, which is what keeps the
bundle at 22 MB instead of ~107 MB.

Measured on 21 real dish photos spanning South Asian, East/Southeast Asian,
Middle Eastern, African, European and Latin American cuisines:
**81% top-1, 95% top-5**. The UI shows the top 5 and asks you to confirm, so
top-5 is the number that matters.

The vocabulary also contains non-food entries ("a person", "an empty plate").
They're never offered as candidates — they exist so that if a photo isn't of
food, the classifier returns *nothing* rather than a confident wrong guess.

### Macros: free-first, degrading gracefully

`NutritionLookup` walks a ladder, cheapest first:

1. **Local `FoodDatabase`** — instant, offline, free, hand-checked.
2. **Open Food Facts** — free, no API key, no practical rate limit, global.
   Strong on packaged products, thin on home-cooked dishes.
3. **Spoonacular `guessNutrition`** — the only source that handles cooked
   dishes by name. Costs quota, so it's last.
4. **Manual entry** — if all three miss, you type the numbers rather than the
   app logging a zeroed-out meal.

In practice this is $0: the first two cover most cases and neither costs
anything.

### What it deliberately does *not* do

**It never guesses portion size.** No model can measure grams from a 2D photo —
that's an industry-wide limitation, not a gap in this implementation. The photo
identifies *what* you ate; *how much* is always your input, defaulted rather
than invented. Sources that return per-serving values (Spoonacular) ask for
servings; per-100g sources (label data) ask for grams. `PortionBasis` keeps
those from being silently conflated, which would misreport a meal ~100x.

**Photos are never stored.** The capture is downsized to 256×256, embedded, and
released — never written to the sandbox, the Photos library, or iCloud, and
never uploaded. `LoggedMeal` holds no image data at all; a log entry is a name,
a portion string and four numbers (a few hundred bytes), so the log stays cheap
to keep forever. A test asserts the encoded record contains no image payload.

## Demo mode

The sign-in screen has a DEBUG-only "Watch the demo" button
(`Sources/Engines/DemoMode.swift`, `Sources/Views/Demo/DemoTourOverlay.swift`)
that seeds a full session in memory — Rahil's preset profile, ~4 months of
promise-grid history, and today's schedule with a realistic mix of
confirmed/pending/missed events — then walks a 9-step guided tour across all
three tabs (Today, Record, Settings), switching tabs automatically as it
narrates each feature. It never touches `PersistenceStore`, so "Exit demo"
(available on every step) drops straight back to the real sign-in/account
state with nothing overwritten. Debug builds only — stripped entirely from
release.

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
