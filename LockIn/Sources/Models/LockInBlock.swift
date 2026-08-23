import Foundation

/// A window of time worth protecting from distraction — a workout, or a
/// manually-started study/focus session. Maps 1:1 to a DeviceActivitySchedule
/// registered with DeviceActivityCenter.
struct LockInBlock: Codable, Equatable, Identifiable {
    let id: String          // stable activity name used as the DeviceActivityName raw value
    let label: String
    let start: Date
    let end: Date
}
