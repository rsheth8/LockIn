import SwiftUI
import UIKit

/// The workout portal: the session run one set at a time, with the load you
/// lifted recorded and the rest clock handled for you.
///
/// Design intent — this is the one screen in the app you use *while moving*, so
/// it breaks the Ledger's density rules on purpose. One decision on screen at a
/// time, a primary target big enough to hit with chalky hands without looking,
/// and every number readable from arm's length on a bench. The weight and rep
/// fields come pre-filled with what you should be lifting, so a straight-sets
/// exercise costs one tap per set and only a miss costs two.
struct WorkoutPortalView: View {
    @StateObject private var runner: WorkoutRunner
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss

    /// Called when the session is closed out, with the permanent record.
    /// The caller decides what that means for the promise.
    let onComplete: (CompletedWorkout) -> Void
    /// Called on every state change so a resume point can be persisted.
    let onProgress: (WorkoutProgress) -> Void

    @State private var showingQuitConfirm = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: WorkoutSession, eventID: UUID, dayKey: String,
         history: [CompletedWorkout] = [],
         resuming: WorkoutProgress? = nil,
         onProgress: @escaping (WorkoutProgress) -> Void,
         onComplete: @escaping (CompletedWorkout) -> Void) {
        _runner = StateObject(wrappedValue: WorkoutRunner(
            session: session, eventID: eventID, dayKey: dayKey,
            history: history, resuming: resuming
        ))
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressBar
                if runner.isFinished {
                    finishedBody
                } else {
                    activeBody
                }
            }
        }
        .onAppear {
            runner.onProgress = onProgress
            // The phone must not lock between sets — the rest clock is the
            // whole point, and re-unlocking mid-set is exactly the friction
            // that sends people back to a notes app.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(tick) { _ in runner.tick() }
        // Rest ending is the one thing you'll miss if you're not looking at the
        // screen, so it gets a haptic rather than only a visual change.
        .onChange(of: runner.phase) { previous, current in
            if previous == .resting && current == .working { Haptics.milestone() }
        }
        .confirmationDialog("Leave the workout?", isPresented: $showingQuitConfirm, titleVisibility: .visible) {
            Button("Save and leave") { dismiss() }
            Button("Finish here", role: .destructive) { complete() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("\(runner.setsDone) of \(runner.totalSets) sets banked. Leaving keeps your place — you can pick it back up today.")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                if runner.setsDone == 0 { dismiss() } else { showingQuitConfirm = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(runner.session.focus.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(runner.setsDone)/\(runner.totalSets) sets").ledgerLabel()
            }

            Spacer()

            Text(runner.elapsedSeconds.asClock)
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(runner.isPaused ? Theme.inkFaint : Theme.inkMuted)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.rule)
                Rectangle()
                    .fill(accent.color)
                    .frame(width: geo.size.width * runner.fraction)
                    .animation(.snappy, value: runner.fraction)
            }
        }
        .frame(height: 2)
    }

    // MARK: - Active session

    private var activeBody: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    currentExerciseCard
                    upNext
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            controls
        }
    }

    @ViewBuilder
    private var currentExerciseCard: some View {
        if let exercise = runner.currentExercise {
            VStack(alignment: .leading, spacing: 0) {
                Text("Exercise \(runner.exerciseIndex + 1) of \(runner.session.exercises.count)")
                    .ledgerLabel()

                Text(exercise.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text("\(exercise.sets) × \(exercise.reps)")
                    .font(Theme.mono(17, weight: .semibold))
                    .foregroundStyle(accent.color)
                    .padding(.top, 6)

                if let note = exercise.note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                setPips(for: exercise).padding(.top, 16)

                if !runner.currentSets.isEmpty {
                    Text("This session: \(runner.currentSets.map(\.shortLine).joined(separator: ", "))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 10)
                }

                if exercise.tracksLoad {
                    Divider().overlay(Theme.rule).padding(.vertical, 14)
                    progressionBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .ledgerCard()
        }
    }

    /// Where the coaching lives: what you did last time, and what that earns you
    /// today. Kept inside the exercise card so the number in the weight field is
    /// never separated from the reason for it.
    private var progressionBlock: some View {
        let advice = runner.suggestion
        return VStack(alignment: .leading, spacing: 8) {
            if let last = runner.lastPerformance {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Last time").ledgerLabel()
                    Text(last.summaryLine)
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: adviceIcon(advice.kind))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(adviceColor(advice.kind))
                Text(advice.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(adviceColor(advice.kind))
            }

            if !advice.reason.isEmpty {
                Text(advice.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func adviceIcon(_ kind: ProgressionSuggestion.Kind) -> String {
        switch kind {
        case .increase: return "arrow.up.circle.fill"
        case .deload: return "arrow.down.circle.fill"
        case .hold: return "equal.circle"
        case .baseline: return "target"
        case .untracked: return "checkmark.circle"
        }
    }

    private func adviceColor(_ kind: ProgressionSuggestion.Kind) -> Color {
        switch kind {
        case .increase: return accent.color
        case .deload: return Theme.signal
        case .hold, .baseline, .untracked: return Theme.ink
        }
    }

    /// One pip per prescribed set — the session's shape at a glance, and the
    /// only place your progress on *this* exercise is visible while resting.
    private func setPips(for exercise: ExercisePrescription) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<exercise.sets, id: \.self) { index in
                Capsule()
                    .fill(index < runner.currentSetsDone ? accent.color : Theme.inkFaint)
                    .frame(height: 6)
            }
        }
    }

    /// The rest of the session, jumpable — a taken squat rack shouldn't derail
    /// the whole workout.
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The session").ledgerLabel().padding(.bottom, 6)
            ForEach(Array(runner.session.exercises.enumerated()), id: \.element.id) { index, exercise in
                Button {
                    Haptics.tap()
                    runner.jump(to: index)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: runner.isComplete(exerciseAt: index)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(runner.isComplete(exerciseAt: index) ? Theme.kept : Theme.inkFaint)
                        Text(exercise.name)
                            .font(.system(size: 14, weight: index == runner.exerciseIndex ? .semibold : .regular))
                            .foregroundStyle(index == runner.exerciseIndex ? Theme.ink : Theme.inkMuted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(runner.setsDone(forExerciseAt: index))/\(exercise.sets)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(runner.session.equipmentNote)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 8)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            LedgerRule()
            if runner.phase == .resting {
                restControls
            } else {
                workControls
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
    }

    private var workControls: some View {
        VStack(spacing: 10) {
            if runner.currentExercise?.tracksLoad == true {
                HStack(spacing: 10) {
                    // 5 lb is the smallest plate pair on most racks and the
                    // standard dumbbell step; 2.5 lb micro-jumps are reachable
                    // by typing rather than by two extra taps per set.
                    numberField(label: "LB",
                                value: runner.entryWeightLbs.map { SetEntry.trim($0) } ?? "—",
                                onMinus: { runner.adjustWeight(by: -5) },
                                onPlus: { runner.adjustWeight(by: 5) })
                    numberField(label: "REPS",
                                value: runner.entryReps.map(String.init) ?? "—",
                                onMinus: { runner.adjustReps(by: -1) },
                                onPlus: { runner.adjustReps(by: 1) })
                }
            }

            Button {
                Haptics.confirm()
                runner.completeSet()
            } label: {
                Text(runner.setLabel + " done")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                secondary(runner.currentSetsDone > 0 ? "Undo set" : "Undo",
                          systemImage: "arrow.uturn.backward",
                          enabled: runner.currentSetsDone > 0) {
                    runner.undoSet()
                }
                secondary("Finish", systemImage: "flag.checkered") {
                    runner.finish()
                }
            }
        }
        .padding(.top, 4)
    }

    /// Stepper with a big centred readout. Deliberately −/+ rather than a
    /// keyboard: entering 135 on a numeric pad between sets means looking at the
    /// phone, and the value is nearly always the prefilled one or one step off.
    private func numberField(label: String, value: String,
                             onMinus: @escaping () -> Void,
                             onPlus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", action: onMinus)
            VStack(spacing: 1) {
                Text(value)
                    .font(Theme.mono(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(Theme.mono(8, weight: .semibold))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", action: onPlus)
        }
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var restControls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(runner.isPaused ? "Paused" : "Rest").ledgerLabel()
                Text(runner.restRemaining.asClock)
                    .font(Theme.mono(40, weight: .semibold))
                    .foregroundStyle(runner.isPaused ? Theme.inkMuted : accent.color)
                    .monospacedDigit()
                Spacer()
                Text("Next: \(runner.setLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.top, 4)

            HStack(spacing: 10) {
                secondary("+30s", systemImage: "plus") { runner.addRest(30) }
                secondary(runner.isPaused ? "Resume" : "Pause",
                          systemImage: runner.isPaused ? "play.fill" : "pause.fill") {
                    runner.togglePause()
                }
                Button {
                    Haptics.tap()
                    runner.skipRest()
                } label: {
                    Text("Skip rest")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func secondary(_ title: String, systemImage: String, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(enabled ? Theme.inkMuted : Theme.inkFaint)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Finished

    private var finishedBody: some View {
        let record = runner.completedWorkout()
        let improved = runner.improvements()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(runner.setsDone >= runner.totalSets ? "Session complete" : "Called it")
                    .font(Theme.hero)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 30)

                Text("\(runner.setsDone) of \(runner.totalSets) sets · \(runner.elapsedSeconds / 60) min")
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 8)

                if !improved.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accent.color)
                            .padding(.top, 1)
                        Text("Up on last time: \(improved.joined(separator: ", "))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(accent.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 16)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(runner.session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        let sets = runner.loggedSets[index]
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(exercise.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(sets.isEmpty ? Theme.inkMuted : Theme.ink)
                                Spacer(minLength: 8)
                                Text("\(sets.count)/\(exercise.sets)")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(runner.isComplete(exerciseAt: index) ? Theme.kept : Theme.inkMuted)
                            }
                            if !sets.isEmpty {
                                Text(sets.map(\.shortLine).joined(separator: ", "))
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
                .padding(.top, 22)

                Button(action: complete) {
                    Text(record.exercises.isEmpty ? "Close" : "Log it")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 19)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    private func complete() {
        Haptics.milestone()
        onComplete(runner.completedWorkout())
        dismiss()
    }
}
