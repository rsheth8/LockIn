import Foundation
import UserNotifications

/// Schedules local notifications for each event, plus escalating follow-ups
/// when a critical event isn't confirmed within its grace window.
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Current authorization for Settings — does not prompt.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func scheduleDay(_ schedule: DaySchedule, tone: ToneIntensity, streak: StreakStatus,
                     currentWeightLbs: Double, goalWeightLbs: Double) {
        center.removeAllPendingNotificationRequests()
        for event in schedule.events {
            // Calendar.app already notifies for commitments; don't double-ping.
            guard event.kind != .commitment else { continue }
            // Already resolved events shouldn't keep escalating.
            guard event.status == .pending || event.status == .snoozed else { continue }
            scheduleReminder(for: event)
            if event.isCritical {
                scheduleEscalations(
                    for: event, tone: tone, streak: streak,
                    currentWeightLbs: currentWeightLbs, goalWeightLbs: goalWeightLbs
                )
            }
        }
    }

    /// Cancels primary + escalation pings for one event. Call on Done / Skip so
    /// a confirmed weigh-in doesn't keep nagging 15 and 45 minutes later.
    func cancelNotifications(for eventID: UUID) {
        let ids = [
            "\(eventID)-primary",
            "\(eventID)-tier1",
            "\(eventID)-tier2"
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func scheduleReminder(for event: ScheduledEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.detail
        content.sound = .default
        addRequest(id: "\(event.id)-primary", date: event.time, content: content)
    }

    /// Grace window: 15 min for a first nudge, 45 min for a firmer tier-1 nudge.
    /// Tier-2 (pattern-based, "missed again this week") is triggered by
    /// AccountabilityEngine when confirming/checking status, not scheduled blind.
    private func scheduleEscalations(for event: ScheduledEvent, tone: ToneIntensity, streak: StreakStatus,
                                     currentWeightLbs: Double, goalWeightLbs: Double) {
        let tier1Time = event.time.addingTimeInterval(15 * 60)
        let tier2Time = event.time.addingTimeInterval(45 * 60)

        let tier1 = UNMutableNotificationContent()
        tier1.title = "Still on \(event.title)?"
        tier1.body = AccountabilityEngine.message(
            for: event, tier: 0, tone: tone, streak: streak,
            currentWeightLbs: currentWeightLbs, goalWeightLbs: goalWeightLbs
        )
        tier1.sound = .default
        addRequest(id: "\(event.id)-tier1", date: tier1Time, content: tier1)

        let tier2 = UNMutableNotificationContent()
        tier2.title = "\(event.title) — still not done"
        tier2.body = AccountabilityEngine.message(
            for: event, tier: 1, tone: tone, streak: streak,
            currentWeightLbs: currentWeightLbs, goalWeightLbs: goalWeightLbs
        )
        tier2.sound = .default
        addRequest(id: "\(event.id)-tier2", date: tier2Time, content: tier2)
    }

    private func addRequest(id: String, date: Date, content: UNMutableNotificationContent) {
        guard date > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
