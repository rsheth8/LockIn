#if DEBUG
import SwiftUI

/// Bottom card that walks through every screen while "Watch the demo" is
/// running. Advancing a step also flips `DashboardView`'s tab via
/// `AppState.demoTabRequest`, so the tour narrates whatever's on screen
/// instead of describing a tab the user hasn't seen yet.
struct DemoTourOverlay: View {
    @EnvironmentObject var appState: AppState
    // Held as its own @ObservedObject (rather than reached via tour
    // inline) so this view actually re-renders when the step index changes —
    // demoTour is a plain `let` on AppState, so its own publishes wouldn't
    // otherwise propagate through appState's EnvironmentObject.
    @ObservedObject var tour: DemoTourController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DEMO · STEP \(tour.stepIndex + 1) OF \(tour.steps.count)")
                    .ledgerLabel()
                Spacer()
                Button {
                    Haptics.tap()
                    appState.exitDemo()
                } label: {
                    Text("Exit demo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.signal)
                }
                .buttonStyle(.plain)
            }

            Text(tour.current.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(tour.current.body)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(tour.steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == tour.stepIndex ? Theme.ink : Theme.inkFaint)
                        .frame(width: index == tour.stepIndex ? 18 : 6, height: 6)
                }
            }
            .padding(.top, 2)

            HStack(spacing: 10) {
                if !tour.isFirst {
                    Button {
                        Haptics.tap()
                        tour.back()
                        goToCurrentTab()
                    } label: {
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Haptics.tap()
                    if tour.isLast {
                        appState.exitDemo()
                    } else {
                        tour.advance()
                        goToCurrentTab()
                    }
                } label: {
                    Text(tour.isLast ? "Finish" : "Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 78) // clears the tab bar
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private func goToCurrentTab() {
        guard let tab = tour.current.tab else { return }
        appState.demoTabRequest = tab
    }
}
#endif
