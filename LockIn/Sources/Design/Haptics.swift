import UIKit

/// Distinct physical signatures for the two outcomes that matter. Confirming a
/// promise should feel like a solid, satisfying click; breaking one should feel
/// wrong in the hand. The body remembers this faster than it reads copy.
enum Haptics {
    static func confirm() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func miss() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Used when a streak milestone lands — heavier, earned.
    static func milestone() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
