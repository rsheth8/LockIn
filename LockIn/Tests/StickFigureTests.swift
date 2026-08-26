import XCTest
import CoreGraphics
@testable import LockIn

/// Hard geometric contracts for every stick-figure clip. These are the
/// invariants that make the animations look like a person rather than a
/// rubber hose — bone lengths never change, planted feet stay planted, and
/// every exercise in Workout Mode has a dedicated clip.
final class StickFigureTests: XCTestCase {

    // MARK: - Coverage

    func testEveryMovementPatternHasKeyframes() {
        for pattern in MovementPattern.allCases {
            let frames = pattern.keyframes
            XCTAssertFalse(frames.isEmpty, "\(pattern.rawValue) has no keyframes")
            XCTAssertGreaterThanOrEqual(frames.count, 2, "\(pattern.rawValue) needs ≥2 keyframes to animate")
        }
    }

    func testEveryWorkoutEngineExerciseHasAGuideAndDedicatedPattern() {
        let goals: Set<FitnessGoal> = [.fatLoss, .fastBowling, .hikingBackpacking]
        var names = Set<String>()
        let kits: [(Equipment, Set<GymAsset>)] = [
            (.apartmentGym, GymAsset.apartmentDefault),
            (.fullGym, Set(GymAsset.allCases)),
            (.homeEquipment, Equipment.homeEquipment.defaultAssets),
            (.bodyweightOnly, Equipment.bodyweightOnly.defaultAssets)
        ]
        for (equipment, assets) in kits {
            names.formUnion(WorkoutEngine.allPrescribableNames(
                equipment: [equipment], assets: assets, goals: goals
            ))
            for dayOffset in 0..<7 {
                var comps = DateComponents()
                comps.year = 2026; comps.month = 8; comps.day = 24 + dayOffset // Mon…Sun week
                let date = Calendar.current.date(from: comps)!
                for exercise in WorkoutEngine.session(
                    for: date, goals: goals, equipment: [equipment], assets: assets
                ).exercises {
                    names.insert(exercise.name)
                }
            }
        }

        XCTAssertFalse(names.isEmpty)
        for name in names.sorted() {
            guard let guide = ExerciseLibrary.guide(for: name) else {
                XCTFail("No ExerciseGuide for \"\(name)\"")
                continue
            }
            // Dedicated clip — never the generic .hold fallback. Plank, pallof,
            // dead bug, hip-flexor stretch each have their own pattern.
            if guide.pattern == .hold {
                XCTFail("\"\(name)\" still maps to generic .hold — give it a dedicated clip")
            }
            XCTAssertEqual(
                MovementPattern.frames[guide.pattern]?.isEmpty, false,
                "\"\(name)\" → \(guide.pattern.rawValue) has no frames"
            )
        }
    }

    func testNoExerciseMapsToMissingRotateCase() {
        // Regression: older guides referenced `.rotate`, which never existed
        // on the FK MovementPattern enum.
        for name in ExerciseLibrary.coveredExerciseNames {
            let pattern = ExerciseLibrary.guide(for: name)!.pattern
            XCTAssertNotNil(MovementPattern(rawValue: pattern.rawValue))
        }
    }

    // MARK: - Bone length constancy

    func testBoneLengthsConstantAcrossEveryPhaseOfEveryPattern() {
        let R = StickFigureRig.self
        let tolerance: CGFloat = 0.6 // sub-unit; FK rounding only

        for pattern in MovementPattern.allCases {
            for step in 0..<16 {
                let phase = Double(step) / 16.0
                // Use the un-anchored pose skeleton for length checks — anchoring
                // is a rigid translate and can't change lengths, but measuring
                // pre-anchor keeps the test focused on FK itself.
                let s = pattern.pose(atPhase: phase).skeleton()

                assertLen(s.hip, s.nearKnee, R.thigh, "\(pattern.rawValue) near thigh @\(step)", tol: tolerance)
                assertLen(s.nearKnee, s.nearAnkle, R.shin, "\(pattern.rawValue) near shin @\(step)", tol: tolerance)
                assertLen(s.hip, s.farKnee, R.thigh, "\(pattern.rawValue) far thigh @\(step)", tol: tolerance)
                assertLen(s.farKnee, s.farAnkle, R.shin, "\(pattern.rawValue) far shin @\(step)", tol: tolerance)
                assertLen(s.shoulder, s.nearElbow, R.upperArm, "\(pattern.rawValue) near upper arm @\(step)", tol: tolerance)
                assertLen(s.nearElbow, s.nearHand, R.forearm, "\(pattern.rawValue) near forearm @\(step)", tol: tolerance)
                assertLen(s.shoulder, s.farElbow, R.upperArm, "\(pattern.rawValue) far upper arm @\(step)", tol: tolerance)
                assertLen(s.farElbow, s.farHand, R.forearm, "\(pattern.rawValue) far forearm @\(step)", tol: tolerance)
                assertLen(s.hip, s.shoulder, R.torso, "\(pattern.rawValue) torso @\(step)", tol: tolerance)
            }
        }
    }

    // MARK: - Anchoring

    func testPlantedPatternsKeepNearFootOnGround() {
        let planted: [MovementPattern] = MovementPattern.allCases.filter {
            if case .planted = $0.anchor { return true }
            return false
        }
        XCTAssertFalse(planted.isEmpty)

        for pattern in planted {
            for step in 0..<12 {
                let phase = Double(step) / 12.0
                let s = pattern.skeleton(atPhase: phase)
                let pose = pattern.pose(atPhase: phase)
                // Lowest contact should sit on the ground (minus intentional lift).
                let lowest = s.contactPoints.map(\.y).max()!
                XCTAssertEqual(
                    lowest, StickFigureRig.ground - pose.lift, accuracy: 0.75,
                    "\(pattern.rawValue) phase \(step): lowest contact \(lowest) not on ground"
                )
            }
        }
    }

    func testHandPinnedPullKeepsNearHandOnBar() {
        let pattern = MovementPattern.pullVertical
        guard case .handPinned(let bar) = pattern.anchor else {
            return XCTFail("pullVertical should be hand-pinned")
        }
        for step in 0..<12 {
            let s = pattern.skeleton(atPhase: Double(step) / 12.0)
            XCTAssertEqual(s.nearHand.x, bar.x, accuracy: 0.5)
            XCTAssertEqual(s.nearHand.y, bar.y, accuracy: 0.5)
        }
    }

    func testToePinnedStepUpKeepsNearToeFixed() {
        let pattern = MovementPattern.stepUp
        guard case .toePinned(let pin) = pattern.anchor else {
            return XCTFail("stepUp should be toe-pinned")
        }
        for step in 0..<12 {
            let s = pattern.skeleton(atPhase: Double(step) / 12.0)
            XCTAssertEqual(s.nearToe.x, pin.x, accuracy: 0.5, "stepUp toe x drifted at \(step)")
            XCTAssertEqual(s.nearToe.y, pin.y, accuracy: 0.5, "stepUp toe y drifted at \(step)")
        }
    }

    func testFlatStandingPoseHasLevelSole() {
        let s = StickFigurePose.standing.skeleton()
        XCTAssertEqual(s.nearHeel.y, s.nearToe.y, accuracy: 1.0, "standing near sole not level")
        XCTAssertEqual(s.farHeel.y, s.farToe.y, accuracy: 1.5, "standing far sole not level")
    }

    // MARK: - Distinctness (clips shouldn't be copies of each other)

    func testSprintAndJogAreVisuallyDistinct() {
        let sprint = MovementPattern.sprint.skeleton(atPhase: 0.125)
        let jog = MovementPattern.jog.skeleton(atPhase: 0.125)
        // Sprint has a markedly bigger forward lean and higher knee drive.
        let sprintLean = abs(sprint.shoulder.x - sprint.hip.x)
        let jogLean = abs(jog.shoulder.x - jog.hip.x)
        XCTAssertGreaterThan(sprintLean, jogLean + 2, "sprint should lean further than jog")
    }

    func testStepUpAndLungeAreDistinct() {
        // Step-up props include a platform; lunge does not.
        XCTAssertTrue(MovementPattern.stepUp.props.contains {
            if case .platformUnderNearFoot = $0 { return true }
            return false
        })
        XCTAssertFalse(MovementPattern.lunge.props.contains {
            if case .platformUnderNearFoot = $0 { return true }
            return false
        })
    }

    // MARK: - The figure has to hold together

    /// Every drawn bone, walked as a graph from the hip, must reach every
    /// joint the figure draws. Regression: the leg chain used to stop at the
    /// ankle and draw the sole as a separate heel→toe line, so on every
    /// single clip the foot hung unattached about six units below the end of
    /// the shin.
    func testEveryJointIsConnectedToTheRestOfTheSkeleton() {
        for pattern in MovementPattern.allCases {
            for step in 0..<8 {
                let s = pattern.skeleton(atPhase: Double(step) / 8)
                let bones = s.spineSegments + s.nearSegments + s.farSegments

                func key(_ p: CGPoint) -> String { String(format: "%.2f,%.2f", p.x, p.y) }
                var reached: Set<String> = [key(s.hip)]
                var changed = true
                while changed {
                    changed = false
                    for (a, b) in bones {
                        let ka = key(a), kb = key(b)
                        if reached.contains(ka) && !reached.contains(kb) { reached.insert(kb); changed = true }
                        if reached.contains(kb) && !reached.contains(ka) { reached.insert(ka); changed = true }
                    }
                }
                // The head hangs off the neck stem, which is drawn to `neckJoin`
                // rather than to the head centre — check that separately.
                for point in s.allPoints where point != s.head {
                    XCTAssertTrue(
                        reached.contains(key(point)),
                        "\(pattern.rawValue) phase \(step): a joint is drawn detached from the body"
                    )
                }
                XCTAssertTrue(reached.contains(key(s.neckJoin)) || reached.contains(key(s.shoulder)))
            }
        }
    }

    /// Nothing the figure draws may sink through the floor it is standing on —
    /// joints or the underside of the skull. Regression: the supine clips
    /// (dead bug, glute bridge, hip thrust) authored their hip height by hand
    /// and buried the back of the head up to six units under the ground line.
    func testNothingIsDrawnThroughTheFloor() {
        for pattern in MovementPattern.allCases where pattern.props.contains(.ground) {
            for step in 0..<24 {
                let phase = Double(step) / 24
                let s = pattern.skeleton(atPhase: phase)
                let floor = StickFigureRig.ground - pattern.pose(atPhase: phase).lift
                let lowestJoint = s.allPoints.map(\.y).max()!
                let skullUnderside = s.head.y + StickFigureRig.headRadius
                XCTAssertLessThanOrEqual(
                    max(lowestJoint, skullUnderside), floor + 0.5,
                    "\(pattern.rawValue) phase \(step) is drawn below the ground line"
                )
            }
        }
    }

    /// A clip whose joints barely move renders as a still image, which reads
    /// as a broken animation rather than a deliberate isometric. Plank and the
    /// generic hold used to move 2–5 units over a three-second cycle.
    func testEveryClipVisiblyMoves() {
        for pattern in MovementPattern.allCases {
            var travel: CGFloat = 0
            for joint in 0..<6 {
                var lo = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
                var hi = CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity)
                for step in 0..<32 {
                    let s = pattern.skeleton(atPhase: Double(step) / 32)
                    let p = [s.head, s.nearHand, s.farHand, s.nearKnee, s.nearAnkle, s.hip][joint]
                    lo = CGPoint(x: min(lo.x, p.x), y: min(lo.y, p.y))
                    hi = CGPoint(x: max(hi.x, p.x), y: max(hi.y, p.y))
                }
                travel = max(travel, hypot(hi.x - lo.x, hi.y - lo.y))
            }
            XCTAssertGreaterThan(
                travel, 6,
                "\(pattern.rawValue) barely moves (\(travel) units) — it will read as a frozen frame"
            )
        }
    }

    // MARK: - Framing

    /// Every clip draws the figure at the same human scale, and none of them
    /// overflow the card. Fitting each pattern to its own bounding box made a
    /// compact half-kneeling stretch render nearly twice the size of a jump,
    /// so flicking between exercises resized the person.
    func testClipsShareOneFigureScaleAndAlwaysFit() {
        let canvas = CGSize(width: 200, height: 200)
        let natural = 200 / StickFigureRig.nominalFrame

        var atNaturalScale = 0
        for pattern in MovementPattern.allCases {
            let (scale, origin) = pattern.layout(in: canvas)
            XCTAssertLessThanOrEqual(scale, natural + 0.001,
                                     "\(pattern.rawValue) is magnified past natural size")
            XCTAssertGreaterThan(scale, natural * 0.7,
                                 "\(pattern.rawValue) is shrunk to less than 70% of every other clip")
            if abs(scale - natural) < 0.001 { atNaturalScale += 1 }

            let box = pattern.viewBox
            let drawn = CGRect(x: origin.x + box.minX * scale, y: origin.y + box.minY * scale,
                               width: box.width * scale, height: box.height * scale)
            XCTAssertGreaterThanOrEqual(drawn.minX, -0.5, "\(pattern.rawValue) overflows left")
            XCTAssertGreaterThanOrEqual(drawn.minY, -0.5, "\(pattern.rawValue) overflows top")
            XCTAssertLessThanOrEqual(drawn.maxX, canvas.width + 0.5, "\(pattern.rawValue) overflows right")
            XCTAssertLessThanOrEqual(drawn.maxY, canvas.height + 0.5, "\(pattern.rawValue) overflows bottom")
        }
        XCTAssertGreaterThan(atNaturalScale, MovementPattern.allCases.count / 2,
                             "most clips should land on the shared natural scale")
    }

    // MARK: - Draw order

    /// The head is filled with the page ground before it is stroked, which is
    /// what masks the arms of a pull-up or an overhead lockout instead of
    /// letting them draw through the face — so it has to be drawn last. Props
    /// the figure stands on go behind the body; gear it holds goes in front.
    func testElementsAreOrderedBackToFront() {
        for pattern in MovementPattern.allCases {
            let elements = pattern.elements(atPhase: 0.3)
            guard case .head = elements.last else {
                return XCTFail("\(pattern.rawValue): head is not the last element drawn")
            }
            let firstBone = elements.firstIndex { if case .bone = $0 { return true }; return false }
            XCTAssertNotNil(firstBone, "\(pattern.rawValue) draws no bones")

            // A figure whose weight is on the floor casts a contact patch, and
            // it has to go down before anything else. A figure up on a box
            // (step-up, calf raise) touches nothing at ground level, so it
            // correctly casts nothing.
            let touchesFloor = pattern.skeleton(atPhase: 0.3).contactPoints
                .contains { $0.y > StickFigureRig.ground - 5 }
            if pattern.props.contains(.ground) && touchesFloor {
                guard case .shadow = elements.first else {
                    return XCTFail("\(pattern.rawValue): contact shadow should be drawn first")
                }
            } else if case .shadow = elements.first, !touchesFloor {
                XCTFail("\(pattern.rawValue): casts a shadow with nothing touching the floor")
            }
            for prop in pattern.props where prop.drawsBehindFigure {
                let count = prop.primitives(for: pattern.skeleton(atPhase: 0.3),
                                            reference: pattern.referenceSkeleton).count
                XCTAssertGreaterThan(count, 0)
            }
        }
    }

    // MARK: - Equipment

    /// A held barbell has to stay in the hand at every phase, not just at the
    /// keyframes.
    func testBarbellPlateTracksTheHand() {
        for pattern in MovementPattern.allCases where pattern.props.contains(.barbellAtHand) {
            for step in 0..<12 {
                let phase = Double(step) / 12
                let s = pattern.skeleton(atPhase: phase)
                let plates = StickFigureProp.barbellAtHand
                    .primitives(for: s, reference: pattern.referenceSkeleton)
                    .compactMap { primitive -> CGPoint? in
                        if case .circle(let c, _) = primitive { return c }
                        return nil
                    }
                guard let plate = plates.first else {
                    return XCTFail("\(pattern.rawValue) draws no plate at phase \(phase)")
                }
                XCTAssertEqual(plate.x, s.nearHand.x, accuracy: 0.01, pattern.rawValue)
                XCTAssertEqual(plate.y, s.nearHand.y, accuracy: 0.01, pattern.rawValue)
            }
        }
    }

    /// A deadlift starts with the bar on the floor. The first cut left the
    /// plate hanging nine units in mid-air at the bottom of the rep, which is
    /// the one thing that separates a deadlift from a stiff-legged hinge.
    func testDeadliftBarReachesTheFloor() {
        // Not phase 0.5: a lift's lowering half is deliberately slower than its
        // drive, so the far end of the rep lands at `restingPhase`, not
        // halfway through the clock.
        let bottom = MovementPattern.deadlift.skeleton(atPhase: MovementPattern.deadlift.restingPhase)
        let plateBottom = bottom.nearHand.y + StickFigureProp.plateRadius
        XCTAssertEqual(plateBottom, StickFigureRig.ground, accuracy: 1.5,
                       "deadlift bar doesn't reach the ground at the bottom of the rep")

        let top = MovementPattern.deadlift.skeleton(atPhase: 0)
        XCTAssertLessThan(top.nearHand.y + StickFigureProp.plateRadius, StickFigureRig.ground - 20,
                          "deadlift lockout should carry the bar well clear of the floor")
    }

    /// The rucksack hangs off the spine's *back*. The rig's angle convention
    /// rotates positive toward the direction the figure faces, so the original
    /// `spine - 90` strapped the pack to the walker's chest.
    func testRuckPackRidesOnTheBack() {
        let pattern = MovementPattern.ruckWalk
        for step in 0..<8 {
            let s = pattern.skeleton(atPhase: Double(step) / 8)
            let points = StickFigureProp.pack
                .primitives(for: s, reference: pattern.referenceSkeleton)
                .flatMap { primitive -> [CGPoint] in
                    if case .polygon(let pts) = primitive { return pts }
                    return []
                }
            XCTAssertFalse(points.isEmpty)
            // The figure faces screen-right, so every corner of the pack has to
            // sit to the left of the spine line at its own height.
            for corner in points {
                let t = (corner.y - s.hip.y) / (s.shoulder.y - s.hip.y)
                let spineX = s.hip.x + (s.shoulder.x - s.hip.x) * t
                XCTAssertLessThan(corner.x, spineX + 0.5,
                                  "pack corner \(corner) is in front of the walker")
            }
        }
    }

    /// A platform has to be under the foot it is supposed to be supporting —
    /// both feet of it, heel included — and its top has to be the surface that
    /// foot is standing on. The calf-raise step used to derive its height from
    /// the *dropped heel*, which collapsed the whole box to a 4-unit sliver.
    func testPlatformsSupportTheFootStandingOnThem() {
        let cases: [(MovementPattern, Bool)] = [(.stepUp, true), (.stepDown, true),
                                                (.calfRaise, true), (.splitSquat, false)]
        for (pattern, nearFoot) in cases {
            let reference = pattern.referenceSkeleton
            let top = pattern.props.compactMap { prop -> CGRect? in
                switch prop {
                case .platformUnderNearFoot, .platformUnderFarFoot:
                    return prop.primitives(for: reference, reference: reference).first?.bounds
                default: return nil
                }
            }.first
            guard let box = top else { return XCTFail("\(pattern.rawValue) has no platform") }

            XCTAssertGreaterThan(box.height, 10, "\(pattern.rawValue) platform is a sliver")
            let toe = nearFoot ? reference.nearToe : reference.farToe
            XCTAssertEqual(box.minY, toe.y, accuracy: 0.5,
                           "\(pattern.rawValue) platform top isn't the surface the toe rests on")
            XCTAssertTrue((box.minX...box.maxX).contains(toe.x),
                          "\(pattern.rawValue) toe is off the side of its own platform")
        }
        // The step-up's whole foot — not just the toe — has to be on the box.
        let stepUp = MovementPattern.stepUp.referenceSkeleton
        guard case .platformUnderNearFoot = MovementPattern.stepUp.props[1] else { return XCTFail() }
        let box = MovementPattern.stepUp.props[1]
            .primitives(for: stepUp, reference: stepUp).first!.bounds
        XCTAssertTrue((box.minX...box.maxX).contains(stepUp.nearHeel.x),
                      "step-up heel hangs off the back of the box")
    }

    /// The rear foot of a split squat is parked on a box and stays there while
    /// the hips travel past it. Hand-authored angles had it drifting 13 units.
    func testSplitSquatRearFootStaysOnItsBox() {
        let pattern = MovementPattern.splitSquat
        let reference = pattern.referenceSkeleton.farToe
        for step in 0..<16 {
            let toe = pattern.skeleton(atPhase: Double(step) / 16).farToe
            XCTAssertEqual(toe.x, reference.x, accuracy: 3.0, "rear foot slid along the box at \(step)")
            XCTAssertEqual(toe.y, reference.y, accuracy: 3.0, "rear foot sank into the box at \(step)")
        }
    }

    // MARK: - Motion quality

    /// Motion has to be smooth in its *second* derivative, not just continuous.
    ///
    /// Straight lerping between keyframes holds a constant speed inside each
    /// segment and then changes direction on a single frame at every authored
    /// pose, which reads as a hitch. The giveaway is a spike in how abruptly
    /// speed itself changes between frames — not in speed, which is high for
    /// any explosive clip and says nothing about smoothness. Measuring peak
    /// speed instead flags a box jump, which is supposed to be fast.
    ///
    /// Measured worst case across all clips: 2.92 with the old piecewise
    /// lerp, 1.05 with the spline. The threshold sits between them.
    func testNoJointHitchesAtKeyframeBoundaries() {
        let steps = 240
        for pattern in MovementPattern.allCases {
            var deltas: [CGFloat] = []
            var previous = pattern.skeleton(atPhase: 0)
            for step in 1...steps {
                let s = pattern.skeleton(atPhase: Double(step) / Double(steps))
                let moved = zip(previous.allPoints, s.allPoints)
                    .map { hypot($1.x - $0.x, $1.y - $0.y) }
                    .reduce(0, +)
                deltas.append(moved)
                previous = s
            }
            let median = deltas.sorted()[deltas.count / 2]
            guard median > 0.0001 else { continue }
            let jerk = zip(deltas, deltas.dropFirst()).map { abs($1 - $0) }.max() ?? 0
            XCTAssertLessThan(
                jerk / median, 2.0,
                "\(pattern.rawValue): speed changes \(jerk / median)x its median step in one frame — a velocity hitch"
            )
        }
    }

    /// The lowering half of a lift should take longer than the drive out of
    /// it, and the seam between the two must not itself be a jolt.
    func testLiftsSpendLongerOnTheEccentric() {
        let slower: [MovementPattern] = [.squat, .hinge, .deadlift, .benchPress, .boxJump, .stepDown]
        for pattern in slower {
            XCTAssertGreaterThan(pattern.eccentricShare, 0.5,
                                 "\(pattern.rawValue) should lower slower than it lifts")
        }
        // Gait cycles and holds have no eccentric/concentric split to skew.
        for pattern in MovementPattern.allCases where pattern.loop == .cycle {
            XCTAssertEqual(pattern.eccentricShare, 0.5, accuracy: 0.0001,
                           "\(pattern.rawValue) is a cycle and shouldn't be tempo-skewed")
        }
    }

    /// Soft floor contact may only ever hold the figure a hair *above* the
    /// true lowest joint — never let one sink through the floor.
    func testSoftFloorContactNeverSinksBelowTheTrueLowestPoint() {
        let cases: [[CGFloat]] = [[152], [152, 152], [150, 152, 148], [152, 151.8, 140, 90],
                                  [152, 152, 152, 152]]
        for ys in cases {
            let soft = MovementPattern.softLowest(ys)
            let hard = ys.max()!
            XCTAssertGreaterThanOrEqual(soft, hard - 0.0001,
                                        "soft contact dropped below the true lowest point")
            XCTAssertLessThan(soft, hard + 0.75,
                              "soft contact floats the figure too far off the floor")
        }
    }

    /// A frozen clip (Reduce Motion, off-screen) must still show the movement.
    /// Holding phase zero would freeze most lifts standing bolt upright.
    func testRestingPhaseShowsTheMovementNotTheStartPosition() {
        for pattern in MovementPattern.allCases where pattern.loop == .pingPong {
            let start = pattern.skeleton(atPhase: 0)
            let resting = pattern.skeleton(atPhase: pattern.restingPhase)
            let moved = zip(start.allPoints, resting.allPoints)
                .map { hypot($1.x - $0.x, $1.y - $0.y) }
                .max() ?? 0
            XCTAssertGreaterThan(
                moved, 5,
                "\(pattern.rawValue): frozen pose is barely distinct from the start position"
            )
        }
    }

    /// Trails and impact flashes are extras — they must never be the only
    /// thing moving, and they must stay behind the figure in the draw order.
    func testTrailsAreDrawnBehindTheFigure() {
        for pattern in MovementPattern.allCases {
            let elements = pattern.elements(atPhase: 0.3)
            let lastTrail = elements.lastIndex { if case .trail = $0 { return true }; return false }
            let firstBone = elements.firstIndex { if case .bone = $0 { return true }; return false }
            guard let lastTrail, let firstBone else { continue }
            XCTAssertLessThan(lastTrail, firstBone,
                              "\(pattern.rawValue): a motion trail draws over the figure")
        }
    }

    // MARK: - Renderer smoke

    func testContactSheetRendererProducesImagesForEveryPattern() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LockInStickSheets-\(UUID().uuidString)", isDirectory: true)
        let urls = try StickFigureRenderer.writeAllContactSheets(to: dir, cellSize: 120)
        XCTAssertEqual(urls.count, MovementPattern.allCases.count)
        for url in urls {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? NSNumber
            XCTAssertGreaterThan(size?.intValue ?? 0, 500, "\(url.lastPathComponent) looks empty")
        }

        // Also drop a copy into the workspace so a human (or the agent) can
        // open the sheets without digging through DerivedData.
        let workspaceSheets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // LockIn/
            .appendingPathComponent("StickFigureSheets", isDirectory: true)
        try? FileManager.default.removeItem(at: workspaceSheets)
        _ = try StickFigureRenderer.writeAllContactSheets(to: workspaceSheets, cellSize: 160)
    }

    // MARK: - Helpers

    private func assertLen(
        _ a: CGPoint, _ b: CGPoint, _ expected: CGFloat,
        _ label: String, tol: CGFloat
    ) {
        let dx = a.x - b.x, dy = a.y - b.y
        let len = sqrt(dx * dx + dy * dy)
        XCTAssertEqual(len, expected, accuracy: tol, label)
    }
}
