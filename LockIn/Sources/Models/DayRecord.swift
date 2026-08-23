import Foundation

/// One day's adherence, kept forever. This is the receipts ledger behind the
/// promise grid — a streak counter only ever shows the good days, which makes
/// it weak motivation. Seeing the empty squares is what actually applies
/// loss-aversion pressure (Kahneman & Tversky), so the history is the point.
struct DayRecord: Codable, Equatable, Identifiable {
    let dayKey: String       // "yyyy-MM-dd" — stable identity across timezone drift
    let date: Date
    var criticalTotal: Int
    var criticalConfirmed: Int
    var criticalMissed: Int
    var distractionEvents: Int
    var weightLbs: Double?

    var id: String { dayKey }

    /// 0...1 — drives the fill weight of the day's square in the grid.
    var adherence: Double {
        guard criticalTotal > 0 else { return 0 }
        return Double(criticalConfirmed) / Double(criticalTotal)
    }

    /// A day is "clean" only if every critical promise was kept and nothing
    /// was actively blown off. Partial credit shows as a partial fill, not a win.
    var isClean: Bool {
        criticalTotal > 0 && criticalConfirmed == criticalTotal && criticalMissed == 0
    }

    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
