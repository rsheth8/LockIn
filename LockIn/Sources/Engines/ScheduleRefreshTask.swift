import Foundation

/// Keeps today's plan from sticking on yesterday after local midnight.
///
/// Two paths: a foreground timer armed to the next midnight while the app is
/// active, and a staleness check whenever the scene becomes active (covers
/// overnight kills / backgrounding past midnight without a wake).
final class ScheduleRefreshTask {
    private var timer: Timer?
    var onMidnight: (() -> Void)?

    /// True when we have no schedule, or the saved schedule is from a prior day.
    static func isStale(_ schedule: DaySchedule?) -> Bool {
        guard let schedule else { return true }
        return !Calendar.current.isDateInToday(schedule.date)
    }

    /// Arms (or re-arms) a one-shot timer for the next local midnight.
    @MainActor
    func arm() {
        timer?.invalidate()
        let interval = Self.secondsUntilNextMidnight()
        // Tolerance keeps iOS from waking the process for sub-second precision.
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onMidnight?()
                self?.arm()
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @MainActor
    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    static func secondsUntilNextMidnight(now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        return max(next.timeIntervalSince(now), 1)
    }
}
