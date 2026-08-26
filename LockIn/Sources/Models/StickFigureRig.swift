import CoreGraphics
import Foundation

/// Bone lengths for the stick figure, in the fixed 100×160 drawing space that
/// every pose and prop is authored in (origin top-left, y grows downward,
/// floor at `ground`).
///
/// Proportioned off a ~1.75 m adult at ~12.2 mm per unit: knee, hip, shoulder
/// and crown all land within a unit of real anthropometry, standing height
/// works out to ~141 units, and a hanging hand reaches mid-thigh. Every pose in `MovementPattern` is built from
/// these same lengths by forward kinematics, so a limb can never stretch or
/// telescope between keyframes — the old hand-placed point poses lost up to
/// 53% of a shin's length mid-rep.
enum StickFigureRig {
    static let torso: CGFloat = 42      // hip → shoulder
    static let neck: CGFloat = 15       // shoulder → head centre
    static let headRadius: CGFloat = 8.5
    static let upperArm: CGFloat = 27   // shoulder → elbow
    static let forearm: CGFloat = 27    // elbow → hand (to the grip, not the fingertips)
    static let thigh: CGFloat = 35      // hip → knee
    static let shin: CGFloat = 35       // knee → ankle
    static let foot: CGFloat = 14.2     // ankle → toe
    static let heel: CGFloat = 7.6      // ankle → heel

    /// The ankle→toe segment isn't perpendicular to the shin — with the sole
    /// flat on the floor and the shin vertical it sits ~66° off the shin's
    /// downward axis, which is what puts the ankle ~5.8 units above the floor.
    static let flatFoot: CGFloat = 66
    /// Angle from ankle→toe round to ankle→heel. Chosen so a flat foot lands
    /// heel and toe at exactly the same height.
    static let heelSplay: CGFloat = 108

    static let space = CGSize(width: 100, height: 160)
    /// The frame a clip is drawn at "natural" size in. Slightly taller than a
    /// standing figure's 152-unit box, so a squat sits comfortably inside the
    /// card with a margin, and every other clip is drawn to the *same* scale
    /// rather than being zoomed to its own bounding box — which used to make
    /// a half-kneeling stretch render half again as large as a squat.
    static let nominalFrame: CGFloat = 168
    static let ground: CGFloat = 152
    /// Hip position of a relaxed standing figure — both feet flat on the floor.
    static let standingHip = CGPoint(x: 50, y: 76.2)

    /// Unit vector for an angle in this rig's convention: degrees, `0` points
    /// straight **down** the screen, positive rotates toward the direction the
    /// figure faces (screen right). So 90° = straight ahead, 180° = straight up.
    static func direction(_ degrees: CGFloat) -> CGVector {
        let r = degrees * .pi / 180
        return CGVector(dx: sin(r), dy: cos(r))
    }

    static func offset(_ from: CGPoint, _ degrees: CGFloat, _ length: CGFloat) -> CGPoint {
        let d = direction(degrees)
        return CGPoint(x: from.x + d.dx * length, y: from.y + d.dy * length)
    }
}

/// One arm, as joint angles rather than positions.
struct StickFigureArm: Equatable {
    /// Shoulder angle **relative to the torso**: 0 hangs the upper arm along
    /// the torso's downward axis, positive swings it forward, 180 puts it
    /// straight overhead. Relative to the torso (not the world) so an arm
    /// keeps its shape when the torso bends over.
    var swing: CGFloat
    /// Elbow flexion in degrees: 0 straight, positive bends the hand toward
    /// the front of the upper arm (anatomical flexion, in any arm position).
    var bend: CGFloat

    init(_ swing: CGFloat, _ bend: CGFloat) { self.swing = swing; self.bend = bend }
}

/// One leg, as joint angles. Hip angle is measured in the world rather than
/// relative to the torso, because it's the floor a leg has to agree with.
struct StickFigureLeg: Equatable {
    /// Thigh angle from straight down; positive drives the knee forward.
    var hip: CGFloat
    /// Knee flexion in degrees: 0 straight, positive folds the heel back.
    var knee: CGFloat
    /// Ankle: positive is plantarflexion (toes pointed down, as in a calf
    /// raise), negative dorsiflexion (shin toward the toes, as in a deep squat).
    var ankle: CGFloat

    init(_ hip: CGFloat, _ knee: CGFloat, _ ankle: CGFloat) {
        self.hip = hip; self.knee = knee; self.ankle = ankle
    }
}

/// One frame of the figure. Everything but `hip` is an angle, which is what
/// makes interpolation between two frames anatomically safe: bones rotate,
/// they never change length.
struct StickFigurePose: Equatable {
    var hip: CGPoint
    /// Torso lean from vertical: 0 upright, positive tips the chest forward,
    /// 90 is bent fully over, negative lies the figure on its back.
    var lean: CGFloat
    /// Head angle relative to the torso; positive drops the chin forward.
    var headTilt: CGFloat
    var nearArm: StickFigureArm
    var farArm: StickFigureArm
    var nearLeg: StickFigureLeg
    var farLeg: StickFigureLeg
    /// How far this frame floats above the floor, for the flight phase of a
    /// run or a jump. Only meaningful under a floor-snapping anchor.
    var lift: CGFloat

    init(hip: CGPoint = StickFigureRig.standingHip,
         lean: CGFloat = 0,
         headTilt: CGFloat = 4,
         nearArm: StickFigureArm,
         farArm: StickFigureArm,
         nearLeg: StickFigureLeg,
         farLeg: StickFigureLeg,
         lift: CGFloat = 0) {
        self.hip = hip; self.lean = lean; self.headTilt = headTilt
        self.nearArm = nearArm; self.farArm = farArm
        self.nearLeg = nearLeg; self.farLeg = farLeg; self.lift = lift
    }

    /// Both arms and both legs mirrored to the same angles — bilateral lifts
    /// (a squat, a press) where the far limb hides directly behind the near one.
    init(hip: CGPoint = StickFigureRig.standingHip,
         lean: CGFloat = 0,
         headTilt: CGFloat = 4,
         arms: StickFigureArm,
         legs: StickFigureLeg,
         lift: CGFloat = 0) {
        // A few degrees of split keeps the hidden limb from z-fighting into a
        // single flat line — real side-view photos read the same way. The far
        // ankle is adjusted so the *world* foot angle matches the near foot
        // (flat stays flat, pointed stays pointed) despite the hip/knee split.
        let farHip = legs.hip - 4
        let farKnee = legs.knee + 3
        let farAnkle = legs.ankle + (farHip - legs.hip) - (farKnee - legs.knee)
        self.init(hip: hip, lean: lean, headTilt: headTilt,
                  nearArm: arms, farArm: StickFigureArm(arms.swing - 5, arms.bend + 4),
                  nearLeg: legs, farLeg: StickFigureLeg(farHip, farKnee, farAnkle),
                  lift: lift)
    }

    /// Angle-space interpolation. Every value here is either a coordinate or a
    /// degree measure, so a straight lerp is exactly right — no bone changes
    /// length, which is the whole reason poses are stored this way.
    static func lerp(_ a: StickFigurePose, _ b: StickFigurePose, _ t: CGFloat) -> StickFigurePose {
        combine(a, b) { $0 + ($1 - $0) * t }
    }

    /// Cardinal-spline interpolation from `b` to `c`, using `a` and `d` as the
    /// neighbouring keyframes that set the tangents.
    ///
    /// Straight `lerp` moves at a constant rate inside each segment and then
    /// changes direction instantly at every keyframe — the figure visibly
    /// hitches at each authored pose, because velocity is discontinuous there.
    /// A spline passes through the same keyframes but carries its velocity
    /// across them, which is the difference between a rep and a flip-book.
    ///
    /// `tension` is the Catmull-Rom shape factor. The textbook value is 0.5;
    /// this rig runs slightly under it because a spline overshoots past its
    /// control points, and an overshoot here means a knee bending a few
    /// degrees further than the keyframe that was checked against the floor.
    static func spline(
        _ a: StickFigurePose, _ b: StickFigurePose,
        _ c: StickFigurePose, _ d: StickFigurePose,
        _ t: CGFloat, tension: CGFloat = 0.38
    ) -> StickFigurePose {
        let t2 = t * t, t3 = t2 * t
        // Hermite basis, with tangents m1 = s(c - a), m2 = s(d - b).
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        func blend(_ pa: CGFloat, _ pb: CGFloat, _ pc: CGFloat, _ pd: CGFloat) -> CGFloat {
            let m1 = tension * (pc - pa)
            let m2 = tension * (pd - pb)
            return h00 * pb + h10 * m1 + h01 * pc + h11 * m2
        }
        return combine4(a, b, c, d, blend)
    }

    /// Applies `f` to every scalar of two poses.
    static func combine(
        _ a: StickFigurePose, _ b: StickFigurePose,
        _ f: (CGFloat, CGFloat) -> CGFloat
    ) -> StickFigurePose {
        combine4(a, a, b, b) { _, x, y, _ in f(x, y) }
    }

    /// Applies `f` to every scalar of four poses at once. Every interpolation
    /// in the rig funnels through here so no field can be forgotten when a new
    /// one is added to the pose.
    static func combine4(
        _ a: StickFigurePose, _ b: StickFigurePose,
        _ c: StickFigurePose, _ d: StickFigurePose,
        _ f: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGFloat
    ) -> StickFigurePose {
        func arm(_ w: StickFigureArm, _ x: StickFigureArm,
                 _ y: StickFigureArm, _ z: StickFigureArm) -> StickFigureArm {
            StickFigureArm(f(w.swing, x.swing, y.swing, z.swing),
                           f(w.bend, x.bend, y.bend, z.bend))
        }
        func leg(_ w: StickFigureLeg, _ x: StickFigureLeg,
                 _ y: StickFigureLeg, _ z: StickFigureLeg) -> StickFigureLeg {
            StickFigureLeg(f(w.hip, x.hip, y.hip, z.hip),
                           f(w.knee, x.knee, y.knee, z.knee),
                           f(w.ankle, x.ankle, y.ankle, z.ankle))
        }
        return StickFigurePose(
            hip: CGPoint(x: f(a.hip.x, b.hip.x, c.hip.x, d.hip.x),
                         y: f(a.hip.y, b.hip.y, c.hip.y, d.hip.y)),
            lean: f(a.lean, b.lean, c.lean, d.lean),
            headTilt: f(a.headTilt, b.headTilt, c.headTilt, d.headTilt),
            nearArm: arm(a.nearArm, b.nearArm, c.nearArm, d.nearArm),
            farArm: arm(a.farArm, b.farArm, c.farArm, d.farArm),
            nearLeg: leg(a.nearLeg, b.nearLeg, c.nearLeg, d.nearLeg),
            farLeg: leg(a.farLeg, b.farLeg, c.farLeg, d.farLeg),
            lift: f(a.lift, b.lift, c.lift, d.lift)
        )
    }
}

/// A pose resolved to actual joint positions.
struct StickFigureSkeleton: Equatable {
    var head: CGPoint
    var shoulder: CGPoint
    var hip: CGPoint
    var nearElbow: CGPoint, nearHand: CGPoint
    var farElbow: CGPoint, farHand: CGPoint
    var nearKnee: CGPoint, nearAnkle: CGPoint, nearToe: CGPoint, nearHeel: CGPoint
    var farKnee: CGPoint, farAnkle: CGPoint, farToe: CGPoint, farHeel: CGPoint

    /// The joints that can plausibly bear weight on the floor. Used to sit the
    /// figure on the ground line no matter what the angles work out to, so a
    /// squat's feet stay planted through every in-between frame.
    var contactPoints: [CGPoint] {
        [nearToe, nearHeel, farToe, farHeel, nearKnee, farKnee, nearHand, farHand, nearElbow, farElbow]
    }

    /// Bones drawn behind the torso, in a lighter ink — the limbs on the far
    /// side of the body.
    var farSegments: [(CGPoint, CGPoint)] {
        [(shoulder, farElbow), (farElbow, farHand),
         (hip, farKnee), (farKnee, farAnkle)] + Self.foot(farAnkle, farHeel, farToe)
    }

    /// Ankle → heel → toe → ankle: a closed wedge that reads as a foot.
    ///
    /// The shin bone stops at the ankle, and the ankle sits ~6 units clear of
    /// the floor on a flat foot. Drawing only the heel→toe sole (as this used
    /// to) therefore left every figure's foot floating unattached below the
    /// end of its leg — the single most noticeable defect in the old clips.
    static func foot(_ ankle: CGPoint, _ heel: CGPoint, _ toe: CGPoint) -> [(CGPoint, CGPoint)] {
        [(ankle, heel), (heel, toe), (toe, ankle)]
    }

    /// Spine and head stem.
    var spineSegments: [(CGPoint, CGPoint)] {
        [(hip, shoulder), (shoulder, neckJoin)]
    }

    /// Where the head stem meets the head circle, so the neck line stops at the
    /// skull instead of running through it.
    var neckJoin: CGPoint {
        let dx = head.x - shoulder.x, dy = head.y - shoulder.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let stop = max(len - StickFigureRig.headRadius, 0)
        return CGPoint(x: shoulder.x + dx / len * stop, y: shoulder.y + dy / len * stop)
    }

    /// Bones drawn in front, in full ink — the limbs nearest the viewer.
    var nearSegments: [(CGPoint, CGPoint)] {
        [(shoulder, nearElbow), (nearElbow, nearHand),
         (hip, nearKnee), (nearKnee, nearAnkle)] + Self.foot(nearAnkle, nearHeel, nearToe)
    }

    var allPoints: [CGPoint] {
        [head, shoulder, hip, nearElbow, nearHand, farElbow, farHand,
         nearKnee, nearAnkle, nearToe, nearHeel, farKnee, farAnkle, farToe, farHeel]
    }

    /// Bounding box including the head circle.
    var bounds: CGRect {
        var rect = CGRect(x: head.x - StickFigureRig.headRadius, y: head.y - StickFigureRig.headRadius,
                          width: StickFigureRig.headRadius * 2, height: StickFigureRig.headRadius * 2)
        for p in allPoints { rect = rect.union(CGRect(origin: p, size: .zero)) }
        return rect
    }

    func translated(by offset: CGVector) -> StickFigureSkeleton {
        func t(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.dx, y: p.y + offset.dy) }
        return StickFigureSkeleton(
            head: t(head), shoulder: t(shoulder), hip: t(hip),
            nearElbow: t(nearElbow), nearHand: t(nearHand), farElbow: t(farElbow), farHand: t(farHand),
            nearKnee: t(nearKnee), nearAnkle: t(nearAnkle), nearToe: t(nearToe), nearHeel: t(nearHeel),
            farKnee: t(farKnee), farAnkle: t(farAnkle), farToe: t(farToe), farHeel: t(farHeel))
    }
}

extension StickFigurePose {
    /// Forward kinematics: turn joint angles into joint positions, hip outward.
    func skeleton() -> StickFigureSkeleton {
        let R = StickFigureRig.self
        let torsoUp = 180 - lean          // hip → shoulder
        let torsoDown = -lean             // shoulder → hip, the arms' zero
        let shoulder = R.offset(hip, torsoUp, R.torso)
        let head = R.offset(shoulder, torsoUp - headTilt, R.neck)

        func arm(_ a: StickFigureArm) -> (CGPoint, CGPoint) {
            let upper = torsoDown + a.swing
            let elbow = R.offset(shoulder, upper, R.upperArm)
            return (elbow, R.offset(elbow, upper + a.bend, R.forearm))
        }
        func leg(_ l: StickFigureLeg) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
            let knee = R.offset(hip, l.hip, R.thigh)
            let shin = l.hip - l.knee
            let ankle = R.offset(knee, shin, R.shin)
            let footAngle = shin + R.flatFoot - l.ankle
            return (knee, ankle,
                    R.offset(ankle, footAngle, R.foot),
                    R.offset(ankle, footAngle - R.heelSplay, R.heel))
        }

        let (ne, nh) = arm(nearArm)
        let (fe, fh) = arm(farArm)
        let (nk, na, nt, nhl) = leg(nearLeg)
        let (fk, fa, ft, fhl) = leg(farLeg)
        return StickFigureSkeleton(
            head: head, shoulder: shoulder, hip: hip,
            nearElbow: ne, nearHand: nh, farElbow: fe, farHand: fh,
            nearKnee: nk, nearAnkle: na, nearToe: nt, nearHeel: nhl,
            farKnee: fk, farAnkle: fa, farToe: ft, farHeel: fhl)
    }
}
