import Foundation

/// How to actually perform a movement.
///
/// Separate from `ExercisePrescription`, which says what to do (4 × 6–10) and
/// why it's in the plan. This says how — and it's the difference between a
/// training app and a list of words you have to go and google.
struct ExerciseGuide: Equatable {
    /// Getting into position. Everything that happens before the first rep.
    var setup: [String]
    /// The rep itself.
    var execution: [String]
    /// Short things to think about mid-set. These are what you actually repeat
    /// to yourself under a bar — full sentences don't survive a heavy single.
    var cues: [String]
    /// What usually goes wrong, and what it costs. Named specifically, because
    /// "use good form" has never fixed anyone's knee valgus.
    var mistakes: [String]
    /// The rep rhythm, when the movement has one. Nil for isometrics, carries,
    /// and steady-state work, which are paced by the clock instead.
    var tempo: MovementTempo?
    /// What to do instead when the equipment is taken, missing, or the movement
    /// hurts. An exercise you can't do is a session you skip.
    var swap: String
    /// Search terms for video, if reading isn't enough.
    var searchTerm: String
}

/// The phases of one rep, in order, with how long each should take.
///
/// Tempo is a real training variable, not decoration: most people rush the
/// lowering phase, which is where a large share of the strength and almost all
/// of the tendon adaptation comes from. Showing the rhythm is the one thing an
/// animation can honestly teach without a camera.
struct MovementTempo: Equatable {
    struct Phase: Equatable, Identifiable {
        var label: String
        var seconds: Double
        var id: String { label }
    }

    var phases: [Phase]

    var totalSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    /// "2s down · 1s up", the one-line version for a collapsed row.
    var summary: String {
        phases.filter { $0.seconds > 0 }
            .map { "\(Int($0.seconds))s \($0.label.lowercased())" }
            .joined(separator: " · ")
    }

    /// The common case: lower under control, no pause, drive back up.
    static func lower(_ down: Double, hold: Double = 0, drive: Double,
                      downLabel: String = "Lower", driveLabel: String = "Drive") -> MovementTempo {
        var phases = [Phase(label: downLabel, seconds: down)]
        if hold > 0 { phases.append(Phase(label: "Pause", seconds: hold)) }
        phases.append(Phase(label: driveLabel, seconds: drive))
        return MovementTempo(phases: phases)
    }
}
