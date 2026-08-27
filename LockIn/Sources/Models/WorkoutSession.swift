import Foundation

enum WorkoutFocus: String, Codable {
    case lowerStrength      // squat/hinge patterns — base strength for bowling power + rucking durability
    case upperPull          // pull/row/rotator-cuff — shoulder durability for bowling, pack-carrying posture
    case rotationalPower    // med ball throws, cable rotations — bowling-specific power transfer
    case sprintConditioning // repeat sprints/intervals — bowling run-up speed + match-day repeat efforts
    case ruckEndurance      // weighted incline walking / stairs — direct backpacking specificity
    case unilateralLegs     // step-ups, lunges, single-leg — trail stability, injury-proofing on descents
    case core               // anti-rotation/anti-extension — lumbar stress protection for fast bowlers
    case mobilityRecovery   // hips/shoulders/ankles/thoracic spine

    var title: String {
        switch self {
        case .lowerStrength: return "Lower Body Strength"
        case .upperPull: return "Upper Pull + Shoulder Health"
        case .rotationalPower: return "Rotational Power"
        case .sprintConditioning: return "Sprint Conditioning"
        case .ruckEndurance: return "Rucking / Loaded Cardio"
        case .unilateralLegs: return "Unilateral Leg Strength"
        case .core: return "Core & Anti-Rotation"
        case .mobilityRecovery: return "Mobility & Recovery"
        }
    }

    /// Default rest between sets, in seconds.
    ///
    /// Heavy compound strength work needs full phosphocreatine recovery or the
    /// later sets stop training strength and start training fatigue (~2–3 min).
    /// Power work rests long for the same reason — a slow med ball throw is a
    /// wasted rep. Conditioning, core and mobility rest short by design, because
    /// the incomplete recovery *is* the stimulus.
    var restSeconds: Int {
        switch self {
        case .lowerStrength, .upperPull: return 150
        case .rotationalPower, .unilateralLegs: return 120
        case .sprintConditioning: return 90
        case .core: return 60
        case .mobilityRecovery: return 30
        case .ruckEndurance: return 0   // one continuous effort, nothing to rest between
        }
    }

    var systemImage: String {
        switch self {
        case .lowerStrength: return "figure.strengthtraining.traditional"
        case .upperPull: return "figure.play"
        case .rotationalPower: return "figure.cricket"
        case .sprintConditioning: return "figure.run"
        case .ruckEndurance: return "figure.hiking"
        case .unilateralLegs: return "figure.step.training"
        case .core: return "figure.core.training"
        case .mobilityRecovery: return "figure.flexibility"
        }
    }
}

struct ExercisePrescription: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: String        // string to allow "8-10", "30s", "400m" etc.
    let note: String?

    init(id: UUID = UUID(), name: String, sets: Int, reps: String, note: String? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.note = note
    }

    /// The prescribed reps as a countable range, or nil when `reps` measures
    /// something else — time ("45s"), distance ("20-30m"), or an effort cue
    /// ("conversational pace").
    ///
    /// This is what separates a lift the app can progress you on from a lift it
    /// can only tick off. Per-limb suffixes are stripped first: "8-10/leg" is
    /// still 8–10 reps, just done twice.
    var repRange: ClosedRange<Int>? {
        var text = reps.trimmingCharacters(in: .whitespaces)
        for suffix in ["/leg", "/side", "/arm"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let low = Int(parts[0]), low > 0 else { return nil }
        guard parts.count == 2 else { return low...low }
        guard let high = Int(parts[1]), high >= low else { return nil }
        return low...high
    }

    /// Whether a weight is worth recording. Anything with countable reps
    /// qualifies — a Pallof press or a dead bug can be loaded even though the
    /// prescription doesn't say so — while timed and distance work cannot.
    /// The weight itself always stays optional, so bodyweight sets never block.
    var tracksLoad: Bool { repRange != nil }
}

struct WorkoutSession: Codable, Equatable, Identifiable {
    let id: UUID
    let focus: WorkoutFocus
    let goalTags: [FitnessGoal]     // which goals this session serves, shown so the "why" is visible
    let exercises: [ExercisePrescription]
    let equipmentNote: String

    init(id: UUID = UUID(), focus: WorkoutFocus, goalTags: [FitnessGoal], exercises: [ExercisePrescription], equipmentNote: String) {
        self.id = id
        self.focus = focus
        self.goalTags = goalTags
        self.exercises = exercises
        self.equipmentNote = equipmentNote
    }

    var summaryLine: String {
        exercises.map { "\($0.name) \($0.sets)x\($0.reps)" }.joined(separator: ", ")
    }

    /// Every set in the session — the denominator the portal counts against.
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets }
    }

    /// Rest owed after a set of `exercise`. A single-set prescription (a ruck, a
    /// 5-minute jog) has nothing to rest *between*, so it goes straight on.
    func restSeconds(after exercise: ExercisePrescription) -> Int {
        exercise.sets <= 1 ? 0 : focus.restSeconds
    }
}

/// One set, as actually performed.
///
/// Weight and reps are both optional: a bodyweight pull-up has reps but no
/// load, and a plank has neither. A set with nothing recorded still counts as
/// done — refusing to log work because the numbers weren't entered would make
/// the portal worse than a notes app.
struct SetEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var weightLbs: Double?
    var reps: Int?
    var completedAt: Date

    init(id: UUID = UUID(), weightLbs: Double? = nil, reps: Int? = nil, completedAt: Date = Date()) {
        self.id = id
        self.weightLbs = weightLbs
        self.reps = reps
        self.completedAt = completedAt
    }

    /// "135 × 8", "× 8", or "done" — the shortest honest description.
    var shortLine: String {
        switch (weightLbs, reps) {
        case let (weight?, reps?): return "\(Self.trim(weight))×\(reps)"
        case let (weight?, nil): return "\(Self.trim(weight)) lb"
        case let (nil, reps?): return "×\(reps)"
        case (nil, nil): return "done"
        }
    }

    /// Weights are entered in 2.5 lb steps, so drop a trailing ".0" but keep a
    /// real half — "137.5" must not read as "137".
    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Every set of one exercise within a session. Keyed by **name**, not by the
/// prescription's id — `WorkoutEngine` mints a fresh UUID each time it builds a
/// session, so an id would never match across two workouts.
struct ExerciseLog: Codable, Equatable, Identifiable {
    var id: UUID
    var exerciseName: String
    var sets: [SetEntry]

    init(id: UUID = UUID(), exerciseName: String, sets: [SetEntry]) {
        self.id = id
        self.exerciseName = exerciseName
        self.sets = sets
    }

    /// The heaviest load recorded — the number that answers "what am I lifting
    /// on this now?" better than an average would.
    var topWeightLbs: Double? {
        sets.compactMap(\.weightLbs).max()
    }

    /// Load × reps summed across sets. The fairest single number for "did this
    /// session beat the last one", since it catches both more weight and more
    /// reps at the same weight.
    var volumeLbs: Double {
        sets.reduce(0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
    }

    /// "135×8, 135×8, 135×6"
    var summaryLine: String {
        sets.map(\.shortLine).joined(separator: ", ")
    }
}

/// A finished (or deliberately cut short) session, kept permanently. This is the
/// record progression reads from.
struct CompletedWorkout: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var focus: WorkoutFocus
    var exercises: [ExerciseLog]
    var durationSeconds: Int

    init(id: UUID = UUID(), date: Date, focus: WorkoutFocus,
         exercises: [ExerciseLog], durationSeconds: Int) {
        self.id = id
        self.date = date
        self.focus = focus
        self.exercises = exercises
        self.durationSeconds = durationSeconds
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    func log(for exerciseName: String) -> ExerciseLog? {
        exercises.first { $0.exerciseName == exerciseName }
    }
}

/// A workout left half-finished. Persisted so walking out of the portal —
/// deliberately, or because the phone locked and something else grabbed focus —
/// doesn't cost you your place, or the numbers you already logged.
struct WorkoutProgress: Codable, Equatable {
    /// The `ScheduledEvent` this belongs to. Progress from a different event, or
    /// a different day, is stale and must not be resumed into.
    var eventID: UUID
    var dayKey: String
    /// Sets performed so far, parallel to `WorkoutSession.exercises`.
    var loggedSets: [[SetEntry]]
    var exerciseIndex: Int
    var elapsedSeconds: Int
}
