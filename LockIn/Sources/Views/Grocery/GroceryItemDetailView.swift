import SwiftUI

/// One product, and the case for or against it.
///
/// The whole point of this screen is the *why* — the score at the top is a
/// summary of the sentences underneath it, not an oracle. Anything the label
/// didn't say is shown as unknown rather than quietly omitted, so a sparse
/// record looks sparse.
struct GroceryItemDetailView: View {
    let scored: ScoredGroceryItem
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent

    private var item: GroceryItem { scored.item }
    private var score: SmartScore { scored.score }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    addToListButton
                    LedgerRule()
                    verdict
                    LedgerRule()
                    macroSection
                    LedgerRule()
                    labelSection
                    LedgerRule()
                    buySection
                    disclaimer
                }
                .padding(Theme.gutter)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = item.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.surfaceMuted
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let quantity = item.quantityText {
                    Text(quantity)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            Spacer(minLength: 8)
            ScoreBadge(score: score, large: true)
        }
    }

    /// Toggles rather than only adding, so the screen can undo itself — the
    /// most likely correction right after adding is realising you didn't mean
    /// to, and making the user go find the list to fix that is a poor trade.
    private var addToListButton: some View {
        let isOnList = appState.isOnShoppingList(item.id)
        return Button {
            Haptics.tap()
            if isOnList {
                appState.removeFromShoppingList(item.id)
            } else {
                appState.addToShoppingList(scored)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOnList ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(isOnList ? "On your list" : "Add to list")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isOnList ? Theme.surface : Theme.ink)
            .foregroundStyle(isOnList ? Theme.ink : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: isOnList ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The read").ledgerLabel()

            if score.confidence == .thin {
                Text("This record barely has a label on it — too little to judge properly. Treat the number as a placeholder, not a verdict.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if score.reasons.isEmpty && score.cautions.isEmpty {
                Text("Nothing on this record stands out either way.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
            }

            ForEach(score.reasons, id: \.self) { reason in
                bullet(reason, icon: "checkmark", tint: accent.color)
            }
            ForEach(score.cautions, id: \.self) { caution in
                bullet(caution, icon: "exclamationmark", tint: Theme.inkMuted)
            }
        }
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Per 100 g").ledgerLabel()
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(item.per100g.calories.rounded()))")
                    .font(Theme.mono(24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("kcal")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                Text("P\(Int(item.per100g.proteinG.rounded()))  F\(Int(item.per100g.fatG.rounded()))  C\(Int(item.per100g.carbG.rounded()))")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What the label says").ledgerLabel()
                .padding(.bottom, 6)

            labelRow("Sugar", grams(item.quality.sugarsPer100g))
            labelRow("Saturated fat", grams(item.quality.saturatedFatPer100g))
            labelRow("Sodium", item.quality.sodiumMgPer100g.map { "\(Int($0.rounded())) mg" })
            labelRow("Fibre", grams(item.quality.fiberPer100g))
            labelRow("Nutri-Score", item.quality.nutriScoreGrade?.uppercased())
            labelRow("Processing", processingLabel)
            labelRow("Additives", item.quality.additivesCount.map(String.init))
            labelRow("Ingredients", item.quality.ingredientCount.map { "\($0) listed" })
        }
    }

    private var buySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go get it").ledgerLabel()
            HStack(spacing: 10) {
                ForEach(Retailer.allCases) { retailer in
                    RetailerButton(term: item.searchTerm, retailer: retailer)
                }
            }
            // Says plainly what the button does, so a search-results page
            // instead of the product isn't a surprise.
            Text("Opens a search for “\(item.searchTerm)” in the retailer's app. Neither store lets other apps link to an exact product or read prices, so the last step is yours.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Attribution names the actual source. The two differ in kind — a
    /// crowd-sourced packet label and a USDA lab assay deserve different levels
    /// of trust, and saying "Open Food Facts" under a USDA figure would be
    /// straightforwardly false.
    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source · \(item.source.label)").ledgerLabel()
            Text("\(item.source.blurb) The score is a rough guide, not a medical opinion.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Pieces

    private func bullet(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14, height: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Missing data reads as "not recorded", never as a blank or a zero — the
    /// gap is information about the record, and hiding it would make a
    /// half-empty entry look complete.
    private func labelRow(_ name: String, _ value: String?) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value ?? "not recorded")
                .font(Theme.mono(13, weight: value == nil ? .regular : .semibold))
                .foregroundStyle(value == nil ? Theme.inkFaint : Theme.ink)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { LedgerRule() }
    }

    private var processingLabel: String? {
        guard let nova = item.quality.novaGroup else { return nil }
        switch nova {
        case 1: return "NOVA 1 · unprocessed"
        case 2: return "NOVA 2 · culinary"
        case 3: return "NOVA 3 · processed"
        default: return "NOVA 4 · ultra"
        }
    }

    private func grams(_ value: Double?) -> String? {
        guard let value else { return nil }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) g" : String(format: "%.1f g", rounded)
    }
}
