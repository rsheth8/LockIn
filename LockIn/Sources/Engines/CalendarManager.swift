import Foundation
import EventKit

/// Reads free/busy blocks from the user's calendars (class/work schedule) via
/// EventKit so the ScheduleEngine can plan around real commitments instead of
/// a hardcoded weekly template.
final class CalendarManager: ObservableObject {
    private let store = EKEventStore()
    @Published var authorized = false

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run { self.authorized = granted }
        } catch {
            await MainActor.run { self.authorized = false }
        }
    }

    /// Busy blocks for the given date across all calendars. Filter out all-day
    /// events (those aren't real time-blocks to plan around).
    func busyBlocks(for date: Date) -> [BusyBlock] {
        let calendar = Calendar.current
        guard let dayStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let dayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return [] }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let events = store.events(matching: predicate)

        return events
            .filter { !$0.isAllDay }
            .map { BusyBlock(title: $0.title ?? "Busy", start: $0.startDate, end: $0.endDate) }
    }
}
