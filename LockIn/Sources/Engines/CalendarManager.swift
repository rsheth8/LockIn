import Foundation
import EventKit
import UIKit

/// Live Calendar + Reminders bridge.
///
/// Reads free/busy and due reminders so the day plan can move when real life
/// does, and writes Lock In's own events onto a dedicated calendar so they
/// show up in Calendar.app, Watch, and anything else that reads EventKit.
final class CalendarManager: ObservableObject {
    static let lockInCalendarTitle = "Lock In"

    private let store = EKEventStore()
    @Published var authorized = false
    @Published var remindersAuthorized = false
    /// Bumped when *external* calendar/reminder data changes. Writing our own
    /// Lock In events must not increment this or the day rebuilds in a loop.
    @Published var revision = 0
    @Published private(set) var todayTasks: [DayTask] = []

    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var lastFingerprint = ""
    /// Fingerprint of the last schedule written to the Lock In calendar, so a
    /// rebuild that produces an identical day is a no-op instead of deleting
    /// and re-creating a dozen EKEvents.
    private var lastWrittenSchedule = ""

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run { self.authorized = granted }
        } catch {
            await MainActor.run { self.authorized = false }
        }

        do {
            let granted = try await store.requestFullAccessToReminders()
            await MainActor.run { self.remindersAuthorized = granted }
        } catch {
            await MainActor.run { self.remindersAuthorized = false }
        }

        await MainActor.run { startObserving() }
        await refreshTasks()
        await MainActor.run {
            lastFingerprint = dayFingerprint(for: Date())
        }
    }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.noteStoreChanged()
        }
    }

    /// Re-read on foreground in case an EventKit ping was missed while suspended.
    func refreshIfNeeded() {
        Task { @MainActor in
            await refreshTasks()
            let fingerprint = dayFingerprint(for: Date())
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint
            revision += 1
        }
    }

    // MARK: - Read

    /// Timed events for the day, excluding all-day items and the Lock In
    /// calendar we write ourselves (those would otherwise look like conflicts).
    func busyBlocks(for date: Date) -> [BusyBlock] {
        guard authorized else { return [] }
        let calendar = Calendar.current
        guard let dayStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let calendars = store.calendars(for: .event).filter { $0.title != Self.lockInCalendarTitle }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map {
                BusyBlock(
                    title: $0.title ?? "Busy",
                    start: $0.startDate,
                    end: $0.endDate,
                    calendarItemIdentifier: $0.calendarItemIdentifier,
                    location: $0.location
                )
            }
    }

    func refreshTasks() async {
        guard remindersAuthorized else {
            await MainActor.run { todayTasks = [] }
            return
        }
        let tasks = await fetchDueTasks(for: Date())
        await MainActor.run { todayTasks = tasks }
    }

    func completeReminder(identifier: String) {
        guard remindersAuthorized else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self, let match = reminders?.first(where: { $0.calendarItemIdentifier == identifier }) else { return }
            match.isCompleted = true
            do {
                try self.store.save(match, commit: true)
            } catch {
                // Completing in Reminders is best-effort — the local check-in still stands.
            }
        }
    }

    // MARK: - Write-back

    /// Mirrors today's Lock In events onto the dedicated calendar so the rest
    /// of the phone (Calendar, Watch, Lock Screen) sees the same day.
    func sync(_ schedule: DaySchedule?) {
        guard authorized, let schedule else { return }

        // A launch rebuilds the day at least twice (local meals, then live
        // ones), and every foreground or calendar change rebuilds it again.
        // Without this, each pass deletes and re-creates every Lock In event —
        // pointless churn that an iCloud-backed calendar then syncs upstream.
        let fingerprint = Self.writeFingerprint(schedule)
        guard fingerprint != lastWrittenSchedule else { return }

        guard let lockIn = lockInCalendar() else { return }

        let calendar = Calendar.current
        guard let dayStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: schedule.date),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let existing = store.events(matching: store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [lockIn]))
        for event in existing {
            try? store.remove(event, span: .thisEvent, commit: false)
        }

        for item in schedule.events where item.kind.writesToCalendar {
            let event = EKEvent(eventStore: store)
            event.calendar = lockIn
            event.title = item.title
            event.notes = notes(for: item)
            event.startDate = item.time
            event.endDate = item.endTime
            event.isAllDay = false
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
        lastWrittenSchedule = fingerprint
    }

    /// Identifies a day's writable events by what would actually land in
    /// EventKit — title, times, and notes.
    static func writeFingerprint(_ schedule: DaySchedule) -> String {
        schedule.events
            .filter { $0.kind.writesToCalendar }
            .map { "\($0.kind.rawValue)|\($0.title)|\($0.time.timeIntervalSince1970)|\($0.endTime.timeIntervalSince1970)|\($0.detail)" }
            .joined(separator: ";")
    }

    // MARK: - Private

    /// EventKit change pings arrive asynchronously and long after any write of
    /// ours has returned, so there is no useful "am I writing right now" flag to
    /// check. What actually keeps a write from rebuilding the day is that
    /// `dayFingerprint` is computed from `busyBlocks`, which excludes the Lock
    /// In calendar — our own events can never move it.
    private func noteStoreChanged() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await refreshTasks()
            let fingerprint = dayFingerprint(for: Date())
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint
            revision += 1
        }
    }

    func dayFingerprint(for date: Date) -> String {
        let busy = busyBlocks(for: date).map {
            "\($0.calendarItemIdentifier ?? $0.title)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)"
        }
        let tasks = todayTasks.map { "\($0.id)|\($0.due.timeIntervalSince1970)" }
        return (busy + tasks).joined(separator: ";")
    }

    private func fetchDueTasks(for date: Date) async -> [DayTask] {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let tasks = (reminders ?? []).compactMap { reminder -> DayTask? in
                    guard let title = reminder.title, !title.isEmpty else { return nil }
                    let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                        ?? start.addingTimeInterval(9 * 3600)
                    return DayTask(id: reminder.calendarItemIdentifier, title: title, due: due, notes: reminder.notes)
                }
                continuation.resume(returning: tasks)
            }
        }
    }

    private func lockInCalendar() -> EKCalendar? {
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.lockInCalendarTitle }) {
            return existing
        }
        let created = EKCalendar(for: .event, eventStore: store)
        created.title = Self.lockInCalendarTitle
        created.source = preferredSource()
        created.cgColor = UIColor(red: 0.66, green: 0.20, blue: 0.16, alpha: 1).cgColor
        do {
            try store.saveCalendar(created, commit: true)
            return created
        } catch {
            return nil
        }
    }

    /// Where the Lock In calendar gets created. The account the user already
    /// writes events to is the right answer — picking the first CalDAV source
    /// instead could drop a personal training calendar into a work or school
    /// account that happens to sync over CalDAV.
    private func preferredSource() -> EKSource? {
        store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
    }

    private func notes(for item: ScheduledEvent) -> String {
        var lines = [item.detail]
        lines.append("")
        lines.append("LockIn:\(item.id.uuidString)")
        return lines.joined(separator: "\n")
    }
}
