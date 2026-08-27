import SwiftUI

/// Weekly weigh-in entry.
///
/// Deliberately one number and one button. The weigh-in is a 20-second job done
/// half-awake on a bathroom floor; anything that needs reading is a reason to
/// skip it, and a skipped weigh-in costs a whole week of trend data.
struct LogWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    let currentWeightLbs: Double
    let goalWeightLbs: Double
    /// Weight at the previous entry, for the "since last week" line. Nil on the
    /// first ever weigh-in.
    let previousWeightLbs: Double?
    let onSave: (Double) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(currentWeightLbs: Double, goalWeightLbs: Double, previousWeightLbs: Double?,
         onSave: @escaping (Double) -> Void) {
        self.currentWeightLbs = currentWeightLbs
        self.goalWeightLbs = goalWeightLbs
        self.previousWeightLbs = previousWeightLbs
        self.onSave = onSave
        // Pre-filled with the last known weight: most weeks the change is under
        // two pounds, so the fastest correct entry is a nudge, not a retype.
        _text = State(initialValue: String(format: "%.1f", currentWeightLbs))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 26) {
                    Text("Same time, same conditions — first thing, after the bathroom, before you eat.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    dial
                    delta

                    Spacer(minLength: 0)

                    Button(action: save) {
                        Text("Save weigh-in")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(parsed == nil ? Theme.inkFaint : Theme.ink)
                            .foregroundStyle(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(parsed == nil)
                }
                .padding(Theme.gutter)
            }
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .onAppear { focused = true }
    }

    private var dial: some View {
        HStack(spacing: 14) {
            stepButton("minus") { adjust(-0.2) }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("", text: $text)
                    .font(Theme.mono(44, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .frame(maxWidth: .infinity)
                Text("lb")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
            }

            stepButton("plus") { adjust(0.2) }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .ledgerCard()
    }

    @ViewBuilder
    private var delta: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let previous = previousWeightLbs, let value = parsed {
                let change = value - previous
                let direction = change == 0 ? "level with" : (change < 0 ? "down from" : "up from")
                Text("\(abs(change), specifier: "%.1f") lb \(direction) \(previous, specifier: "%.1f")")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text("Goal \(Int(goalWeightLbs)) lb")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The typed value, if it's a number in a range a human could actually be.
    /// Rejecting nonsense here is what keeps a fat-fingered "1980" out of the
    /// weight trend, where it would flatten the chart for months.
    private var parsed: Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)),
              (50...700).contains(value) else { return nil }
        return value
    }

    private func adjust(_ by: Double) {
        let base = parsed ?? currentWeightLbs
        text = String(format: "%.1f", base + by)
    }

    private func save() {
        guard let value = parsed else { return }
        Haptics.confirm()
        onSave(value)
        dismiss()
    }
}
