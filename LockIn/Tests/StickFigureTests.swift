import XCTest
import CoreGraphics
@testable import LockIn

/// The figure is only honest if it moves at the tempo it's shown next to, and
/// only readable if the skeleton holds together between keyframes.
final class StickFigureTests: XCTestCase {

    // MARK: - The pairing that makes the animation match the tempo

    /// One keyframe per tempo phase: phase *i* animates keyframes[i] → [i+1],
    /// wrapping. Break this and a 3-second eccentric plays at the wrong speed.
    func testEveryAnimationHasOneKeyframePerTempoPhase() {
        for name in MovementAnimationLibrary.allNames {
            guard let animation = MovementAnimationLibrary.animation(for: name),
                  let tempo = ExerciseLibrary.guide(for: name)?.tempo else {
                return XCTFail("\(name) has an animation but no tempo to drive it")
            }
            XCTAssertEqual(animation.keyframes.count, tempo.phases.count,
                           "\(name): \(animation.keyframes.count) keyframes for \(tempo.phases.count) phases")
        }
    }

    func testEveryAnimatedMovementIsOneTheAppCanPrescribe() {
        let prescribed = Set(
            WorkoutEngine.weeklySplit(for: [.fatLoss, .fastBowling, .hikingBackpacking])
                .flatMap { $0.exercises.map(\.name) }
        )
        for name in MovementAnimationLibrary.allNames {
            XCTAssertTrue(prescribed.contains(name), "\(name) is animated but never prescribed")
        }
    }

    /// Coverage is deliberately partial — rotation and supine drills don't read
    /// as a side-on figure. This pins that decision so a later change is a
    /// choice rather than an accident.
    func testMovementsThatCannotBeDrawnHonestlyHaveNoFigure() {
        for name in ["Rotational Med Ball Throw", "Bowling-Action Shadow Reps (no ball)",
                     "Dead Bug", "Thoracic Spine Rotation Drill",
                     "Step-Down (eccentric focus)", "Single-Leg Calf Raise"] {
            XCTAssertNil(MovementAnimationLibrary.animation(for: name),
                         "\(name) can't be shown honestly side-on")
            XCTAssertNotNil(ExerciseLibrary.guide(for: name),
                            "\(name) still needs its written guide")
        }
    }

    func testAnimationsExistForTheMovementsPeopleAreMostLikelyToGetWrong() {
        for name in ["Barbell Back Squat", "Romanian Deadlift", "Barbell Row",
                     "Bulgarian Split Squat", "Pull-Up / Lat Pulldown"] {
            XCTAssertNotNil(MovementAnimationLibrary.animation(for: name), "\(name) needs a figure")
        }
    }

    // MARK: - Playback

    func testPhaseZeroAtProgressZeroIsTheFirstKeyframe() {
        let animation = MovementAnimationLibrary.animation(for: "Barbell Back Squat")!
        XCTAssertEqual(animation.pose(phase: 0, progress: 0).hip, animation.keyframes[0].resolved().hip)
    }

    func testAPhaseEndsOnTheNextKeyframe() {
        let animation = MovementAnimationLibrary.animation(for: "Barbell Back Squat")!
        let end = animation.pose(phase: 0, progress: 1)
        XCTAssertEqual(end.hip.x, animation.keyframes[1].resolved().hip.x, accuracy: 0.001)
        XCTAssertEqual(end.hip.y, animation.keyframes[1].resolved().hip.y, accuracy: 0.001)
    }

    /// The last phase returns to the start, so the rep loops seamlessly.
    func testTheFinalPhaseWrapsBackToTheOpeningPose() {
        let animation = MovementAnimationLibrary.animation(for: "Barbell Back Squat")!
        let end = animation.pose(phase: animation.keyframes.count - 1, progress: 1)
        XCTAssertEqual(end.hip.y, animation.keyframes[0].resolved().hip.y, accuracy: 0.001)
    }

    /// A "hold" phase has identical keyframes on both sides, so the figure must
    /// sit perfectly still — that stillness is what an isometric looks like.
    func testAHoldPhaseDoesNotMoveTheFigure() {
        let animation = MovementAnimationLibrary.animation(for: "Pallof Press")!
        let start = animation.pose(phase: 1, progress: 0)
        let middle = animation.pose(phase: 1, progress: 0.5)
        let end = animation.pose(phase: 1, progress: 1)
        XCTAssertEqual(start.hand.x, middle.hand.x, accuracy: 0.0001)
        XCTAssertEqual(start.hand.x, end.hand.x, accuracy: 0.0001)
    }

    func testOutOfRangePhasesDoNotCrash() {
        let animation = MovementAnimationLibrary.animation(for: "Barbell Row")!
        _ = animation.pose(phase: -3, progress: 0.5)
        _ = animation.pose(phase: 99, progress: 0.5)
        _ = animation.pose(phase: 0, progress: -1)
        _ = animation.pose(phase: 0, progress: 4)
    }

    // MARK: - The skeleton holds together

    /// Interpolating between poses must not stretch a limb. Lerping joint
    /// positions is only safe because the keyframes share one skeleton — this
    /// catches a keyframe authored with the wrong segment lengths.
    func testLimbLengthsStayWithinToleranceThroughEveryAnimation() {
        for name in MovementAnimationLibrary.allNames {
            let animation = MovementAnimationLibrary.animation(for: name)!
            for phase in animation.keyframes.indices {
                for step in 0...10 {
                    let pose = animation.pose(phase: phase, progress: Double(step) / 10)
                    // Straight-line interpolation shortens a rotating segment at
                    // the midpoint; 25% is well inside "still looks like a leg".
                    assertSegment(pose.hip, pose.knee, StickPose.Body.thigh, name, "thigh")
                    assertSegment(pose.knee, pose.ankle, StickPose.Body.shin, name, "shin")
                    assertSegment(pose.shoulder, pose.elbow, StickPose.Body.upperArm, name, "upper arm")
                    assertSegment(pose.elbow, pose.hand, StickPose.Body.forearm, name, "forearm")
                    assertSegment(pose.hip, pose.neck, StickPose.Body.torso, name, "torso")
                }
            }
        }
    }

    private func assertSegment(_ a: CGPoint, _ b: CGPoint, _ expected: Double,
                               _ name: String, _ label: String) {
        let length = a.distance(to: b)
        XCTAssertGreaterThan(length, expected * 0.75, "\(name): \(label) collapsed to \(length)")
        XCTAssertLessThanOrEqual(length, expected * 1.02, "\(name): \(label) stretched to \(length)")
    }

    /// Every keyframe has to sit inside the box it's drawn into, or limbs get
    /// clipped off the edge of the card.
    func testEveryKeyframeStaysInsideTheDrawingBox() {
        for name in MovementAnimationLibrary.allNames {
            let animation = MovementAnimationLibrary.animation(for: name)!
            for (index, spec) in animation.keyframes.enumerated() {
                let pose = spec.resolved()
                for (label, point) in [("head", pose.head), ("hand", pose.hand),
                                       ("toe", pose.toe), ("ankle", pose.ankle),
                                       ("hip", pose.hip), ("knee", pose.knee)] {
                    XCTAssertTrue((0.0...1.0).contains(point.x),
                                  "\(name) frame \(index): \(label) x = \(point.x)")
                    XCTAssertTrue((0.0...1.0).contains(point.y),
                                  "\(name) frame \(index): \(label) y = \(point.y)")
                }
                if let rearToe = pose.rearToe {
                    XCTAssertTrue((0.0...1.0).contains(rearToe.x),
                                  "\(name) frame \(index): rear toe x = \(rearToe.x)")
                }
            }
        }
    }

    /// A grounded figure must actually stand on the floor. Feet hovering in
    /// mid-air is the most obvious way for a pose to look broken.
    func testStandingFiguresKeepAFootOnTheGround() {
        let onTheFloor = ["Barbell Back Squat", "Romanian Deadlift", "Walking Lunge",
                          "Cable Woodchop", "Barbell Row", "Face Pull", "Pallof Press"]
        for name in onTheFloor {
            let animation = MovementAnimationLibrary.animation(for: name)!
            for (index, spec) in animation.keyframes.enumerated() {
                let pose = spec.resolved()
                XCTAssertEqual(pose.ankle.y, StickPose.Body.ground, accuracy: 0.001,
                               "\(name) frame \(index) is floating")
            }
        }
    }

    /// Figures standing on a box should have their ankle at the box top, not
    /// the floor — otherwise the box is drawn around a figure ignoring it.
    func testFiguresOnAPlatformStandOnIt() {
        for name in ["Weighted Step-Up"] {
            let animation = MovementAnimationLibrary.animation(for: name)!
            guard case let .box(minX, maxX, top) = animation.platform else {
                return XCTFail("\(name) should sit on a box")
            }
            for pose in animation.keyframes.map({ $0.resolved() }) {
                XCTAssertTrue((minX...maxX).contains(pose.ankle.x), "\(name) stands off the box")
                XCTAssertEqual(pose.ankle.y, top, accuracy: 0.02, "\(name) isn't on the box top")
            }
        }
    }

    // MARK: - Geometry

    func testGroundedPoseResolvesUpwardFromTheAnkle() {
        let pose = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                     upperArm: 0, forearm: 0).resolved()
        XCTAssertEqual(pose.ankle.y, StickPose.Body.ground, accuracy: 0.0001)
        XCTAssertEqual(pose.knee.x, 0.5, accuracy: 0.0001, "A vertical shin shouldn't drift")
        XCTAssertLessThan(pose.hip.y, pose.knee.y, "Hip should be above the knee")
        XCTAssertLessThan(pose.neck.y, pose.hip.y, "Neck should be above the hip")
        XCTAssertLessThan(pose.head.y, pose.neck.y)
    }

    func testPositiveAnglesLeanForward() {
        let upright = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                        upperArm: 0, forearm: 0).resolved()
        let hinged = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 60,
                                       upperArm: 0, forearm: 0).resolved()
        XCTAssertGreaterThan(hinged.neck.x, upright.neck.x, "A positive torso angle leans forward")
        XCTAssertGreaterThan(hinged.neck.y, upright.neck.y, "...and therefore lower")
    }

    func testArmAngleZeroHangsStraightDown() {
        let pose = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                     upperArm: 0, forearm: 0).resolved()
        XCTAssertEqual(pose.hand.x, pose.shoulder.x, accuracy: 0.0001)
        XCTAssertGreaterThan(pose.hand.y, pose.shoulder.y)
    }

    func testRearLegIsOnlyBuiltWhenAskedFor() {
        let single = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                       upperArm: 0, forearm: 0).resolved()
        XCTAssertNil(single.rearKnee)
        let split = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                      upperArm: 0, forearm: 0, rear: (-20, -10)).resolved()
        XCTAssertNotNil(split.rearKnee)
        XCTAssertNotNil(split.rearToe)
        XCTAssertLessThan(split.rearKnee!.x, split.hip.x, "A negative rear angle goes backward")
    }

    func testInterpolationIsClampedAtBothEnds() {
        let a = PoseSpec.grounded(ankleX: 0.3, shin: 0, thigh: 0, torso: 0, upperArm: 0, forearm: 0)
        let b = PoseSpec.grounded(ankleX: 0.7, shin: 0, thigh: 0, torso: 0, upperArm: 0, forearm: 0)
        XCTAssertEqual(a.interpolated(to: b, -5).resolved().ankle.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(a.interpolated(to: b, 9).resolved().ankle.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(a.interpolated(to: b, 0.5).resolved().ankle.x, 0.5, accuracy: 0.0001)
    }

    /// Angles take the short way round, so a limb crossing the 180° boundary
    /// swings a few degrees rather than spinning all the way back.
    func testAnglesInterpolateTheShortWayAround() {
        let a = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                  upperArm: 170, forearm: 0)
        let b = PoseSpec.grounded(ankleX: 0.5, shin: 0, thigh: 0, torso: 0,
                                  upperArm: -170, forearm: 0)
        let mid = a.interpolated(to: b, 0.5)
        // Halfway between 170 and -170 the short way is 180, not 0.
        XCTAssertEqual(abs(mid.upperArm), 180, accuracy: 0.001)
    }

    /// Mixing a grounded and a hanging keyframe inside one movement would
    /// teleport the figure mid-rep.
    func testNoAnimationMixesAnchorTypes() {
        for name in MovementAnimationLibrary.allNames {
            let animation = MovementAnimationLibrary.animation(for: name)!
            let grounded = animation.keyframes.map { spec -> Bool in
                if case .ground = spec.anchor { return true }
                return false
            }
            XCTAssertEqual(Set(grounded).count, 1, "\(name) mixes grounded and free keyframes")
        }
    }
}
