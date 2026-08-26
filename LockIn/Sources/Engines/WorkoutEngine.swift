import Foundation

/// Builds the **Hybrid PPL + sport days** week — the best overall split for
/// LockIn's audience (fat loss + bowling and/or hiking on apartment-gym kit).
///
/// Weekly map (Calendar weekday: Sun=1 … Sat=7):
/// - Mon Push · Tue Pull · Wed Legs  → each pattern ~2×/week with Fri/Sat extras
/// - Thu Bowling power+sprint (or mobility if bowling is off)
/// - Fri Push B (volume / accessories)
/// - Sat Hike conditioning (or Pull B if hiking is off)
/// - Sun Mobility + easy zone-2 flush
///
/// Why this beats plain PPL or a bro-split here:
/// - Frequency evidence sits near 2×/week per muscle for hypertrophy while
///   cutting (Schoenfeld). Pure bro-splits under-serve that on a deficit.
/// - Sport days are additive finishers with their own recovery, not bolted
///   onto the end of a heavy legs day where quality dies.
/// - Apartment-gym variants (Smith, cable, Peloton, rower) resolve in
///   `pickVariant` so the prescription matches the room.
enum WorkoutEngine {

    enum EquipmentTier: Equatable {
        case fullGym, apartment, home, bodyweight

        static func resolve(_ equipment: [Equipment]) -> EquipmentTier {
            if equipment.contains(.fullGym) { return .fullGym }
            if equipment.contains(.apartmentGym) { return .apartment }
            if equipment.contains(.homeEquipment) { return .home }
            return .bodyweight
        }

        var noteSuffix: String {
            switch self {
            case .fullGym: return "Full gym — free weights + machines."
            case .apartment: return "Apartment gym — Smith, cables, DBs, cardio machines."
            case .home: return "Home setup — dumbbells / bands / bench."
            case .bodyweight: return "Bodyweight only."
            }
        }
    }

    /// Full hybrid week as an ordered list (Mon→Sun), useful for Lab / tests.
    static func weeklySplit(for goals: Set<FitnessGoal>,
                            equipment: [Equipment] = [.apartmentGym],
                            assets: Set<GymAsset> = GymAsset.apartmentDefault,
                            brief: TrainingBrief = .empty) -> [WorkoutSession] {
        let tier = EquipmentTier.resolve(equipment)
        let kit = assets.isEmpty ? (equipment.first?.defaultAssets ?? []) : assets
        // Align to Mon…Sun for display; `session(for:)` uses real weekday.
        let days: [(String, () -> WorkoutSession)] = [
            ("Mon", { pushSession(goals: goals, kit: kit, secondary: false) }),
            ("Tue", { pullSession(goals: goals, kit: kit, secondary: false) }),
            ("Wed", { legsSession(goals: goals, kit: kit) }),
            ("Thu", {
                goals.contains(.fastBowling)
                    ? bowlingPowerSession(kit: kit)
                    : mobilitySession(goals: goals, kit: kit)
            }),
            ("Fri", { pushSession(goals: goals, kit: kit, secondary: true) }),
            ("Sat", {
                goals.contains(.hikingBackpacking)
                    ? hikeConditioningSession(kit: kit)
                    : pullSession(goals: goals, kit: kit, secondary: true)
            }),
            ("Sun", { mobilitySession(goals: goals, kit: kit) })
        ]
        return days.map { _, builder in
            var session = adapt(builder(), to: tier, kit: kit)
            if !brief.isEmpty { session = annotate(session, with: brief) }
            return session
        }
    }

    /// Picks today's session from the hybrid calendar map.
    static func session(for date: Date, goals: Set<FitnessGoal>,
                        equipment: [Equipment] = [.apartmentGym],
                        assets: Set<GymAsset> = GymAsset.apartmentDefault,
                        brief: TrainingBrief = .empty) -> WorkoutSession {
        let tier = EquipmentTier.resolve(equipment)
        let kit = assets.isEmpty ? (equipment.first?.defaultAssets ?? []) : assets
        let weekday = Calendar.current.component(.weekday, from: date) // 1=Sun
        let raw: WorkoutSession
        switch weekday {
        case 2: raw = pushSession(goals: goals, kit: kit, secondary: false)      // Mon
        case 3: raw = pullSession(goals: goals, kit: kit, secondary: false)      // Tue
        case 4: raw = legsSession(goals: goals, kit: kit)                        // Wed
        case 5:                                                                  // Thu sport
            raw = goals.contains(.fastBowling)
                ? bowlingPowerSession(kit: kit)
                : mobilitySession(goals: goals, kit: kit)
        case 6: raw = pushSession(goals: goals, kit: kit, secondary: true)       // Fri
        case 7:                                                                  // Sat sport
            raw = goals.contains(.hikingBackpacking)
                ? hikeConditioningSession(kit: kit)
                : pullSession(goals: goals, kit: kit, secondary: true)
        default: raw = mobilitySession(goals: goals, kit: kit)                   // Sun
        }
        var session = adapt(raw, to: tier, kit: kit)
        if !brief.isEmpty { session = annotate(session, with: brief) }
        return session
    }

    static func weeklySplit(for goals: Set<FitnessGoal>, equipment: [Equipment]) -> [WorkoutSession] {
        weeklySplit(for: goals, equipment: equipment, assets: equipment.first?.defaultAssets ?? [], brief: .empty)
    }

    static func session(for date: Date, goals: Set<FitnessGoal>, equipment: [Equipment]) -> WorkoutSession {
        session(for: date, goals: goals, equipment: equipment, assets: equipment.first?.defaultAssets ?? [], brief: .empty)
    }

    /// Every concrete exercise name the engine can emit for the given kit —
    /// used to keep ExerciseLibrary coverage honest.
    static func allPrescribableNames(equipment: [Equipment] = [.apartmentGym],
                                     assets: Set<GymAsset> = GymAsset.apartmentDefault,
                                     goals: Set<FitnessGoal> = [.fatLoss, .fastBowling, .hikingBackpacking]) -> Set<String> {
        Set(weeklySplit(for: goals, equipment: equipment, assets: assets).flatMap { $0.exercises.map(\.name) })
    }

    // MARK: - Adaptation

    static func adapt(_ session: WorkoutSession, to tier: EquipmentTier, kit: Set<GymAsset>) -> WorkoutSession {
        let exercises = session.exercises.map { pickVariant($0, tier: tier, kit: kit) }
        return WorkoutSession(
            id: session.id,
            focus: session.focus,
            goalTags: session.goalTags,
            exercises: exercises,
            equipmentNote: kitNote(tier: tier, kit: kit)
        )
    }

    private static func kitNote(tier: EquipmentTier, kit: Set<GymAsset>) -> String {
        let highlights = [
            kit.contains(.smithMachine) ? "Smith" : nil,
            kit.contains(.cablePulley) ? "cable" : nil,
            kit.contains(.dumbbells) ? "DBs" : nil,
            kit.contains(.medicineBall) ? "med ball" : nil,
            kit.contains(.rower) ? "rower" : nil,
            kit.contains(.peloton) ? "Peloton" : nil,
            kit.contains(.treadmill) ? "treadmill" : nil
        ].compactMap { $0 }
        if highlights.isEmpty { return tier.noteSuffix }
        return "Hybrid PPL · \(tier.noteSuffix) Using: \(highlights.joined(separator: ", "))."
    }

    private static func annotate(_ session: WorkoutSession, with brief: TrainingBrief) -> WorkoutSession {
        guard let tip = brief.sessionEmphases.first else { return session }
        var exercises = session.exercises
        if let first = exercises.first {
            let note = [first.note, "Focus: \(tip)"].compactMap { $0 }.joined(separator: " · ")
            exercises[0] = ExercisePrescription(id: first.id, name: first.name, sets: first.sets, reps: first.reps, note: note)
        }
        return WorkoutSession(id: session.id, focus: session.focus, goalTags: session.goalTags, exercises: exercises, equipmentNote: session.equipmentNote)
    }

    private static func pickVariant(_ exercise: ExercisePrescription, tier: EquipmentTier, kit: Set<GymAsset>) -> ExercisePrescription {
        let name: String
        switch exercise.name {
        case "SquatPattern":
            if kit.contains(.barbellRack) { name = "Back Squat" }
            else if kit.contains(.smithMachine) { name = "Smith Squat" }
            else if kit.contains(.dumbbells) { name = "Goblet Squat" }
            else if tier == .bodyweight { name = "Air Squat" }
            else { name = "Back Squat" }
        case "HingePattern":
            if kit.contains(.barbellRack) { name = "Romanian Deadlift" }
            else if kit.contains(.smithMachine) { name = "Smith Romanian Deadlift" }
            else if kit.contains(.dumbbells) { name = "Dumbbell Romanian Deadlift" }
            else { name = "Single-Leg Hip Hinge" }
        case "HorizontalPress":
            if kit.contains(.barbellRack) && kit.contains(.bench) { name = "Barbell Bench Press" }
            else if kit.contains(.smithMachine) && kit.contains(.bench) { name = "Smith Bench Press" }
            else if kit.contains(.dumbbells) && kit.contains(.bench) { name = "Dumbbell Bench Press" }
            else if kit.contains(.dumbbells) { name = "Floor Press" }
            else { name = "Push-Up" }
        case "VerticalPress":
            if kit.contains(.barbellRack) { name = "Overhead Press" }
            else if kit.contains(.dumbbells) { name = "Seated Dumbbell Shoulder Press" }
            else if kit.contains(.smithMachine) { name = "Smith Overhead Press" }
            else { name = "Pike Push-Up" }
        case "HorizontalPull":
            if kit.contains(.barbellRack) { name = "Barbell Row" }
            else if kit.contains(.cablePulley) { name = "Seated Cable Row" }
            else if kit.contains(.dumbbells) { name = "Dumbbell Row" }
            else if kit.contains(.smithMachine) { name = "Smith Bent-Over Row" }
            else { name = "Inverted Row" }
        case "VerticalPull":
            if kit.contains(.cablePulley) { name = "Lat Pulldown" }
            else if kit.contains(.pullUpBar) { name = "Pull-Up" }
            else if kit.contains(.dumbbells) { name = "Dumbbell Pullover" }
            else { name = "Band Pulldown / Doorway Row" }
        case "FacePullPattern":
            if kit.contains(.cablePulley) { name = "Cable Face Pull" }
            else if kit.contains(.resistanceBands) { name = "Band Face Pull" }
            else { name = "Prone Y-T-W Raise" }
        case "WoodchopPattern":
            if kit.contains(.cablePulley) { name = "Cable Woodchop" }
            else if kit.contains(.medicineBall) { name = "Med Ball Rotational Slam" }
            else { name = "Standing Twist Reach" }
        case "RotationalThrow":
            if kit.contains(.medicineBall) { name = "Rotational Med Ball Throw" }
            else if kit.contains(.cablePulley) { name = "Cable Rotational Row" }
            else { name = "Standing Rotational Punch" }
        case "PallofPattern":
            if kit.contains(.cablePulley) { name = "Cable Pallof Press" }
            else if kit.contains(.resistanceBands) { name = "Band Pallof Press" }
            else { name = "Dead Bug (anti-rotation)" }
        case "UnilateralLunge":
            if kit.contains(.dumbbells) { name = "Dumbbell Bulgarian Split Squat" }
            else if kit.contains(.smithMachine) { name = "Smith Split Squat" }
            else { name = "Reverse Lunge" }
        case "StepPattern":
            if kit.contains(.dumbbells) { name = "Dumbbell Step-Up" }
            else { name = "Step-Up / Step-Down" }
        case "CarryPattern":
            if kit.contains(.dumbbells) { name = "Dumbbell Farmer's Carry" }
            else { name = "Loaded Backpack Carry" }
        case "Zone2Cardio":
            if kit.contains(.peloton) { name = "Peloton Zone 2 Ride" }
            else if kit.contains(.rower) { name = "Rower Zone 2" }
            else if kit.contains(.treadmill) { name = "Treadmill Incline Walk" }
            else { name = "Brisk Outdoor Walk" }
        case "SprintIntervals":
            if kit.contains(.treadmill) { name = "Treadmill Sprint Intervals" }
            else if kit.contains(.rower) { name = "Rower Sprint Intervals" }
            else { name = "Outdoor Sprint Repeats" }
        case "TricepFinish":
            if kit.contains(.cablePulley) { name = "Cable Tricep Pushdown" }
            else if kit.contains(.dumbbells) { name = "Dumbbell Overhead Tricep Ext." }
            else { name = "Diamond Push-Up" }
        case "BicepFinish":
            if kit.contains(.cablePulley) { name = "Cable Curl" }
            else if kit.contains(.dumbbells) { name = "Dumbbell Curl" }
            else { name = "Towel Curl / Isometric" }
        default:
            return exercise
        }
        return ExercisePrescription(id: exercise.id, name: name, sets: exercise.sets, reps: exercise.reps, note: exercise.note)
    }

    // MARK: - Sessions

    private static func pushSession(goals: Set<FitnessGoal>, kit _: Set<GymAsset>, secondary: Bool) -> WorkoutSession {
        var exercises = [
            ExercisePrescription(name: "HorizontalPress", sets: secondary ? 3 : 4, reps: "6-8", note: "Primary press — progressive overload."),
            ExercisePrescription(name: "VerticalPress", sets: 3, reps: "8-10"),
            ExercisePrescription(name: "TricepFinish", sets: 3, reps: "10-12"),
            ExercisePrescription(name: "PallofPattern", sets: 3, reps: "10/side", note: "Anti-rotation — bowling lumbar insurance.")
        ]
        if goals.contains(.fastBowling) {
            exercises.append(ExercisePrescription(name: "FacePullPattern", sets: 3, reps: "15", note: "Shoulder durability for overhead load."))
        }
        return WorkoutSession(focus: .push, goalTags: [.fatLoss, .fastBowling], exercises: exercises, equipmentNote: "")
    }

    private static func pullSession(goals: Set<FitnessGoal>, kit _: Set<GymAsset>, secondary: Bool) -> WorkoutSession {
        var exercises = [
            ExercisePrescription(name: "VerticalPull", sets: secondary ? 3 : 4, reps: "6-10"),
            ExercisePrescription(name: "HorizontalPull", sets: 3, reps: "8-10"),
            ExercisePrescription(name: "FacePullPattern", sets: 3, reps: "12-15", note: "Rear delt + cuff — bowling arm health."),
            ExercisePrescription(name: "BicepFinish", sets: 2, reps: "10-12")
        ]
        if goals.contains(.hikingBackpacking) {
            exercises.append(ExercisePrescription(name: "CarryPattern", sets: 3, reps: "40m", note: "Pack-carry grip and trap endurance."))
        }
        return WorkoutSession(focus: .pull, goalTags: [.fatLoss, .fastBowling, .hikingBackpacking], exercises: exercises, equipmentNote: "")
    }

    private static func legsSession(goals: Set<FitnessGoal>, kit _: Set<GymAsset>) -> WorkoutSession {
        var exercises = [
            ExercisePrescription(name: "SquatPattern", sets: 4, reps: "5-8", note: "Front-foot landing force capacity."),
            ExercisePrescription(name: "HingePattern", sets: 3, reps: "8", note: "Posterior chain — lumbar protection under load."),
            ExercisePrescription(name: "UnilateralLunge", sets: 3, reps: "8-10/leg")
        ]
        if goals.contains(.hikingBackpacking) {
            exercises.append(ExercisePrescription(name: "StepPattern", sets: 3, reps: "10/leg", note: "Trail ascent + eccentric descent control."))
        }
        return WorkoutSession(focus: .legs, goalTags: [.fatLoss, .fastBowling, .hikingBackpacking], exercises: exercises, equipmentNote: "")
    }

    private static func bowlingPowerSession(kit _: Set<GymAsset>) -> WorkoutSession {
        WorkoutSession(
            focus: .rotationalPower,
            goalTags: [.fastBowling],
            exercises: [
                ExercisePrescription(name: "RotationalThrow", sets: 4, reps: "6/side", note: "Hip-shoulder separation for the bowling action."),
                ExercisePrescription(name: "WoodchopPattern", sets: 3, reps: "10/side"),
                ExercisePrescription(name: "SprintIntervals", sets: 6, reps: "20-30s on / 60s off", note: "Run-up speed + repeat-spell demand."),
                ExercisePrescription(name: "PallofPattern", sets: 3, reps: "12/side"),
                ExercisePrescription(name: "Bowling-Action Shadow Reps (no ball)", sets: 3, reps: "8/side", note: "Groove the pattern without run-up load.")
            ],
            equipmentNote: ""
        )
    }

    private static func hikeConditioningSession(kit _: Set<GymAsset>) -> WorkoutSession {
        WorkoutSession(
            focus: .ruckEndurance,
            goalTags: [.hikingBackpacking, .fatLoss],
            exercises: [
                ExercisePrescription(name: "Zone2Cardio", sets: 1, reps: "40-55 min", note: "Conversational pace — multi-day aerobic base."),
                ExercisePrescription(name: "StepPattern", sets: 3, reps: "12/leg"),
                ExercisePrescription(name: "CarryPattern", sets: 3, reps: "40-60m"),
                ExercisePrescription(name: "UnilateralLunge", sets: 2, reps: "8/leg", note: "Light — quality over load today.")
            ],
            equipmentNote: ""
        )
    }

    private static func mobilitySession(goals _: Set<FitnessGoal>, kit: Set<GymAsset>) -> WorkoutSession {
        WorkoutSession(
            focus: .mobilityRecovery,
            goalTags: [.fatLoss, .fastBowling, .hikingBackpacking],
            exercises: [
                ExercisePrescription(name: "Thoracic Spine Rotation Drill", sets: 2, reps: "10/side"),
                ExercisePrescription(name: "Hip Flexor + 90/90 Stretch", sets: 2, reps: "45s/side"),
                ExercisePrescription(name: "Ankle Dorsiflexion Drill", sets: 2, reps: "10/side", note: "Bowling front-foot + trail terrain."),
                ExercisePrescription(name: "Zone2Cardio", sets: 1, reps: "20-30 min easy", note: "Optional flush — keep it easy.")
            ],
            equipmentNote: kit.contains(.stretchingMats) ? "Mat work + easy cardio." : "Mat optional."
        )
    }
}
