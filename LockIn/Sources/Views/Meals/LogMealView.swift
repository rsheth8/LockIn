import SwiftUI

/// Sheet for logging something that wasn't on the plan.
///
/// Reached two ways: the always-available "Log a meal" action, and "Ate
/// something else" on a scheduled meal. Both land in the same flow — the only
/// difference is whether the result replaces a planned event.
struct LogMealView: View {
    @StateObject private var model: LogMealViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var showingCamera = false
    @State private var showingLibrary = false

    /// Called with the finished entry so the caller can commit it to AppState.
    let onSave: (LoggedMeal) -> Void

    init(replacingEvent: ScheduledEvent? = nil, onSave: @escaping (LoggedMeal) -> Void) {
        _model = StateObject(wrappedValue: LogMealViewModel(replacingEvent: replacingEvent))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let event = model.replacingEvent {
                            plannedInstead(event)
                        }
                        stepContent
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.canSave {
                        Button("Save") { save() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent.color)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView { image in model.identify(from: image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingLibrary) {
                PhotoLibraryPicker { image in model.identify(from: image) }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        if let error = model.errorMessage {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(Theme.signal)
                .fixedSize(horizontal: false, vertical: true)
        }

        switch model.step {
        case .choosing:
            chooseSection
        case .identifying:
            busy("Looking at the photo…")
        case .candidates(let candidates):
            candidateSection(candidates)
        case .noMatch:
            noMatchSection
        case .resolving(let name):
            busy("Finding macros for \(name)…")
        case .portion(let facts):
            portionSection(facts)
        case .manualEntry(let name):
            manualSection(name)
        }
    }

    /// What the plan had for this slot, when swapping a scheduled meal.
    private func plannedInstead(_ event: ScheduledEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Instead of").ledgerLabel()
            Text(event.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chooseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hidden where there's no camera — the simulator, or a device
            // where it's restricted. Presenting the camera picker there gives
            // a dead black sheet rather than a useful failure.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    Haptics.tap()
                    showingCamera = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.system(size: 15, weight: .semibold))
                        Text("Take a photo").font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptics.tap()
                showingLibrary = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .semibold))
                    Text("Upload a photo").font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.surface)
                .foregroundStyle(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.rule, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text("Recognised on this device against ~720 foods from every major cuisine. The photo is never saved or uploaded, and picking one doesn't give the app access to your library.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            LedgerRule()

            Text("Or type it").ledgerLabel()
            searchField
            searchResultList
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            TextField("e.g. chicken shawarma", text: $model.searchText)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: model.searchText) { _, _ in model.updateSearch() }
                .onSubmit { model.useTypedName() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var searchResultList: some View {
        if !model.searchResults.isEmpty {
            VStack(spacing: 0) {
                ForEach(model.searchResults, id: \.self) { name in
                    nameRow(name) { model.choose(name) }
                    if name != model.searchResults.last { LedgerRule() }
                }
            }
        } else if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            // Nothing in the vocabulary matched, but the lookup chain can still
            // resolve arbitrary text — so offer it rather than dead-ending.
            Button {
                Haptics.tap()
                model.useTypedName()
            } label: {
                HStack {
                    Text("Look up “\(model.searchText)”")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func candidateSection(_ candidates: [FoodVisionClassifier.Candidate]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let preview = model.pendingPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best guesses").ledgerLabel()
                    Text("Tap the right one — or search instead if none fit.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(candidates) { candidate in
                    nameRow(candidate.name, confidence: candidate.score) {
                        model.choose(candidate.name)
                    }
                    if candidate != candidates.last { LedgerRule() }
                }
            }

            Button("None of these") { model.backToChoosing() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent.color)
                .buttonStyle(.plain)
        }
    }

    private var noMatchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn't identify that one")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Mixed plates and unusual angles are hard. Type what you had and it'll still get macros.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            searchField
            searchResultList
        }
    }

    private func portionSection(_ facts: NutritionFacts) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(facts.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(facts.source.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How much").ledgerLabel()
                HStack(spacing: 8) {
                    ForEach(facts.basis.quickAmounts, id: \.self) { value in
                        Button {
                            Haptics.tap()
                            model.amount = value
                        } label: {
                            Text(label(for: value, basis: facts.basis))
                                .font(Theme.mono(13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(model.amount == value ? Theme.ink : Theme.surface)
                                .foregroundStyle(model.amount == value ? Theme.surface : Theme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Theme.rule, lineWidth: model.amount == value ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Photos can't measure a portion — no model can, from a 2D
                // image — so the amount is always the user's call, defaulted
                // rather than guessed.
                Slider(
                    value: $model.amount,
                    in: facts.basis == .per100g ? 20...800 : 0.25...4,
                    step: facts.basis == .per100g ? 10 : 0.25
                )
                .tint(accent.color)

                Text(facts.portionDescription(for: model.amount))
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            LedgerRule()
            macroReadout(facts.scaled(to: model.amount))

            if facts.source.isEstimate {
                Text("Estimated from the dish name — no photo can measure a portion, so treat this as a ballpark, not a weighed meal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Pick something else") { model.backToChoosing() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent.color)
                .buttonStyle(.plain)
        }
    }

    private func manualSection(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("No macro data found for this one — enter what you know.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // Label databases only cover ingredients and packaged goods
                // well, so without the (free) Spoonacular key most cooked
                // dishes land here. Worth saying once, where it's relevant,
                // rather than leaving it looking broken.
                if Secrets.spoonacularKey == nil {
                    Text("Cooked dishes need a Spoonacular key to estimate automatically — see Setup in the README. It's free.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            macroField("Calories", text: $model.manualCalories)
            macroField("Protein (g)", text: $model.manualProtein)
            macroField("Fat (g)", text: $model.manualFat)
            macroField("Carbs (g)", text: $model.manualCarbs)

            Button("Pick something else") { model.backToChoosing() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent.color)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Pieces

    private func nameRow(_ name: String, confidence: Float? = nil, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Text(name.capitalizedFirst)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let confidence {
                    Text("\(Int(confidence * 100))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func macroReadout(_ macros: MacroTargetsLite) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Int(macros.calories.rounded()))")
                .font(Theme.mono(24, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("kcal")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text("P\(Int(macros.proteinG.rounded()))  F\(Int(macros.fatG.rounded()))  C\(Int(macros.carbG.rounded()))")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private func busy(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.inkMuted)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func label(for value: Double, basis: PortionBasis) -> String {
        switch basis {
        case .per100g: return "\(Int(value))g"
        case .perServing: return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        }
    }

    private func save() {
        guard let meal = model.buildLoggedMeal() else { return }
        Haptics.confirm()
        onSave(meal)
        dismiss()
    }
}

private extension String {
    /// Vocabulary names are stored lowercase for matching; the UI shouldn't
    /// shout them back in that form.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
