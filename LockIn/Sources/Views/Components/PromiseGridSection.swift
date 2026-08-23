import SwiftUI

/// The full "Promises" block: headline stats, range picker, the grid itself,
/// legend, and an inspector for whichever day you tap. This is the emotional
/// centre of the app — the one screen that shows the whole record at once.
struct PromiseGridSection: View {
    let records: [DayRecord]
    let accent: AppAccent

    @State private var range: GridRange = .quarter
    @State private var selection: DayRecord?
    @State private var revealProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statsRow
            PromiseGrid(
                records: records,
                keptColor: accent.color,
                range: range,
                selection: $selection,
                revealProgress: revealProgress
            )
            PromiseGridLegend(keptColor: accent.color)

            if let selection {
                DayInspector(record: selection, accent: accent)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .onAppear {
            guard revealProgress == 0 else { return }
            withAnimation(.easeOut(duration: 0.7)) { revealProgress = 1 }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Promises").ledgerLabel()
            Spacer()
            HStack(spacing: 2) {
                ForEach(GridRange.allCases) { option in
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) {
                            range = option
                            selection = nil
                        }
                    } label: {
                        Text(option.label)
                            .font(Theme.mono(10, weight: .semibold))
                            .foregroundStyle(range == option ? Theme.surface : Theme.inkMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(range == option ? Theme.ink : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(value: "\(currentStreak)", label: "Current", detail: "day streak",
                 highlight: currentStreak > 0)
            stat(value: "\(longestStreak)", label: "Longest", detail: "days")
            stat(value: cleanRatio, label: "Clean", detail: "of tracked days")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { LedgerRule() }
        .overlay(alignment: .bottom) { LedgerRule() }
    }

    private func stat(value: String, label: String, detail: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ledgerLabel()
            Text(value)
                .font(Theme.mono(22, weight: .semibold))
                .foregroundStyle(highlight ? accent.color : Theme.ink)
                .contentTransition(.numericText())
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived stats
    //
    // Computed from the record rather than stored, so they can never drift out
    // of sync with what the grid is actually showing.

    private var tracked: [DayRecord] {
        records.filter { $0.criticalTotal > 0 }.sorted { $0.date < $1.date }
    }

    /// Counts back from today. A day still in progress doesn't break the
    /// streak — only a day that ended without being clean does.
    private var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())

        while true {
            let key = DayRecord.key(for: cursor)
            guard let record = records.first(where: { $0.dayKey == key }) else {
                // Today with no record yet is simply unfinished, not a break.
                if calendar.isDateInToday(cursor) {
                    cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
                    continue
                }
                break
            }
            if record.isClean {
                streak += 1
            } else if !calendar.isDateInToday(cursor) {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private var longestStreak: Int {
        var best = 0, running = 0
        for record in tracked {
            if record.isClean {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
        }
        return best
    }

    private var cleanRatio: String {
        guard !tracked.isEmpty else { return "—" }
        let clean = tracked.filter { $0.isClean }.count
        return "\(clean)/\(tracked.count)"
    }
}

// MARK: - Day inspector

/// Detail for a tapped square. Shows what actually happened that day rather
/// than just an intensity — the grid poses the question, this answers it.
private struct DayInspector: View {
    let record: DayRecord
    let accent: AppAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(verdict)
                    .font(Theme.mono(10, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(verdictColor)
            }

            if record.criticalTotal == 0 {
                Text("Nothing tracked on this day.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
            } else {
                progressBar
                HStack(spacing: 16) {
                    metric("\(record.criticalConfirmed)/\(record.criticalTotal)", "kept")
                    if record.criticalMissed > 0 {
                        metric("\(record.criticalMissed)", "missed", color: Theme.signal)
                    }
                    if record.distractionEvents > 0 {
                        metric("\(record.distractionEvents)", "distracted", color: Theme.signal)
                    }
                    if let weight = record.weightLbs {
                        metric("\(Int(weight))", "lb")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerCard()
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inkFaint)
                Capsule()
                    .fill(record.criticalMissed > 0 ? Theme.signal : accent.color)
                    .frame(width: geo.size.width * record.adherence)
            }
        }
        .frame(height: 5)
    }

    private func metric(_ value: String, _ label: String, color: Color = Theme.ink) -> some View {
        HStack(spacing: 4) {
            Text(value).font(Theme.mono(13, weight: .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.inkMuted)
        }
    }

    private var verdict: String {
        if record.criticalTotal == 0 { return "No data" }
        if record.criticalMissed > 0 || record.distractionEvents > 0 { return "Broken" }
        if record.isClean { return "Clean" }
        return "Partial"
    }

    private var verdictColor: Color {
        if record.criticalTotal == 0 { return Theme.inkMuted }
        if record.criticalMissed > 0 || record.distractionEvents > 0 { return Theme.signal }
        if record.isClean { return accent.color }
        return Theme.inkMuted
    }
}
