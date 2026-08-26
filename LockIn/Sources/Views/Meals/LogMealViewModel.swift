import SwiftUI
import UIKit

/// Drives the "log a meal" sheet: identify the food (photo, search, or free
/// text), resolve its macros, pick a portion, save.
///
/// The photo is held only as a `UIImage` in `pendingPreview` for as long as the
/// confirm step is on screen, and dropped the moment the food is identified —
/// nothing is ever written to disk. See `identify(from:)`.
@MainActor
final class LogMealViewModel: ObservableObject {

    /// Where the sheet currently is. A single enum rather than a pile of
    /// booleans, so impossible combinations (searching *and* resolving) can't
    /// be represented.
    enum Step: Equatable {
        case choosing
        case identifying
        case candidates([FoodVisionClassifier.Candidate])
        case noMatch
        case resolving(String)
        case portion(NutritionFacts)
        case manualEntry(String)
    }

    @Published private(set) var step: Step = .choosing
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [String] = []
    /// Shown next to the candidate list while the confirm step is up; cleared
    /// as soon as a food is chosen.
    @Published private(set) var pendingPreview: UIImage?
    @Published var amount: Double = 200
    @Published private(set) var errorMessage: String?

    /// Manual-entry fields, used when every lookup misses.
    @Published var manualCalories: String = ""
    @Published var manualProtein: String = ""
    @Published var manualFat: String = ""
    @Published var manualCarbs: String = ""

    /// Set when this log is replacing a scheduled meal.
    let replacingEvent: ScheduledEvent?
    private var usedPhoto = false
    private var vocabulary: FoodVocabulary?

    init(replacingEvent: ScheduledEvent? = nil) {
        self.replacingEvent = replacingEvent
    }

    var title: String {
        replacingEvent == nil ? "Log a meal" : "Ate something else"
    }

    // MARK: - Identification

    /// Runs the on-device classifier and moves to the candidate list.
    ///
    /// The full-resolution capture is passed straight through and never
    /// retained here; `pendingPreview` holds a small thumbnail purely so the
    /// user can see what they shot while picking from the guesses.
    func identify(from image: UIImage) {
        usedPhoto = true
        pendingPreview = Self.thumbnail(from: image)
        step = .identifying
        errorMessage = nil

        Task {
            do {
                let candidates = try await FoodVisionClassifier.shared.classify(image)
                if candidates.isEmpty {
                    step = .noMatch
                } else {
                    step = .candidates(candidates)
                }
            } catch {
                // A classifier failure shouldn't dead-end the flow — typing the
                // dish name still works and reaches the same lookup.
                step = .noMatch
                errorMessage = "Couldn't read that photo. You can type what you had instead."
            }
        }
    }

    func updateSearch() {
        Task {
            let vocabulary = await loadVocabulary()
            searchResults = vocabulary?.search(searchText) ?? []
        }
    }

    /// User picked a name — from the photo guesses, from search, or typed.
    func choose(_ name: String) {
        // The photo has done its job. Drop it now rather than at dismiss, so
        // it isn't held while a network lookup runs.
        pendingPreview = nil
        step = .resolving(name)
        errorMessage = nil

        Task {
            if let facts = await NutritionLookup.facts(for: name) {
                amount = facts.basis.defaultAmount
                step = .portion(facts)
            } else {
                step = .manualEntry(name)
            }
        }
    }

    func useTypedName() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        choose(trimmed)
    }

    func backToChoosing() {
        pendingPreview = nil
        searchText = ""
        searchResults = []
        errorMessage = nil
        step = .choosing
    }

    // MARK: - Saving

    /// Builds the log entry for the chosen portion, or nil if the state isn't
    /// ready to save.
    func buildLoggedMeal() -> LoggedMeal? {
        switch step {
        case .portion(let facts):
            return LoggedMeal(
                name: facts.name,
                portionDescription: facts.portionDescription(for: amount),
                macros: facts.scaled(to: amount),
                source: facts.source,
                replacedEventID: replacingEvent?.id,
                identifiedFromPhoto: usedPhoto
            )
        case .manualEntry(let name):
            guard let calories = Double(manualCalories), calories > 0 else { return nil }
            return LoggedMeal(
                name: name,
                portionDescription: "1 serving",
                macros: MacroTargetsLite(
                    calories: calories,
                    proteinG: Double(manualProtein) ?? 0,
                    fatG: Double(manualFat) ?? 0,
                    carbG: Double(manualCarbs) ?? 0
                ),
                source: .manual,
                replacedEventID: replacingEvent?.id,
                identifiedFromPhoto: usedPhoto
            )
        default:
            return nil
        }
    }

    var canSave: Bool { buildLoggedMeal() != nil }

    // MARK: - Helpers

    private func loadVocabulary() async -> FoodVocabulary? {
        if let vocabulary { return vocabulary }
        let loaded = try? FoodVocabulary.loadBundled()
        vocabulary = loaded
        return loaded
    }

    /// Small preview so the confirm step isn't holding a multi-megabyte
    /// decoded capture just to draw a 120pt thumbnail.
    private static func thumbnail(from image: UIImage, maxSide: CGFloat = 240) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
