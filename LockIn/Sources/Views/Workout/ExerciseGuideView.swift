import SwiftUI

/// How to perform a movement, reached from the portal when you're stood there
/// unsure what the words mean.
///
/// Ordered the way you need it in the moment: set up, do the rep, what to think
/// about, what usually goes wrong. Cues before mistakes on purpose — you want
/// the thing to *do* before the thing to avoid.
struct ExerciseGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accent) private var accent

    let exerciseName: String
    /// Sets and reps, shown so the guide stands on its own.
    let prescription: String?
    let guide: ExerciseGuide?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    if let guide {
                        VStack(alignment: .leading, spacing: 26) {
                            if let prescription {
                                Text(prescription)
                                    .font(Theme.mono(15, weight: .semibold))
                                    .foregroundStyle(accent.color)
                            }
                            if let tempo = guide.tempo {
                                TempoPacerView(
                                    tempo: tempo,
                                    animation: MovementAnimationLibrary.animation(for: exerciseName)
                                )
                            }
                            steps("Set up", guide.setup, numbered: true)
                            steps("The rep", guide.execution, numbered: true)
                            cueChips(guide.cues)
                            steps("What goes wrong", guide.mistakes, numbered: false, marker: "exclamationmark")
                            swapBlock(guide.swap)
                            videoLink(guide.searchTerm)
                        }
                        .padding(Theme.gutter)
                        .padding(.bottom, 20)
                    } else {
                        missing
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    // MARK: - Sections

    private func steps(_ title: String, _ items: [String], numbered: Bool,
                       marker: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).ledgerLabel()
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    if let marker {
                        Image(systemName: marker)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.signal)
                            .frame(width: 18, alignment: .leading)
                            .padding(.top, 3)
                    } else if numbered {
                        Text("\(index + 1)")
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(width: 18, alignment: .leading)
                            .padding(.top, 2)
                    }
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The two or three words you actually repeat to yourself mid-set. Given
    /// their own treatment because full sentences don't survive a heavy rep.
    private func cueChips(_ cues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Think about").ledgerLabel()
            FlowLayout(spacing: 8) {
                ForEach(cues, id: \.self) { cue in
                    Text(cue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceMuted)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
                }
            }
        }
    }

    private func swapBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Can't do it?").ledgerLabel()
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Opens a YouTube *search*, not a specific video — nothing here is curated
    /// or endorsed, and saying so beats implying we picked it.
    private func videoLink(_ term: String) -> some View {
        Button {
            Haptics.tap()
            let query = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            if let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Search video demos")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Opens YouTube results for “\(term)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No guide for this one yet.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Every exercise in your plan should have one — if you're seeing this, it's a gap on our side, not yours.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.gutter)
    }
}

/// Wrapping row of chips. `HStack` would push the last cue off the screen and
/// `LazyVGrid` would force equal columns onto text of very different lengths.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
