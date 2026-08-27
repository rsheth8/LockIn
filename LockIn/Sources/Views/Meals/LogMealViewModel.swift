import SwiftUI
import UIKit

/// Drives the "log a meal" sheet: identify the food (photo, search, or free
/// text), resolve its macros, adjust them if they're wrong, pick a portion,
/// optionally stack several items into one bowl, save.
///
/// The photo is held only as a `UIImage` in `pendingPreview` for as long as the
/// confirm step is on screen, and dropped the moment the food is identified —
/// nothing is ever written to disk. See `identify(from:)`.
///
/// Two escape hatches exist because photo recognition has two distinct failure
/// modes, and neither is fixable by a better model:
///
/// - **It returns one label.** A bowl of yogurt, fruit, granola and a scoop of
///   whey classifies as "granola bowl" and logs ~6 g of protein. `components`
///   lets the meal be built from its parts instead.
/// - **It can be confidently wrong.** A plausible lookup used to be
///   unappealable — `adjustMacros` makes every number the user's to overrule.
@MainActor
final class LogMealViewModel: ObservableObject {

    /// Why the editable-macro form is on screen. The fields are identical in
    /// all three cases; only the explanation and the recorded source differ.
    enum ManualReason: Equatable {
        /// Every lookup missed.
        case nothingFound
        /// The user chose to overrule numbers a lookup did return.
        case correcting(NutritionSource)
        /// OCR read them off a Nutrition Facts panel, and they're presented
        /// for checking rather than typing.
        case scannedLabel(found: Int)

        /// What to store on the saved entry.
        var savedSource: NutritionSource {
            if case .scannedLabel = self { return .nutritionLabel }
            return .manual
        }
    }

    /// A food the user is entering or checking macros for by hand.
    struct ManualDraft: Equatable {
        let name: String
        let portionDescription: String
        let reason: ManualReason

        var correcting: NutritionSource? {
            if case .correcting(let source) = reason { return source }
            return nil
        }
    }

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
        case manualEntry(ManualDraft)
    }

    @Published private(set) var step: Step = .choosing
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [String] = []
    /// Shown next to the candidate list while the confirm step is up; cleared
    /// as soon as a food is chosen.
    @Published private(set) var pendingPreview: UIImage?
    @Published var amount: Double = 200
    @Published private(set) var errorMessage: String?

    /// Items already added to the bowl. Empty for an ordinary single-food log,
    /// which stays exactly as simple as it was.
    @Published private(set) var components: [LoggedComponent] = []
    /// What to call the finished bowl. Blank means "derive one from the parts".
    @Published var bowlName: String = ""

    /// Manual-entry fields, used when a lookup misses *or* when the user is
    /// overriding one that didn't.
    ///
    /// The name is editable too: OCR can't read a product name off a nutrition
    /// panel, and a photo guess is often nearly-but-not-quite right.
    @Published var manualName: String = ""
    @Published var manualCalories: String = ""
    @Published var manualProtein: String = ""
    @Published var manualFat: String = ""
    @Published var manualCarbs: String = ""

    /// Set when this log is replacing a scheduled meal.
    let replacingEvent: ScheduledEvent?
    private var usedPhoto = false
    private var didEditMacros = false
    /// Kept so cancelling an adjustment can return to the portion picker
    /// rather than dumping the user back at the start.
    private var factsBeforeAdjusting: NutritionFacts?
    private var vocabulary: FoodVocabulary?

    init(replacingEvent: ScheduledEvent? = nil) {
        self.replacingEvent = replacingEvent
    }

    var title: String {
        if isBuildingBowl { return "Build a meal" }
        return replacingEvent == nil ? "Log a meal" : "Ate something else"
    }

    var isBuildingBowl: Bool { !components.isEmpty }

    /// Running total of what's in the bowl so far, before the in-progress item.
    var componentsTotal: MacroTargetsLite { .sum(components.map(\.macros)) }

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
    ///
    /// `isFreeText` marks names the user typed that aren't in the vocabulary;
    /// those get the restaurant-menu lookup, which vocabulary names skip.
    func choose(_ name: String, isFreeText: Bool = false) {
        // The photo has done its job. Drop it now rather than at dismiss, so
        // it isn't held while a network lookup runs.
        pendingPreview = nil
        step = .resolving(name)
        errorMessage = nil

        Task {
            // Whether this is a composed dish or a single ingredient decides
            // which nutrition source is tried first — see NutritionLookup.
            let vocabulary = await loadVocabulary()
            let isDish = vocabulary?.isDish(name) ?? true
            let unknownToVocabulary = isFreeText && !(vocabulary?.contains(name) ?? false)

            if let facts = await NutritionLookup.facts(for: name, isDish: isDish, isFreeText: unknownToVocabulary) {
                present(facts)
            } else {
                startManualEntry(name: name, portionDescription: "1 serving", reason: .nothingFound)
            }
        }
    }

    func useTypedName() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        choose(trimmed, isFreeText: true)
    }

    // MARK: - Barcode

    /// Looks up a scanned barcode against Open Food Facts.
    ///
    /// The most accurate path in the app: a barcode names one exact product,
    /// so there's no guessing what the food is and the numbers are the
    /// manufacturer's. Unknown codes are a normal outcome — Open Food Facts is
    /// crowd-sourced — so a miss routes to the label scanner rather than an
    /// error, since the box in the user's hand has the answer printed on it.
    func lookUpBarcode(_ code: String) {
        pendingPreview = nil
        step = .resolving("barcode \(code)")
        errorMessage = nil

        Task {
            do {
                if let facts = try await OpenFoodFactsClient.shared.product(barcode: code) {
                    present(facts)
                } else {
                    step = .choosing
                    errorMessage = "That barcode isn't in the food database yet. Scan the nutrition label instead — that always works."
                }
            } catch {
                step = .choosing
                errorMessage = "Couldn't reach the food database. Scan the nutrition label or type it instead."
            }
        }
    }

    // MARK: - Nutrition label

    /// Reads a photographed Nutrition Facts panel with on-device OCR.
    ///
    /// Always lands on the editable form rather than a finished result: OCR on
    /// a curved, glossy or crumpled package does misread, and a number the
    /// user hasn't looked at is exactly the kind of fake precision the rest of
    /// this flow avoids. Whatever was read is pre-filled for checking.
    func readLabel(from image: UIImage) {
        usedPhoto = true
        pendingPreview = Self.thumbnail(from: image)
        step = .identifying
        errorMessage = nil

        Task {
            let reading = (try? await NutritionLabelReader.read(image)) ?? NutritionLabelReader.Reading()
            pendingPreview = nil

            guard reading.isUsable else {
                startManualEntry(name: "", portionDescription: "1 serving", reason: .nothingFound)
                errorMessage = "Couldn't read that label. Fill the numbers in by hand, or try again with the panel filling the frame and the light off the plastic."
                return
            }

            manualCalories = Self.field(reading.calories ?? 0)
            manualProtein = reading.protein.map(Self.field) ?? ""
            manualFat = reading.fat.map(Self.field) ?? ""
            manualCarbs = reading.carbs.map(Self.field) ?? ""
            manualName = ""
            step = .manualEntry(ManualDraft(
                name: "",
                // The panel's own serving wording, so the entry records what
                // the numbers actually describe.
                portionDescription: reading.servingText ?? "1 serving",
                reason: .scannedLabel(found: reading.foundCount)
            ))
        }
    }

    func backToChoosing() {
        pendingPreview = nil
        factsBeforeAdjusting = nil
        searchText = ""
        searchResults = []
        errorMessage = nil
        step = .choosing
    }

    // MARK: - Correcting the numbers

    /// Moves from the portion picker into hand-editable macros, seeded with
    /// whatever the lookup produced for the currently chosen portion.
    ///
    /// Seeding rather than blanking matters: the common correction is one
    /// number being wrong (the scoop of whey the photo couldn't see), not all
    /// four, and retyping the other three invites new errors.
    func adjustMacros() {
        guard case .portion(let facts) = step else { return }
        let scaled = facts.scaled(to: amount)
        manualName = facts.name
        manualCalories = Self.field(scaled.calories)
        manualProtein = Self.field(scaled.proteinG)
        manualFat = Self.field(scaled.fatG)
        manualCarbs = Self.field(scaled.carbG)
        factsBeforeAdjusting = facts
        didEditMacros = true
        step = .manualEntry(ManualDraft(
            name: facts.name,
            portionDescription: facts.portionDescription(for: amount),
            reason: .correcting(facts.source)
        ))
    }

    /// Back to the portion picker, abandoning the edit.
    func cancelAdjusting() {
        guard let facts = factsBeforeAdjusting else { return backToChoosing() }
        factsBeforeAdjusting = nil
        didEditMacros = false
        step = .portion(facts)
    }

    var canCancelAdjusting: Bool { factsBeforeAdjusting != nil }

    // MARK: - Building a bowl

    /// Banks the item currently on screen and returns to the picker for the
    /// next one.
    func addCurrentToBowl() {
        guard let component = currentComponent() else { return }
        components.append(component)
        didEditMacros = false
        factsBeforeAdjusting = nil
        manualName = ""
        clearManualFields()
        backToChoosing()
    }

    func removeComponent(_ component: LoggedComponent) {
        components.removeAll { $0.id == component.id }
    }

    /// Whether "add another" makes sense right now — there has to be something
    /// on screen worth banking.
    var canAddToBowl: Bool { currentComponent() != nil }

    // MARK: - Saving

    /// Builds the log entry, or nil if the state isn't ready to save.
    ///
    /// Whatever item is on screen is folded in automatically, so a user who
    /// stacks three things and hits Save on the fourth gets all four rather
    /// than silently losing the one they were looking at.
    func buildLoggedMeal() -> LoggedMeal? {
        let pending = currentComponent()
        let all = components + (pending.map { [$0] } ?? [])
        guard let first = all.first else { return nil }

        // A plain single-food log keeps its original shape — no components
        // array, no derived name — so the common case is untouched.
        guard all.count > 1 else {
            return LoggedMeal(
                name: first.name,
                portionDescription: first.portionDescription,
                macros: first.macros,
                source: first.source,
                replacedEventID: replacingEvent?.id,
                identifiedFromPhoto: usedPhoto,
                macrosWereEdited: didEditMacros
            )
        }

        return LoggedMeal.composed(
            from: all,
            name: resolvedBowlName(for: all),
            replacedEventID: replacingEvent?.id,
            identifiedFromPhoto: usedPhoto
        )
    }

    var canSave: Bool { buildLoggedMeal() != nil }

    /// The user's title if they gave one, otherwise the derived fallback.
    func resolvedBowlName(for items: [LoggedComponent]) -> String {
        let typed = bowlName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Self.derivedName(for: items) : typed
    }

    /// Something honest and specific enough to recognise in the log a week
    /// later, without pretending to know what the user would have called it.
    private static func derivedName(for items: [LoggedComponent]) -> String {
        guard let first = items.first else { return "Meal" }
        return items.count == 1 ? first.name : "\(first.name) + \(items.count - 1) more"
    }

    /// Placeholder for the bowl-name field, so it previews what Save would
    /// store. Read-only — it must never touch `bowlName`, or typing in the
    /// field would fight the view that renders it.
    var bowlNamePlaceholder: String {
        var items = components
        if let pending = currentComponent() { items.append(pending) }
        return Self.derivedName(for: items)
    }

    // MARK: - Helpers

    /// Whatever the current step represents, as a bankable item — nil when
    /// there's nothing resolved yet, or the manual entry isn't usable.
    private func currentComponent() -> LoggedComponent? {
        switch step {
        case .portion(let facts):
            return LoggedComponent(
                name: facts.name,
                portionDescription: facts.portionDescription(for: amount),
                macros: facts.scaled(to: amount),
                source: facts.source
            )
        case .manualEntry(let draft):
            // Both a name and calories are required. A label scan starts with
            // no name at all, and "0 kcal" for an unnamed item is not a meal.
            let name = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let calories = Double(manualCalories), calories > 0 else { return nil }
            return LoggedComponent(
                name: name,
                portionDescription: draft.portionDescription,
                macros: MacroTargetsLite(
                    calories: calories,
                    proteinG: Double(manualProtein) ?? 0,
                    fatG: Double(manualFat) ?? 0,
                    carbG: Double(manualCarbs) ?? 0
                ),
                source: draft.reason.savedSource
            )
        default:
            return nil
        }
    }

    /// Shows a resolved food, starting at whatever portion the source implies —
    /// a scanned bar opens at its own 40 g serving, not the generic 200 g.
    private func present(_ facts: NutritionFacts) {
        amount = facts.startingAmount
        step = .portion(facts)
    }

    private func startManualEntry(name: String, portionDescription: String, reason: ManualReason) {
        manualName = name
        clearManualFields()
        step = .manualEntry(ManualDraft(name: name, portionDescription: portionDescription, reason: reason))
    }

    private func clearManualFields() {
        manualCalories = ""
        manualProtein = ""
        manualFat = ""
        manualCarbs = ""
    }

    /// Whole numbers without a trailing ".0" — these land in a text field the
    /// user is about to edit, and "48" is easier to correct than "48.0".
    ///
    /// A half gram is kept, though. Labels really do print "Total Fat 3.5g",
    /// and rounding that to 4 on the way into the form would throw away
    /// precision the label actually stated — "3.5" is no harder to correct.
    private static func field(_ value: Double) -> String {
        let clamped = max(0, value)
        guard clamped != clamped.rounded() else { return String(Int(clamped)) }
        return String(format: "%.1f", clamped)
    }

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
