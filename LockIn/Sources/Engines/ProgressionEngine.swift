import Foundation

/// Decides what you should be lifting today, from what you lifted last time.
///
/// The model is **double progression**, which is the standard answer for
/// intermediate lifters and the only one that works without a coach watching
/// your bar speed: hold the weight and climb the rep range, and when every set
/// reaches the top of the range, add load and drop back to the bottom.
///
/// Why not "add 5 lb every session" — the linear-progression approach beginners
/// start on: it works for a few months and then stops, and continuing to demand
/// it turns training into a weekly failed rep. Double progression keeps the
/// pressure on without asking for a PR every single session.
///
/// Why a stall rule: two sessions in a row under the bottom of the range means
/// the weight is genuinely too heavy, not that you had a bad day. Grinding a
/// third session at a weight you're missing builds fatigue, not strength, and
/// on the fast-bowling side it's exactly the accumulating-load pattern that
/// precedes lumbar stress injuries. Backing off ~10% and re-climbing is faster
/// than stalling for a month.
enum ProgressionEngine {

    /// How much to add when the range is cleared.
    ///
    /// Heavy lower-body compounds take a bigger jump because 5 lb on a squat is
    /// inside the noise of how much you ate and slept; on a face pull it's a
    /// real step. This is the smallest honest distinction — anything finer
    /// would be guessing at equipment we don't know the user has.
    static func increment(for focus: WorkoutFocus) -> Double {
        focus == .lowerStrength ? 10 : 5
    }

    /// Fraction of load dropped when a lift has stalled twice.
    private static let deloadFraction = 0.10

    /// The most recent time this exercise was actually performed, newest first.
    /// Sessions where it was skipped (logged with no sets) don't count — an
    /// exercise you walked past isn't a data point.
    static func history(of exerciseName: String, in workouts: [CompletedWorkout]) -> [ExerciseLog] {
        workouts
            .sorted { $0.date > $1.date }
            .compactMap { $0.log(for: exerciseName) }
            .filter { !$0.sets.isEmpty }
    }

    static func lastPerformance(of exerciseName: String, in workouts: [CompletedWorkout]) -> ExerciseLog? {
        history(of: exerciseName, in: workouts).first
    }

    /// What to load the bar with, and why.
    static func suggestion(for exercise: ExercisePrescription,
                           focus: WorkoutFocus,
                           history workouts: [CompletedWorkout]) -> ProgressionSuggestion {
        guard let range = exercise.repRange else {
            return ProgressionSuggestion(targetWeightLbs: nil, targetReps: nil,
                                         headline: "Log it when it's done",
                                         reason: "", kind: .untracked)
        }

        let past = history(of: exercise.name, in: workouts)
        guard let last = past.first, let lastWeight = last.topWeightLbs, lastWeight > 0 else {
            return ProgressionSuggestion(
                targetWeightLbs: nil, targetReps: range.upperBound,
                headline: "First time on this",
                reason: "Pick a weight you could stop 2 reps short of failure on. Whatever you log becomes the baseline.",
                kind: .baseline
            )
        }

        let working = last.sets.filter { ($0.weightLbs ?? 0) >= lastWeight }
        let repsAtTopWeight = working.compactMap(\.reps)
        let weightText = SetEntry.trim(lastWeight)

        // Cleared the range on every set at the top weight → earn the jump.
        if !repsAtTopWeight.isEmpty, repsAtTopWeight.allSatisfy({ $0 >= range.upperBound }) {
            let next = round(to: lastWeight + increment(for: focus))
            return ProgressionSuggestion(
                targetWeightLbs: next, targetReps: range.lowerBound,
                headline: "Go up to \(SetEntry.trim(next)) lb",
                reason: "You hit \(range.upperBound) on every set at \(weightText). Back down to \(range.lowerBound)s and climb again.",
                kind: .increase
            )
        }

        // Missed the bottom of the range twice running → the weight is wrong.
        if missedRange(last, range: range, at: lastWeight),
           past.count >= 2, let previous = past.dropFirst().first,
           let previousWeight = previous.topWeightLbs, previousWeight >= lastWeight,
           missedRange(previous, range: range, at: previousWeight) {
            let next = round(to: lastWeight * (1 - deloadFraction))
            return ProgressionSuggestion(
                targetWeightLbs: next, targetReps: range.upperBound,
                headline: "Drop to \(SetEntry.trim(next)) lb",
                reason: "Two sessions under \(range.lowerBound) reps at \(weightText). Take 10% off and build back — grinding it a third time isn't training.",
                kind: .deload
            )
        }

        let best = repsAtTopWeight.max() ?? range.lowerBound
        let needed = range.upperBound
        return ProgressionSuggestion(
            targetWeightLbs: lastWeight, targetReps: min(best + 1, needed),
            headline: "Stay at \(weightText) lb",
            reason: "Last time: \(last.summaryLine). Get \(needed) on all \(exercise.sets) sets and the weight goes up.",
            kind: .hold
        )
    }

    /// True when no set at the session's top weight reached the bottom of the
    /// prescribed range.
    private static func missedRange(_ log: ExerciseLog, range: ClosedRange<Int>, at weight: Double) -> Bool {
        let reps = log.sets.filter { ($0.weightLbs ?? 0) >= weight }.compactMap(\.reps)
        guard !reps.isEmpty else { return false }
        return reps.allSatisfy { $0 < range.lowerBound }
    }

    /// Plates and dumbbells come in 2.5 lb steps at best, so a suggestion of
    /// 121.5 lb is a number nobody can load.
    static func round(to weight: Double) -> Double {
        max(2.5, (weight / 2.5).rounded() * 2.5)
    }

    // MARK: - Session comparison

    /// Exercises in `workout` that beat the previous time they were performed,
    /// by total volume. Drives the "3 lifts up on last time" line after a
    /// session — the payoff that makes logging the numbers feel worth it.
    static func improvements(in workout: CompletedWorkout,
                             history workouts: [CompletedWorkout]) -> [String] {
        let earlier = workouts.filter { $0.id != workout.id && $0.date < workout.date }
        return workout.exercises.filter { log in
            guard log.volumeLbs > 0,
                  let previous = lastPerformance(of: log.exerciseName, in: earlier) else { return false }
            return log.volumeLbs > previous.volumeLbs
        }.map(\.exerciseName)
    }
}

/// What the portal shows above the weight field, and what it prefills.
struct ProgressionSuggestion: Equatable {
    enum Kind: String, Equatable {
        case increase   // cleared the range, add load
        case hold       // inside the range, chase reps
        case deload     // stalled twice, back off
        case baseline   // no history yet
        case untracked  // timed or distance work, nothing to load
    }

    /// Prefilled into the weight field. Nil means "we don't know yet" — the
    /// first session on a lift, or work that isn't loaded.
    var targetWeightLbs: Double?
    var targetReps: Int?
    var headline: String
    var reason: String
    var kind: Kind

    var isIncrease: Bool { kind == .increase }
}
