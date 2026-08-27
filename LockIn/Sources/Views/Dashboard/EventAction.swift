import Foundation

/// The one thing a scheduled event most wants you to *do*, beyond ticking it off.
///
/// This exists so the hero card, the timeline row and the context menu all read
/// the same answer. Before it, "Ate something else" was hand-wired onto meals in
/// three places and a workout had no path at all — you could confirm a session
/// you were never actually walked through.
enum EventAction: String, Equatable {
    case logMeal
    case startWorkout
    case logWeight
    case takePhoto

    /// Full label, for the hero card's primary button.
    var title: String {
        switch self {
        case .logMeal: return "Log what you ate"
        case .startWorkout: return "Start workout"
        case .logWeight: return "Log your weight"
        case .takePhoto: return "Take the photo"
        }
    }

    /// Compressed label for context menus and tight rows.
    var shortTitle: String {
        switch self {
        case .logMeal: return "Log meal"
        case .startWorkout: return "Start"
        case .logWeight: return "Weigh in"
        case .takePhoto: return "Camera"
        }
    }

    var systemImage: String {
        switch self {
        case .logMeal: return "fork.knife"
        case .startWorkout: return "figure.strengthtraining.traditional"
        case .logWeight: return "scalemass"
        case .takePhoto: return "camera.fill"
        }
    }

    /// Nil for events whose only honest answer is "did it / didn't" — waking up,
    /// coffee, wind-down — and for the structural class/commute blocks, which
    /// aren't promises at all.
    static func primary(for event: ScheduledEvent) -> EventAction? {
        switch event.kind {
        case .meal: return .logMeal
        case .workout: return .startWorkout
        case .weighIn: return .logWeight
        case .progressPhoto: return .takePhoto
        case .wake, .caffeine, .mealPrep, .windDown, .sleep, .hydration, .custom:
            return nil
        case .classSession, .commute:
            return nil
        }
    }
}
