import SwiftUI

/// The receipts. One square per day, fill weight = share of critical promises
/// kept. Empty squares are the point — this is the only surface in the app that
/// shows you the days you didn't show up, all at once, with no way to argue.
///
/// Doubles as LockIn's visual signature: the same mark reads as the app icon,
/// the home-screen widget, and the Watch complication.
struct PromiseGrid: View {
    let records: [DayRecord]
    /// Weeks of history to render. 13 ≈ a quarter, which is roughly the window
    /// of the 220→180 cut.
    var weeks: Int = 13
    var squareSize: CGFloat = 13
    var spacing: CGFloat = 3

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Wind back to the most recent Sunday so columns are clean calendar weeks.
        let weekdayOffset = calendar.component(.weekday, from: today) - 1
        guard let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today),
              let start = calendar.date(byAdding: .day, value: -((weeks - 1) * 7), to: lastColumnStart)
        else { return [] }

        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func record(for date: Date) -> DayRecord? {
        records.first { $0.dayKey == DayRecord.key(for: date) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(stride(from: 0, to: days.count, by: 7)), id: \.self) { weekStart in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { offset in
                                let index = weekStart + offset
                                if index < days.count {
                                    square(for: days[index])
                                }
                            }
                        }
                        .id(weekStart)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                // Land on the present, not three months ago.
                proxy.scrollTo(((weeks - 1) / 1) * 7, anchor: .trailing)
            }
        }
    }

    @ViewBuilder
    private func square(for date: Date) -> some View {
        let calendar = Calendar.current
        let isFuture = date > calendar.startOfDay(for: Date())
        let isToday = calendar.isDateInToday(date)
        let rec = record(for: date)

        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(for: rec, isFuture: isFuture))
            .frame(width: squareSize, height: squareSize)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(isToday ? Theme.ink : .clear, lineWidth: 1.5)
            )
    }

    private func fill(for record: DayRecord?, isFuture: Bool) -> Color {
        // Days that haven't happened yet are near-invisible — they're not failures.
        if isFuture { return Theme.inkFaint.opacity(0.2) }
        // Nor are days from before you started tracking. Only days the app
        // actually planned for are allowed to read as a miss — otherwise a fresh
        // install opens on a wall of grey that implies months of failure.
        guard let record, record.criticalTotal > 0 else { return Theme.inkFaint.opacity(0.28) }

        // Anything actively blown off flags red regardless of how much else got done —
        // a broken promise shouldn't be laundered by a high completion count.
        if record.criticalMissed > 0 || record.distractionEvents > 0 {
            return Theme.signal.opacity(0.35 + 0.5 * record.adherence)
        }
        if record.adherence == 0 { return Theme.inkFaint }
        return Theme.kept.opacity(0.25 + 0.75 * record.adherence)
    }
}

/// Compact legend so the fill language is learnable at a glance.
struct PromiseGridLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: Theme.inkFaint, label: "Nothing")
            legendItem(color: Theme.kept.opacity(0.55), label: "Partial")
            legendItem(color: Theme.kept, label: "Clean")
            legendItem(color: Theme.signal.opacity(0.7), label: "Broken")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
        }
    }
}
