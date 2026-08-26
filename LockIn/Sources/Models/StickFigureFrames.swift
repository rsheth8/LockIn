import CoreGraphics

/// Keyframe data for every `MovementPattern`.
///
/// Everything here is joint angles in degrees (see `StickFigureRig` for the
/// convention: 0° points straight down, positive rotates toward the direction
/// the figure faces, which is always screen-right). Poses are authored as
/// angles rather than joint positions so bones can't change length between
/// keyframes, and so the anchor can plant the feet exactly on the floor for
/// every in-between frame rather than only at the two ends of a rep.
///
/// A negative elbow or knee value means the joint folds the *other* way in
/// this side-on projection. That isn't anatomical nonsense — it's what a limb
/// rotated out of the picture plane (a back-squat grip, a supine dead bug)
/// actually projects to when you look at it from the side.

private func arm(_ swing: CGFloat, _ bend: CGFloat) -> StickFigureArm { StickFigureArm(swing, bend) }

private func leg(_ hip: CGFloat, _ knee: CGFloat, _ ankle: CGFloat) -> StickFigureLeg {
    StickFigureLeg(hip, knee, ankle)
}

/// A leg whose foot is flat on the floor. The sole is level exactly when the
/// ankle→toe segment sits at `flatFoot` in world terms, so the ankle angle
/// isn't a free choice once the shin angle is picked — deriving it here is
/// what keeps every standing pose's heel and toe on the same line.
private func flatLeg(_ hip: CGFloat, _ knee: CGFloat) -> StickFigureLeg {
    // shin = hip - knee; want footAngle = shin + flatFoot - ankle ≈ flatFoot
    // ⇒ ankle ≈ hip - knee. The −0.4 nudge matches the heel/toe length ratio
    // so both land at the same height (see StickFigureRig.heelSplay).
    StickFigureLeg(hip, knee, hip - knee - 0.4)
}

private func frame(lean: CGFloat = 3, head: CGFloat = 4,
                   _ nearArm: StickFigureArm, _ farArm: StickFigureArm,
                   _ nearLeg: StickFigureLeg, _ farLeg: StickFigureLeg,
                   hip: CGPoint = StickFigureRig.standingHip, lift: CGFloat = 0) -> StickFigurePose {
    StickFigurePose(hip: hip, lean: lean, headTilt: head,
                    nearArm: nearArm, farArm: farArm, nearLeg: nearLeg, farLeg: farLeg, lift: lift)
}

/// Bilateral: the far limbs shadow the near ones a few degrees off, so the
/// hidden side reads as depth instead of vanishing into one flat line.
private func mirrored(lean: CGFloat = 3, head: CGFloat = 4,
                      arms: StickFigureArm, legs: StickFigureLeg,
                      hip: CGPoint = StickFigureRig.standingHip, lift: CGFloat = 0) -> StickFigurePose {
    StickFigurePose(hip: hip, lean: lean, headTilt: head, arms: arms, legs: legs, lift: lift)
}

extension StickFigurePose {
    /// Relaxed standing figure — the shared start/end of most standing lifts.
    static let standing = mirrored(lean: 3, arms: arm(1, 7), legs: flatLeg(0, 4))
}

extension MovementPattern {
    static let frames: [MovementPattern: [StickFigurePose]] = [

        // MARK: Lower body — bilateral

        // High-bar back squat: hips and knees break together, bar path stays
        // over midfoot. Bottom depth = hip crease below knee (~parallel+).
        // Arms locked on the bar behind the neck (negative elbow = out of plane).
        .squat: [
            mirrored(lean: 6, arms: arm(-33, -137), legs: flatLeg(0, 5)),
            mirrored(lean: 18, arms: arm(-33, -137), legs: flatLeg(38, 48)),
            mirrored(lean: 28, arms: arm(-33, -137), legs: flatLeg(68, 82)),
            mirrored(lean: 36, arms: arm(-33, -137), legs: flatLeg(92, 112)),
        ],

        // Romanian deadlift: soft knees, shins nearly vertical, hips travel
        // straight back, bar tracks the thighs to about mid-shin. Arms hang
        // plumb — their swing equals torso lean so the bar stays over midfoot.
        .hinge: [
            mirrored(lean: 4, arms: arm(4, 3), legs: flatLeg(0, 6)),
            mirrored(lean: 28, arms: arm(28, 3), legs: flatLeg(6, 10)),
            mirrored(lean: 48, arms: arm(48, 3), legs: flatLeg(10, 14)),
            mirrored(lean: 68, arms: arm(68, 3), legs: flatLeg(14, 18)),
        ],

        // Conventional deadlift from the floor. The bottom frame is solved
        // backwards from the plate: arms hang plumb (swing == lean), so the
        // hand sits 54 below the shoulder, and the hips have to drop far
        // enough that 54 lands the plate's underside on the ground line. Any
        // shallower and the bar floats in mid-air, which is what the old
        // 78°/94° bottom did.
        .deadlift: [
            mirrored(lean: 3, arms: arm(3, 2), legs: flatLeg(0, 4)),
            mirrored(lean: 26, arms: arm(26, 2), legs: flatLeg(26, 32)),
            mirrored(lean: 44, arms: arm(44, 2), legs: flatLeg(58, 68)),
            mirrored(lean: 58, arms: arm(58, 2), legs: flatLeg(84, 96)),
        ],

        // Single-leg calf raise off a step: working toes stay pinned to the
        // edge; the heel drops below for the stretch, then rises onto the ball
        // of the foot. Non-working leg is tucked so it can't be mistaken for a
        // bilateral raise or a hop.
        .calfRaise: [
            frame(lean: 2, arm(10, 28), arm(-4, 22), leg(0, 3, -36), leg(45, 105, 25)),
            frame(lean: 2, arm(10, 28), arm(-4, 22), leg(0, 3, 0), leg(45, 105, 25)),
            frame(lean: 2, arm(10, 28), arm(-4, 22), leg(0, 2, 42), leg(45, 105, 25)),
        ],

        // Countermovement dip → full extension with arms driving up → brief
        // hang time. Lift is what sells the jump; without it it's just a squat.
        .boxJump: [
            mirrored(lean: 8, arms: arm(-24, 18), legs: flatLeg(0, 5)),
            mirrored(lean: 34, arms: arm(-58, 30), legs: flatLeg(46, 60)),
            frame(lean: 8, arm(160, 12), arm(146, 24), leg(-2, 2, 40), leg(-6, 5, 40), lift: 18),
            frame(lean: 4, arm(172, 10), arm(156, 22), leg(-4, 2, 48), leg(-8, 5, 48), lift: 28),
        ],

        // MARK: Lower body — split stance

        // Walking lunge: front shin near vertical, back knee drops toward the
        // floor, torso stays tall. Near leg = front leg throughout.
        .lunge: [
            frame(lean: 5, arm(-18, 16), arm(18, 16), flatLeg(0, 5), flatLeg(-3, 8)),
            frame(lean: 6, arm(-22, 18), arm(22, 18), flatLeg(36, 40), leg(-8, 36, -6)),
            frame(lean: 6, arm(-26, 20), arm(26, 20), flatLeg(62, 68), leg(-14, 64, -10)),
            frame(lean: 6, arm(-28, 20), arm(28, 20), flatLeg(78, 84), leg(-18, 82, -12)),
        ],

        // Bulgarian / RFE split squat: rear instep parked on the box, nearly
        // all load on the front leg. Front shin stays close to vertical.
        //
        // The rear leg is solved by inverse kinematics against a *fixed* box
        // at (2, 133) — the rear foot has to stay exactly where it was put
        // while the hips travel 22 units past it, and hand-authored angles
        // had it riding 50 units up in mid-air on a table-height prop.
        .splitSquat: [
            frame(lean: 8, arm(-10, 12), arm(10, 12), flatLeg(24, 30), leg(-3, 62, 75)),
            frame(lean: 10, arm(-12, 14), arm(12, 14), flatLeg(48, 58), leg(16, 95, 62)),
            frame(lean: 12, arm(-14, 14), arm(14, 14), flatLeg(72, 86), leg(26, 122, 44)),
        ],

        // Step-up: near foot pinned to the box for the whole rep. Drive comes
        // from the top leg — trailing leg hangs, then tucks as you stand tall.
        .stepUp: [
            frame(lean: 14, arm(-17, 6), arm(-5, 9), flatLeg(88, 112), flatLeg(-2, 4)),
            frame(lean: 12, arm(-15, 6), arm(-3, 9), flatLeg(52, 66), flatLeg(-6, 12)),
            frame(lean: 6, arm(-9, 6), arm(3, 9), flatLeg(8, 10), leg(42, 70, -8)),
            frame(lean: 4, arm(-7, 6), arm(5, 9), flatLeg(2, 5), leg(58, 88, -10)),
        ],

        // Eccentric step-down: standing leg stays on the box, free leg reaches
        // for the floor under control. Hips drop straight — no lateral shunt.
        .stepDown: [
            frame(lean: 6, arm(-8, 20), arm(8, 20), flatLeg(2, 5), leg(24, 30, -6)),
            frame(lean: 12, arm(-12, 24), arm(12, 24), flatLeg(38, 50), leg(20, 20, -4)),
            frame(lean: 16, arm(-14, 28), arm(14, 28), flatLeg(62, 80), leg(16, 10, -2)),
            frame(lean: 20, arm(-16, 30), arm(16, 30), flatLeg(86, 112), leg(12, 4, 0)),
        ],

        // Half-kneeling ankle rock: front heel pinned, knee travels forward
        // over the toes to load dorsiflexion. Back knee stays down.
        .ankleRock: [
            frame(lean: 4, arm(18, 44), arm(22, 48), flatLeg(92, 108), leg(-6, 95, 66)),
            frame(lean: 8, arm(22, 48), arm(26, 52), flatLeg(100, 122), leg(-6, 95, 66)),
            frame(lean: 12, arm(24, 50), arm(28, 54), flatLeg(108, 138), leg(-6, 95, 66)),
        ],

        // Half-kneeling hip-flexor stretch: same base, but the *back* hip opens
        // — glute squeezes, pelvis tucks, torso stays tall or leans slightly back.
        // Total joint travel used to be 11 units across the whole clip, which
        // on screen is indistinguishable from a still image. The tuck is now
        // a 22° swing through the torso with the rear hip opening behind it.
        .hipFlexorStretch: [
            frame(lean: 6, arm(14, 60), arm(18, 64), flatLeg(92, 108), leg(-6, 95, 66)),
            frame(lean: -5, arm(6, 56), arm(10, 60), flatLeg(100, 116), leg(-14, 100, 66)),
            frame(lean: -16, arm(-2, 52), arm(2, 56), flatLeg(108, 124), leg(-22, 105, 66)),
        ],

        // MARK: Pulls and presses

        // Dead hang → chest to bar. Hands pinned; the body travels. Elbows
        // drive down and back; a slight lean-back at the top is honest.
        //
        // Two things this pose has to fight, both of them side-view problems
        // rather than anatomy problems:
        //
        // 1. Arms reaching *straight* up sit exactly on top of the neck and
        //    spine, which in a flat side projection means the arms disappear
        //    into the torso line — the figure read as a head on a stick. The
        //    reach is carried ~12° forward of the spine so the arm is its own
        //    line all the way to the bar. Real hanging arms are near-vertical;
        //    this is the same licence a side-view illustration takes.
        // 2. Knees folded to ~80° (as these were) collapse the whole lower
        //    body into a stub barely longer than a foot. A hanging figure has
        //    to bend its knees to fit under a bar at all, but the fold belongs
        //    at the *hip* — thigh forward, shin hanging back — which keeps both
        //    segments readable and is what a tucked hang actually looks like.
        // 3. Even offset forward, the arm still ran within a head-radius of the
        //    skull. The chin comes back (negative head tilt) to clear it, which
        //    is also just what someone hanging from a bar does — they look up
        //    at it — and it eases back toward level as the chest arrives.
        .pullVertical: [
            frame(lean: 0, head: -22, arm(166, 10), arm(158, 18), leg(34, 68, 18), leg(28, 71, 18)),
            frame(lean: -6, head: -18, arm(144, 46), arm(136, 54), leg(36, 70, 18), leg(30, 73, 18)),
            frame(lean: -11, head: -13, arm(122, 88), arm(114, 96), leg(38, 72, 18), leg(32, 75, 18)),
            frame(lean: -16, head: -8, arm(100, 126), arm(92, 134), leg(40, 74, 18), leg(34, 77, 18)),
        ],

        // Bent-over row: torso fixed ~45°, only the arms move — bar to lower
        // ribs, then full stretch. Soft knees, flat back held the whole time.
        .pullHorizontal: [
            mirrored(lean: 46, arms: arm(46, 2), legs: flatLeg(10, 14)),
            mirrored(lean: 46, arms: arm(12, 56), legs: flatLeg(10, 14)),
            mirrored(lean: 46, arms: arm(-18, 105), legs: flatLeg(10, 14)),
        ],

        // Face pull: elbows stay high, hands finish beside the ears with
        // external rotation. Light weight — the end-range is the point.
        .facePull: [
            mirrored(lean: 3, arms: arm(96, 8), legs: flatLeg(0, 5)),
            mirrored(lean: 3, arms: arm(104, 70), legs: flatLeg(0, 5)),
            mirrored(lean: 3, arms: arm(111, 136), legs: flatLeg(0, 5)),
        ],

        // Push-up: one rigid line from shoulders to heels. Lean and leg angle
        // are equal-and-opposite so that line stays straight at every depth.
        .pushUp: [
            frame(lean: 68, head: -22, arm(68, 0), arm(64, 6), leg(-68, 0, 0), leg(-64, 4, 0)),
            frame(lean: 72, head: -21, arm(52, 40), arm(48, 46), leg(-72, 0, 0), leg(-68, 4, 0)),
            frame(lean: 78, head: -20, arm(34, 92), arm(30, 98), leg(-78, 0, 0), leg(-74, 4, 0)),
        ],

        // Bench press: supine on the bench, bar path from lockout down to the
        // mid-chest. Feet stay planted; hips don't lift.
        .benchPress: [
            frame(lean: -90, head: 0, arm(90, 0), arm(86, 6), leg(98, 89, 8), leg(104, 93, 8),
                  hip: CGPoint(x: 70, y: 116)),
            frame(lean: -90, head: 0, arm(62, 56), arm(58, 62), leg(98, 89, 8), leg(104, 93, 8),
                  hip: CGPoint(x: 70, y: 116)),
            frame(lean: -90, head: 0, arm(34, 112), arm(30, 118), leg(98, 89, 8), leg(104, 93, 8),
                  hip: CGPoint(x: 70, y: 116)),
        ],

        // Strict overhead press: bar starts racked at the shoulders, finishes
        // locked out overhead with a slight lean-back to clear the face.
        .overheadPress: [
            frame(lean: 2, arm(28, 124), arm(20, 132), flatLeg(0, 5), flatLeg(-4, 8)),
            frame(lean: 0, arm(90, 70), arm(80, 78), flatLeg(0, 5), flatLeg(-4, 8)),
            frame(lean: -3, arm(168, 10), arm(154, 20), flatLeg(0, 4), flatLeg(-4, 7)),
        ],

        // MARK: Rotation

        // High-to-low cable woodchop: arms stay long, torso does the rotating.
        // Start high/away, finish low/across — the whole arm line sweeps as one.
        .woodchop: [
            frame(lean: -10, arm(156, 6), arm(152, 10), flatLeg(-2, 4), flatLeg(2, 8)),
            frame(lean: 4, arm(110, 8), arm(106, 12), flatLeg(0, 10), flatLeg(0, 12)),
            frame(lean: 18, arm(60, 10), arm(56, 14), flatLeg(2, 16), flatLeg(2, 18)),
            frame(lean: 32, arm(18, 10), arm(14, 14), flatLeg(4, 22), flatLeg(2, 24)),
        ],

        // Rotational med-ball throw: load away from the wall, fire hips-first,
        // release around hip height, follow through past the target.
        .medBallThrow: [
            frame(lean: -10, arm(-50, 36), arm(-44, 42), flatLeg(-4, 22), flatLeg(8, 16)),
            frame(lean: -2, arm(-10, 30), arm(-6, 34), flatLeg(0, 16), flatLeg(4, 14)),
            frame(lean: 8, arm(40, 22), arm(34, 26), flatLeg(4, 12), flatLeg(2, 12)),
            frame(lean: 20, arm(108, 8), arm(102, 12), flatLeg(12, 12), leg(-4, 28, 8)),
        ],

        // Quadruped open-book: hands and knees planted, free arm opens to the
        // ceiling and the eyes follow — hips stay still.
        .thoracicRotation: [
            frame(lean: 63, head: 28, arm(63, 0), arm(63, 0), leg(-5, 85, 66), leg(-9, 88, 66),
                  hip: CGPoint(x: 34, y: 112)),
            frame(lean: 63, head: 0, arm(150, 26), arm(63, 0), leg(-5, 85, 66), leg(-9, 88, 66),
                  hip: CGPoint(x: 34, y: 112)),
            frame(lean: 63, head: -36, arm(238, 34), arm(63, 0), leg(-5, 85, 66), leg(-9, 88, 66),
                  hip: CGPoint(x: 34, y: 112)),
        ],

        // Fast-bowling delivery (side-on): gather → front-foot brace → bowling
        // arm (near) over the top while the front foot stays planted → follow-
        // through across the braced front side. The planted front foot during
        // the overhead frame is what separates this from a jump.
        .bowlingAction: [
            frame(lean: 14, arm(-55, 42), arm(45, 48), leg(38, 64, -4), leg(-30, 50, 20), lift: 3),
            frame(lean: 10, arm(-115, 22), arm(125, 28), flatLeg(52, 26), leg(-36, 72, 16)),
            // Release — front foot planted, bowling arm vertical, front arm pulling down
            frame(lean: 8, arm(-175, 4), arm(35, 70), flatLeg(16, 14), leg(-22, 86, 22)),
            // Follow-through across the braced front side
            frame(lean: 30, arm(55, 28), arm(-35, 36), flatLeg(4, 18), leg(-12, 96, 26)),
        ],

        // MARK: Gait

        // Easy jog: modest lean, mid foot strike, opposite arm/leg, brief
        // float between contacts. Four frames = one full stride cycle.
        .jog: [
            frame(lean: 7, arm(-28, 82), arm(30, 78), flatLeg(2, 10), leg(28, 74, -6)),
            frame(lean: 7, arm(-34, 76), arm(36, 86), leg(-28, 26, 26), leg(34, 22, -2), lift: 4),
            frame(lean: 7, arm(30, 78), arm(-28, 82), leg(28, 74, -6), flatLeg(2, 10)),
            frame(lean: 7, arm(36, 86), arm(-34, 76), leg(34, 22, -2), leg(-28, 26, 26), lift: 4),
        ],

        // Sprint: bigger lean, higher knee drive, longer stride, more float,
        // arms pumping harder — same cycle structure as the jog, different
        // amplitudes so the two clips don't read as the same animation sped up.
        .sprint: [
            frame(lean: 18, arm(-50, 94), arm(56, 88), leg(8, 18, 6), leg(62, 108, -12)),
            frame(lean: 18, arm(-62, 86), arm(68, 98), leg(-46, 36, 36), leg(52, 28, 0), lift: 12),
            frame(lean: 18, arm(56, 88), arm(-50, 94), leg(62, 108, -12), leg(8, 18, 6)),
            frame(lean: 18, arm(68, 98), arm(-62, 86), leg(52, 28, 0), leg(-46, 36, 36), lift: 12),
        ],

        // Loaded ruck walk: no float phase, shorter stride, taller posture —
        // the pack is the point, so it rides high on the back.
        .ruckWalk: [
            frame(lean: 6, arm(-16, 26), arm(18, 24), flatLeg(4, 8), leg(16, 34, -4)),
            frame(lean: 6, arm(-20, 24), arm(22, 28), leg(-16, 14, 18), flatLeg(22, 10)),
            frame(lean: 6, arm(18, 24), arm(-16, 26), leg(16, 34, -4), flatLeg(4, 8)),
            frame(lean: 6, arm(22, 28), arm(-20, 24), flatLeg(22, 10), leg(-16, 14, 18)),
        ],

        // Farmer's carry: arms locked straight at the sides with dumbbells,
        // ribs stacked over hips. The walk is small; the posture is the work.
        // The near and far hands used to hang within 4° of each other, so the
        // two dumbbells drew as one blob straddling the thigh. Splitting the
        // swing puts daylight between them without either arm leaving the side.
        .carry: [
            frame(lean: 2, arm(8, 2), arm(-9, 3), flatLeg(4, 8), leg(14, 30, -4)),
            frame(lean: 2, arm(8, 2), arm(-9, 3), leg(-14, 12, 16), flatLeg(20, 10)),
            frame(lean: 2, arm(8, 2), arm(-9, 3), leg(14, 30, -4), flatLeg(4, 8)),
            frame(lean: 2, arm(8, 2), arm(-9, 3), flatLeg(20, 10), leg(-14, 12, 16)),
        ],

        // MARK: Core and floor work

        // Forearm plank: elbows under shoulders, one line head-to-heels. The
        // "motion" is a brace pulse — honest to what a plank actually is.
        .plank: [
            frame(lean: 84, head: -27, arm(84, 90), arm(81, 94), leg(-84, 2, 0), leg(-81, 5, 0)),
            frame(lean: 79, head: -23, arm(79, 90), arm(76, 94), leg(-79, 0, 0), leg(-76, 3, 0)),
        ],

        // Dead bug: supine, knees stacked over hips, then opposite arm and leg
        // reach away without the lumbar peeling up.
        //
        // Two things the first cut got wrong. The hip sat 2 units off the
        // floor, which put a supine head — a circle centred on the spine —
        // six units *through* it. And the limbs that move were the far ones,
        // drawn in light ink, so the only thing animating was the faintest
        // part of the picture. Now the body lies a head-radius clear of the
        // floor and the near leg is the one that extends.
        .deadBug: [
            frame(lean: -90, head: 0,
                  arm(90, 4), arm(84, 10),
                  leg(180, 90, 16), leg(174, 96, 16),
                  hip: CGPoint(x: 74, y: StickFigureRig.ground - 9)),
            frame(lean: -90, head: 0,
                  arm(90, 4), arm(116, 10),
                  leg(156, 64, 13), leg(174, 96, 16),
                  hip: CGPoint(x: 74, y: StickFigureRig.ground - 9)),
            frame(lean: -90, head: 0,
                  arm(90, 4), arm(142, 16),
                  leg(135, 40, 10), leg(174, 96, 16),
                  hip: CGPoint(x: 74, y: StickFigureRig.ground - 9)),
        ],

        // Bird dog: quadruped, then opposite arm and leg to horizontal without
        // the hips rolling open. Return is the other half of the ping-pong.
        .birdDog: [
            frame(lean: 63, head: 24, arm(63, 0), arm(63, 0), leg(-5, 85, 66), leg(-9, 88, 66),
                  hip: CGPoint(x: 34, y: 112)),
            frame(lean: 63, head: 12, arm(110, 0), arm(63, 0), leg(-5, 85, 66), leg(-50, 40, 40),
                  hip: CGPoint(x: 34, y: 112)),
            frame(lean: 63, head: 6, arm(158, 0), arm(63, 0), leg(-5, 85, 66), leg(-90, 0, 18),
                  hip: CGPoint(x: 34, y: 112)),
        ],

        // Mountain climber: straight-arm plank with alternating knee drives.
        // Cycle loop so it doesn't reverse mid-stride.
        .mountainClimber: [
            frame(lean: 69, head: -22, arm(69, 0), arm(65, 6), leg(60, 110, 0), leg(-65, 4, 0)),
            frame(lean: 69, head: -22, arm(69, 0), arm(65, 6), leg(-10, 56, 0), leg(-30, 58, 0)),
            frame(lean: 69, head: -22, arm(69, 0), arm(65, 6), leg(-69, 0, 0), leg(60, 110, 0)),
            frame(lean: 69, head: -22, arm(69, 0), arm(65, 6), leg(-30, 58, 0), leg(-10, 56, 0)),
        ],

        // Pallof press: cable trying to twist the torso; pressed-out position
        // is the hardest moment to resist. Soft athletic stance throughout.
        .pallofPress: [
            mirrored(lean: 2, arms: arm(74, 96), legs: flatLeg(6, 20)),
            mirrored(lean: 2, arms: arm(82, 50), legs: flatLeg(6, 20)),
            mirrored(lean: 2, arms: arm(90, 4), legs: flatLeg(6, 20)),
        ],

        // Glute bridge: shoulders and the back of the head stay on the floor;
        // only the hips travel. Top = full hip extension, ribs down.
        //
        // Arm swings track the torso so the arms stay flat along the floor at
        // every height (swing == lean puts the world angle back at 90°), and
        // the legs are solved to hold the heels on one spot while the hips
        // rise 25 units past them.
        .gluteBridge: [
            frame(lean: -90, head: 0, arm(0, 4), arm(-5, 8), flatLeg(133, 93), flatLeg(129, 89),
                  hip: CGPoint(x: 68, y: 143.5)),
            frame(lean: -120, head: 34, arm(-30, 4), arm(-35, 8), flatLeg(108, 75), flatLeg(104, 71),
                  hip: CGPoint(x: 64, y: 127)),
            frame(lean: -149, head: 69, arm(-59, 4), arm(-64, 8), flatLeg(75, 35), flatLeg(71, 31),
                  hip: CGPoint(x: 60, y: 110)),
        ],

        // Hip thrust: shoulders up on a bench, bar across the hips — longer
        // range than a floor bridge. Top is a straight shoulder-hip-knee line.
        .hipThrust: [
            frame(lean: -62, head: 0, arm(28, 6), arm(24, 10), leg(123, 105, 18), leg(119, 101, 18),
                  hip: CGPoint(x: 66, y: 132)),
            frame(lean: -76, head: 0, arm(14, 6), arm(10, 10), leg(106, 94, 12), leg(102, 90, 12),
                  hip: CGPoint(x: 66, y: 122)),
            frame(lean: -90, head: 0, arm(0, 6), arm(-4, 10), leg(91, 83, 8), leg(87, 79, 8),
                  hip: CGPoint(x: 66, y: 112)),
        ],

        // Generic isometric fallback: tall, braced, ribs down, slow pulse.
        .hold: [
            mirrored(lean: 6, arms: arm(9, 20), legs: flatLeg(7, 14)),
            mirrored(lean: 0, arms: arm(2, 10), legs: flatLeg(0, 4)),
        ],
    ]
}
