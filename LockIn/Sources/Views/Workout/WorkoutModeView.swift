import SwiftUI

/// Full-screen active session: one exercise at a time, a real rest timer
/// between sets, and a tap-through guide for anyone who doesn't already know
/// the movement. This is "Workout Mode" — started from today's workout event
/// and, unlike the rest of the app's Done/Skip pattern, stays in front of you
/// for the whole session rather than asking you to remember to come back.
struct WorkoutModeView: View {
    @StateObject private var controller: WorkoutModeController
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss
    @State private var showingGuide = false
    @State private var confirmingExit = false

    /// Called once, when the person finishes or explicitly ends the session
    /// with real progress — lets the caller confirm today's workout event
    /// through the normal streak/adherence path rather than duplicating it.
    let onFinish: () -> Void

    init(session: WorkoutSession, onFinish: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: WorkoutModeController(session: session))
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if controller.phase == .finished {
                WorkoutCompleteView(controller: controller) {
                    onFinish()
                    dismiss()
                }
            } else {
                activeSession
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            controller.startTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            controller.stopTimer()
        }
        .confirmationDialog("End this session?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Mark workout done") {
                onFinish()
                dismiss()
            }
            Button("Leave without credit", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) { }
        } message: {
            Text("\(controller.completedSets) set\(controller.completedSets == 1 ? "" : "s") logged so far.")
        }
        .sheet(isPresented: $showingGuide) {
            ExerciseGuideSheet(exercise: controller.currentExercise)
        }
    }

    private var activeSession: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.top, 8)
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    exerciseCard
                    if controller.phase == .resting {
                        restTimer
                    }
                }
            }

            Spacer(minLength: 12)
            controls
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 24)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    Haptics.tap()
                    // Never credit a workout on the way out without being told
                    // to. This used to confirm the day's workout whenever the
                    // screen had been open for 20 seconds, so opening Workout
                    // Mode, doing nothing, and closing it kept the streak
                    // alive — the one thing an accountability app must not do.
                    if controller.hasCreditableWork {
                        confirmingExit = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(elapsedLabel)
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)

                Spacer()

                Button {
                    Haptics.tap()
                    controller.isPaused.toggle()
                } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkFaint).frame(height: 3)
                    Capsule().fill(accent.color)
                        .frame(width: geo.size.width * controller.progress, height: 3)
                }
            }
            .frame(height: 3)

            HStack {
                Text("EXERCISE \(controller.exerciseIndex + 1) OF \(controller.totalExercises)")
                    .ledgerLabel()
                Spacer()
                Text(controller.session.focus.title)
                    .ledgerLabel()
            }
        }
    }

    private var elapsedLabel: String {
        let m = controller.elapsedSeconds / 60
        let s = controller.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Exercise card

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(controller.currentExercise.name)
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let guide = ExerciseLibrary.guide(for: controller.currentExercise.name) {
                // Full width rather than a square thumbnail: the clips are
                // drawn at one shared figure scale, so a wide panel is what
                // lets the horizontal ones (plank, dead bug, push-up) run at
                // the same size as a squat instead of shrinking to fit a box.
                StickFigureAnimator(pattern: guide.pattern,
                                    isPaused: controller.isPaused,
                                    speed: guide.demoSpeed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                statPair(label: "SET", value: "\(controller.setNumber) / \(controller.currentExercise.sets)")
                statPair(label: "TARGET", value: controller.currentExercise.reps)
            }

            if let note = controller.currentExercise.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                showingGuide = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                    Text("How to do this")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.color)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerCard()
    }

    private func statPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ledgerLabel()
            Text(value)
                .font(Theme.mono(22, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Rest timer

    private var restTimer: some View {
        VStack(spacing: 14) {
            Text("REST").ledgerLabel().foregroundStyle(Theme.signal)
            Text(restLabel)
                .font(.system(size: 56, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: controller.restSecondsRemaining)
            Button {
                Haptics.tap()
                controller.skipRest()
            } label: {
                Text("Skip Rest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var restLabel: String {
        let m = controller.restSecondsRemaining / 60
        let s = controller.restSecondsRemaining % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)"
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.confirm()
                withAnimation(.snappy) { controller.completeSet() }
            } label: {
                Text(controller.phase == .resting ? "Resting…" : primaryLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(controller.phase == .resting ? Theme.inkFaint : Theme.ink)
                    .foregroundStyle(controller.phase == .resting ? Theme.inkMuted : Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(controller.phase == .resting)

            Button {
                Haptics.tap()
                withAnimation(.snappy) { controller.skipExercise() }
            } label: {
                Text(controller.isLastExercise ? "Finish workout" : "Skip this exercise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryLabel: String {
        let isFinalSet = controller.setNumber >= controller.currentExercise.sets
        if isFinalSet && controller.isLastExercise { return "Finish Set — Done" }
        return isFinalSet ? "Set Complete — Next Exercise" : "Set Complete"
    }
}

// MARK: - Exercise guide sheet

private struct ExerciseGuideSheet: View {
    let exercise: ExercisePrescription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let guide = ExerciseLibrary.guide(for: exercise.name) {
                        StickFigureAnimator(pattern: guide.pattern, speed: guide.demoSpeed)
                            .frame(maxWidth: .infinity)
                            .frame(height: 230)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HOW TO").ledgerLabel()
                            ForEach(Array(guide.cues.enumerated()), id: \.offset) { index, cue in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(Theme.mono(12, weight: .semibold))
                                        .foregroundStyle(Theme.inkMuted)
                                        .frame(width: 18, alignment: .leading)
                                    Text(cue)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WATCH FOR").ledgerLabel().foregroundStyle(Theme.signal)
                            HStack(alignment: .top, spacing: 10) {
                                Rectangle().fill(Theme.signal).frame(width: 2)
                                Text(guide.watchFor)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text("No cue sheet yet for this one — go by feel and keep the target reps honest.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ground)
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Completion

private struct WorkoutCompleteView: View {
    @ObservedObject var controller: WorkoutModeController
    @Environment(\.accent) private var accent
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46))
                .foregroundStyle(accent.color)
            Text("Workout Complete")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("\(controller.totalExercises) exercises · \(elapsedLabel)")
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.ink)
                    .foregroundStyle(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.gutter)
        .padding(.bottom, 12)
    }

    private var elapsedLabel: String {
        let m = controller.elapsedSeconds / 60
        let s = controller.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
