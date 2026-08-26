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
    @State private var showingBarcode = false
    @State private var showingLabelCamera = false
    @State private var showingLabelLibrary = false
    @State private var choosingLabelSource = false

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
                        if model.isBuildingBowl {
                            bowlSection
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
            .fullScreenCover(isPresented: $showingBarcode) {
                BarcodeScannerView { code in model.lookUpBarcode(code) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingLabelCamera) {
                CameraCaptureView { image in model.readLabel(from: image) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingLabelLibrary) {
                PhotoLibraryPicker { image in model.readLabel(from: image) }
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
        case .manualEntry(let draft):
            manualSection(draft)
        }
    }

    // MARK: - Bowl

    /// What's been stacked so far, with a running total. Only appears once
    /// there's more than one item in play, so a plain single-food log never
    /// sees it.
    private var bowlSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("In this meal").ledgerLabel()
                Spacer()
                let total = model.componentsTotal
                Text("\(Int(total.calories.rounded())) kcal · P\(Int(total.proteinG.rounded()))")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.bottom, 8)

            ForEach(model.components) { component in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.name.capitalizedFirst)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("\(component.portionDescription) · \(Int(component.macros.calories.rounded()))kcal · P\(Int(component.macros.proteinG.rounded())) F\(Int(component.macros.fatG.rounded())) C\(Int(component.macros.carbG.rounded()))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) { model.removeComponent(component) }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 7)
            }

            LedgerRule().padding(.top, 4)

            HStack(spacing: 8) {
                Text("Call it").ledgerLabel()
                TextField(model.bowlNamePlaceholder, text: $model.bowlName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.done)
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        )
    }

    /// Banks the item on screen and goes back for the next one.
    private func addAnotherButton(_ label: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { model.addCurrentToBowl() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surfaceMuted)
            .foregroundStyle(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.canAddToBowl)
        .opacity(model.canAddToBowl ? 1 : 0.4)
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
            if model.isBuildingBowl {
                Text("Add the next item — or hit Save to log what's there.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

            packagedSection

            LedgerRule()

            Text("Or type it").ledgerLabel()
            searchField
            searchResultList
        }
    }

    /// Anything that came out of a box. Recognising a plate of food and
    /// reading a package are genuinely different problems — a protein bar
    /// looks like every other protein bar, but its barcode and its label both
    /// say exactly what it is.
    @ViewBuilder
    private var packagedSection: some View {
        Text("Packaged food").ledgerLabel()

        // Barcode first: it's the most accurate lookup in the app and needs
        // nothing from the user but pointing the camera.
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            secondaryButton("barcode.viewfinder", "Scan a barcode") {
                showingBarcode = true
            }
        }

        secondaryButton("doc.text.viewfinder", "Scan a nutrition label") {
            // Both sources matter here in a way they don't for the barcode: a
            // label is often already in the camera roll (a photo taken in the
            // shop, a screenshot of a product page), and OCR treats a saved
            // image exactly the same as a fresh capture.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                choosingLabelSource = true
            } else {
                showingLabelLibrary = true
            }
        }
        .confirmationDialog("Scan a nutrition label", isPresented: $choosingLabelSource, titleVisibility: .visible) {
            Button("Take a photo") { showingLabelCamera = true }
            Button("Choose an existing photo") { showingLabelLibrary = true }
            Button("Cancel", role: .cancel) {}
        }

        Text("A barcode gets the manufacturer's own numbers from a database of millions of products — Costco, Trader Joe's, the lot. If it's not in there, the label on the box is read on this device with no internet at all.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func secondaryButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 14)
            .background(Theme.surface)
            .foregroundStyle(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                HStack(alignment: .firstTextBaseline) {
                    Text("How much").ledgerLabel()
                    Spacer()
                    // A scanned product knows its own serving, which is a far
                    // better anchor than a round number of grams.
                    if let serving = facts.servingLabel, facts.servingGrams != nil {
                        Text("1 serving = \(serving)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(facts.quickAmounts, id: \.self) { value in
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
                Slider(value: $model.amount, in: facts.amountRange, step: facts.amountStep)
                    .tint(accent.color)

                Text(facts.portionDescription(for: model.amount))
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            LedgerRule()
            macroReadout(facts.scaled(to: model.amount))

            // No lookup is authoritative — the scoop of whey in a yogurt bowl
            // is invisible to every source the app has. Correcting the numbers
            // has to be one tap from where they're shown, or the log quietly
            // records something the user knows is wrong.
            Button {
                Haptics.tap()
                model.adjustMacros()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                    Text("Adjust these numbers").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(accent.color)
            }
            .buttonStyle(.plain)

            if facts.source.isEstimate {
                Text("Estimated from the dish name — no photo can measure a portion, so treat this as a ballpark, not a weighed meal.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LedgerRule()

            addAnotherButton(model.isBuildingBowl ? "Add this, then another" : "Add another item")
            Text("Building a bowl? Add each part separately — yogurt, granola, a scoop of whey — and they're added up. One photo can only ever name one food.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Pick something else") { model.backToChoosing() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent.color)
                .buttonStyle(.plain)
        }
    }

    private func manualSection(_ draft: LogMealViewModel.ManualDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                // Editable, because a label scan starts with no name at all and
                // a photo guess is often nearly-but-not-quite right.
                TextField("What was it?", text: $model.manualName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { LedgerRule() }

                switch draft.reason {
                case .correcting(let source):
                    // Reached by choice, not by failure — say which numbers are
                    // being overruled so the edit is an informed one.
                    Text("\(draft.portionDescription) · was \(source.label.lowercased()). Change whatever's wrong; the rest stays.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                case .scannedLabel(let found):
                    Text("Read \(found) of 4 off the label\(draft.portionDescription == "1 serving" ? "" : " · per \(draft.portionDescription)"). Check them against the box before saving — OCR misreads glossy packaging.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                case .nothingFound:
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
            }

            macroField("Calories", text: $model.manualCalories)
            macroField("Protein (g)", text: $model.manualProtein)
            macroField("Fat (g)", text: $model.manualFat)
            macroField("Carbs (g)", text: $model.manualCarbs)

            addAnotherButton(model.isBuildingBowl ? "Add this, then another" : "Add another item")

            if model.canCancelAdjusting {
                Button("Back to the original numbers") { model.cancelAdjusting() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent.color)
                    .buttonStyle(.plain)
            } else {
                Button("Pick something else") { model.backToChoosing() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent.color)
                    .buttonStyle(.plain)
            }
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
