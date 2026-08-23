import Foundation

/// Generates escalating accountability messages when a critical event is missed.
/// Grounded in behavioral science: loss aversion (Kahneman & Tversky) framing
/// ("don't break the streak") tends to outperform pure praise for adherence;
/// specific, immediate feedback beats vague reminders (implementation intentions,
/// Gollwitzer 1999). Tone stays "tough coach," never identity-attacking —
/// call out the action, not the person.
enum AccountabilityEngine {
    /// tier: 0 = first miss reminder, 1 = still missed after grace window, 2 = repeated pattern this week.
    static func message(for event: ScheduledEvent, tier: Int, tone: ToneIntensity, streak: StreakStatus) -> String {
        switch tone {
        case .gentle:
            return gentleMessage(event: event, tier: tier, streak: streak)
        case .toughLove:
            return toughLoveMessage(event: event, tier: tier, streak: streak)
        case .hardcore:
            return hardcoreMessage(event: event, tier: tier, streak: streak)
        }
    }

    private static func gentleMessage(event: ScheduledEvent, tier: Int, streak: StreakStatus) -> String {
        switch tier {
        case 0: return "Hey — it's time for \(event.title). Jump on it when you can."
        case 1: return "Still haven't done \(event.title). No pressure, but your plan needs it."
        default: return "\(event.title) keeps slipping. Want to adjust the schedule instead of skipping it?"
        }
    }

    private static func toughLoveMessage(event: ScheduledEvent, tier: Int, streak: StreakStatus) -> String {
        switch tier {
        case 0:
            return "\(event.title) was supposed to happen right now. Go do it."
        case 1:
            return "You're late on \(event.title). The plan doesn't move itself — you said this mattered. Prove it."
        default:
            if streak.currentStreakDays > 0 {
                return "\(event.title) missed again. That's a \(streak.currentStreakDays)-day streak on the line — don't throw it away because it got inconvenient."
            }
            return "\(event.title) missed again. 220 to 180 doesn't happen by accident, and it's not happening right now because you're not doing the work. Get back on schedule."
        }
    }

    private static func hardcoreMessage(event: ScheduledEvent, tier: Int, streak: StreakStatus) -> String {
        switch tier {
        case 0:
            return "\(event.title). Now. Not in five minutes."
        case 1:
            return "Still nothing on \(event.title)? You wrote this schedule for a reason and you're already bailing on it."
        default:
            return "\(event.title) blown off again. You're not going to wake up at 180 by accident — every skip like this is you choosing to stay exactly where you are. Move."
        }
    }

    /// Positive reinforcement — used sparingly, on streak milestones and full-adherence days,
    /// so the system doesn't read as purely punitive (variable reinforcement + genuine wins matter too).
    static func winMessage(streak: StreakStatus) -> String? {
        guard streak.currentStreakDays > 0, streak.currentStreakDays % 7 == 0 else { return nil }
        return "\(streak.currentStreakDays) days straight. That's not luck, that's discipline compounding. Keep going."
    }
}
