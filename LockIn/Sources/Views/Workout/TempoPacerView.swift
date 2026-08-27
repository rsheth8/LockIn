import SwiftUI
import Combine

/// An animated pacer for one rep's rhythm.
///
/// This is the honest thing an animation can teach without a camera in the gym:
/// *timing*. It doesn't pretend to show you a body — it shows you how long each
/// phase should take, which is the coaching point almost everyone gets wrong.
/// Most people spend under a second on the lowering phase of a squat when it
/// should be two or three, and that phase is where a large share of the strength
/// and nearly all of the tendon adaptation comes from.
///
/// Follow it with your eyes for a rep or two and your tempo fixes itself.
struct TempoPacerView: View {
    let tempo: MovementTempo
    /// The figure, when the movement is one a side-on drawing can show
    /// honestly. Driven by this same clock, so the rep on screen takes exactly
    /// as long as the tempo prescribes.
    var animation: MovementAnimation?
    @Environment(\.accent) private var accent

    /// Seconds into the current cycle.
    @State private var elapsed: Double = 0
    @State private var isRunning = true

    /// 20 Hz — smooth enough that the bar doesn't visibly step, cheap enough
    /// that it costs nothing while the sheet is open.
    private let step = 0.05
    private var timer: Timer.TimerPublisher { Timer.publish(every: step, on: .main, in: .common) }
    @State private var cancellable: Cancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tempo").ledgerLabel()
                Spacer()
                Text(tempo.summary)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }

            if let animation {
                StickFigureView(
                    pose: animation.pose(phase: phaseIndex, progress: phaseProgress),
                    platform: animation.platform,
                    showsFloor: animation.showsFloor,
                    accent: accent.color
                )
                .frame(height: 168)
                .frame(maxWidth: .infinity)

                Text(animation.viewNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentPhase?.label ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.identity)
                Spacer()
                Text(String(format: "%.1fs", remainingInPhase))
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(accent.color)
            }

            track

            HStack(spacing: 8) {
                ForEach(tempo.phases) { phase in
                    Text(phase.label)
                        .font(Theme.mono(9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(phase.id == currentPhase?.id ? Theme.ink : Theme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                Haptics.tap()
                isRunning.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isRunning ? "Pause" : "Play")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerCard()
        .onAppear(perform: start)
        .onDisappear { cancellable?.cancel() }
    }

    /// Phase blocks sized by duration, with a playhead sweeping across.
    private var track: some View {
        GeometryReader { geo in
            let total = max(tempo.totalSeconds, 0.01)
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(tempo.phases) { phase in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(phase.id == currentPhase?.id ? accent.color.opacity(0.28) : Theme.inkFaint)
                            .frame(width: max(0, geo.size.width * (phase.seconds / total)) - 2)
                    }
                }
                Capsule()
                    .fill(accent.color)
                    .frame(width: 3)
                    .offset(x: geo.size.width * (elapsed / total))
            }
        }
        .frame(height: 30)
    }

    // MARK: - Cycle

    private var currentPhase: MovementTempo.Phase? {
        tempo.phases.indices.contains(phaseIndex) ? tempo.phases[phaseIndex] : tempo.phases.last
    }

    /// Which phase the clock is in, and how far through it — the two numbers
    /// both the track and the figure are drawn from.
    private var phaseIndex: Int {
        var cursor = 0.0
        for (index, phase) in tempo.phases.enumerated() {
            cursor += phase.seconds
            if elapsed < cursor { return index }
        }
        return max(0, tempo.phases.count - 1)
    }

    private var phaseProgress: Double {
        var cursor = 0.0
        for phase in tempo.phases {
            if elapsed < cursor + phase.seconds {
                return phase.seconds > 0 ? (elapsed - cursor) / phase.seconds : 1
            }
            cursor += phase.seconds
        }
        return 1
    }

    private var remainingInPhase: Double {
        var cursor = 0.0
        for phase in tempo.phases {
            cursor += phase.seconds
            if elapsed < cursor { return max(0, cursor - elapsed) }
        }
        return 0
    }

    private func start() {
        cancellable = timer.autoconnect().sink { _ in
            guard isRunning else { return }
            let previous = currentPhase?.id
            elapsed += step
            if elapsed >= tempo.totalSeconds { elapsed = 0 }
            // A tick at each phase boundary makes the rhythm followable without
            // watching the screen — which is the point, since your eyes should
            // be on the bar.
            if currentPhase?.id != previous { Haptics.tap() }
        }
    }
}
