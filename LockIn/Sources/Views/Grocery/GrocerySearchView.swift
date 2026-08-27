import SwiftUI

/// Shop Smart: look up a grocery item, see what the label actually says, and
/// go buy it.
///
/// Reached from the log-a-meal sheet, which is where the "what should I even
/// get" question tends to land.
struct GrocerySearchView: View {
    @StateObject private var model: GrocerySearchViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    init(provider: GroceryProvider = OpenFoodFactsGroceryProvider()) {
        _model = StateObject(wrappedValue: GrocerySearchViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        searchField
                        content
                    }
                    .padding(Theme.gutter)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Shop Smart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .navigationDestination(for: ScoredGroceryItem.self) { scored in
                GroceryItemDetailView(scored: scored)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            TextField("e.g. greek yogurt", text: $model.query)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
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
    private var content: some View {
        switch model.state {
        case .idle:
            introSection

        case .searching:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.inkMuted)
                Text("Looking along the shelf…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)

        case .results(let scored):
            resultList(scored)

        case .empty(let query):
            emptySection(query)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.signal)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.retry() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent.color)
                    .buttonStyle(.plain)
            }
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What it does").ledgerLabel()
            Text("Search a grocery item and it's ranked on what the label actually says — sugar, saturated fat, sodium, fibre, protein and how processed it is. Then take the pick straight to Walmart or Target.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            LedgerRule()

            Text("Try")
                .ledgerLabel()
            // Suggestions rather than an empty screen, chosen to show the tool
            // at its best: packaged goods are where the label database is deep.
            // Two per row so the longer ones don't clip on a small phone.
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { pair in
                    HStack(spacing: 8) {
                        ForEach(pair, id: \.self) { suggestion in
                            suggestionChip(suggestion)
                        }
                    }
                }
            }
        }
    }

    private static let suggestions = [
        ["greek yogurt", "peanut butter"],
        ["protein bar", "granola"],
        ["oat milk", "tortilla"]
    ]

    private func suggestionChip(_ suggestion: String) -> some View {
        Button {
            Haptics.tap()
            model.query = suggestion
        } label: {
            Text(suggestion)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.rule, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func emptySection(_ query: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing for “\(query)”")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            // Naming the actual limitation beats a generic "no results" —
            // otherwise loose produce reads as the feature being broken.
            Text("The label database covers packaged food well and fresh produce badly. Try a brand or a boxed version — or search the retailer directly.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(Retailer.allCases) { retailer in
                    RetailerButton(term: query, retailer: retailer, prominent: false)
                }
            }
            .padding(.top, 4)
        }
    }

    private func resultList(_ scored: [ScoredGroceryItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(scored.count) \(scored.count == 1 ? "result" : "results")").ledgerLabel()
                .padding(.bottom, 4)

            ForEach(scored) { entry in
                NavigationLink(value: entry) {
                    GroceryResultRow(scored: entry)
                }
                .buttonStyle(.plain)
                if entry.id != scored.last?.id { LedgerRule() }
            }

            Text("A rough guide from public label data, not a medical opinion. Crowd-sourced entries have gaps — check the box.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
    }
}

/// One product on the shelf.
struct GroceryResultRow: View {
    let scored: ScoredGroceryItem
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scored.item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                let macros = scored.item.per100g
                Text("\(Int(macros.calories.rounded())) kcal · P\(Int(macros.proteinG.rounded())) F\(Int(macros.fatG.rounded())) C\(Int(macros.carbG.rounded())) per 100 g")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkMuted)

                // The single most useful sentence, not the whole list — the
                // detail screen is one tap away for the rest.
                if let headline = scored.score.reasons.first ?? scored.score.cautions.first {
                    Text(headline)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            ScoreBadge(score: scored.score)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// The number and its band.
///
/// Monochrome by design — Theme reserves the signal red for "you're slipping",
/// and a jar of jam scoring badly on a shelf isn't a broken promise. Rank is
/// carried by the accent and by weight instead.
struct ScoreBadge: View {
    let score: SmartScore
    var large: Bool = false
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(score.value)")
                .font(Theme.mono(large ? 34 : 20, weight: .semibold))
                .foregroundStyle(score.band == .smart ? accent.color : Theme.ink)
            Text(score.confidence == .thin ? "Thin data" : score.band.label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

/// A link out to a retailer's search.
struct RetailerButton: View {
    let term: String
    let retailer: Retailer
    var prominent: Bool = true

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = RetailerLink.searchURL(for: term, at: retailer) else { return }
            Haptics.tap()
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                Text(retailer.displayName)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(prominent ? Theme.ink : Theme.surface)
            .foregroundStyle(prominent ? Theme.surface : Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: prominent ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
