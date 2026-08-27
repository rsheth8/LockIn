import Foundation
import CoreGraphics

/// A schematic figure described by its joint **angles**.
///
/// Angles rather than points because that's what makes the movement between
/// keyframes correct. Interpolating joint positions draws the chord of the arc
/// a limb travels, so a 112° arm swing would shorten the arm to three quarters
/// of its length at the midpoint and snap back — visible, and wrong. Rotating
/// the angles and resolving the skeleton afterwards keeps every limb its own
/// length in every frame, which `StickFigureTests` enforces.
///
/// Deliberately schematic. It shows the *shape* of the movement — where the
/// hips go, which way the torso travels, what bends — and the written cues and
/// mistakes carry the detail a line drawing can't honestly convey.
struct PoseSpec: Equatable {

    /// What the figure is fixed to. Standing figures resolve upward from the
    /// planted foot so it can't drift off the floor; hanging and lying figures
    /// resolve outward from the pelvis.
    enum Anchor: Equatable {
        case ground(ankleX: Double, ground: Double, heelLift: Double)
        case hip(CGPoint)
    }

    var anchor: Anchor
    /// Legs: 0 points straight up from the joint below, positive tips forward.
    var shin: Double
    var thigh: Double
    /// 0 is upright, positive leans forward.
    var torso: Double
    /// Arms: 0 hangs straight down from the shoulder, positive swings forward,
    /// 180 points straight up.
    var upperArm: Double
    var forearm: Double
    /// The trailing leg, for split-stance work. A lunge drawn with one leg is
    /// unreadable — it just looks like a person bending oddly.
    var rearThigh: Double?
    var rearShin: Double?
    var load: LoadKind

    static func grounded(ankleX: Double, ground: Double = StickPose.Body.ground,
                         shin: Double, thigh: Double, torso: Double,
                         upperArm: Double, forearm: Double,
                         heelLift: Double = 0,
                         rear: (thigh: Double, shin: Double)? = nil,
                         load: LoadKind = .none) -> PoseSpec {
        PoseSpec(anchor: .ground(ankleX: ankleX, ground: ground, heelLift: heelLift),
                 shin: shin, thigh: thigh, torso: torso,
                 upperArm: upperArm, forearm: forearm,
                 rearThigh: rear?.thigh, rearShin: rear?.shin, load: load)
    }

    static func free(hip: CGPoint, torso: Double, thigh: Double, shin: Double,
                     upperArm: Double, forearm: Double,
                     rear: (thigh: Double, shin: Double)? = nil,
                     load: LoadKind = .none) -> PoseSpec {
        PoseSpec(anchor: .hip(hip), shin: shin, thigh: thigh, torso: torso,
                 upperArm: upperArm, forearm: forearm,
                 rearThigh: rear?.thigh, rearShin: rear?.shin, load: load)
    }

    // MARK: - Interpolation

    /// Blends every angle toward another pose. Angles are taken by the short
    /// way round, so 170° → −170° swings 20° through the top rather than 340°
    /// back through the bottom.
    func interpolated(to other: PoseSpec, _ t: Double) -> PoseSpec {
        let t = min(max(t, 0), 1)
        func angle(_ a: Double, _ b: Double) -> Double {
            var delta = (b - a).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            return a + delta * t
        }
        func optional(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return a ?? b }
            return angle(a, b)
        }
        return PoseSpec(
            anchor: anchor.interpolated(to: other.anchor, t),
            shin: angle(shin, other.shin),
            thigh: angle(thigh, other.thigh),
            torso: angle(torso, other.torso),
            upperArm: angle(upperArm, other.upperArm),
            forearm: angle(forearm, other.forearm),
            rearThigh: optional(rearThigh, other.rearThigh),
            rearShin: optional(rearShin, other.rearShin),
            // The implement can't morph mid-rep; hold the outgoing one until
            // the pose has fully arrived.
            load: t < 1 ? load : other.load
        )
    }

    // MARK: - Resolving to points

    /// Runs the skeleton out from the anchor and returns drawable joints.
    func resolved() -> StickPose {
        let hip: CGPoint, knee: CGPoint, ankle: CGPoint, toe: CGPoint

        switch anchor {
        case let .ground(ankleX, ground, heelLift):
            ankle = CGPoint(x: ankleX, y: ground - heelLift)
            knee = ankle + Self.up(shin) * StickPose.Body.shin
            hip = knee + Self.up(thigh) * StickPose.Body.thigh
            toe = CGPoint(x: ankleX + StickPose.Body.foot, y: ground)
        case let .hip(point):
            hip = point
            knee = hip + Self.down(thigh) * StickPose.Body.thigh
            ankle = knee + Self.down(shin) * StickPose.Body.shin
            // The foot continues the shin's line, rotated forward a quarter turn.
            toe = ankle + Self.down(shin + 90) * StickPose.Body.foot
        }

        let spine = Self.up(torso)
        let neck = hip + spine * StickPose.Body.torso
        let shoulder = hip + spine * (StickPose.Body.torso * 0.88)
        let head = neck + spine * (StickPose.Body.neckToHead + StickPose.Body.headRadius)
        let elbow = shoulder + Self.down(upperArm) * StickPose.Body.upperArm
        let hand = elbow + Self.down(forearm) * StickPose.Body.forearm

        var rearKnee: CGPoint?, rearAnkle: CGPoint?, rearToe: CGPoint?
        if let rearThigh, let rearShin {
            let rk = hip + Self.down(rearThigh) * StickPose.Body.thigh
            let ra = rk + Self.down(rearShin) * StickPose.Body.shin
            rearKnee = rk
            rearAnkle = ra
            rearToe = ra + Self.down(rearShin + 90) * StickPose.Body.foot
        }

        return StickPose(head: head, neck: neck, shoulder: shoulder, elbow: elbow,
                         hand: hand, hip: hip, knee: knee, ankle: ankle, toe: toe,
                         rearKnee: rearKnee, rearAnkle: rearAnkle, rearToe: rearToe,
                         load: load)
    }

    // MARK: - Trig

    /// Unit vector pointing "up" from a joint — 0 straight up, positive forward.
    static func up(_ degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: sin(r), y: -cos(r))
    }

    /// Unit vector pointing "down" from a joint — 0 straight down, positive
    /// forward, 180 straight up.
    static func down(_ degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: sin(r), y: cos(r))
    }
}

extension PoseSpec.Anchor {
    func interpolated(to other: PoseSpec.Anchor, _ t: Double) -> PoseSpec.Anchor {
        switch (self, other) {
        case let (.ground(ax, ag, ah), .ground(bx, bg, bh)):
            return .ground(ankleX: ax + (bx - ax) * t,
                           ground: ag + (bg - ag) * t,
                           heelLift: ah + (bh - ah) * t)
        case let (.hip(a), .hip(b)):
            return .hip(a.lerp(b, t))
        default:
            // Mixing anchors within one movement would teleport the figure.
            // `StickFigureTests` rejects it; this just picks a side.
            return t < 0.5 ? self : other
        }
    }
}

/// A figure in one position, as resolved joint points, ready to draw.
struct StickPose: Equatable {
    var head: CGPoint
    var neck: CGPoint
    var shoulder: CGPoint
    var elbow: CGPoint
    var hand: CGPoint
    var hip: CGPoint
    var knee: CGPoint
    var ankle: CGPoint
    var toe: CGPoint
    var rearKnee: CGPoint?
    var rearAnkle: CGPoint?
    var rearToe: CGPoint?
    var load: LoadKind

    /// Segment lengths, as a fraction of the drawing box. One skeleton for
    /// every pose, so no keyframe can be authored with different proportions.
    enum Body {
        static let shin = 0.185
        static let thigh = 0.195
        static let torso = 0.275
        static let upperArm = 0.135
        static let forearm = 0.135
        static let neckToHead = 0.055
        static let headRadius = 0.05
        static let foot = 0.075
        /// Where the floor sits in the box.
        static let ground = 0.88
    }
}

/// What's in the figure's hands (or on its back), drawn alongside the skeleton
/// so a squat doesn't read as an air squat.
enum LoadKind: Equatable {
    case none
    case barOnBack
    case barInHands
    case dumbbells
    case ball
    /// A cable or band running to a fixed anchor, in the same 0…1 space.
    case cable(anchor: CGPoint)
    /// A fixed overhead bar the figure hangs from.
    case fixedBar
}

/// Furniture the movement is performed on or against.
enum StagePlatform: Equatable {
    case none
    /// A box, bench or step, in the same 0…1 space as the figure.
    case box(minX: Double, maxX: Double, top: Double)
    case wall(x: Double)
}

/// A movement drawn as one keyframe per tempo phase.
///
/// `keyframes[i]` is the position at the **start** of `tempo.phases[i]`, and
/// that phase animates toward `keyframes[i+1]`, wrapping at the end. So a
/// three-second lowering phase takes three seconds on screen, and a "hold"
/// phase whose two keyframes match sits perfectly still — which is exactly what
/// an isometric pause should look like.
struct MovementAnimation: Equatable {
    var keyframes: [PoseSpec]
    /// What the viewer is looking at — a figure standing on a box is a
    /// different picture from one standing on the floor.
    var viewNote: String
    /// A bench, box or wall the movement needs in order to make sense.
    var platform: StagePlatform = .none
    /// Off for a hanging figure, where a floor line would be a lie.
    var showsFloor: Bool = true

    /// The pose at `phase`, `progress` of the way through it.
    func pose(phase: Int, progress: Double) -> StickPose {
        guard !keyframes.isEmpty else {
            return PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                     upperArm: 0, forearm: 0).resolved()
        }
        let index = min(max(phase, 0), keyframes.count - 1)
        let from = keyframes[index]
        let to = keyframes[(index + 1) % keyframes.count]
        // Ease slightly: a real rep accelerates out of the turnaround rather
        // than moving at a machine-constant speed.
        let t = min(max(progress, 0), 1)
        return from.interpolated(to: to, t * t * (3 - 2 * t)).resolved()
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func * (p: CGPoint, s: Double) -> CGPoint { CGPoint(x: p.x * s, y: p.y * s) }

    func lerp(_ other: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    func distance(to other: CGPoint) -> Double {
        let dx = other.x - x, dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}
