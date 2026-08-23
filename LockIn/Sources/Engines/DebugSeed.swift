#if DEBUG
import Foundation

/// Generates plausible history so the promise grid, streak stats and weight
/// chart can be designed and reviewed against realistic data instead of an
/// empty state. DEBUG-only — this never ships in a release build.
enum DebugSeed {
    /// Roughly four months of days: mostly good with a believable mix of
    /// partial days, a couple of broken stretches, and a weight trend that
    /// actually goes somewhere.
    static func dayRecords(days: Int = 118, startWeight: Double = 220, endWeight: Double = 205) -> [DayRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var generator = SeededGenerator(seed: 42)

        return (0..<days).compactMap { offset -> DayRecord? in
            guard let date = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today) else { return nil }

            let progress = Double(offset) / Double(days - 1)
            let weight = startWeight + (endWeight - startWeight) * progress
                + Double.random(in: -0.8...0.8, using: &generator)

            let total = 9
            // Two deliberate rough patches so the grid shows what falling off
            // actually looks like, not just an unbroken wall of green.
            let inSlump = (offset >= 34 && offset <= 41) || (offset >= 78 && offset <= 82)
            let roll = Double.random(in: 0...1, using: &generator)

            let confirmed: Int
            let missed: Int
            let distractions: Int

            if inSlump {
                confirmed = Int.random(in: 2...5, using: &generator)
                missed = Int.random(in: 2...4, using: &generator)
                distractions = Int.random(in: 0...2, using: &generator)
            } else if roll < 0.62 {
                confirmed = total
                missed = 0
                distractions = 0
            } else if roll < 0.88 {
                confirmed = Int.random(in: 6...8, using: &generator)
                missed = 0
                distractions = 0
            } else {
                confirmed = Int.random(in: 4...7, using: &generator)
                missed = 1
                distractions = Int.random(in: 0...1, using: &generator)
            }

            return DayRecord(
                dayKey: DayRecord.key(for: date),
                date: date,
                criticalTotal: total,
                criticalConfirmed: confirmed,
                criticalMissed: missed,
                distractionEvents: distractions,
                weightLbs: (weight * 10).rounded() / 10
            )
        }
    }

    static func weightHistory(from records: [DayRecord]) -> [WeightEntry] {
        records.compactMap { record in
            record.weightLbs.map { WeightEntry(date: record.date, weightLbs: $0) }
        }
    }
}

/// Deterministic RNG so seeded data looks the same across runs — otherwise
/// every relaunch reshuffles the grid and you can't judge a design change.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
#endif
