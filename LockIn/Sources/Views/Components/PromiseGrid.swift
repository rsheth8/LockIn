import SwiftUI

/// How much history the grid shows at once.
enum GridRange: String, CaseIterable, Identifiable {
    case quarter, halfYear, year

    var id: String { rawValue }

    var weeks: Int {
        switch self {
        case .quarter: return 13
        case .halfYear: return 26
        case .year: return 53
        }
    }

    var label: String {
        switch self {
        case .quarter: return "3M"
        case .halfYear: return "6M"
        case .year: return "1Y"
        }
    }

    /// Squares shrink as the window widens so a quarter fills the screen
    /// comfortably and a year stays legible while scrolling.
    var squareSize: CGFloat {
        switch self {
        case .quarter: return 20
        case .halfYear: return 14
        case .year: return 11
        }
    }
}

/// The receipts, GitHub-contribution style.
///
/// One square per day, intensity = share of critical promises kept. Empty
/// squares are the whole point — a streak counter only shows the good days,
/// which makes it weak motivation. Seeing the gaps is what applies real
/// loss-aversion pressure, so the history is the feature.
///
/// Also LockIn's visual signature: the same mark works as the app icon, the
/// home-screen widget, and the Watch complication.
struct PromiseGrid: View {
    let records: [DayRecord]
    var keptColor: Color = Theme.kept
    var range: GridRange = .quarter
    @Binding var selection: DayRecord?
    /// Drives the stagger-in animation the first time the grid appears.
    var revealProgress: Double = 1

    private let spacing: CGFloat = 3
    private let weekdayGutter: CGFloat = 18
    private let monthLabelHeight: CGFloat = 14

    private var calendar: Calendar { Calendar.current }

    /// Every day in the window, starting on a Sunday so columns are clean
    /// calendar weeks and the weekday labels line up.
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekdayOffset = calendar.component(.weekday, from: today) - 1
        guard let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today),
              let start = calendar.date(byAdding: .day, value: -((range.weeks - 1) * 7), to: lastColumnStart)
        else { return [] }
        return (0..<(range.weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekStarts: [Int] {
        Array(stride(from: 0, to: days.count, by: 7))
    }

    private func record(for date: Date) -> DayRecord? {
        records.first { $0.dayKey == DayRecord.key(for: date) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    weekdayLabels
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels
                        gridBody
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 4)
            }
            .onAppear {
                // Land on the present, not a year ago.
                proxy.scrollTo(weekStarts.last ?? 0, anchor: .trailing)
            }
            .onChange(of: range) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(weekStarts.last ?? 0, anchor: .trailing) }
            }
        }
    }

    // MARK: - Axes

    /// Sparse weekday labels — Mon/Wed/Fri only, like GitHub. Labelling all
    /// seven crowds the axis and adds nothing.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            Color.clear.frame(height: monthLabelHeight)
            ForEach(0..<7, id: \.self) { index in
                Group {
                    if index == 1 || index == 3 || index == 5 {
                        Text(["S", "M", "T", "W", "T", "F", "S"][index])
                            .font(Theme.mono(8))
                            .foregroundStyle(Theme.inkMuted)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: range.squareSize)
            }
        }
        .frame(width: weekdayGutter, alignment: .trailing)
        .padding(.top, 4)
    }

    /// A month name sits above the first column that begins that month.
    private var monthLabels: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(weekStarts, id: \.self) { weekStart in
                Group {
                    if let label = monthLabel(forWeekStartingAt: weekStart) {
                        Text(label)
                            .font(Theme.mono(8, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize()
                            .frame(width: range.squareSize, alignment: .leading)
                    } else {
                        Color.clear.frame(width: range.squareSize)
                    }
                }
            }
        }
        .frame(height: monthLabelHeight, alignment: .bottom)
    }

    private func monthLabel(forWeekStartingAt index: Int) -> String? {
        guard index < days.count else { return nil }
        let date = days[index]
        let month = calendar.component(.month, from: date)
        // Label a column only when it's the first column of that month in view.
        if index == 0 {
            return monthName(month)
        }
        let previous = days[index - 7]
        return calendar.component(.month, from: previous) != month ? monthName(month) : nil
    }

    private func monthName(_ month: Int) -> String {
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard month >= 1, month <= symbols.count else { return "" }
        return symbols[month - 1].uppercased()
    }

    // MARK: - Grid

    private var gridBody: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(weekStarts.enumerated()), id: \.element) { column, weekStart in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { offset in
                        let index = weekStart + offset
                        if index < days.count {
                            square(for: days[index], column: column)
                        } else {
                            Color.clear.frame(width: range.squareSize, height: range.squareSize)
                        }
                    }
                }
                .id(weekStart)
            }
        }
    }

    @ViewBuilder
    private func square(for date: Date, column: Int) -> some View {
        let isFuture = date > calendar.startOfDay(for: Date())
        let isToday = calendar.isDateInToday(date)
        let rec = record(for: date)
        let isSelected = selection?.dayKey == DayRecord.key(for: date)

        // Columns reveal left-to-right on first paint so the record reads as
        // something that accumulated over time rather than appearing at once.
        let columnThreshold = Double(column) / Double(max(weekStarts.count, 1))
        let revealed = revealProgress >= columnThreshold

        RoundedRectangle(cornerRadius: range.squareSize * 0.24, style: .continuous)
            .fill(fill(for: rec, isFuture: isFuture))
            .frame(width: range.squareSize, height: range.squareSize)
            .overlay(
                RoundedRectangle(cornerRadius: range.squareSize * 0.24, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.ink : (isToday ? Theme.ink.opacity(0.7) : .clear),
                        lineWidth: isSelected ? 2 : 1.5
                    )
            )
            .scaleEffect(revealed ? (isSelected ? 1.15 : 1) : 0.5)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: revealed)
            .animation(.snappy(duration: 0.18), value: isSelected)
            .onTapGesture {
                guard !isFuture else { return }
                Haptics.tap()
                withAnimation(.snappy) {
                    // Tapping the selected day clears it, so the detail card
                    // can be dismissed without hunting for a close button.
                    selection = isSelected ? nil : (rec ?? DayRecord(
                        dayKey: DayRecord.key(for: date), date: date,
                        criticalTotal: 0, criticalConfirmed: 0, criticalMissed: 0,
                        distractionEvents: 0, weightLbs: nil
                    ))
                }
            }
    }

    private func fill(for record: DayRecord?, isFuture: Bool) -> Color {
        // Days that haven't happened yet are near-invisible — they're not failures.
        if isFuture { return Theme.inkFaint.opacity(0.2) }
        // Nor are days from before you started tracking. Only days the app
        // actually planned for are allowed to read as a miss — otherwise a fresh
        // install opens on a wall of grey implying months of failure.
        guard let record, record.criticalTotal > 0 else { return Theme.inkFaint.opacity(0.28) }

        // Anything actively blown off flags red regardless of how much else got
        // done — a broken promise shouldn't be laundered by a high completion count.
        if record.criticalMissed > 0 || record.distractionEvents > 0 {
            return Theme.signal.opacity(0.35 + 0.5 * record.adherence)
        }
        if record.adherence == 0 { return Theme.inkFaint.opacity(0.28) }
        // Four visible steps rather than a continuous ramp, so intensity is
        // readable at a glance the way GitHub's is.
        let step = (record.adherence * 4).rounded(.up) / 4
        return keptColor.opacity(0.22 + 0.78 * step)
    }
}

// MARK: - Legend

struct PromiseGridLegend: View {
    var keptColor: Color = Theme.kept

    var body: some View {
        HStack(spacing: 8) {
            Text("Less").font(Theme.mono(8)).foregroundStyle(Theme.inkMuted)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(level == 0 ? Theme.inkFaint.opacity(0.28) : keptColor.opacity(0.22 + 0.78 * level))
                    .frame(width: 9, height: 9)
            }
            Text("More").font(Theme.mono(8)).foregroundStyle(Theme.inkMuted)

            Spacer()

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.signal.opacity(0.7))
                .frame(width: 9, height: 9)
            Text("Broken").font(Theme.mono(8)).foregroundStyle(Theme.inkMuted)
        }
    }
}
