import Foundation

/// How to perform every movement `WorkoutEngine` can prescribe.
///
/// Keyed by exercise **name**, matching `ExercisePrescription.name` exactly.
/// `ExerciseLibraryTests` walks every split and fails if any prescribed
/// exercise has no entry — so a new movement can't ship without instructions.
///
/// The content is deliberately specific about failure modes. "Use good form"
/// has never fixed anyone's knees caving in; "spread the floor with your feet"
/// sometimes does.
enum ExerciseLibrary {

    static func guide(for exerciseName: String) -> ExerciseGuide? {
        guides[exerciseName]
    }

    static var allNames: [String] { guides.keys.sorted() }

    private static let guides: [String: ExerciseGuide] = [

        // MARK: - Lower body strength

        "Barbell Back Squat": ExerciseGuide(
            setup: [
                "Bar across the meat of your upper back — on the rear delts, never on the neck bones.",
                "Hands just outside the shoulders, elbows pointing down rather than flared back.",
                "Feet shoulder-width, toes turned out 15–30°.",
                "Big breath into the belly and brace like you're about to take a punch. Hold it for the whole rep."
            ],
            execution: [
                "Break at the hips and knees at the same time — sit down between your hips, not backwards onto a chair.",
                "Keep the bar stacked over the middle of your foot the whole way.",
                "Go down until the hip crease passes below the top of the knee, or as deep as you can hold a flat back.",
                "Drive up through the whole foot, hips and chest rising together."
            ],
            cues: ["Spread the floor with your feet", "Ribs down, chest proud", "Knees out over the toes"],
            mistakes: [
                "Knees caving inward — that's the position that stresses the MCL and ACL. Push them out against the arch of your foot.",
                "Heels lifting: usually ankle mobility. Try lifting shoes with a raised heel, or widen your stance.",
                "Letting the breath go at the bottom. The brace is what keeps your lower back neutral under load."
            ],
            tempo: .lower(2, drive: 1, driveLabel: "Stand up"),
            swap: "No rack? Goblet squat holding one heavy dumbbell at the chest — same pattern, self-limiting load.",
            searchTerm: "barbell back squat form"
        ),

        "Romanian Deadlift": ExerciseGuide(
            setup: [
                "Start standing with the bar at the top, touching your thighs.",
                "Feet hip-width. Bend the knees slightly once, then keep that same angle for every rep.",
                "Pull the shoulders back and squeeze your armpits tight to lock the lats on."
            ],
            execution: [
                "Push the hips straight back and let the bar slide down your legs, staying in contact.",
                "Stop when you feel a strong hamstring stretch or your lower back starts to round — usually mid-shin.",
                "Drive the hips forward to stand up. Squeeze the glutes at the top; don't lean back."
            ],
            cues: ["Hips back, not down", "Drag the bar up your legs", "Long spine from head to tail"],
            mistakes: [
                "Turning it into a squat by bending the knees on the way down — this is a hip hinge, the knees stay put.",
                "Letting the bar drift away from your legs. Every inch forward multiplies the load on your lower back.",
                "Chasing depth past your hamstring flexibility and rounding to get there. Range is earned, not forced."
            ],
            tempo: .lower(3, drive: 1, downLabel: "Hinge back", driveLabel: "Stand tall"),
            swap: "Dumbbell RDL, or single-leg RDL if your lower back is cranky — less load, more balance demand.",
            searchTerm: "romanian deadlift form"
        ),

        "Walking Lunge": ExerciseGuide(
            setup: [
                "Stand tall, dumbbells at your sides or a bar on the back.",
                "Pick a clear lane — you're travelling, not stepping back to the start."
            ],
            execution: [
                "Step forward far enough that both knees can reach roughly 90°.",
                "Lower until the back knee is just off the floor.",
                "Push through the front heel to stand, then step straight through into the next rep."
            ],
            cues: ["Torso tall", "Front heel drives", "Land soft"],
            mistakes: [
                "Steps too short, which pushes the front knee way past the toes and loads the kneecap.",
                "Letting the front knee collapse inward as you stand up.",
                "Leaning the torso forward to help — that turns it into a bad Good Morning."
            ],
            tempo: .lower(2, drive: 1, downLabel: "Sink", driveLabel: "Push through"),
            swap: "Reverse lunges in place if you're short on room, or split squats if balance is the limit.",
            searchTerm: "walking lunge form"
        ),

        "Weighted Step-Up": ExerciseGuide(
            setup: [
                "Box or bench at roughly knee height — higher demands more hip, lower more knee.",
                "Dumbbells at your sides. Place the whole working foot on the box."
            ],
            execution: [
                "Drive through the top foot to stand up. The bottom leg does nothing — don't push off the floor.",
                "Stand fully upright on the box.",
                "Lower under control until the trailing foot touches, then go again."
            ],
            cues: ["All the weight on the top foot", "No push off the back leg", "Control the way down"],
            mistakes: [
                "Bouncing off the trailing foot, which is where most of the work quietly goes.",
                "Dropping down rather than lowering — you're skipping the eccentric, which is most of the point.",
                "Box too high, so you lean forward and turn it into a hip hinge."
            ],
            tempo: .lower(3, drive: 1, downLabel: "Lower", driveLabel: "Step up"),
            swap: "A staircase and a backpack works. So does a lower box with a slower descent.",
            searchTerm: "weighted step up exercise form"
        ),

        // MARK: - Rotational power

        "Rotational Med Ball Throw": ExerciseGuide(
            setup: [
                "Stand side-on to a solid wall, about an arm's length plus a step away.",
                "Feet a bit wider than the shoulders, ball held at the chest.",
                "Use a wall you're allowed to hit — this is meant to be thrown hard."
            ],
            execution: [
                "Load into the back hip, letting the trunk wind up behind the hips.",
                "Drive the back hip through first, then let the shoulders follow and release the ball into the wall.",
                "Catch or collect it, reset fully, and repeat. Every rep is maximum intent."
            ],
            cues: ["Hips lead, shoulders follow", "Throw it through the wall", "Reset every rep"],
            mistakes: [
                "Turning shoulders and hips together as one block — the hip-shoulder separation *is* the exercise.",
                "Going submaximal to get the reps done. This is a power lift; a slow rep trains nothing here.",
                "Rushing the reset and losing the position."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Load back hip", seconds: 2),
                .init(label: "Explode", seconds: 0.5),
                .init(label: "Reset", seconds: 3)
            ]),
            swap: "No ball or wall? A resistance band anchored at chest height, same rotation, same intent.",
            searchTerm: "rotational medicine ball throw cricket"
        ),

        "Cable Woodchop": ExerciseGuide(
            setup: [
                "Cable set high. Stand side-on, far enough away that the stack stays lifted at the start.",
                "Grip the handle with both hands, arms nearly straight.",
                "Feet planted wider than the shoulders."
            ],
            execution: [
                "Rotate through the trunk and pull the handle down and across to the opposite hip.",
                "Let the back heel pivot — forcing the foot flat grinds the knee.",
                "Return under control, resisting the rotation on the way back."
            ],
            cues: ["Arms stay long", "Turn the ribcage, not just the arms", "Slow on the way back"],
            mistakes: [
                "Yanking with the arms and shoulders instead of rotating the torso.",
                "Locking the back foot flat so the rotation is forced through the knee.",
                "Letting the weight snap you back to the start — the return is half the work."
            ],
            tempo: .lower(1, drive: 3, downLabel: "Chop across", driveLabel: "Resist back"),
            swap: "A resistance band over a door anchor. Same movement, same tension curve.",
            searchTerm: "cable woodchop exercise form"
        ),

        "Bowling-Action Shadow Reps (no ball)": ExerciseGuide(
            setup: [
                "Space to move through a couple of walking strides. No ball, no run-up.",
                "Start from your normal delivery stride position."
            ],
            execution: [
                "Walk through the action at maybe half speed: back foot lands, front foot braces, hips rotate, arm comes over.",
                "Hold the front-foot-contact position for a beat and feel where your trunk actually is.",
                "Focus on a braced front leg and a tall trunk rather than arm speed."
            ],
            cues: ["Front leg braces, doesn't collapse", "Stay tall through contact", "Slow enough to feel it"],
            mistakes: [
                "Doing it at full speed, which turns a technique drill into extra bowling workload.",
                "Letting the trunk hyperextend and side-flex hard — that combined position is exactly what drives lumbar bone stress.",
                "Adding a ball. The moment you're bowling, this counts against your weekly bowling load."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Approach", seconds: 2),
                .init(label: "Hold contact", seconds: 2),
                .init(label: "Follow through", seconds: 2)
            ]),
            swap: "If your back is sore, skip it entirely this week and do the Pallof press instead.",
            searchTerm: "fast bowling action technique drill"
        ),

        // MARK: - Conditioning

        "Run-up Length Sprints": ExerciseGuide(
            setup: [
                "Measure out your real bowling run-up and mark both ends.",
                "Warm up properly first — at least five minutes easy plus a few build-ups. Cold sprints tear hamstrings."
            ],
            execution: [
                "Accelerate the way you do when bowling, not from blocks.",
                "Hit full speed by the end of the marked distance.",
                "Walk back slowly. That walk is the rest interval."
            ],
            cues: ["Build like a run-up, not a race start", "Tall posture", "Full recovery between reps"],
            mistakes: [
                "Skipping the warm-up. Almost every sprint hamstring injury happens cold or fatigued.",
                "Cutting the rest short, which turns speed work into conditioning and drops the quality.",
                "Doing these the day before you bowl a long spell."
            ],
            tempo: nil,
            swap: "Hill sprints if you're worried about hamstrings — the incline caps top speed and lowers the risk.",
            searchTerm: "sprint technique acceleration drill"
        ),

        "Repeat Sprint Sets": ExerciseGuide(
            setup: [
                "Mark 20 m. Have a clock or a timer you can see.",
                "Come into this fresh enough to hold your times."
            ],
            execution: [
                "Sprint 20 m, walk or jog back inside the 20-second rest, go again.",
                "Complete the set of reps, then take a full rest before the next set.",
                "Track roughly how the last rep compares to the first."
            ],
            cues: ["Even effort across reps", "Breathe on the walk back", "Hold your times"],
            mistakes: [
                "Going too hard on the first two and crawling through the rest — the point is repeatability, which is what a bowling spell demands.",
                "Stretching the rest until it becomes pure speed work.",
                "Running these on a hard surface in worn shoes."
            ],
            tempo: nil,
            swap: "A bike or rower with the same work-to-rest ratio if your legs need a break from impact.",
            searchTerm: "repeat sprint ability training"
        ),

        "Easy Jog Recovery": ExerciseGuide(
            setup: ["Nothing to set up. Straight into it after the hard work."],
            execution: [
                "Jog at a pace where you could hold a conversation without gasping.",
                "Let the breathing come back down. That's the whole objective."
            ],
            cues: ["Conversational", "Relaxed shoulders"],
            mistakes: ["Treating it as another interval. If it's hard, it isn't recovery."],
            tempo: nil,
            swap: "A brisk walk does the same job.",
            searchTerm: "active recovery jog"
        ),

        "Weighted Ruck Walk": ExerciseGuide(
            setup: [
                "Pack loaded to about 10–15% of your bodyweight, weight sitting high and close to your back.",
                "Straps tight enough that the load doesn't swing.",
                "Shoes you'd actually hike in."
            ],
            execution: [
                "Walk at a steady, purposeful pace. You should be able to talk but not sing.",
                "Keep the torso tall — leaning forward under the pack is what wrecks lower backs over an hour.",
                "Add incline before you add weight."
            ],
            cues: ["Tall through the chest", "Steady rhythm", "Incline before load"],
            mistakes: [
                "Jumping the weight up too fast. The connective tissue adapts far slower than the muscle does.",
                "A loose pack that swings and shears at your shoulders.",
                "Loading the bottom of the pack, which pulls you backwards and into a forward lean."
            ],
            tempo: nil,
            swap: "Incline treadmill at 10–15% with a pack, or stairs, if the weather's against you.",
            searchTerm: "rucking technique beginner"
        ),

        "Zone 2 Effort": ExerciseGuide(
            setup: ["Any steady cardio — walk, jog, bike, row.", "Give it enough time to be worth doing; 30 minutes minimum."],
            execution: [
                "Hold an effort where you could speak a full sentence but would rather not.",
                "If you use heart rate, that's roughly 60–70% of your max.",
                "Keep it steady. No surges."
            ],
            cues: ["Full sentences, reluctantly", "Boring on purpose"],
            mistakes: [
                "Drifting up into moderate intensity, which is the classic mistake — too hard to build the aerobic base, too easy to be a real interval session.",
                "Cutting it short. The duration is the stimulus."
            ],
            tempo: nil,
            swap: "Any modality you'll actually keep doing for 45 minutes.",
            searchTerm: "zone 2 training explained"
        ),

        // MARK: - Unilateral legs

        "Bulgarian Split Squat": ExerciseGuide(
            setup: [
                "Back foot on a bench roughly knee height, laces down or toes tucked — whichever your ankle prefers.",
                "Front foot far enough forward that the front shin stays near vertical at the bottom.",
                "Dumbbells at your sides."
            ],
            execution: [
                "Lower straight down until the back knee is just above the floor.",
                "Keep about 90% of the weight through the front foot.",
                "Drive through the front heel to stand."
            ],
            cues: ["Straight down, not forward", "Front heel glued", "Back leg is a kickstand"],
            mistakes: [
                "Front foot too close, which jams the knee forward and lights up the kneecap.",
                "Pushing off the back foot — it's there for balance, not drive.",
                "Rushing. This one punishes sloppy tempo more than almost anything else."
            ],
            tempo: .lower(3, drive: 1),
            swap: "Split squat with the back foot on the floor — same pattern, far easier to balance.",
            searchTerm: "bulgarian split squat form"
        ),

        "Step-Down (eccentric focus)": ExerciseGuide(
            setup: [
                "Stand on a box or step, one foot at the edge, the other hanging free off the side.",
                "Start low — 6 to 8 inches. This is harder than it looks.",
                "Hands out in front for balance."
            ],
            execution: [
                "Bend the standing knee and lower the free heel slowly toward the floor.",
                "Tap the heel lightly — no weight through it.",
                "Stand back up through the working leg."
            ],
            cues: ["Three seconds down", "Tap, don't land", "Knee tracks over the second toe"],
            mistakes: [
                "Dropping down instead of lowering. The controlled descent is the entire exercise — it's what trains your knees for downhill trail.",
                "Pushing off the tapping foot to stand up.",
                "Letting the standing knee dive inward at the bottom."
            ],
            tempo: .lower(3, hold: 1, drive: 1, downLabel: "Lower", driveLabel: "Stand"),
            swap: "Lower the step, or hold a rail, until you can control the descent for three full seconds.",
            searchTerm: "eccentric step down exercise knee"
        ),

        "Single-Leg Calf Raise": ExerciseGuide(
            setup: [
                "Ball of one foot on a step, heel hanging off the back.",
                "Fingertips on a wall for balance only — don't hold your weight.",
                "Other foot hooked behind the working ankle."
            ],
            execution: [
                "Rise as high as you can onto the ball of the foot.",
                "Pause briefly at the top.",
                "Lower slowly until you feel a full stretch through the calf."
            ],
            cues: ["All the way up, all the way down", "Pause at the top", "Don't lean on the wall"],
            mistakes: [
                "Short range at the bottom, which skips the stretch where most of the adaptation lives.",
                "Bouncing on the Achilles rather than controlling the descent.",
                "Rolling out onto the little toe at the top."
            ],
            tempo: .lower(3, drive: 1, downLabel: "Lower into stretch", driveLabel: "Rise"),
            swap: "Both feet at once if single-leg is too much, or hold a dumbbell if it's too easy.",
            searchTerm: "single leg calf raise form"
        ),

        // MARK: - Upper pull

        "Pull-Up / Lat Pulldown": ExerciseGuide(
            setup: [
                "Grip slightly wider than the shoulders, palms forward.",
                "For pulldowns, thighs locked under the pad. For pull-ups, hang fully with the shoulders active, not slack.",
                "Ribs down, a slight lean back — not a full swing."
            ],
            execution: [
                "Start by pulling the shoulder blades down and back, before the elbows bend.",
                "Drive the elbows down toward your back pockets until the bar reaches roughly the collarbone.",
                "Control the way back to a full stretch at the top."
            ],
            cues: ["Elbows to the back pockets", "Chest to the bar", "Full stretch at the top"],
            mistakes: [
                "Pulling with the arms first, which leaves the lats mostly out of it. Shoulder blades move first.",
                "Kipping or swinging to grind out extra reps once you're fatigued.",
                "Cutting the top short and losing the stretch — that's half the range gone."
            ],
            tempo: .lower(3, drive: 1, downLabel: "Lower", driveLabel: "Pull"),
            swap: "Band-assisted pull-ups, or an inverted row under a bar set at hip height.",
            searchTerm: "pull up lat pulldown form"
        ),

        "Barbell Row": ExerciseGuide(
            setup: [
                "Hinge at the hips until the torso is 15–45° above horizontal, knees soft.",
                "Bar hanging under the shoulders, grip just outside the knees.",
                "Brace hard. A rounded lower back here is the classic way to hurt yourself."
            ],
            execution: [
                "Pull the bar to somewhere between the navel and the lower ribs.",
                "Lead with the elbows, squeezing the shoulder blades together at the top.",
                "Lower under control without letting the torso rise."
            ],
            cues: ["Elbows past the ribs", "Torso stays still", "Squeeze at the top"],
            mistakes: [
                "Standing up a little on each rep to help the bar — if the torso is moving, the weight is too heavy.",
                "Letting the lower back round, especially on the last few reps.",
                "Yanking with the biceps instead of driving the elbows back."
            ],
            tempo: .lower(2, drive: 1, downLabel: "Lower", driveLabel: "Row"),
            swap: "Chest-supported dumbbell row or a seated cable row if your lower back is already taxed.",
            searchTerm: "barbell row form"
        ),

        "Face Pull": ExerciseGuide(
            setup: [
                "Rope on a cable set at roughly face height.",
                "Grip with thumbs pointing back at you, palms facing each other.",
                "Step back until there's tension with the arms straight."
            ],
            execution: [
                "Pull the rope toward your forehead, splitting the two ends apart as you go.",
                "Finish with the hands beside your ears and the knuckles pointing behind you.",
                "Return slowly, keeping the shoulders down."
            ],
            cues: ["Pull it apart, not just back", "Hands beside the ears", "Shoulders down, not shrugged"],
            mistakes: [
                "Going too heavy, which turns it into a bad upright row and does the opposite of what it's for.",
                "Shrugging the traps up to move the weight.",
                "Pulling to the chest instead of the face — that's a row, not a face pull."
            ],
            tempo: .lower(2, hold: 1, drive: 1, downLabel: "Return", driveLabel: "Pull apart"),
            swap: "A resistance band around any solid anchor works just as well here.",
            searchTerm: "face pull exercise form rotator cuff"
        ),

        "Farmer's Carry": ExerciseGuide(
            setup: [
                "A heavy dumbbell or kettlebell in each hand, picked up with a hinge, not a bent-back scoop.",
                "Stand fully tall before the first step.",
                "Know your route before you start."
            ],
            execution: [
                "Walk at a steady pace with the shoulders pulled back and down.",
                "Keep the ribs down and don't let the weight tip you side to side.",
                "Set them down under control — don't just drop them."
            ],
            cues: ["Tall and stacked", "Squeeze the handles", "Small, quick steps"],
            mistakes: [
                "Leaning back to counterbalance, which loads the lower back for the whole walk.",
                "Letting the shoulders round forward under the load.",
                "Choosing a weight your grip fails at in ten seconds — grip should be the limit at the end, not the start."
            ],
            tempo: nil,
            swap: "One heavy weight on one side only (a suitcase carry) if you're short on dumbbells — great anti-lean work.",
            searchTerm: "farmers carry form"
        ),

        // MARK: - Core

        "Pallof Press": ExerciseGuide(
            setup: [
                "Cable or band anchored at chest height. Stand side-on.",
                "Both hands on the handle, held at the sternum.",
                "Step away until there's real tension trying to rotate you. Feet shoulder-width, knees soft."
            ],
            execution: [
                "Press the handle straight out in front of your chest.",
                "Hold for a beat while the cable tries to twist you — refuse to let it.",
                "Bring it back to the chest under control."
            ],
            cues: ["Don't let it turn you", "Ribs down, glutes on", "Press straight, not across"],
            mistakes: [
                "Letting the torso rotate toward the anchor — the whole exercise is *not* rotating.",
                "Standing too close, so there's no tension to resist.",
                "Holding the breath. Breathe normally through the hold; that's part of the skill."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Press out", seconds: 1),
                .init(label: "Resist", seconds: 3),
                .init(label: "Return", seconds: 1)
            ]),
            swap: "A resistance band around a post. This is one of the easiest exercises to set up anywhere.",
            searchTerm: "pallof press form anti rotation"
        ),

        "Dead Bug": ExerciseGuide(
            setup: [
                "On your back, arms straight up over the shoulders, hips and knees bent to 90°.",
                "Press your lower back flat into the floor. There should be no gap under it.",
                "That flat back is the position you're protecting for every rep."
            ],
            execution: [
                "Slowly lower one arm overhead and the opposite leg toward the floor.",
                "Go only as far as you can without the lower back lifting off the ground.",
                "Return and swap sides. Exhale as you extend."
            ],
            cues: ["Lower back glued to the floor", "Exhale on the way out", "Slow beats far"],
            mistakes: [
                "Letting the back arch as the leg extends — the moment there's a gap under your spine, you've gone too far.",
                "Rushing through reps. This is a control drill, not a burner.",
                "Holding the breath, which makes the brace harder to keep."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Extend", seconds: 2),
                .init(label: "Return", seconds: 2)
            ]),
            swap: "Keep the arms still and move only the legs until you can hold the flat back reliably.",
            searchTerm: "dead bug exercise form"
        ),

        "Front Plank": ExerciseGuide(
            setup: [
                "Forearms on the floor under the shoulders, elbows bent 90°.",
                "Legs straight, weight on the toes.",
                "Body in one line from the ears to the heels."
            ],
            execution: [
                "Squeeze the glutes and tuck the ribs down so the lower back flattens slightly.",
                "Push the floor away to spread the shoulder blades.",
                "Breathe steadily. Hold until form breaks, not until the clock says so."
            ],
            cues: ["Squeeze the glutes", "Ribs down", "Push the floor away"],
            mistakes: [
                "Hips sagging, which turns a core exercise into a lower-back stretch.",
                "Hips too high, which quietly makes it easier.",
                "Chasing long holds. Thirty hard seconds beats three soft minutes."
            ],
            tempo: nil,
            swap: "Knees down, same line through the body, if you can't hold the position for the full time.",
            searchTerm: "front plank form"
        ),

        // MARK: - Mobility

        "Thoracic Spine Rotation Drill": ExerciseGuide(
            setup: [
                "Kneel and sit back onto your heels — this locks the lower back so the rotation has to come from the upper back.",
                "One hand behind the head, the other flat on the floor in front."
            ],
            execution: [
                "Rotate the elbow of the raised arm up toward the ceiling, following it with your eyes.",
                "Pause at the end range and take a breath into the ribs.",
                "Return slowly and repeat, then swap sides."
            ],
            cues: ["Sit on the heels", "Follow the elbow with your eyes", "Breathe at the end range"],
            mistakes: [
                "Rotating from the lower back instead of the ribcage — sitting on the heels is what prevents that.",
                "Forcing the range instead of breathing into it.",
                "Speeding through. Mobility work responds to time, not reps."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Rotate open", seconds: 2),
                .init(label: "Breathe", seconds: 3),
                .init(label: "Return", seconds: 2)
            ]),
            swap: "Open-book rotations lying on your side if kneeling bothers your knees.",
            searchTerm: "thoracic spine rotation mobility drill"
        ),

        "Hip Flexor + 90/90 Stretch": ExerciseGuide(
            setup: [
                "Hip flexor: half-kneeling, back toe tucked, front foot flat.",
                "90/90: seated with the front leg bent 90° in front and the back leg bent 90° out to the side."
            ],
            execution: [
                "Hip flexor: tuck the pelvis under and squeeze the back glute, then shift forward slightly. You should feel the front of the back hip.",
                "90/90: sit tall, then lean over the front shin to deepen it.",
                "Hold each for the prescribed time, breathing slowly."
            ],
            cues: ["Tuck the pelvis first", "Squeeze the back glute", "Sit tall before you lean"],
            mistakes: [
                "Lunging forward without tucking the pelvis, which just arches the lower back and stretches nothing.",
                "Rounding the spine in the 90/90 instead of hinging from the hip.",
                "Holding your breath — the nervous system won't let range go while you're braced."
            ],
            tempo: nil,
            swap: "Couch stretch against a wall for a stronger hip flexor version.",
            searchTerm: "couch stretch 90 90 hip mobility"
        ),

        "Ankle Dorsiflexion Drill": ExerciseGuide(
            setup: [
                "Half-kneeling with the working foot flat and a wall about a hand's width in front of the toes.",
                "Foot pointing straight at the wall."
            ],
            execution: [
                "Drive the knee forward over the toes toward the wall, keeping the heel down.",
                "Touch the wall if you can, hold for a second, return.",
                "Move the foot back a little further each time you can reach it."
            ],
            cues: ["Heel stays down", "Knee over the second toe", "Move back as you improve"],
            mistakes: [
                "Letting the heel lift, which fakes the range you're trying to build.",
                "Collapsing the arch inward to reach further.",
                "Doing it once. This one only responds to being done often."
            ],
            tempo: MovementTempo(phases: [
                .init(label: "Knee forward", seconds: 2),
                .init(label: "Hold", seconds: 1),
                .init(label: "Return", seconds: 1)
            ]),
            swap: "Do it standing with the foot on a low step if kneeling is uncomfortable.",
            searchTerm: "ankle dorsiflexion knee to wall drill"
        )
    ]
}
