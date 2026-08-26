import CoreGraphics
import Foundation

// MARK: - Props

/// Equipment and scenery drawn alongside the figure. A bar, a box or a cable
/// is often what separates two movements that put the body in nearly the same
/// shape — a step-up from a lunge, a hip thrust from a glute bridge — so props
/// aren't decoration here, they're half the read.
///
/// Anything the figure *holds* is positioned from the live frame so it tracks
/// the hands; anything the figure *stands on* is positioned from the pattern's
/// reference frame, so a box can't drift mid-rep.
enum StickFigureProp: Equatable {
    case ground
    /// A platform the near foot works from — a step, a plyo box. Extents are
    /// measured forward/back from the reference frame's near toe.
    case platformUnderNearFoot(back: CGFloat, front: CGFloat)
    /// Same, for the far foot: the bench a rear-foot-elevated split squat uses.
    case platformUnderFarFoot(back: CGFloat, front: CGFloat)
    /// A flat bench under the reference frame's torso.
    case benchUnderTorso
    /// A bench the upper back rests against while the hips stay off it — the
    /// difference between a hip thrust and a floor bridge.
    case benchUnderShoulders
    /// A fixed overhead bar, centred on the given point.
    case fixedBar(CGPoint)
    /// A loaded barbell seen end-on — a plate circle centred on the near hand.
    case barbellAtHand
    /// A loaded barbell racked across the shoulders.
    case barbellOnBack
    /// A loaded barbell across the hips, for a thrust.
    case barbellAtHip
    case dumbbellsAtBothHands
    case medBall
    /// A rucksack, drawn against the back along the torso line.
    case pack
    /// A cable or band running from a fixed anchor to the near hand.
    case cable(CGPoint)
    /// A wall to throw at, at the given x.
    case wall(CGFloat)
}

/// Resolved drawing geometry — the same primitives feed the SwiftUI renderer
/// and the offline contact-sheet renderer used to eyeball every keyframe, so
/// what gets checked is what ships.
enum StickFigurePrimitive: Equatable {
    case line(CGPoint, CGPoint)
    case circle(centre: CGPoint, radius: CGFloat)
    /// A circle filled with the page ground before it is stroked — used for
    /// the hub of a plate and the head, so whatever passes behind is masked
    /// rather than drawn straight through.
    case disc(centre: CGPoint, radius: CGFloat)
    case polygon([CGPoint])
    /// An open path — a bench outline that shouldn't close back on itself,
    /// a box with no bottom edge.
    case path([CGPoint])
}

/// One drawable piece of a frame, in rig space, emitted back-to-front.
///
/// Ordering, ink choice and head masking live here rather than in each
/// renderer, so the in-app `Canvas` and the offline contact-sheet renderer
/// physically cannot drift apart — what a test eyeballs is what ships.
enum StickFigureElement: Equatable {
    /// Soft contact patch on the floor under the weight-bearing joints. The
    /// single cheapest thing that stops a figure looking like it is hovering.
    ///
    /// `strength` is 1 at rest and spikes on impact — a landing punches the
    /// patch darker and wider for a few frames, which is what sells a jump as
    /// having weight rather than settling onto the floor like a feather.
    case shadow(centre: CGPoint, radii: CGSize, strength: CGFloat)
    /// An echo of a fast-moving limb a few frames back, drawn faintest first.
    /// Only emitted for clips quick enough that a single crisp frame reads as
    /// a still image rather than as speed.
    case trail(CGPoint, CGPoint, strength: CGFloat)
    /// Scenery or equipment.
    case prop(StickFigurePrimitive)
    /// A bone. Far-side limbs arrive with `far: true` and are drawn lighter
    /// and slightly thinner.
    case bone(CGPoint, CGPoint, far: Bool)
    /// The skull, drawn last and filled before it is stroked so arms that
    /// pass behind it (a pull-up, an overhead lockout) are masked instead of
    /// slicing through the face.
    case head(centre: CGPoint, radius: CGFloat)
}

extension StickFigureProp {
    /// Plate radius. A real 20 kg plate is 450 mm across, which at this rig's
    /// ~12.2 mm per unit would be radius 18 and swallow the figure's head, so
    /// it's drawn at training-plate size instead — big enough to read as a
    /// loaded bar, small enough to leave the body legible.
    static let plateRadius: CGFloat = 13

    /// Scenery goes behind the body, gear the figure is holding goes in front.
    /// A plate the torso draws over stops reading as something being lifted,
    /// and a bench drawn over the person stops reading as something they're
    /// lying on.
    var drawsBehindFigure: Bool {
        switch self {
        case .barbellAtHand, .barbellAtHip, .dumbbellsAtBothHands, .medBall: return false
        default: return true
        }
    }

    func primitives(for s: StickFigureSkeleton, reference: StickFigureSkeleton) -> [StickFigurePrimitive] {
        switch self {
        case .ground:
            return [.line(CGPoint(x: -400, y: StickFigureRig.ground), CGPoint(x: 500, y: StickFigureRig.ground))]
        case .platformUnderNearFoot(let back, let front):
            return Self.platform(toe: reference.nearToe, back: back, front: front)
        case .platformUnderFarFoot(let back, let front):
            return Self.platform(toe: reference.farToe, back: back, front: front)
        case .benchUnderTorso:
            return Self.bench(reference: reference)
        case .benchUnderShoulders:
            return Self.shoulderBench(reference: reference)
        case .fixedBar(let p):
            return [.line(CGPoint(x: p.x - 30, y: p.y), CGPoint(x: p.x + 30, y: p.y)),
                    .line(CGPoint(x: p.x - 30, y: p.y), CGPoint(x: p.x - 30, y: p.y - 12)),
                    .line(CGPoint(x: p.x + 30, y: p.y), CGPoint(x: p.x + 30, y: p.y - 12))]
        case .barbellAtHand:
            return Self.plate(at: s.nearHand)
        case .barbellOnBack:
            // Racked on the upper traps and set back behind the neck, so the
            // plate clears the skull instead of ringing it like a halo. The
            // head is still drawn last and masked, which keeps the overlap
            // that is left reading as depth.
            let spine = Self.angle(s.hip, s.shoulder)
            return Self.plate(at: StickFigureRig.offset(StickFigureRig.offset(s.shoulder, spine, -1), spine + 90, 13))
        case .barbellAtHip:
            return Self.plate(at: s.hip)
        case .dumbbellsAtBothHands:
            // Held at the side, a dumbbell is seen end-on: one plate, not the
            // stacked pair of discs that read as a chain link over the thigh.
            return [.disc(centre: s.nearHand, radius: 7), .disc(centre: s.farHand, radius: 7)]
        case .medBall:
            // One solid ball. A second concentric ring made it read as a
            // barbell plate, which is the one thing it must not look like.
            return [.disc(centre: s.nearHand, radius: 9)]
        case .pack:
            // `spine + 90` is the figure's *back*: the rig's angle convention
            // rotates positive toward the direction it faces, so `spine - 90`
            // hung the rucksack off the chest.
            let spine = Self.angle(s.hip, s.shoulder)
            let backwards = spine + 90
            func p(_ along: CGFloat, _ out: CGFloat) -> CGPoint {
                StickFigureRig.offset(StickFigureRig.offset(s.hip, spine, along), backwards, out)
            }
            return [.polygon([p(6, 1), p(6, 15), p(34, 17), p(34, 3)]),
                    .line(p(30, 2), p(12, 1))]
        case .cable(let anchor):
            // A stack, a pulley and the line: three strokes is the difference
            // between "cable machine" and "stray dot in the corner".
            let post = CGPoint(x: anchor.x, y: StickFigureRig.ground)
            return [.line(anchor, post),
                    .line(CGPoint(x: anchor.x - 9, y: StickFigureRig.ground),
                          CGPoint(x: anchor.x + 9, y: StickFigureRig.ground)),
                    .disc(centre: anchor, radius: 4),
                    .line(anchor, s.nearHand)]
        case .wall(let x):
            // Hatched on the near face, the way a section is drawn — two flat
            // ticks made it read as a lamp post rather than a wall.
            return [.line(CGPoint(x: x, y: 4), CGPoint(x: x, y: StickFigureRig.ground))]
                + stride(from: CGFloat(16), to: CGFloat(150), by: 22).map {
                    .line(CGPoint(x: x, y: $0), CGPoint(x: x - 9, y: $0 + 9))
                }
        }
    }

    /// A loaded plate seen end-on: one rim the body can show through, plus a
    /// solid hub so the bar reads as steel rather than as an empty ring. A
    /// second concentric ring turns the whole thing into a dartboard.
    private static func plate(at p: CGPoint) -> [StickFigurePrimitive] {
        [.circle(centre: p, radius: plateRadius), .disc(centre: p, radius: 3.4)]
    }

    /// A step or plyo box. Top is the reference frame's toe — the surface the
    /// foot is actually standing on. Taking the *lowest* of toe/heel/ankle (as
    /// this used to) collapsed a calf-raise step to a 4-unit sliver, because
    /// that pose's whole point is a heel hanging below the edge.
    private static func platform(toe: CGPoint, back: CGFloat, front: CGFloat) -> [StickFigurePrimitive] {
        let top = toe.y
        let x0 = toe.x - back, x1 = toe.x + front
        return [.path([CGPoint(x: x0, y: StickFigureRig.ground), CGPoint(x: x0, y: top),
                       CGPoint(x: x1, y: top), CGPoint(x: x1, y: StickFigureRig.ground)]),
                .line(CGPoint(x: x0 + 4, y: top + 6), CGPoint(x: x1 - 4, y: top + 6))]
    }

    /// A flat bench: a pad the full length of the torso *including the head*,
    /// on two legs. The old version stopped at the shoulder, so every supine
    /// figure's skull hung off the end in mid-air.
    private static func bench(reference r: StickFigureSkeleton) -> [StickFigurePrimitive] {
        let top = max(r.shoulder.y, r.hip.y) + 5
        let x0 = min(r.shoulder.x, r.hip.x, r.head.x - StickFigureRig.headRadius) - 8
        let x1 = max(r.shoulder.x, r.hip.x, r.head.x + StickFigureRig.headRadius) + 8
        let ground = StickFigureRig.ground
        return [.path([CGPoint(x: x0, y: top + 6), CGPoint(x: x0, y: top),
                       CGPoint(x: x1, y: top), CGPoint(x: x1, y: top + 6)]),
                .line(CGPoint(x: x0 + 7, y: top + 6), CGPoint(x: x0 + 7, y: ground)),
                .line(CGPoint(x: x1 - 7, y: top + 6), CGPoint(x: x1 - 7, y: ground))]
    }

    /// The pad a hip thrust drives off: it stops at the shoulder blades and
    /// runs away *behind* the lifter, leaving the hips in free air where the
    /// whole movement happens.
    private static func shoulderBench(reference r: StickFigureSkeleton) -> [StickFigurePrimitive] {
        let top = r.shoulder.y + 6
        let front = r.shoulder.x + 8
        let back = min(r.head.x, r.shoulder.x) - 30
        let ground = StickFigureRig.ground
        return [.path([CGPoint(x: back, y: top + 6), CGPoint(x: back, y: top),
                       CGPoint(x: front, y: top), CGPoint(x: front, y: top + 6)]),
                .line(CGPoint(x: back + 7, y: top + 6), CGPoint(x: back + 7, y: ground)),
                .line(CGPoint(x: front - 7, y: top + 6), CGPoint(x: front - 7, y: ground))]
    }

    private static func angle(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
        atan2(to.x - from.x, to.y - from.y) * 180 / .pi
    }
}

// MARK: - Anchoring

/// How a pose is placed in the frame once forward kinematics has run. Because
/// the anchor is re-applied to every interpolated frame — not just the
/// keyframes — a planted foot stays exactly planted for the whole rep instead
/// of drifting through the middle of it.
enum StickFigureAnchor: Equatable {
    /// Use the authored hip position as-is.
    case free
    /// Drop the figure until its lowest *drawn* point rests on the floor —
    /// every joint, plus the underside of the head circle.
    ///
    /// For poses whose contact with the ground isn't a joint the rig knows
    /// about: a supine dead bug rests on its back and the back of its skull,
    /// not on a heel. Authoring the hip height by hand instead (what `free`
    /// forced) had three of the floor clips sitting 3–6 units *through* the
    /// ground line.
    case floored
    /// Drop the figure so its lowest weight-bearing joint rests on the floor,
    /// minus the frame's own `lift`. Horizontal position stays as authored,
    /// which is what lets a gait cycle swing its feet through.
    case grounded
    /// `grounded`, plus slide the figure so the near ankle sits at `footX` —
    /// for anything performed with the feet rooted to one spot.
    case planted(footX: CGFloat)
    /// Pin the near toe to a fixed point: the foot that's up on a box and
    /// stays there while the rest of the body travels past it.
    case toePinned(CGPoint)
    /// Pin the near hand to a fixed point: a pull-up bar, a machine handle.
    case handPinned(CGPoint)
}

// MARK: - Loop style

enum StickFigureLoop: Equatable {
    /// Play the keyframes forward then back — one rep out and one rep home.
    case pingPong
    /// Wrap the last keyframe round to the first: a gait cycle, where "back to
    /// the start" would look like running backwards.
    case cycle
}

// MARK: - Movement patterns

/// One looping animation. Roughly one per distinct movement rather than one
/// per exercise — a cable woodchop and a med-ball throw are different lifts
/// but nearly the same shape — while still keeping anything that *reads*
/// differently (a step-up vs. a lunge, a plank vs. a dead bug) on its own clip.
enum MovementPattern: String, Equatable, CaseIterable {
    case squat, hinge, deadlift, lunge, splitSquat, stepUp, stepDown
    case calfRaise, ankleRock
    case pullVertical, pullHorizontal, facePull, pushUp, benchPress, overheadPress
    case woodchop, medBallThrow, thoracicRotation, bowlingAction
    case sprint, jog, ruckWalk, carry, boxJump, mountainClimber
    case plank, deadBug, birdDog, pallofPress
    case hipFlexorStretch, gluteBridge, hipThrust
    case hold

    /// Human-readable name, used in tests and debug tooling.
    var title: String {
        switch self {
        case .squat: return "Squat"
        case .hinge: return "Hip hinge"
        case .deadlift: return "Deadlift"
        case .lunge: return "Lunge"
        case .splitSquat: return "Rear-foot-elevated split squat"
        case .stepUp: return "Step-up"
        case .stepDown: return "Eccentric step-down"
        case .calfRaise: return "Calf raise"
        case .ankleRock: return "Ankle dorsiflexion rock"
        case .pullVertical: return "Vertical pull"
        case .pullHorizontal: return "Horizontal row"
        case .facePull: return "Face pull"
        case .pushUp: return "Push-up"
        case .benchPress: return "Bench press"
        case .overheadPress: return "Overhead press"
        case .woodchop: return "Cable woodchop"
        case .medBallThrow: return "Rotational throw"
        case .thoracicRotation: return "Thoracic open-book"
        case .bowlingAction: return "Bowling action"
        case .sprint: return "Sprint"
        case .jog: return "Easy run"
        case .ruckWalk: return "Loaded walk"
        case .carry: return "Loaded carry"
        case .boxJump: return "Jump"
        case .mountainClimber: return "Mountain climber"
        case .plank: return "Front plank"
        case .deadBug: return "Dead bug"
        case .birdDog: return "Bird dog"
        case .pallofPress: return "Pallof press"
        case .hipFlexorStretch: return "Half-kneeling hip stretch"
        case .gluteBridge: return "Glute bridge"
        case .hipThrust: return "Hip thrust"
        case .hold: return "Braced hold"
        }
    }

    var loop: StickFigureLoop {
        switch self {
        case .sprint, .jog, .ruckWalk, .carry, .bowlingAction, .mountainClimber: return .cycle
        default: return .pingPong
        }
    }

    /// Full cycle time in seconds — a plank brace breathes slowly, a sprint
    /// cycle turns over in well under a second.
    var cycleDuration: Double {
        switch self {
        case .sprint: return 0.62
        case .jog: return 0.78
        case .mountainClimber: return 0.7
        case .ruckWalk, .carry: return 1.15
        case .bowlingAction: return 1.9
        case .boxJump, .medBallThrow: return 1.5
        case .hold, .plank, .hipFlexorStretch: return 3.0
        case .deadBug, .birdDog, .pallofPress, .thoracicRotation: return 2.6
        case .deadlift, .squat, .hinge: return 2.8
        default: return 2.2
        }
    }

    var anchor: StickFigureAnchor {
        switch self {
        case .pullVertical: return .handPinned(CGPoint(x: 52, y: 22))
        case .stepUp: return .toePinned(CGPoint(x: 58, y: 115.4))
        case .stepDown: return .toePinned(CGPoint(x: 60, y: 116))
        case .calfRaise: return .toePinned(CGPoint(x: 56, y: 132))
        case .deadBug, .gluteBridge, .hipThrust, .benchPress: return .floored
        case .sprint, .jog, .ruckWalk, .carry, .bowlingAction: return .grounded
        case .pushUp, .plank, .mountainClimber, .birdDog, .thoracicRotation: return .grounded
        case .lunge: return .planted(footX: 62)
        case .splitSquat: return .planted(footX: 60)
        default: return .planted(footX: 50)
        }
    }

    var props: [StickFigureProp] {
        switch self {
        case .squat: return [.ground, .barbellOnBack]
        case .hinge, .deadlift, .pullHorizontal, .overheadPress: return [.ground, .barbellAtHand]
        case .benchPress: return [.ground, .benchUnderTorso, .barbellAtHand]
        case .hipThrust: return [.ground, .benchUnderShoulders, .barbellAtHip]
        case .stepUp: return [.ground, .platformUnderNearFoot(back: 22, front: 16), .dumbbellsAtBothHands]
        case .stepDown: return [.ground, .platformUnderNearFoot(back: 34, front: 8)]
        case .calfRaise: return [.ground, .platformUnderNearFoot(back: 10, front: 24)]
        case .splitSquat: return [.ground, .platformUnderFarFoot(back: 24, front: 18)]
        case .pullVertical: return [.fixedBar(CGPoint(x: 52, y: 22))]
        case .facePull: return [.ground, .cable(CGPoint(x: 98, y: 30))]
        case .woodchop: return [.ground, .cable(CGPoint(x: 98, y: 18))]
        case .pallofPress: return [.ground, .cable(CGPoint(x: 98, y: 62))]
        case .medBallThrow: return [.ground, .wall(116), .medBall]
        case .carry: return [.ground, .dumbbellsAtBothHands]
        case .ruckWalk: return [.ground, .pack]
        default: return [.ground]
        }
    }

    var keyframes: [StickFigurePose] { Self.frames[self] ?? [.standing] }

    /// The single frame that best explains the movement, for when the clip
    /// isn't allowed to move — Reduce Motion, or a card that has scrolled off.
    ///
    /// Deliberately not phase zero: the first keyframe of most lifts is the
    /// start position, and a squat drawn standing upright tells you nothing.
    /// The bottom of the rep is the pose worth freezing on.
    var restingPhase: Double {
        switch loop {
        case .cycle: return 0.25
        case .pingPong: return eccentricShare
        }
    }

    /// Joint positions for one point in the loop, with the anchor applied — the
    /// single entry point both renderers use.
    func skeleton(atPhase phase: Double) -> StickFigureSkeleton {
        place(pose(atPhase: phase))
    }

    /// The frame props that don't move are positioned from — keyframe 0.
    var referenceSkeleton: StickFigureSkeleton { place(keyframes[0]) }

    func primitives(atPhase phase: Double) -> [StickFigurePrimitive] {
        let live = skeleton(atPhase: phase)
        let reference = referenceSkeleton
        return props.flatMap { $0.primitives(for: live, reference: reference) }
    }

    /// Everything one frame draws, back-to-front. Both renderers consume this
    /// and nothing else, so the in-app animation and the offline contact
    /// sheets can't drift apart.
    func elements(atPhase phase: Double) -> [StickFigureElement] {
        let s = skeleton(atPhase: phase)
        let reference = referenceSkeleton
        var out: [StickFigureElement] = []

        if let shadow = contactShadow(for: s, atPhase: phase) { out.append(shadow) }
        for prop in props where prop.drawsBehindFigure {
            out += prop.primitives(for: s, reference: reference).map(StickFigureElement.prop)
        }
        out += trails(atPhase: phase)
        out += s.farSegments.map { .bone($0.0, $0.1, far: true) }
        out += (s.spineSegments + s.nearSegments).map { .bone($0.0, $0.1, far: false) }
        for prop in props where !prop.drawsBehindFigure {
            out += prop.primitives(for: s, reference: reference).map(StickFigureElement.prop)
        }
        out.append(.head(centre: s.head, radius: StickFigureRig.headRadius))
        return out
    }

    /// A soft patch on the floor spanning whatever is currently bearing
    /// weight. Only for patterns that draw a floor at all — a supine bench
    /// press has nothing to cast onto.
    private func contactShadow(for s: StickFigureSkeleton, atPhase phase: Double) -> StickFigureElement? {
        guard props.contains(.ground) else { return nil }
        let touching = s.contactPoints.filter { $0.y > StickFigureRig.ground - 5 }
        guard let lo = touching.map(\.x).min(), let hi = touching.map(\.x).max() else { return nil }
        let punch = impact(atPhase: phase)
        return .shadow(centre: CGPoint(x: (lo + hi) / 2, y: StickFigureRig.ground),
                       radii: CGSize(width: (hi - lo) / 2 + 10 + punch * 5, height: 2.8 + punch * 1.2),
                       strength: 1 + punch * 1.6)
    }

    /// How hard the figure is arriving on the floor right now, 0...1.
    ///
    /// Measured from the descent rate of whatever is about to bear weight, so
    /// it fires on the frames where a jump lands or a sprint foot strikes and
    /// stays at zero for everything that never leaves the ground. Landing is
    /// the one moment a stick figure can show force, and letting the contact
    /// patch flinch is far cheaper than animating a squash.
    private func impact(atPhase phase: Double) -> CGFloat {
        guard impacts else { return 0 }
        let dt = 0.03
        func lowest(_ p: Double) -> CGFloat {
            skeleton(atPhase: p).contactPoints.map(\.y).max() ?? StickFigureRig.ground
        }
        let now = lowest(phase)
        // Only count it while something is actually down at floor level.
        guard now > StickFigureRig.ground - 3 else { return 0 }
        let closingSpeed = (now - lowest(phase - dt)) / CGFloat(dt)
        return max(0, min(1, closingSpeed / 90))
    }

    /// Clips with a real flight phase, where a landing is a distinct event
    /// rather than a continuous roll of contact.
    private var impacts: Bool {
        switch self {
        case .boxJump, .sprint, .jog, .mountainClimber: return true
        default: return false
        }
    }

    /// Faint echoes of the fastest-moving limb, a few frames behind.
    ///
    /// A sprint at 0.62s per cycle moves a shin further between two frames
    /// than the shin is long, and a single crisp line at one instant reads as
    /// a pose rather than as speed. Drawn behind the figure so the current
    /// frame stays the one in focus.
    private func trails(atPhase phase: Double) -> [StickFigureElement] {
        guard trailCount > 0 else { return [] }
        var out: [StickFigureElement] = []
        for step in stride(from: trailCount, through: 1, by: -1) {
            // Tight spacing on purpose: spread them out and the ghosts stop
            // overlapping, so instead of a blur you get a fan of separate
            // legs, which reads as a scribble rather than as speed.
            let back = Double(step) * 0.015
            let ghost = skeleton(atPhase: phase - back)
            let fade = CGFloat(1 - Double(step) / Double(trailCount + 1))
            for (a, b) in trailSegments(of: ghost) {
                out.append(.trail(a, b, strength: fade))
            }
        }
        return out
    }

    private var trailCount: Int {
        switch self {
        case .sprint: return 3
        case .boxJump, .medBallThrow, .bowlingAction: return 2
        case .jog, .mountainClimber: return 1
        default: return 0
        }
    }

    /// The limbs worth echoing: the ones actually travelling fast. Trailing
    /// the whole skeleton just smears the figure.
    private func trailSegments(of s: StickFigureSkeleton) -> [(CGPoint, CGPoint)] {
        switch self {
        case .medBallThrow, .bowlingAction:
            return [(s.shoulder, s.nearElbow), (s.nearElbow, s.nearHand)]
        default:
            // Near leg only. Echoing both legs doubles the line count for no
            // extra read — the far limb is already drawn faint, and ghosting
            // it too just fills the space under the figure with clutter.
            return [(s.hip, s.nearKnee), (s.nearKnee, s.nearAnkle)]
        }
    }

    /// The interpolated pose at `phase` (0...1 through one full loop), with
    /// secondary motion applied on top of the authored keyframes.
    func pose(atPhase phase: Double) -> StickFigurePose {
        var pose = basePose(atPhase: phase)
        applySecondaryMotion(to: &pose, atPhase: phase)
        return pose
    }

    /// The pose the keyframes alone describe, before any secondary motion.
    /// Split out so the follow-through can measure how fast the torso is
    /// moving without recursing into itself.
    func basePose(atPhase phase: Double) -> StickFigurePose {
        let frames = keyframes
        guard frames.count > 1 else { return frames[0] }

        // Both loop styles reduce to "walk a closed ring of poses". A ping-pong
        // is just the keyframes followed by their reverse (minus the repeated
        // endpoints), which means the turnaround needs no special case: the
        // spline's tangent at a pose whose two neighbours are the same pose is
        // exactly zero, so the rep decelerates into the turn and accelerates
        // out of it on its own.
        let ring: [StickFigurePose]
        switch loop {
        case .cycle: ring = frames
        case .pingPong: ring = frames + Array(frames.dropFirst().dropLast().reversed())
        }

        let position = ringPosition(atPhase: phase, count: ring.count)
        let i = Int(position) % ring.count
        let t = CGFloat(position - position.rounded(.down))
        func at(_ offset: Int) -> StickFigurePose {
            ring[((i + offset) % ring.count + ring.count) % ring.count]
        }
        return StickFigurePose.spline(at(-1), at(0), at(1), at(2), t)
    }

    /// Where in the ring of poses `phase` lands, after the tempo skew.
    private func ringPosition(atPhase phase: Double, count: Int) -> Double {
        let p = phase - phase.rounded(.down)
        guard loop == .pingPong, count > 1 else { return p * Double(count) }

        // Lifts aren't symmetric: the lowering half of a rep is slower than the
        // drive out of it. Splitting the cycle unevenly costs nothing in
        // smoothness because the seam falls exactly on a turnaround, where the
        // spline's velocity is already zero on both sides.
        let half = Double(count) / 2
        let share = eccentricShare
        return p < share
            ? (p / share) * half
            : half + ((p - share) / (1 - share)) * half
    }

    /// Fraction of the cycle spent travelling from the first keyframe to the
    /// last — the lowering half of most lifts. `0.5` is an even out-and-back.
    var eccentricShare: Double {
        switch self {
        // Controlled descents: the whole point of the exercise is the lowering.
        case .stepDown: return 0.68
        case .squat, .hinge, .deadlift, .splitSquat, .benchPress, .pullVertical: return 0.6
        case .overheadPress, .pullHorizontal, .lunge, .stepUp, .hipThrust, .gluteBridge: return 0.58
        // Explosive: a jump or a throw is a slow load and a violent release.
        case .boxJump, .medBallThrow: return 0.72
        // Holds, stretches and gait cycles have no eccentric/concentric split.
        default: return 0.5
        }
    }

    /// How far the head lags behind the torso, in degrees of extra tilt per
    /// degree-per-cycle of torso rotation. Zero for clips where the head is
    /// pinned by the movement itself (a supine press has it on a bench).
    private var headLag: CGFloat {
        switch self {
        case .benchPress, .hipThrust, .gluteBridge, .deadBug: return 0
        case .sprint, .boxJump, .medBallThrow, .bowlingAction: return 0.055
        default: return 0.035
        }
    }

    /// Adds the motion that isn't authored anywhere: the head trailing the
    /// torso through a direction change.
    ///
    /// Without it every joint starts, turns and stops on exactly the same
    /// frame, which is what makes a rigged figure read as a puppet — real
    /// mass arrives late. Derived from the torso's own angular velocity
    /// rather than simulated, so it stays a pure function of phase and both
    /// renderers (and the tests) agree on it.
    private func applySecondaryMotion(to pose: inout StickFigurePose, atPhase phase: Double) {
        let lag = headLag
        guard lag != 0 else { return }
        let dt = 0.02
        let previous = basePose(atPhase: phase - dt)
        let leanVelocity = (pose.lean - previous.lean) / CGFloat(dt)
        // Clamped so a fast clip can't whip the head off the end of the neck.
        pose.headTilt += max(-9, min(9, leanVelocity * lag))
    }

    /// Applies this pattern's anchor to a pose. Called per frame, which is what
    /// keeps planted feet planted through the in-betweens.
    func place(_ pose: StickFigurePose) -> StickFigureSkeleton {
        let raw = pose.skeleton()
        switch anchor {
        case .free:
            return raw
        case .floored:
            let lowest = max(raw.allPoints.map(\.y).max() ?? StickFigureRig.ground,
                             raw.head.y + StickFigureRig.headRadius)
            return raw.translated(by: CGVector(dx: 0, dy: StickFigureRig.ground - pose.lift - lowest))
        case .grounded:
            return raw.translated(by: CGVector(dx: 0, dy: floorDrop(raw, lift: pose.lift)))
        case .planted(let footX):
            return raw.translated(by: CGVector(dx: footX - raw.nearAnkle.x, dy: floorDrop(raw, lift: pose.lift)))
        case .toePinned(let point):
            return raw.translated(by: CGVector(dx: point.x - raw.nearToe.x, dy: point.y - raw.nearToe.y))
        case .handPinned(let point):
            return raw.translated(by: CGVector(dx: point.x - raw.nearHand.x, dy: point.y - raw.nearHand.y))
        }
    }

    private func floorDrop(_ s: StickFigureSkeleton, lift: CGFloat) -> CGFloat {
        let lowest = Self.softLowest(s.contactPoints.map(\.y))
        return StickFigureRig.ground - lift - lowest
    }

    /// A smooth stand-in for `max` over the weight-bearing joints.
    ///
    /// A hard maximum is continuous but its *slope* isn't: the instant a
    /// stride's support swaps from the trailing toe to the leading heel, the
    /// whole figure's vertical motion changes direction on one frame and the
    /// gait visibly ticks. Blending across the swap removes the crease.
    ///
    /// The result is always slightly *above* the true maximum, never below —
    /// so this can only ever lift the figure a hair off the floor, never sink
    /// it through. `softness` is in rig units and stays well inside the
    /// tolerance the planted-foot tests allow.
    static func softLowest(_ ys: [CGFloat], softness: CGFloat = 0.35) -> CGFloat {
        guard var acc = ys.first else { return StickFigureRig.ground }
        for y in ys.dropFirst() {
            // Smooth maximum: exact when the two are far apart, rounded when
            // they are within a unit or so of each other.
            let hi = max(acc, y), lo = min(acc, y)
            acc = hi + softness * log1p(exp(-(hi - lo) / softness))
        }
        return acc
    }

    /// Where this pattern's rig-space geometry lands inside a canvas of
    /// `size`, as a uniform scale plus an origin.
    ///
    /// Two rules, in this order: never draw the figure larger than natural
    /// size, and never let it overflow the canvas. Fitting each clip to its
    /// own bounding box (the old behaviour) meant a compact half-kneeling
    /// pose filled the card while a tall jump shrank into it, so flicking
    /// between exercises resized the person by nearly 2×.
    func layout(in size: CGSize, inset: CGFloat = 0.94) -> (scale: CGFloat, origin: CGPoint) {
        let box = viewBox
        guard box.width > 0, box.height > 0, size.width > 0, size.height > 0 else {
            return (1, .zero)
        }
        let fit = min(size.width / box.width, size.height / box.height) * inset
        let natural = min(size.width, size.height) / StickFigureRig.nominalFrame
        let scale = min(fit, natural)
        return (scale, CGPoint(
            x: (size.width - box.width * scale) / 2 - box.minX * scale,
            y: (size.height - box.height * scale) / 2 - box.minY * scale
        ))
    }

    /// The rectangle this pattern actually occupies across its whole loop,
    /// props included, padded a little. Framing is derived rather than assumed
    /// so a movement that reaches a long way forward (a deadlift, a woodchop)
    /// scales to fit instead of running off the edge of the card.
    ///
    /// Cached: this sweeps 24 phases and resolves every prop at each one, and
    /// `layout(in:)` needs it on every single drawn frame. Recomputing it at
    /// 60fps was doing ~50 full pose solves per frame for a number that can
    /// never change — the keyframes are compile-time constants.
    var viewBox: CGRect {
        Self.viewBoxCache.value(for: self) { $0.computedViewBox }
    }

    private static let viewBoxCache = PatternCache<CGRect>()

    private var computedViewBox: CGRect {
        var rect: CGRect?
        for step in 0..<24 {
            let phase = Double(step) / 24
            var frame = skeleton(atPhase: phase).bounds
            for primitive in primitives(atPhase: phase) where !primitive.isUnbounded {
                frame = frame.union(primitive.bounds)
            }
            rect = rect.map { $0.union(frame) } ?? frame
        }
        var box = rect ?? CGRect(x: 0, y: 0, width: 100, height: 160)
        if props.contains(.ground) {
            box = box.union(CGRect(x: box.midX, y: StickFigureRig.ground, width: 0, height: 0))
        }
        return box.insetBy(dx: -6, dy: -6)
    }
}

extension StickFigurePrimitive {
    /// The ground line runs off to either side forever; it shouldn't drag the
    /// framing out with it.
    var isUnbounded: Bool {
        if case .line(let a, let b) = self { return abs(a.x - b.x) > 300 }
        return false
    }

    var bounds: CGRect {
        switch self {
        case .line(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .circle(let c, let r), .disc(let c, let r):
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .polygon(let pts), .path(let pts):
            guard let first = pts.first else { return .null }
            return pts.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        }
    }
}

/// Memoises a value derived purely from a `MovementPattern`.
///
/// Everything a pattern computes about itself — its framing, its signature —
/// is a function of compile-time keyframe constants, so it is worth computing
/// once. `Canvas` draws on the main thread but the offline renderer and the
/// tests don't, hence the lock.
final class PatternCache<Value> {
    private var storage: [MovementPattern: Value] = [:]
    private let lock = NSLock()

    func value(for pattern: MovementPattern, build: (MovementPattern) -> Value) -> Value {
        lock.lock()
        if let hit = storage[pattern] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Built outside the lock: this can be slow, and a duplicate build on a
        // race is harmless because the result is deterministic.
        let made = build(pattern)
        lock.lock()
        storage[pattern] = made
        lock.unlock()
        return made
    }
}
