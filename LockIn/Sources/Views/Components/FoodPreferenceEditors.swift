import SwiftUI

/// Wrapping chip row used by the quiz and Settings. iOS 16+ `Layout` so we
/// don't have to guess line breaks.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.origins.count else { continue }
            subview.place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var origins: [CGPoint] = []
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if maxWidth.isFinite, origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(origin)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, origin.x - spacing)
            maxY = max(maxY, origin.y + size.height)
        }
        return (origins, CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: maxY))
    }
}

struct IngredientChip: View {
    let title: String
    var selected: Bool
    var muted: Bool = false
    let accent: AppAccent
    /// Whole-chip tap when `secondaryAction` is nil (the delete-only chips:
    /// favourites, dislikes, allergies, and unselected suggestions). When
    /// `secondaryAction` is set, this becomes the label's own tap target
    /// instead — e.g. pantry's "mark running low" toggle — so it stops
    /// double-booking as delete.
    let action: () -> Void
    /// If set, splits the chip into two tap targets: the label calls
    /// `action`, the trailing icon calls this. Only takes effect while
    /// `selected` is true, since that's the only state the icon renders in.
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        if selected, let secondaryAction {
            HStack(spacing: 6) {
                Button(action: action) {
                    Text(title).font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                Button(action: secondaryAction) {
                    Image(systemName: muted ? "exclamationmark" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .modifier(ChipBackground(selected: selected, muted: muted, accent: accent))
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if selected {
                        Image(systemName: muted ? "exclamationmark" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .modifier(ChipBackground(selected: selected, muted: muted, accent: accent))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ChipBackground: ViewModifier {
    let selected: Bool
    let muted: Bool
    let accent: AppAccent

    func body(content: Content) -> some View {
        content
            .foregroundStyle(selected ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(selected ? accent.color.opacity(muted ? 0.18 : 0.22) : Theme.surfaceMuted)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(selected ? accent.color.opacity(0.55) : Theme.rule, lineWidth: 1)
            )
    }
}

/// Free-text chips plus tap-to-add suggestions. Used for favourites, dislikes,
/// and intolerances — the three lists that make a meal plan feel like yours.
struct IngredientChipEditor: View {
    let placeholder: String
    var suggestions: [String] = []
    @Binding var items: [String]
    let accent: AppAccent

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(placeholder, text: $draft)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { addDraft() }
                Button("Add") { addDraft() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canAdd ? accent.color : Theme.inkFaint)
                    .disabled(!canAdd)
            }
            .padding(.vertical, 8)
            LedgerRule()

            if !items.isEmpty {
                ChipFlow {
                    ForEach(items, id: \.self) { item in
                        IngredientChip(title: item, selected: true, accent: accent) {
                            Haptics.tap()
                            items.removeAll { $0.caseInsensitiveCompare(item) == .orderedSame }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !unusedSuggestions.isEmpty {
                ChipFlow {
                    ForEach(unusedSuggestions, id: \.self) { item in
                        IngredientChip(title: item, selected: false, accent: accent) {
                            Haptics.tap()
                            add(item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unusedSuggestions: [String] {
        suggestions.reduced().filter { suggestion in
            !items.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }

    private func addDraft() {
        add(draft)
        draft = ""
    }

    private func add(_ raw: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard !items.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) else { return }
        items.append(cleaned)
    }
}

struct PantryEditor: View {
    @Binding var pantry: [PantryItem]
    var suggestions: [String] = []
    let accent: AppAccent

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("What's in the kitchen?", text: $draft)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { addDraft() }
                Button("Add") { addDraft() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canAdd ? accent.color : Theme.inkFaint)
                    .disabled(!canAdd)
            }
            .padding(.vertical, 8)
            LedgerRule()

            if !pantry.isEmpty {
                ChipFlow {
                    ForEach(pantry) { item in
                        IngredientChip(
                            title: item.name, selected: true, muted: item.isRunningOut, accent: accent,
                            action: {
                                Haptics.tap()
                                toggleRunningOut(item)
                            },
                            secondaryAction: {
                                Haptics.tap()
                                pantry.removeAll { $0.id == item.id }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Tap an item to mark it running low — tap again to clear that. Tap the small icon to remove it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
            }

            if !unusedSuggestions.isEmpty {
                ChipFlow {
                    ForEach(unusedSuggestions, id: \.self) { name in
                        IngredientChip(title: name, selected: false, accent: accent) {
                            Haptics.tap()
                            add(name)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var canAdd: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unusedSuggestions: [String] {
        suggestions.reduced().filter { suggestion in
            !pantry.contains { $0.name.caseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }

    private func addDraft() {
        add(draft)
        draft = ""
    }

    private func add(_ raw: String) {
        let item = PantryItem(name: raw)
        guard !item.name.isEmpty else { return }
        guard !pantry.contains(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) else { return }
        pantry.append(item)
    }

    private func toggleRunningOut(_ item: PantryItem) {
        guard let index = pantry.firstIndex(where: { $0.id == item.id }) else { return }
        pantry[index].isRunningOut.toggle()
    }
}
