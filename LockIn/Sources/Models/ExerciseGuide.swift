import Foundation

/// How to actually perform one movement — shown in Workout Mode for anyone
/// who doesn't already know the exercise by name. Text-only by design: the
/// app is offline-first with no media pipeline, and terse, correct cues
/// ("brace, don't arch") teach faster than a looping video most people
/// glance at once and ignore anyway.
struct ExerciseGuide: Equatable {
    let cues: [String]
    /// The single most common way people get this wrong — called out
    /// separately from the how-to cues so it reads as a warning, not just
    /// another step.
    let watchFor: String
    /// Which looping stick-figure animation demonstrates this movement in
    /// real time. Every exercise in `WorkoutEngine` maps to a dedicated
    /// `MovementPattern` clip — not a vague catch-all — so the demo matches
    /// the cues.
    let pattern: MovementPattern
    /// Multiplies the clip's own pace for this specific exercise. Below 1 is
    /// slower.
    ///
    /// A pattern is shared by several exercises, but tempo isn't: a cue that
    /// says "count 3-4 seconds down" is contradicted by a demo running at the
    /// same speed as everything else, and the animation is supposed to be
    /// showing you the cue, not just the shape.
    var demoSpeed: Double = 1

    init(cues: [String], watchFor: String, pattern: MovementPattern, demoSpeed: Double = 1) {
        self.cues = cues
        self.watchFor = watchFor
        self.pattern = pattern
        self.demoSpeed = demoSpeed
    }
}

/// Cue text for every exercise `WorkoutEngine` can prescribe, keyed by exact
/// name. Matched exactly first; then aliases; then longest substring; then a
/// keyword fallback so apartment-gym variants never show a blank card.
enum ExerciseLibrary {
    static func guide(for exerciseName: String) -> ExerciseGuide? {
        if let exact = library[exerciseName] { return exact }
        if let alias = aliases[exerciseName], let guide = library[alias] { return guide }
        let contained = library.keys
            .filter { exerciseName.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(exerciseName) }
            .sorted { $0.count > $1.count }
        if let key = contained.first, let guide = library[key] { return guide }
        return keywordGuide(for: exerciseName)
    }

    /// Every exercise name currently emitted by `WorkoutEngine`. Kept public
    /// so geometry / coverage tests can assert the library stays complete.
    static var coveredExerciseNames: [String] { Array(library.keys).sorted() }

    /// Maps a kit-specific prescription name onto a canonical library key.
    private static let aliases: [String: String] = [
        // Squats
        "Smith Squat": "Back Squat",
        "Goblet Squat": "Back Squat",
        "Air Squat": "Back Squat",
        "Barbell Back Squat": "Back Squat",
        // Hinge
        "Smith Romanian Deadlift": "Romanian Deadlift",
        "Dumbbell Romanian Deadlift": "Romanian Deadlift",
        "Single-Leg Hip Hinge": "Romanian Deadlift",
        "Conventional Deadlift": "Romanian Deadlift",
        // Press
        "Smith Bench Press": "Barbell Bench Press",
        "Dumbbell Bench Press": "Barbell Bench Press",
        "Floor Press": "Barbell Bench Press",
        "Smith Overhead Press": "Overhead Press",
        "Seated Dumbbell Shoulder Press": "Overhead Press",
        "Pike Push-Up": "Overhead Press",
        // Pull
        "Seated Cable Row": "Barbell Row",
        "Dumbbell Row": "Barbell Row",
        "Smith Bent-Over Row": "Barbell Row",
        "Inverted Row": "Barbell Row",
        "Lat Pulldown": "Pull-Up",
        "Pull-Up / Lat Pulldown": "Pull-Up",
        "Dumbbell Pullover": "Pull-Up",
        "Band Pulldown / Doorway Row": "Pull-Up",
        // Face / shoulders
        "Cable Face Pull": "Face Pull",
        "Band Face Pull": "Face Pull",
        "Prone Y-T-W Raise": "Face Pull",
        // Core / rotation
        "Med Ball Rotational Slam": "Cable Woodchop",
        "Standing Twist Reach": "Cable Woodchop",
        "Cable Rotational Row": "Rotational Med Ball Throw",
        "Standing Rotational Punch": "Rotational Med Ball Throw",
        "Cable Pallof Press": "Pallof Press",
        "Band Pallof Press": "Pallof Press",
        "Dead Bug (anti-rotation)": "Dead Bug",
        // Legs unilateral
        "Dumbbell Bulgarian Split Squat": "Bulgarian Split Squat",
        "Smith Split Squat": "Bulgarian Split Squat",
        "Reverse Lunge": "Walking Lunge",
        "Dumbbell Step-Up": "Weighted Step-Up",
        "Step-Up / Step-Down": "Weighted Step-Up",
        "Step-Down (eccentric focus)": "Weighted Step-Up",
        // Carry / cardio
        "Dumbbell Farmer's Carry": "Farmer's Carry",
        "Loaded Backpack Carry": "Weighted Ruck Walk",
        "Peloton Zone 2 Ride": "Zone 2 Effort",
        "Rower Zone 2": "Zone 2 Effort",
        "Treadmill Incline Walk": "Zone 2 Effort",
        "Brisk Outdoor Walk": "Zone 2 Effort",
        "Treadmill Sprint Intervals": "Repeat Sprint Sets",
        "Rower Sprint Intervals": "Repeat Sprint Sets",
        "Outdoor Sprint Repeats": "Repeat Sprint Sets",
        "Run-up Length Sprints": "Repeat Sprint Sets",
        "Easy Jog Recovery": "Zone 2 Effort",
        // Arms
        "Cable Tricep Pushdown": "Tricep Extension",
        "Dumbbell Overhead Tricep Ext.": "Tricep Extension",
        "Diamond Push-Up": "Push-Up",
        "Cable Curl": "Bicep Curl",
        "Dumbbell Curl": "Bicep Curl",
        "Towel Curl / Isometric": "Bicep Curl"
    ]

    private static func keywordGuide(for name: String) -> ExerciseGuide? {
        let n = name.lowercased()
        if n.contains("squat") && n.contains("split") { return library["Bulgarian Split Squat"] }
        if n.contains("squat") { return library["Back Squat"] }
        if n.contains("deadlift") || n.contains("hinge") || n.contains("rdl") { return library["Romanian Deadlift"] }
        if n.contains("bench") || n.contains("floor press") { return library["Barbell Bench Press"] }
        if n.contains("overhead") || n.contains("shoulder press") || n.contains("pike") { return library["Overhead Press"] }
        if n.contains("push-up") || n.contains("pushup") { return library["Push-Up"] }
        if n.contains("face pull") || n.contains("y-t-w") { return library["Face Pull"] }
        if n.contains("pulldown") || n.contains("pull-up") || n.contains("pullover") { return library["Pull-Up"] }
        if n.contains("row") { return library["Barbell Row"] }
        if n.contains("woodchop") || n.contains("slam") || n.contains("twist") { return library["Cable Woodchop"] }
        if n.contains("throw") || n.contains("rotational") || n.contains("punch") { return library["Rotational Med Ball Throw"] }
        if n.contains("pallof") { return library["Pallof Press"] }
        if n.contains("dead bug") { return library["Dead Bug"] }
        if n.contains("lunge") { return library["Walking Lunge"] }
        if n.contains("step") { return library["Weighted Step-Up"] }
        if n.contains("farmer") || n.contains("carry") { return library["Farmer's Carry"] }
        if n.contains("ruck") || n.contains("backpack") { return library["Weighted Ruck Walk"] }
        if n.contains("sprint") { return library["Repeat Sprint Sets"] }
        if n.contains("zone 2") || n.contains("ride") || n.contains("walk") || n.contains("jog") || n.contains("rower") { return library["Zone 2 Effort"] }
        if n.contains("tricep") || n.contains("pushdown") { return library["Tricep Extension"] }
        if n.contains("curl") { return library["Bicep Curl"] }
        if n.contains("bowling") { return library["Bowling-Action Shadow Reps (no ball)"] }
        if n.contains("thoracic") { return library["Thoracic Spine Rotation Drill"] }
        if n.contains("hip flexor") || n.contains("90/90") { return library["Hip Flexor + 90/90 Stretch"] }
        if n.contains("ankle") { return library["Ankle Dorsiflexion Drill"] }
        if n.contains("plank") { return library["Front Plank"] }
        if n.contains("bird dog") { return library["Bird Dog"] }
        return nil
    }

    private static let library: [String: ExerciseGuide] = [
        "Back Squat": ExerciseGuide(
            cues: [
                "Bar or load sits on your upper traps (or goblet at chest) — brace like you're about to take a punch.",
                "Break at the hips and knees together; sit until your hip crease drops below your knee.",
                "Drive through the whole foot to stand — push the floor apart with your feet."
            ],
            watchFor: "Knees caving inward on the way up — think 'push the floor apart'.",
            pattern: .squat
        ),
        "Barbell Back Squat": ExerciseGuide(
            cues: [
                "Bar sits on your upper traps, not your neck — grip just outside shoulder width.",
                "Brace like you're about to take a punch, then break at the hips and knees together.",
                "Sit back until your hip crease drops below your knee, drive through the whole foot to stand."
            ],
            watchFor: "Knees caving inward on the way up — think 'push the floor apart' with your feet.",
            pattern: .squat
        ),
        "Conventional Deadlift": ExerciseGuide(
            cues: [
                "Bar over mid-foot, shins nearly touching it, grip just outside your knees.",
                "Chest up, flat back, take the slack out of the bar before you pull.",
                "Drive the floor away with your legs — the bar stays close, hips and shoulders rise together."
            ],
            watchFor: "Hips shooting up first while the chest stays down — that turns it into a bad-back stiff-leg pull.",
            pattern: .deadlift
        ),
        "Barbell Hip Thrust": ExerciseGuide(
            cues: [
                "Upper back on a bench, feet flat, bar rolled up over your hips.",
                "Drive through your heels and squeeze your glutes to lift your hips until your body is a straight line, chin tucked.",
                "Lower under control — don't let the bar bounce off the floor between reps."
            ],
            watchFor: "Overextending the lower back at the top instead of squeezing the glutes — stop the range where your ribs stack over your pelvis.",
            pattern: .hipThrust
        ),
        "Romanian Deadlift": ExerciseGuide(
            cues: [
                "Soft knees, then push your hips straight back — the load stays close, dragging down your thighs.",
                "Lower until you feel a hard hamstring stretch, usually mid-shin. Depth isn't the goal, the stretch is.",
                "Reverse by driving your hips forward, not by rounding your back up first."
            ],
            watchFor: "Rounding the lower back to chase more range — stop at your hamstring's limit, not the floor.",
            pattern: .hinge
        ),
        "Walking Lunge": ExerciseGuide(
            cues: [
                "Step out far enough that your front shin stays vertical at the bottom.",
                "Drop your back knee straight down toward the floor, torso tall.",
                "Push through the front heel to stand into the next step."
            ],
            watchFor: "Front knee drifting past the toes and inward — track it over the second/third toe.",
            pattern: .lunge
        ),
        "Weighted Step-Up": ExerciseGuide(
            cues: [
                "Box height: your knee should be at roughly a 90° bend when your foot lands on top.",
                "Drive through the top foot's heel — don't push off the trailing leg.",
                "Control the descent; don't just drop back down."
            ],
            watchFor: "Using the back leg to spring up — the whole point is single-leg strength.",
            pattern: .stepUp
        ),
        "Rotational Med Ball Throw": ExerciseGuide(
            cues: [
                "Stand side-on to the wall, feet athletic width, knees soft.",
                "Load by rotating your hips and shoulders away from the target, then fire them back through in sequence — hips first.",
                "Release at hip height, let the whole body follow through."
            ],
            watchFor: "Throwing arms-only — power comes from hip-shoulder separation, not the shoulders.",
            pattern: .medBallThrow
        ),
        "Box Jump": ExerciseGuide(
            cues: [
                "Stand arm's length from the box, feet hip-width, knees soft.",
                "Swing your arms back then explosively drive them forward and up as you jump — land softly with both feet flat.",
                "Step back down; don't jump down off the box, that's just extra landing stress for no benefit."
            ],
            watchFor: "Landing with stiff knees and a loud stomp — absorb it silently, that's the actual skill being trained.",
            pattern: .boxJump
        ),
        "Cable Woodchop": ExerciseGuide(
            cues: [
                "Set the cable high (or hold a med ball overhead), stand side-on, arms long.",
                "Rotate through your torso and hips to pull down and across your body.",
                "Control it back to the start — don't let the stack or momentum yank you around."
            ],
            watchFor: "Bending the arms to pull — keep them long and let the core do the rotating.",
            pattern: .woodchop
        ),
        "Bowling-Action Shadow Reps (no ball)": ExerciseGuide(
            cues: [
                "Full run-up rhythm and delivery action, at match intensity, just without releasing a ball.",
                "Focus on one technical cue per rep — front-arm height, or hip-shoulder separation, not everything at once.",
                "Finish the follow-through fully; don't pull out of the action early since there's no ball to release."
            ],
            watchFor: "Rushing through it as a warm-up rather than treating each rep as real technical practice.",
            pattern: .bowlingAction
        ),
        "Run-up Length Sprints": ExerciseGuide(
            cues: [
                "Full effort over your actual bowling run-up distance — this trains match-speed approach, not top-end sprinting.",
                "Walk back to the start; the point is quality speed, not conditioning.",
                "Stop the set if your form breaks down from fatigue — quality over quantity here."
            ],
            watchFor: "Jogging the first half and only sprinting the last few strides — go from the first step.",
            pattern: .sprint
        ),
        "Repeat Sprint Sets": ExerciseGuide(
            cues: [
                "Hold the prescribed rest strictly — this is what makes it mimic repeat spells, not a straight conditioning run.",
                "Same effort on the last rep as the first, even as it gets harder.",
                "Land on the balls of your feet, drive your arms — sprint mechanics, not a stride-out."
            ],
            watchFor: "Letting rest creep longer as you fatigue — set a timer and stick to it.",
            pattern: .sprint
        ),
        "Easy Jog Recovery": ExerciseGuide(
            cues: [
                "Conversational pace — you should be able to talk in full sentences.",
                "This is active recovery, not a cooldown to rush through."
            ],
            watchFor: "Turning it into another conditioning effort — the whole point is low intensity.",
            pattern: .jog
        ),
        "Weighted Ruck Walk": ExerciseGuide(
            cues: [
                "Pack sits high and snug against your back, hip belt taking most of the load, not your shoulders.",
                "Walking pace, upright posture — resist the urge to lean forward into the load.",
                "Add incline before adding weight once bodyweight-in-pack feels easy."
            ],
            watchFor: "Leaning forward at the hips to compensate for the load — that's what wrecks your lower back on long carries.",
            pattern: .ruckWalk
        ),
        "Zone 2 Effort": ExerciseGuide(
            cues: [
                "Conversational pace, nasal breathing if you can hold it.",
                "Consistency over multiple sessions builds this, not any single hard effort."
            ],
            watchFor: "Creeping up in pace until it's not actually zone 2 anymore — check yourself against the talk test.",
            pattern: .jog
        ),
        "Bulgarian Split Squat": ExerciseGuide(
            cues: [
                "Rear foot up on a bench, front foot far enough forward that your shin stays close to vertical at the bottom.",
                "Most of your weight stays on the front leg — the back foot is just for balance.",
                "Drop straight down, drive straight up through the front heel."
            ],
            watchFor: "Placing the front foot too close to the bench — it turns into a quad-dominant knee-forward grind.",
            pattern: .splitSquat
        ),
        "Step-Down (eccentric focus)": ExerciseGuide(
            cues: [
                "Stand on a box or step, one foot hanging off the edge.",
                "Lower slowly — count 3-4 seconds down — until your back toe just grazes the floor.",
                "Push back up through the standing leg."
            ],
            watchFor: "Letting the hips shift sideways instead of dropping straight down — this is exactly the control that protects your knees on descents.",
            pattern: .stepDown, demoSpeed: 0.55
        ),
        "Single-Leg Calf Raise": ExerciseGuide(
            cues: [
                "Hold something for balance if you need to — the calf is the target, not your balance.",
                "Rise all the way onto the ball of the foot, pause briefly at the top.",
                "Lower under control past level if you're on a step, for a full stretch."
            ],
            watchFor: "Bouncing through the bottom — control it, don't use momentum.",
            pattern: .calfRaise, demoSpeed: 0.8
        ),
        "Pull-Up": ExerciseGuide(
            cues: [
                "Start from a full hang (or full stack extension) — don't cut the bottom range short.",
                "Pull your elbows down and back, chest toward the bar/handle.",
                "Lower under control to a full stretch before the next rep."
            ],
            watchFor: "Kipping or using momentum to get the chin over — slow it down and it's a completely different exercise.",
            pattern: .pullVertical
        ),
        "Pull-Up / Lat Pulldown": ExerciseGuide(
            cues: [
                "Start from a full hang (or full stack extension) — don't cut the bottom range short.",
                "Pull your elbows down and back, chest toward the bar/handle.",
                "Lower under control to a full stretch before the next rep."
            ],
            watchFor: "Kipping or using momentum to get the chin over — slow it down and it's a completely different exercise.",
            pattern: .pullVertical
        ),
        "Barbell Row": ExerciseGuide(
            cues: [
                "Hinge to roughly 45°, flat back, load hanging at arm's length.",
                "Pull to your lower ribs, elbows driving back and slightly out.",
                "Lower fully under control each rep — don't let it become a series of half-pulls."
            ],
            watchFor: "Using body English (jerking the torso up) to move the weight — that's your lower back doing the lift's job.",
            pattern: .pullHorizontal
        ),
        "Face Pull": ExerciseGuide(
            cues: [
                "Cable or band at roughly face height, rope attachment.",
                "Pull toward your face, aiming to finish with your hands either side of your head, elbows high.",
                "Externally rotate at the end range — this is the part that actually trains the rotator cuff."
            ],
            watchFor: "Using too much weight and turning it into a row — this should feel light and controlled.",
            pattern: .facePull
        ),
        "Farmer's Carry": ExerciseGuide(
            cues: [
                "Heavy dumbbells or a trap bar, arms straight at your sides.",
                "Walk tall — ribs stacked over hips, shoulders back and down, don't let the weight round you forward.",
                "Grip hard the whole way; that grip endurance is the point as much as the walk."
            ],
            watchFor: "Shrugging or leaning to one side to fight the weight — stay stacked and even.",
            pattern: .carry
        ),
        "Barbell Bench Press": ExerciseGuide(
            cues: [
                "Shoulder blades pinched and pulled down into the bench, feet planted flat.",
                "Lower the bar (or DBs) to your lower chest under control, elbows at roughly 45° from your torso.",
                "Press back up in a slight arc toward your face, driving through your feet."
            ],
            watchFor: "Elbows flaring straight out to the sides — that shifts the load onto the shoulder joint instead of the chest.",
            pattern: .benchPress
        ),
        "Overhead Press": ExerciseGuide(
            cues: [
                "Load at your collarbones, grip just outside shoulder width, forearms vertical.",
                "Brace your core and glutes, then press straight up, moving your head back slightly to let the bar pass.",
                "Lock out overhead with your bicep by your ear — don't stop short at forehead height."
            ],
            watchFor: "Arching the lower back to muscle the weight up — that's a sign it's too heavy or your core isn't braced.",
            pattern: .overheadPress
        ),
        "Push-Up": ExerciseGuide(
            cues: [
                "Hands just outside shoulder width, body in one straight line from head to heels.",
                "Lower your chest to just above the floor, elbows tracking back at roughly 45°.",
                "Press back up without letting your hips sag or pike."
            ],
            watchFor: "Hips dropping first as you fatigue — that's the plank part of the movement breaking down, not just the arms.",
            pattern: .pushUp
        ),
        "Pallof Press": ExerciseGuide(
            cues: [
                "Cable or band at chest height, stand side-on so the pull is trying to rotate you.",
                "Press the handle straight out in front of your chest and hold — resist the rotation, don't let your torso twist.",
                "Brace hard through the hold; it's an isometric anti-rotation drill, not a press for reps of motion."
            ],
            watchFor: "Letting your hips or shoulders drift toward the anchor point — that's the rotation this exercise exists to prevent.",
            pattern: .pallofPress, demoSpeed: 0.75
        ),
        "Dead Bug": ExerciseGuide(
            cues: [
                "Flat on your back, knees stacked over hips at 90°, arms reaching straight up.",
                "Press your lower back into the floor and keep it there the whole set.",
                "Slowly extend the opposite arm and leg toward the floor without letting your back arch off it."
            ],
            watchFor: "Your lower back lifting off the floor as the leg extends — that's the rep breaking down, shorten the range.",
            pattern: .deadBug, demoSpeed: 0.8
        ),
        "Bird Dog": ExerciseGuide(
            cues: [
                "On all fours, hands under shoulders, knees under hips, spine neutral.",
                "Reach one arm forward and the opposite leg straight back at the same time, staying level.",
                "Hold briefly, then return to all-fours with control before switching sides."
            ],
            watchFor: "Your hips rotating open as the leg extends — keep both hip points square to the floor the whole rep.",
            pattern: .birdDog, demoSpeed: 0.8
        ),
        "Front Plank": ExerciseGuide(
            cues: [
                "Forearms down, elbows under shoulders, body in one straight line from head to heels.",
                "Squeeze your glutes and brace your abs like you're about to be poked in the stomach.",
                "Breathe normally — holding your breath isn't the goal, holding the position is."
            ],
            watchFor: "Hips sagging toward the floor or piking up toward the ceiling as you fatigue — both mean the set should end.",
            pattern: .plank
        ),
        "Side Plank Hold": ExerciseGuide(
            cues: [
                "Forearm down, elbow under your shoulder, feet stacked, body in one straight line.",
                "Lift your hips until your body forms a straight diagonal line, top hand on your hip or reaching up.",
                "Keep your hips pushed forward — don't let them drift back to take load off."
            ],
            watchFor: "Hips sinking toward the floor as you fatigue — that's the set ending whether the clock says so or not.",
            pattern: .plank
        ),
        "Mountain Climbers": ExerciseGuide(
            cues: [
                "Start in a high plank, hands under shoulders, body in one straight line.",
                "Drive one knee toward your chest, then switch legs quickly, keeping your hips level.",
                "Keep the pace controlled enough that your hips don't bounce up and down."
            ],
            watchFor: "Hips riding up into a pike as you speed up — slow down and keep the plank line, that's the point of the drill.",
            pattern: .mountainClimber
        ),
        "Thoracic Spine Rotation Drill": ExerciseGuide(
            cues: [
                "On all fours or side-lying, one hand behind your head.",
                "Rotate your upper back to open your elbow toward the ceiling, following it with your eyes.",
                "Keep your hips still — the rotation should come entirely from your upper back, not your lower back."
            ],
            watchFor: "Rotating from the lower back/hips instead of the upper back — that defeats the point of the drill.",
            pattern: .thoracicRotation, demoSpeed: 0.8
        ),
        "Hip Flexor + 90/90 Stretch": ExerciseGuide(
            cues: [
                "Half-kneeling, back knee down, squeeze that side's glute to tuck your pelvis under.",
                "Lean your torso slightly forward and away until you feel a stretch in the front of the back hip.",
                "For 90/90: sit with front shin and back shin both at 90°, lean forward from the hips over the front leg."
            ],
            watchFor: "Letting your lower back arch to fake more range — the stretch should come from the hip, not a bent spine.",
            pattern: .hipFlexorStretch, demoSpeed: 0.7
        ),
        "Ankle Dorsiflexion Drill": ExerciseGuide(
            cues: [
                "Half-kneeling with the front foot flat, knee tracking straight over the toes.",
                "Drive the knee forward over the toes without the heel lifting off the floor.",
                "You're chasing range at the ankle, not speed — hold briefly at end range each rep."
            ],
            watchFor: "Letting the heel pop up to fake extra range — that just moves the stretch out of the ankle entirely.",
            pattern: .ankleRock, demoSpeed: 0.8
        ),
        "Tricep Extension": ExerciseGuide(
            cues: [
                "Elbows pinned at your sides (pushdown) or beside your head (overhead) — only the forearms move.",
                "Extend fully without shrugging; squeeze the triceps at lockout.",
                "Lower under control — don't let the stack or DBs yank your elbows out of position."
            ],
            watchFor: "Letting the elbows drift forward or flare — that turns it into a shoulder exercise.",
            pattern: .overheadPress, demoSpeed: 0.85
        ),
        "Bicep Curl": ExerciseGuide(
            cues: [
                "Arms at your sides, elbows glued to your ribs, palms facing forward.",
                "Curl without swinging — only the forearms move; squeeze at the top.",
                "Lower fully under control until the arms are almost straight."
            ],
            watchFor: "Using hip swing or leaning back to finish the rep — drop the weight if you need momentum.",
            pattern: .pullHorizontal, demoSpeed: 0.9
        )
    ]
}
