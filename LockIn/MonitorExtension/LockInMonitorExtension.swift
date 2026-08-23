import DeviceActivity
import ManagedSettings
import FamilyControls
import UserNotifications

/// Runs in its own process, scheduled by ScreenTimeManager via
/// DeviceActivityCenter. Two jobs per lock-in block:
///   1. Shield the guarded apps/categories for the block's duration — this is
///      the actual enforcement, not just a nag.
///   2. If the user still burns real time on them (1-min cumulative threshold,
///      set in ScreenTimeManager) — via web/related apps outside the shield,
///      or before they gave up trying to get past it — fire an immediate
///      tough-love notification and log the event for the main app's streak.
class LockInMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        applyShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        clearShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        let blockLabel = activity.rawValue
        AppGroup.appendDistractionEvent(DistractionEvent(date: Date(), blockLabel: blockLabel))
        fireGuiltNotification(blockLabel: blockLabel)
    }

    private func applyShield() {
        guard let data = AppGroup.sharedDefaults.data(forKey: AppGroup.Key.selectedAppsData),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    private func fireGuiltNotification(blockLabel: String) {
        let toneRaw = AppGroup.sharedDefaults.string(forKey: AppGroup.Key.toneIntensity) ?? ToneIntensity.toughLove.rawValue
        let tone = ToneIntensity(rawValue: toneRaw) ?? .toughLove

        let dummyEvent = ScheduledEvent(kind: .workout, title: blockLabel, detail: "", time: Date(), durationMinutes: 0, isCritical: true)
        // Reaching the threshold during a lock-in block is itself the repeated-pattern
        // signal — go straight to the hardest tier available for this tone.
        let body = AccountabilityEngine.message(for: dummyEvent, tier: 2, tone: tone, streak: StreakStatus())

        let content = UNMutableNotificationContent()
        content.title = "Caught you"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
