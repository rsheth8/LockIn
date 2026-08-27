import Foundation
import Combine

/// Drives a workout session set by set: which exercise you're on, what you
/// lifted for each set, and the rest clock between them.
///
/// The clock is *not* owned here — `tick()` is called once a second by the view.
/// That keeps the whole state machine synchronous and testable: a test can run
/// three minutes of rest in three lines without waiting three minutes.
@MainActor
final class WorkoutRunner: ObservableObject {

    enum Phase: String, Equatable {
        case working    // the set is in front of you
        case resting    // clock is counting down to the next set
        case finished   // every set banked, or you called it early
    }

    let session: WorkoutSession
    /// Past sessions, for "last time" and the progression suggestion.
    let history: [CompletedWorkout]

    @Published private(set) var phase: Phase = .working
    @Published private(set) var exerciseIndex: Int = 0
    /// Sets performed per exercise, parallel to `session.exercises`.
    @Published private(set) var loggedSets: [[SetEntry]]
    @Published private(set) var restRemaining: Int = 0
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var elapsedSeconds: Int = 0

    /// The weight and reps the next "set done" will record. Seeded from the
    /// progression suggestion and carried forward from the last set you logged,
    /// so a straight-sets exercise is one tap per set.
    @Published var entryWeightLbs: Double?
    @Published var entryReps: Int?

    /// Fired after every mutation so the caller can persist a resume point.
    /// Left nil in tests, where persistence is noise.
    var onProgress: ((WorkoutProgress) -> Void)?

    private let eventID: UUID
    private let dayKey: String
    private let startedAt = Date()

    /// - Parameter resuming: a previously saved point. Applied only when it
    ///   belongs to this event, this day, and this session shape — a schedule
    ///   rebuild can change the exercise list underneath a stale record.
    init(session: WorkoutSession, eventID: UUID, dayKey: String,
         history: [CompletedWorkout] = [], resuming: WorkoutProgress? = nil) {
        self.session = session
        self.history = history
        self.eventID = eventID
        self.dayKey = dayKey
        self.loggedSets = Array(repeating: [], count: session.exercises.count)

        if let resuming,
           resuming.eventID == eventID,
           resuming.dayKey == dayKey,
           resuming.loggedSets.count == session.exercises.count {
            // Clamp rather than trust: more sets than the prescription calls for
            // would leave the progress bar reading past 100%.
            self.loggedSets = zip(resuming.loggedSets, session.exercises).map {
                Array($0.prefix($1.sets))
            }
            self.elapsedSeconds = max(0, resuming.elapsedSeconds)
            self.exerciseIndex = min(max(0, resuming.exerciseIndex), max(0, session.exercises.count - 1))
            if self.setsDone >= session.totalSets { self.phase = .finished }
        }
        primeEntry()
    }

    // MARK: - Derived

    var currentExercise: ExercisePrescription? {
        guard session.exercises.indices.contains(exerciseIndex) else { return nil }
        return session.exercises[exerciseIndex]
    }

    /// Sets banked on the current exercise.
    var currentSetsDone: Int {
        loggedSets.indices.contains(exerciseIndex) ? loggedSets[exerciseIndex].count : 0
    }

    var setsDone: Int { loggedSets.reduce(0) { $0 + $1.count } }

    var totalSets: Int { session.totalSets }

    /// 0...1 across the whole session — what the progress bar draws.
    var fraction: Double {
        totalSets > 0 ? Double(setsDone) / Double(totalSets) : 0
    }

    var isFinished: Bool { phase == .finished }

    func setsDone(forExerciseAt index: Int) -> Int {
        loggedSets.indices.contains(index) ? loggedSets[index].count : 0
    }

    func isComplete(exerciseAt index: Int) -> Bool {
        guard session.exercises.indices.contains(index) else { return false }
        return setsDone(forExerciseAt: index) >= session.exercises[index].sets
    }

    /// "Set 2 of 4" — the label on the primary button.
    var setLabel: String {
        guard let exercise = currentExercise else { return "Done" }
        return "Set \(min(currentSetsDone + 1, exercise.sets)) of \(exercise.sets)"
    }

    /// Today's advice for the exercise in front of you.
    var suggestion: ProgressionSuggestion {
        guard let exercise = currentExercise else {
            return ProgressionSuggestion(targetWeightLbs: nil, targetReps: nil,
                                         headline: "", reason: "", kind: .untracked)
        }
        return ProgressionEngine.suggestion(for: exercise, focus: session.focus, history: history)
    }

    /// What this exercise looked like the last time it came round.
    var lastPerformance: ExerciseLog? {
        guard let exercise = currentExercise else { return nil }
        return ProgressionEngine.lastPerformance(of: exercise.name, in: history)
    }

    /// Sets already logged on the current exercise, for the "this session so
    /// far" line — the only way to see set 1 while you're resting before set 2.
    var currentSets: [SetEntry] {
        loggedSets.indices.contains(exerciseIndex) ? loggedSets[exerciseIndex] : []
    }

    // MARK: - Clock

    /// One second of wall time. A paused or finished session ignores it, so the
    /// elapsed readout reflects time actually trained.
    func tick() {
        guard !isPaused, phase != .finished else { return }
        elapsedSeconds += 1
        guard phase == .resting else { return }
        restRemaining -= 1
        if restRemaining <= 0 {
            restRemaining = 0
            phase = .working
            save()
        }
    }

    // MARK: - Entry field

    func adjustWeight(by delta: Double) {
        let base = entryWeightLbs ?? suggestion.targetWeightLbs ?? 0
        entryWeightLbs = max(0, base + delta)
    }

    func adjustReps(by delta: Int) {
        let base = entryReps ?? currentExercise?.repRange?.upperBound ?? 0
        entryReps = max(0, base + delta)
    }

    func setWeight(_ value: Double?) { entryWeightLbs = value.map { max(0, $0) } }
    func setReps(_ value: Int?) { entryReps = value.map { max(0, $0) } }

    /// Seeds the entry fields for the current exercise: repeat what you just
    /// lifted on it, else take the progression target.
    private func primeEntry() {
        guard let exercise = currentExercise, exercise.tracksLoad else {
            entryWeightLbs = nil
            entryReps = nil
            return
        }
        let advice = suggestion
        if let latest = currentSets.last {
            entryWeightLbs = latest.weightLbs ?? advice.targetWeightLbs
            entryReps = latest.reps ?? advice.targetReps
        } else {
            entryWeightLbs = advice.targetWeightLbs
            entryReps = advice.targetReps
        }
    }

    // MARK: - Actions

    /// Banks the set in front of you — with whatever's in the entry fields — and
    /// moves the session on: more sets left on this exercise means rest then
    /// repeat; otherwise advance to the next unfinished exercise, or finish.
    func completeSet() {
        guard phase != .finished, let exercise = currentExercise else { return }
        guard currentSetsDone < exercise.sets else { return }

        let entry = SetEntry(
            weightLbs: exercise.tracksLoad ? entryWeightLbs : nil,
            reps: exercise.tracksLoad ? entryReps : nil
        )
        loggedSets[exerciseIndex].append(entry)
        let rest = session.restSeconds(after: exercise)

        if currentSetsDone >= exercise.sets {
            guard let next = nextUnfinishedIndex() else {
                phase = .finished
                restRemaining = 0
                save()
                return
            }
            exerciseIndex = next
        }

        primeEntry()

        if rest > 0 {
            restRemaining = rest
            phase = .resting
        } else {
            phase = .working
        }
        save()
    }

    /// Undoes a mis-tap on the current exercise. Deliberately only touches the
    /// exercise you're looking at — a general undo stack is more machinery than
    /// a fat-fingered set is worth.
    func undoSet() {
        guard loggedSets.indices.contains(exerciseIndex), !loggedSets[exerciseIndex].isEmpty else { return }
        loggedSets[exerciseIndex].removeLast()
        phase = .working
        restRemaining = 0
        primeEntry()
        save()
    }

    func skipRest() {
        guard phase == .resting else { return }
        restRemaining = 0
        phase = .working
        save()
    }

    func addRest(_ seconds: Int = 30) {
        guard phase == .resting else { return }
        restRemaining += seconds
    }

    func togglePause() {
        guard phase != .finished else { return }
        isPaused.toggle()
    }

    /// Jump straight to an exercise — for reordering on the fly when a rack is
    /// taken, which is the normal case in a busy gym.
    func jump(to index: Int) {
        guard session.exercises.indices.contains(index), phase != .finished else { return }
        exerciseIndex = index
        phase = .working
        restRemaining = 0
        primeEntry()
        save()
    }

    /// Ends the session where it stands. What's banked stays banked — this is
    /// "that's enough", not "throw it away".
    func finish() {
        phase = .finished
        restRemaining = 0
        isPaused = false
        save()
    }

    // MARK: - Result

    /// The permanent record of what was just done. Exercises with no sets are
    /// dropped — logging a skipped lift as "0 sets" would poison the
    /// progression history with a session you never performed.
    func completedWorkout() -> CompletedWorkout {
        let logs = zip(session.exercises, loggedSets).compactMap { exercise, sets -> ExerciseLog? in
            sets.isEmpty ? nil : ExerciseLog(exerciseName: exercise.name, sets: sets)
        }
        return CompletedWorkout(date: startedAt, focus: session.focus,
                                exercises: logs, durationSeconds: elapsedSeconds)
    }

    /// Exercises that beat their previous outing, for the summary screen.
    func improvements() -> [String] {
        ProgressionEngine.improvements(in: completedWorkout(), history: history)
    }

    // MARK: - Internals

    /// The next exercise with sets still owed, searching forward and then
    /// wrapping — so skipping something and coming back to it works.
    private func nextUnfinishedIndex() -> Int? {
        let count = session.exercises.count
        guard count > 0 else { return nil }
        for offset in 1...count {
            let index = (exerciseIndex + offset) % count
            if !isComplete(exerciseAt: index) { return index }
        }
        return nil
    }

    private func save() {
        onProgress?(WorkoutProgress(
            eventID: eventID,
            dayKey: dayKey,
            loggedSets: loggedSets,
            exerciseIndex: exerciseIndex,
            elapsedSeconds: elapsedSeconds
        ))
    }
}

extension Int {
    /// Seconds as "4:05" — the format every clock on this screen uses.
    var asClock: String {
        // Qualified: inside an Int extension, bare `max` resolves to `Int.max`.
        let total = Swift.max(0, self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
