import Foundation

/// Shared between the main LockIn app and the LockInMonitor DeviceActivity
/// extension, which runs in its own process — an App Group container is the
/// only way for the two to pass data (the selected apps to watch, and
/// distraction events the extension detects).
enum AppGroup {
    static let identifier = "group.com.rahilsheth.lockin"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    enum Key {
        static let selectedAppsData = "screenTime.selectedAppsData"
        static let pendingDistractionEvents = "screenTime.pendingDistractionEvents"
        static let toneIntensity = "screenTime.toneIntensity"
        static let currentWeightLbs = "screenTime.currentWeightLbs"
        static let goalWeightLbs = "screenTime.goalWeightLbs"
    }
}

/// A distraction the monitor extension detected — you opened / kept using a
/// shielded app during a lock-in block. The main app drains this queue on
/// next launch/foreground to update the streak and fire an in-app guilt card
/// (the extension itself only has a narrow window to act, so it also fires a
/// local notification immediately — this is the durable record).
struct DistractionEvent: Codable, Equatable {
    let date: Date
    let blockLabel: String
}

extension AppGroup {
    static func appendDistractionEvent(_ event: DistractionEvent) {
        var events = pendingDistractionEvents()
        events.append(event)
        if let data = try? JSONEncoder().encode(events) {
            sharedDefaults.set(data, forKey: Key.pendingDistractionEvents)
        }
    }

    static func pendingDistractionEvents() -> [DistractionEvent] {
        guard let data = sharedDefaults.data(forKey: Key.pendingDistractionEvents),
              let events = try? JSONDecoder().decode([DistractionEvent].self, from: data) else { return [] }
        return events
    }

    static func clearPendingDistractionEvents() {
        sharedDefaults.removeObject(forKey: Key.pendingDistractionEvents)
    }
}
