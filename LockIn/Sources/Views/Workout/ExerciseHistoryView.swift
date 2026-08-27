import SwiftUI
import Charts

/// An exercise name that `.sheet(item:)` can drive.
struct NamedExercise: Identifiable {
    let name: String
    var id: String { name }
}

/// One lift's whole story: top set over time, and every session's numbers.
///
/// This is the screen that answers "am I actually getting stronger", which the
/// session-by-session log can't — you'd have to hold six weeks in your head.
/// The chart plots the **top set**, not volume, because that's the number people
/// track their lifts by and the one progression moves.
struct ExerciseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    let exerciseName: String
    /// Newest first.
    let logs: [ExerciseLog]
    /// Full history, for dating each log.
    let workouts: [CompletedWorkout]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headline
                        if dated.count >= 2 { chart }
                        sessions
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Best", value: best.map { "\(SetEntry.trim($0))" } ?? "—", detail: "lb top set")
            stat("Now", value: current.map { "\(SetEntry.trim($0))" } ?? "—", detail: "last session")
            stat("Sessions", value: "\(logs.count)", detail: "logged")
        }
    }

    private func stat(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ledgerLabel()
            Text(value)
                .font(Theme.mono(24, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart {
            ForEach(dated, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Top set", point.weight))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(accent.color)
                PointMark(x: .value("Date", point.date), y: .value("Top set", point.weight))
                    .foregroundStyle(accent.color)
                    .symbolSize(28)
            }
        }
        // Scaled to the data, never from zero — a 20 lb gain on a 200 lb squat
        // is the whole point and an axis from 0 flattens it into nothing.
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel().font(Theme.mono(9)).foregroundStyle(Theme.inkMuted)
                AxisGridLine().foregroundStyle(Theme.rule)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.mono(9)).foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(height: 170)
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every session").ledgerLabel().padding(.bottom, 8)
            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(date(of: log), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: 8)
                        if let top = log.topWeightLbs {
                            Text("\(SetEntry.trim(top)) lb")
                                .font(Theme.mono(12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    Text(log.summaryLine)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
                LedgerRule()
            }
        }
    }

    // MARK: - Derived

    /// Logs paired with the date of the session they came from, oldest first so
    /// the chart reads left to right.
    private var dated: [(date: Date, weight: Double)] {
        logs.compactMap { log -> (Date, Double)? in
            guard let weight = log.topWeightLbs else { return nil }
            return (date(of: log), weight)
        }
        .sorted { $0.0 < $1.0 }
        .map { (date: $0.0, weight: $0.1) }
    }

    private func date(of log: ExerciseLog) -> Date {
        workouts.first { $0.exercises.contains(where: { $0.id == log.id }) }?.date
            ?? log.sets.first?.completedAt
            ?? Date()
    }

    private var best: Double? { logs.compactMap(\.topWeightLbs).max() }
    private var current: Double? { logs.first?.topWeightLbs }

    private var domain: ClosedRange<Double> {
        let weights = dated.map(\.weight)
        guard let low = weights.min(), let high = weights.max() else { return 0...100 }
        let padding = max((high - low) * 0.2, 5)
        return (low - padding)...(high + padding)
    }
}
