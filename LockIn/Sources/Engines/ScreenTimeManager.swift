import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings

/// Owns Family Controls authorization, which apps/categories are being
/// guarded, and scheduling lock-in blocks with DeviceActivityCenter. The
/// actual shielding and distraction detection happens in the LockInMonitor
/// extension (LockIn/MonitorExtension) — this class just configures it,
/// since DeviceActivityMonitor extensions can't be talked to directly once
/// scheduled, only through the shared App Group container.
@MainActor
final class ScreenTimeManager: ObservableObject {
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var selection = FamilyActivitySelection()
    @Published var activeBlocks: [LockInBlock] = []

    private let center = DeviceActivityCenter()

    init() {
        loadSelection()
        // Restore the real Family Controls status so Settings doesn't show
        // "Grant" after every relaunch when the user already approved.
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        }
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    func saveSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        guard let data = try? JSONEncoder().encode(newSelection) else { return }
        AppGroup.sharedDefaults.set(data, forKey: AppGroup.Key.selectedAppsData)
    }

    private func loadSelection() {
        guard let data = AppGroup.sharedDefaults.data(forKey: AppGroup.Key.selectedAppsData),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        selection = decoded
    }

    /// Registers a lock-in block: the monitor extension will shield the
    /// selected apps/categories for its duration and flag any attempt to use
    /// them (see LockInMonitor.swift `intervalDidStart`/`eventDidReachThreshold`).
    /// A 1-minute cumulative-usage threshold on the guarded set is what fires
    /// the guilt notification — short enough to catch a slip fast, long
    /// enough to not fire on an accidental tap-and-close.
    func scheduleLockInBlock(_ block: LockInBlock) {
        guard isAuthorized, !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else { return }

        // Replace any prior registration with the same id (e.g. rebuilt workout).
        cancelBlock(block)

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: block.start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: block.end)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            threshold: DateComponents(minute: 1)
        )

        let activityName = DeviceActivityName(block.id)
        let eventName = DeviceActivityEvent.Name("distraction.\(block.id)")

        do {
            try center.startMonitoring(activityName, during: schedule, events: [eventName: event])
            activeBlocks.append(block)
        } catch {
            // Scheduling failures (e.g. overlapping activity name) are non-fatal —
            // the day's other reminders still fire, just without app-shielding for this block.
        }
    }

    /// Starts an immediate focus / study lock-in for `minutes` from now.
    @discardableResult
    func startFocusBlock(label: String = "Focus", minutes: Int = 45) -> LockInBlock? {
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let block = LockInBlock(
            id: "focus-\(DayRecord.key(for: start))-\(Int(start.timeIntervalSince1970))",
            label: label,
            start: start,
            end: end
        )
        scheduleLockInBlock(block)
        return activeBlocks.contains(where: { $0.id == block.id }) ? block : nil
    }

    func cancelBlock(_ block: LockInBlock) {
        center.stopMonitoring([DeviceActivityName(block.id)])
        activeBlocks.removeAll { $0.id == block.id }
    }

    func cancelAllBlocks() {
        center.stopMonitoring()
        activeBlocks.removeAll()
    }
}
