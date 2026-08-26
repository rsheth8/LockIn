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
- **Meal logging** (`FoodVisionClassifier`, `NutritionLabelReader`,
  `NutritionLookup`, `BarcodeScannerView`) — log anything you eat by photo,
  barcode, nutrition label, or text. Photo recognition and label OCR both run
  fully on-device. Meals can be built from several items and every number is
  editable, before or after saving. See [Meal logging](#meal-logging) below.
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

- **Spoonacular** (`SpoonacularAPIKey`) — real recipes, and macro estimates for
  cooked dishes in photo meal logging. Without it the app still runs on the
  built-in food database and Open Food Facts, but logging a *cooked dish* falls
  through to manual entry (see [Meal logging](#meal-logging)), and
  the 10 `SpoonacularClientTests` skip-fail with `missingKey`.

  The free tier is **150 points/day**. A cold app launch spends a few on the
  weekly recipe pool, and each dish nutrition estimate costs 1 — so normal use
  is comfortably inside it, but a day of heavy testing can run it down.
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

212 tests covering the metabolic engine (BMR pinned to hand-computed
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

## Meal logging

Two ways in, both landing in the same flow:

- **"Log a meal"** in the Today header — always available, for anything eaten
  off-plan.
- **"Ate something else"** on any scheduled *meal* — swaps what you actually
  had into that slot. The event is then marked **confirmed**, not missed: the
  streak tracks whether you followed through on eating, not whether you hit
  the exact grams. Blowing a meal off entirely is still a miss, via Skip.

Inside, there are four ways to say what you ate, in descending order of how
much the app can do for you:

| route | best for | accuracy | cost |
|---|---|---|---|
| **Scan a barcode** | anything packaged — the Costco bar, the granola | exact, manufacturer's own | free, keyless |
| **Scan a nutrition label** | packaged food not yet in the database | exact, if OCR reads it | free, fully offline |
| **Take/upload a photo** | a plate of food | 84% top-1, 94% top-5 | free, fully offline |
| **Search or type it** | everything else, incl. chain restaurants | varies by source | mostly free |

Every one of them lands on a screen where **the numbers are editable**, and any
meal can be corrected after saving. Nothing the app looks up is final.

### Meals made of several things

Photo recognition returns exactly *one* label. That's fine for a plate of pad
thai and useless for a bowl of Greek yogurt with fruit, granola and a scoop of
whey — which classifies as "granola bowl" and logs ~6 g of protein when the
real answer is closer to 50 g.

So a meal can be **built from its parts**: "Add another item" banks what's on
screen and goes back for the next one, and the totals are summed. The saved
entry keeps the breakdown (`LoggedMeal.components`), and its recorded source is
the *least* trustworthy of its parts — a bowl is only as good as its weakest
component, and claiming otherwise would dress an estimate up as label data.

### Packaged food: barcodes and labels

**Barcode → Open Food Facts.** ~3 million crowd-sourced products including
Costco/Kirkland, Trader Joe's and most supermarket own-brands. A barcode names
one exact manufactured product, so there's no name matching, no plausibility
gate and no estimate. The product's own serving weight comes back with it, so a
40 g protein bar opens at 40 g rather than the generic 200 g — the difference
between logging 190 kcal and 950.

**No barcode, or not in the database? Photograph the label.** `NutritionLabelReader`
runs Vision's on-device OCR, regroups the text into visual rows (a nutrition
panel is two columns — "Total Fat" and "8g" arrive as *separate* observations,
and matching them back up by vertical position is what makes the parse work),
then extracts calories, protein, fat, carbs and the serving size. No key, no
quota, no network.

It always lands on the editable form rather than a finished result, labelled
"read 3 of 4 off the label" — OCR on curved, glossy or crumpled packaging does
misread, and a number nobody has looked at is exactly the fake precision the
rest of this flow avoids.

**Chain restaurants** are covered via Spoonacular's menu-item database — Chili's,
Moe's, Jersey Mike's, Panera and a few hundred others, with published figures
rather than estimates. It's only queried for free text you typed that isn't in
the vocabulary, since that's what a brand query looks like. **Coverage is
genuinely partial: Chipotle is not in it.** For a Chipotle bowl, building it
from parts (chicken, rice, black beans, salsa) is the accurate route.

### How recognition works

`FoodImageEncoder.mlpackage` is Apple's **MobileCLIP-S0** image encoder (~22 MB,
compiled to `.mlmodelc` by Xcode at build time). CLIP matches an image against
*arbitrary text* rather than a fixed set of trained classes, so coverage is
bounded by the vocabulary we ship — not by what the model was trained to
classify. Adding a cuisine is a data change, never a retrain.

The ~720 names and their text embeddings live in `FoodVocabulary.json` /
`FoodVocabulary.bin` (~700 KB of float16). Those are precomputed at build time
by `LockIn/Tools/` — the app never runs a text encoder, which is what keeps the
bundle at 22 MB instead of ~107 MB.

Measured on **95 real dish photos** across eight regions (`Tools/eval_food_recognition.py`):

| region | n | top-1 | top-5 |
|---|---|---|---|
| American | 8 | 100% | 100% |
| European | 15 | 93% | 93% |
| East Asian | 13 | 92% | 100% |
| Latin American | 11 | 91% | 100% |
| South Asian | 15 | 87% | 100% |
| Middle Eastern | 10 | 80% | 90% |
| Southeast Asian | 13 | 77% | 92% |
| African | 10 | 50% | 70% |
| **overall** | **95** | **84%** | **94%** |

The UI shows the top 5 and asks you to confirm, so top-5 is the number that
matters in practice.

**African coverage is the known weak spot** and it's a limit of the model, not
the pipeline: zero-shot CLIP was trained on web captions that underrepresent
West and East African food. It reads fufu as "rasgulla" (white spheres) and
egusi soup as "sunflower seeds" (it is a melon-seed stew). Adding descriptive
aliases — "ethiopian chicken stew" alongside "doro wat" — lifted the region
from 40%/60% to 50%/70%, but no amount of vocabulary fixes a gap in what the
model was trained on. Those dishes are all still in the vocabulary and findable
by search; the photo just may not rank them.

The vocabulary also contains non-food entries ("a person", "an empty plate").
They're never offered as candidates — they exist so that if a photo isn't of
food, the classifier returns *nothing* rather than a confident wrong guess.

### Macros: free-first, degrading gracefully

The local `FoodDatabase` always leads — instant, offline, free, hand-checked.
After that the order depends on **what kind of food it is**, because the two
online sources are good at opposite things:

- **Ingredients** ("greek yogurt", "almonds") → Open Food Facts first. It's a
  label database: free, keyless, global, no practical rate limit.
- **Dishes** ("chicken biryani", "pad thai") → Spoonacular `guessNutrition`
  first, which estimates from a dish name. Costs quota, so it's never tried
  first for something a label database answers well.
- **Free text not in the vocabulary** ("jersey mike's turkey wrap") → the
  restaurant menu-item lookup leads, since that's what a brand query looks
  like. Vocabulary names never pay that extra quota.

If everything misses you get **manual entry** rather than a zeroed-out meal.

Concentrated foods carry a `typicalServingGrams` so the portion picker doesn't
open them at the generic 200 g — a scoop of whey is 30 g, a tablespoon of olive
oil 14 g. Getting this wrong isn't a rounding error: whey at 200 g is seven
scoops and 760 kcal instead of 114.

Stress testing is what forced this split. Routing everything to Open Food Facts
first returned *"céréales et légumes, façon pad thaï, bio"* — a French packaged
side dish — at 122 kcal/100g for a plate of pad thai. Open Food Facts matches
loosely, so a result now has to pass a plausibility check: most of the
*product's* words must be words you actually asked for. "Chicken Shawarma" for
"chicken shawarma" passes; a ready-meal that merely shares a word doesn't.

**Consequence worth knowing:** with no Spoonacular key configured, cooked
dishes fall through to manual entry rather than returning a confidently wrong
number. That's the honest trade, and it means the free Spoonacular key (see
Setup above) is what makes dish lookup work smoothly — with it, a pad thai
photo resolves to 500 kcal / P23 F21 C57 per serving. Ingredients and packaged
foods work fully offline/free either way.

### What it deliberately does *not* do

**It never guesses portion size.** No model can measure grams from a 2D photo —
that's an industry-wide limitation, not a gap in this implementation. The photo
identifies *what* you ate; *how much* is always your input, defaulted rather
than invented. Sources that return per-serving values (Spoonacular) ask for
servings; per-100g sources (label data) ask for grams. `PortionBasis` keeps
those from being silently conflated, which would misreport a meal ~100x.

**No number is unappealable.** Every lookup can be overruled — "Adjust these
numbers" on the portion screen, and tapping any logged meal to edit it
afterwards. A meal whose macros were hand-corrected reports itself as "adjusted
by hand" rather than continuing to credit the lookup it replaced. Opening the
edit sheet and closing it unchanged is *not* an edit: the fields show whole
grams, so comparing them naively would silently round a stored 1.5 g of fat to
2 g and stamp the meal as user-edited.

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
