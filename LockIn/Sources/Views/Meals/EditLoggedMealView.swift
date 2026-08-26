import SwiftUI

/// Corrects a meal that's already in the log.
///
/// Exists because a wrong number used to be unappealable: the only fix was to
/// delete the entry and log it again, which loses the time it was eaten and
/// un-swaps any scheduled meal it replaced. Spotting a mistake an hour later is
/// the normal case, not an edge case.
///
/// Deliberately plain — name and four numbers. Re-running a lookup here would
/// just reproduce whatever was wrong the first time; the point of this screen
/// is that the user knows better than the sources do.
struct EditLoggedMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String

    private let original: LoggedMeal
    /// The field values the sheet opened with.
    ///
    /// Compared against as strings, not as numbers. The fields show whole
    /// grams, so a stored 1.5 g of fat renders as "2" — comparing that back
    /// against 1.5 would read as an edit, and merely opening and closing the
    /// sheet would silently round the meal and stamp it "adjusted by hand".
    private let initialFields: [String]
    let onSave: (LoggedMeal) -> Void
    let onDelete: (LoggedMeal) -> Void

    init(meal: LoggedMeal, onSave: @escaping (LoggedMeal) -> Void, onDelete: @escaping (LoggedMeal) -> Void) {
        self.original = meal
        self.onSave = onSave
        self.onDelete = onDelete
        let fields = [
            Self.field(meal.macros.calories),
            Self.field(meal.macros.proteinG),
            Self.field(meal.macros.fatG),
            Self.field(meal.macros.carbG)
        ]
        self.initialFields = fields
        _name = State(initialValue: meal.name)
        _calories = State(initialValue: fields[0])
        _protein = State(initialValue: fields[1])
        _fat = State(initialValue: fields[2])
        _carbs = State(initialValue: fields[3])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What you ate").ledgerLabel()
                            TextField("Meal", text: $name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) { LedgerRule() }
                            Text("\(original.portionDescription) · \(original.attribution)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkMuted)
                        }

                        // A composed meal's parts are shown but not editable
                        // here: changing one would leave the stored total
                        // disagreeing with the items it claims to be made of.
                        if original.isComposed {
                            componentBreakdown
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Macros").ledgerLabel().padding(.bottom, 6)
                            macroField("Calories", text: $calories)
                            macroField("Protein (g)", text: $protein)
                            macroField("Fat (g)", text: $fat)
                            macroField("Carbs (g)", text: $carbs)
                        }

                        Button(role: .destructive) {
                            Haptics.tap()
                            onDelete(original)
                            dismiss()
                        } label: {
                            Text("Remove this meal")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.signal)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(Theme.rule, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let edited {
                        Button("Save") {
                            Haptics.confirm()
                            onSave(edited)
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent.color)
                    }
                }
            }
        }
    }

    private var componentBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Built from").ledgerLabel().padding(.bottom, 8)
            ForEach(original.components) { component in
                HStack(alignment: .top) {
                    Text(component.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text("\(component.portionDescription) · \(Int(component.macros.calories.rounded()))kcal")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.vertical, 5)
            }
            Text("Editing the totals below detaches them from these parts.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 6)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The edited meal, or nil when the input isn't usable.
    ///
    /// A meal with no name or no calories isn't a correction, it's a way to
    /// lose the entry — so Save simply doesn't appear.
    private var edited: LoggedMeal? {
        Self.apply(name: name, fields: [calories, protein, fat, carbs],
                   initialFields: initialFields, to: original)
    }

    /// The edited meal, or nil when nothing usable changed.
    ///
    /// Pulled out of the view as a pure function so the rules — what counts as
    /// an edit, what makes Save appear — are testable without driving UI.
    static func apply(
        name: String,
        fields: [String],
        initialFields: [String],
        to original: LoggedMeal
    ) -> LoggedMeal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, fields.count == 4,
              let kcal = Double(fields[0]), kcal > 0 else { return nil }

        // Unchanged input is not an edit — don't stamp "adjusted by hand" on a
        // meal the user only opened and closed, and don't round its macros to
        // whole grams on the way back out.
        let macrosTouched = fields != initialFields
        guard macrosTouched || trimmed != original.name else { return nil }

        var result = original
        result.name = trimmed
        if macrosTouched {
            result.macros = MacroTargetsLite(
                calories: kcal,
                proteinG: Double(fields[1]) ?? 0,
                fatG: Double(fields[2]) ?? 0,
                carbG: Double(fields[3]) ?? 0
            )
            result.macrosWereEdited = true
        }
        return result
    }

    private func macroField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 90)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { LedgerRule() }
    }

    /// Whole numbers without a trailing ".0" — these are about to be edited,
    /// and "48" is easier to correct than "48.0".
    private static func field(_ value: Double) -> String {
        String(Int(max(0, value.rounded())))
    }
}
