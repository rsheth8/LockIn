import Foundation
import Combine

/// Drives a workout session set by set: which exercise you're on, how many sets
/// are banked, and the rest clock between them.
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

    @Published private(set) var phase: Phase = .working
    @Published private(set) var exerciseIndex: Int = 0
    /// Sets completed per exercise, parallel to `session.exercises`.
    @Published private(set) var completedSets: [Int]
    @Published private(set) var restRemaining: Int = 0
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var elapsedSeconds: Int = 0

    /// Fired after every mutation so the caller can persist a resume point.
    /// Left nil in tests, where persistence is noise.
    var onProgress: ((WorkoutProgress) -> Void)?

    private let eventID: UUID
    private let dayKey: String

    /// - Parameter resuming: a previously saved point. Applied only when it
    ///   belongs to this event, this day, and this session shape — a schedule
    ///   rebuild can change the exercise list underneath a stale record.
    init(session: WorkoutSession, eventID: UUID, dayKey: String, resuming: WorkoutProgress? = nil) {
        self.session = session
        self.eventID = eventID
        self.dayKey = dayKey
        self.completedSets = Array(repeating: 0, count: session.exercises.count)

        if let resuming,
           resuming.eventID == eventID,
           resuming.dayKey == dayKey,
           resuming.completedSets.count == session.exercises.count {
            // Clamp rather than trust: a saved count above the prescription
            // would leave the progress bar reading past 100%.
            self.completedSets = zip(resuming.completedSets, session.exercises).map {
                min(max(0, $0), $1.sets)
            }
            self.elapsedSeconds = max(0, resuming.elapsedSeconds)
            self.exerciseIndex = min(max(0, resuming.exerciseIndex), max(0, session.exercises.count - 1))
            if self.setsDone >= session.totalSets { self.phase = .finished }
        }
    }

    // MARK: - Derived

    var currentExercise: ExercisePrescription? {
        guard session.exercises.indices.contains(exerciseIndex) else { return nil }
        return session.exercises[exerciseIndex]
    }

    /// Sets banked on the current exercise.
    var currentSetsDone: Int {
        completedSets.indices.contains(exerciseIndex) ? completedSets[exerciseIndex] : 0
    }

    var setsDone: Int { completedSets.reduce(0, +) }

    var totalSets: Int { session.totalSets }

    /// 0...1 across the whole session — what the progress bar draws.
    var fraction: Double {
        totalSets > 0 ? Double(setsDone) / Double(totalSets) : 0
    }

    var isFinished: Bool { phase == .finished }

    func isComplete(exerciseAt index: Int) -> Bool {
        guard session.exercises.indices.contains(index) else { return false }
        return completedSets[index] >= session.exercises[index].sets
    }

    /// "Set 2 of 4" — the label on the primary button.
    var setLabel: String {
        guard let exercise = currentExercise else { return "Done" }
        return "Set \(min(currentSetsDone + 1, exercise.sets)) of \(exercise.sets)"
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

    // MARK: - Actions

    /// Banks the set in front of you and moves the session on: more sets left on
    /// this exercise means rest then repeat; otherwise advance to the next
    /// unfinished exercise, or finish.
    func completeSet() {
        guard phase != .finished, let exercise = currentExercise else { return }

        completedSets[exerciseIndex] = min(completedSets[exerciseIndex] + 1, exercise.sets)
        let rest = session.restSeconds(after: exercise)

        if completedSets[exerciseIndex] >= exercise.sets {
            guard let next = nextUnfinishedIndex() else {
                phase = .finished
                restRemaining = 0
                save()
                return
            }
            exerciseIndex = next
        }

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
        guard completedSets.indices.contains(exerciseIndex), completedSets[exerciseIndex] > 0 else { return }
        completedSets[exerciseIndex] -= 1
        phase = .working
        restRemaining = 0
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
            completedSets: completedSets,
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
