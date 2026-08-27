import SwiftUI

/// What you decided to buy, in the order you'd walk it.
///
/// Built to be used in a shop rather than admired at home: everything is
/// on-device, nothing here needs a network, and the primary gesture is one tap
/// to tick something off.
struct ShoppingListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent

    private var items: [ShoppingListItem] { appState.shoppingList.shoppingOrder }
    private var remaining: Int { appState.shoppingList.filter { !$0.isChecked }.count }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if appState.shoppingList.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        ForEach(items) { item in
                            row(item)
                            if item.id != items.last?.id { LedgerRule() }
                        }
                        actions
                    }
                    .padding(Theme.gutter)
                }
            }
        }
        .navigationTitle("Shopping list")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        Text(remaining == 0 ? "All ticked off" : "\(remaining) to get")
            .ledgerLabel()
            .padding(.bottom, 6)
    }

    private func row(_ item: ShoppingListItem) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { appState.toggleShoppingItem(item.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isChecked ? accent.color : Theme.inkFaint)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.isChecked ? Theme.inkMuted : Theme.ink)
                        .strikethrough(item.isChecked, color: Theme.inkFaint)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        if let quantity = item.quantityText {
                            Text(quantity)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.inkMuted)
                                Text("·").foregroundStyle(Theme.inkFaint)
                        }
                        Text("\(Int(item.per100g.calories.rounded())) kcal · P\(Int(item.per100g.proteinG.rounded())) per 100 g")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                Spacer(minLength: 8)

                Text("\(item.scoreValue)")
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(item.isChecked ? Theme.inkFaint : Theme.ink)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActionsCompat {
            Haptics.tap()
            withAnimation(.snappy) { appState.removeFromShoppingList(item.id) }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            LedgerRule().padding(.vertical, 10)

            HStack(spacing: 10) {
                ForEach(Retailer.allCases) { retailer in
                    RetailerButton(term: firstUnchecked?.searchTerm ?? "", retailer: retailer, prominent: false)
                        .disabled(firstUnchecked == nil)
                        .opacity(firstUnchecked == nil ? 0.4 : 1)
                }
            }
            // Says exactly what the button does. Neither retailer accepts a
            // multi-item list over a URL, so pretending the whole list goes
            // across would be a promise the hand-off can't keep.
            Text(firstUnchecked.map { "Opens a search for “\($0.searchTerm)” — the next thing on the list. Retailers only take one search term at a time." }
                 ?? "Nothing left to get.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                UIPasteboard.general.string = appState.shoppingList.plainText
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold))
                    Text("Copy the list").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(accent.color)
            }
            .buttonStyle(.plain)
            .disabled(remaining == 0)
            .opacity(remaining == 0 ? 0.4 : 1)

            if appState.shoppingList.contains(where: \.isChecked) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { appState.clearCheckedShoppingItems() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                        Text("Clear what's ticked").font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var firstUnchecked: ShoppingListItem? {
        items.first { !$0.isChecked }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing on the list yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Search for something, open it, and hit Add to list. It stays on this device and survives a relaunch — write it at home, tick it off in the shop.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.gutter)
    }
}

private extension View {
    /// Swipe-to-delete on a plain `Button` row.
    ///
    /// The list is a hand-built `VStack` rather than a `List` — `List` brings
    /// its own background, separators and insets that fight the ledger styling
    /// used on every other screen — so the standard row swipe isn't available
    /// and a long-press menu stands in.
    func swipeActionsCompat(_ delete: @escaping () -> Void) -> some View {
        contextMenu {
            Button(role: .destructive, action: delete) {
                Label("Remove from list", systemImage: "trash")
            }
        }
    }
}
