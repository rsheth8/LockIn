import SwiftUI
import UIKit

/// The workout portal: the session run one set at a time, with the rest clock
/// handled for you.
///
/// Design intent — this is the one screen in the app you use *while moving*, so
/// it breaks the Ledger's density rules on purpose. One decision on screen at a
/// time, a primary target big enough to hit with chalky hands without looking,
/// and every number readable from arm's length on a bench.
struct WorkoutPortalView: View {
    @StateObject private var runner: WorkoutRunner
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss

    /// Called when the session is closed out, with the minutes actually trained.
    /// The caller decides what that means for the promise.
    let onComplete: (Int) -> Void
    /// Called on every state change so a resume point can be persisted.
    let onProgress: (WorkoutProgress) -> Void

    @State private var showingQuitConfirm = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: WorkoutSession, eventID: UUID, dayKey: String,
         resuming: WorkoutProgress? = nil,
         onProgress: @escaping (WorkoutProgress) -> Void,
         onComplete: @escaping (Int) -> Void) {
        _runner = StateObject(wrappedValue: WorkoutRunner(
            session: session, eventID: eventID, dayKey: dayKey, resuming: resuming
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
                .padding(.top, 24)
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
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text("\(exercise.sets) × \(exercise.reps)")
                    .font(Theme.mono(17, weight: .semibold))
                    .foregroundStyle(accent.color)
                    .padding(.top, 6)

                if let note = exercise.note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }

                setPips(for: exercise).padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .ledgerCard()
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
                        Text("\(runner.completedSets[index])/\(exercise.sets)")
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
        VStack(spacing: 12) {
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
            Button {
                Haptics.confirm()
                runner.completeSet()
            } label: {
                Text(runner.setLabel + " done")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
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
            .padding(.vertical, 16)
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
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(runner.setsDone >= runner.totalSets ? "Session complete" : "Called it")
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)

            Text("\(runner.setsDone) of \(runner.totalSets) sets · \(runner.elapsedSeconds / 60) min")
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(runner.session.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack {
                        Text(exercise.name)
                            .font(.system(size: 14))
                            .foregroundStyle(runner.isComplete(exerciseAt: index) ? Theme.ink : Theme.inkMuted)
                        Spacer(minLength: 8)
                        Text("\(runner.completedSets[index])/\(exercise.sets)")
                            .font(Theme.mono(12))
                            .foregroundStyle(runner.isComplete(exerciseAt: index) ? Theme.kept : Theme.inkMuted)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 0)

            Button(action: complete) {
                Text("Log it")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func complete() {
        Haptics.milestone()
        onComplete(max(1, runner.elapsedSeconds / 60))
        dismiss()
    }
}
