import Foundation

/// Drives an active Workout Mode session: which exercise/set you're on, the
/// rest countdown between sets, and total elapsed time.
///
/// Deliberately doesn't auto-time the *work* phase — the reps you actually
/// need (a plank hold, a set of squats) vary too much person to person for a
/// guessed countdown to be anything but annoying. It does auto-time *rest*
/// between sets, which is where a timer genuinely earns its keep: nobody
/// reliably self-polices 90 seconds of rest without one.
///
/// `tick()` is a plain method rather than being wired to a live `Timer`
/// internally, so a second of wall-clock time can be simulated directly in
/// tests without waiting on one.
@MainActor
final class WorkoutModeController: ObservableObject {
    enum Phase: Equatable {
        case working, resting, finished
    }

    let session: WorkoutSession

    @Published private(set) var exerciseIndex = 0
    @Published private(set) var setNumber = 1
    @Published private(set) var phase: Phase = .working
    @Published private(set) var restSecondsRemaining = 0
    @Published private(set) var elapsedSeconds = 0
    @Published var isPaused = false
    /// Sets actually logged this session. The only honest evidence that any
    /// training happened — elapsed time is not, since the screen sitting open
    /// on a bench accrues it just as fast as work does.
    @Published private(set) var completedSets = 0

    private var timer: Timer?

    init(session: WorkoutSession) {
        self.session = session
    }

    var currentExercise: ExercisePrescription { session.exercises[exerciseIndex] }
    var totalExercises: Int { session.exercises.count }
    var isLastExercise: Bool { exerciseIndex == session.exercises.count - 1 }
    /// 0...1 across the whole session, exercise-granular (not set-granular —
    /// set-level jumps read as noisy jitter on a progress bar this short).
    var progress: Double { Double(exerciseIndex) / Double(max(session.exercises.count, 1)) }

    // MARK: - Timer plumbing

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Advances state by one second. Public and side-effect-pure enough to
    /// drive directly from tests.
    func tick() {
        guard !isPaused, phase != .finished else { return }
        elapsedSeconds += 1
        guard phase == .resting else { return }
        restSecondsRemaining -= 1
        if restSecondsRemaining > 0 && restSecondsRemaining <= 3 {
            Haptics.tap()
        } else if restSecondsRemaining <= 0 {
            restSecondsRemaining = 0
            Haptics.confirm()
            phase = .working
        }
    }

    // MARK: - Actions

    /// The current set is done. Either starts rest before the next set of
    /// the same exercise, or moves on if that was the last set.
    func completeSet() {
        guard phase == .working else { return }
        Haptics.tap()
        completedSets += 1
        if setNumber < currentExercise.sets {
            setNumber += 1
            beginRest()
        } else {
            advanceExercise()
        }
    }

    func skipRest() {
        guard phase == .resting else { return }
        restSecondsRemaining = 0
        phase = .working
    }

    /// Moves to the next exercise (fresh set count, no forced rest — the
    /// walk to different equipment is its own transition). Finishes the
    /// session from the last exercise.
    func advanceExercise() {
        if isLastExercise {
            finish()
            return
        }
        exerciseIndex += 1
        setNumber = 1
        phase = .working
    }

    /// Bails out of the current exercise entirely — doesn't count as sets
    /// completed, just moves on. Distinct from `advanceExercise()` mainly in
    /// intent at the call site (a "Skip" affordance vs. finishing normally).
    func skipExercise() { advanceExercise() }

    func finish() {
        phase = .finished
        stopTimer()
    }

    /// User ends the session early, from wherever they are.
    func end() { finish() }

    /// Whether ending now should be able to credit today's workout. One logged
    /// set is the bar — enough that a real (if short) session counts, and
    /// enough that opening the screen and closing it does not.
    var hasCreditableWork: Bool { completedSets > 0 }

    private func beginRest() {
        let seconds = Self.restSeconds(focus: session.focus, reps: currentExercise.reps)
        guard seconds > 0 else {
            phase = .working
            return
        }
        restSecondsRemaining = seconds
        phase = .resting
    }

    // MARK: - Rest duration

    /// An explicit rest baked into the reps string (e.g. "10x20m, 20s rest")
    /// wins; otherwise a sensible default per training focus. Pure and static
    /// so it's trivially testable without spinning up a controller.
    static func restSeconds(focus: WorkoutFocus, reps: String) -> Int {
        if let explicit = explicitRestSeconds(from: reps) { return explicit }
        switch focus {
        case .push, .pull, .legs, .lowerStrength, .rotationalPower, .upperPull:
            return 90
        case .sprintConditioning:
            return 30
        case .unilateralLegs, .core:
            return 45
        case .ruckEndurance:
            return 60
        case .mobilityRecovery:
            return 15
        }
    }

    static func explicitRestSeconds(from reps: String) -> Int? {
        guard let range = reps.range(of: #"(\d+)s rest"#, options: .regularExpression) else { return nil }
        let digits = reps[range].prefix(while: \.isNumber)
        return Int(digits)
    }
}
