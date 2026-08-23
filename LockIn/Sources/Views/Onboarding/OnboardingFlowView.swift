import SwiftUI

/// First run sets the tone as much as it collects data. Full-bleed dark, one
/// question per screen, big monospaced numbers you dial in — it should feel
/// like being enrolled in something, not filling out a form.
struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var profile = UserProfile.default
    @State private var step = 0

    private let lastStep = 4

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                progressRail
                    .padding(.top, 12)
                    .padding(.bottom, 40)

                Group {
                    switch step {
                    case 0: introStep
                    case 1: bodyStep
                    case 2: goalStep
                    case 3: activityStep
                    default: trainingStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                primaryButton
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Chrome

    private var progressRail: some View {
        HStack(spacing: 4) {
            ForEach(0...lastStep, id: \.self) { index in
                Rectangle()
                    .fill(index <= step ? Theme.ink : Theme.inkFaint)
                    .frame(height: 2)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) {
                if step < lastStep { step += 1 } else { finish() }
            }
        } label: {
            Text(step < lastStep ? "Continue" : "Lock In")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.ink)
                .foregroundStyle(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Steps

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Wordmark(size: 42)
            Text("This app keeps the promises you make to yourself. It plans your day around your real schedule, tells you exactly what to eat and when, and calls you out when you drift.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every number it gives you comes from published research, not vibes.")
                .font(Theme.coach)
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
        }
    }

    private var bodyStep: some View {
        stepScaffold(label: "About you", title: "The baseline") {
            dial(label: "Age", value: "\(profile.age)", unit: "yrs",
                 decrement: { profile.age = max(13, profile.age - 1) },
                 increment: { profile.age = min(90, profile.age + 1) })
            LedgerRule()
            dial(label: "Height", value: "\(Int(profile.heightInches / 12))′\(Int(profile.heightInches) % 12)″", unit: "",
                 decrement: { profile.heightInches = max(48, profile.heightInches - 1) },
                 increment: { profile.heightInches = min(84, profile.heightInches + 1) })
            LedgerRule()
            HStack {
                Text("Sex").font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.vertical, 8)
        }
    }

    private var goalStep: some View {
        stepScaffold(label: "The target", title: "Where you're going") {
            dial(label: "Current", value: "\(Int(profile.currentWeightLbs))", unit: "lb",
                 decrement: { profile.currentWeightLbs = max(80, profile.currentWeightLbs - 1) },
                 increment: { profile.currentWeightLbs = min(400, profile.currentWeightLbs + 1) })
            LedgerRule()
            dial(label: "Goal", value: "\(Int(profile.goalWeightLbs))", unit: "lb",
                 decrement: { profile.goalWeightLbs = max(80, profile.goalWeightLbs - 1) },
                 increment: { profile.goalWeightLbs = min(400, profile.goalWeightLbs + 1) })

            let delta = Int(profile.currentWeightLbs - profile.goalWeightLbs)
            if delta > 0 {
                Text("\(delta) lb to lose. At a sustainable deficit that's real work, not a month.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 12)
            }
        }
    }

    private var activityStep: some View {
        stepScaffold(label: "Baseline output", title: "How much you move") {
            ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { LedgerRule() }
                selectRow(
                    title: activityTitle(level),
                    subtitle: activityBlurb(level),
                    isSelected: profile.activityLevel == level
                ) { profile.activityLevel = level }
            }
        }
    }

    private var trainingStep: some View {
        stepScaffold(label: "Beyond fat loss", title: "What you're training for") {
            ForEach(Array(FitnessGoal.allCases.filter { $0 != .fatLoss }.enumerated()), id: \.element) { index, goal in
                if index > 0 { LedgerRule() }
                selectRow(
                    title: goal.displayName,
                    subtitle: goalBlurb(goal),
                    isSelected: profile.fitnessGoals.contains(goal)
                ) {
                    if profile.fitnessGoals.contains(goal) {
                        profile.fitnessGoals.remove(goal)
                    } else {
                        profile.fitnessGoals.insert(goal)
                    }
                }
            }
            Text("Fat loss is always on. These add sport-specific sessions to the split.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 12)
        }
    }

    // MARK: - Building blocks

    private func stepScaffold<Content: View>(label: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).ledgerLabel()
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 0, content: content)
        }
    }

    /// Big monospaced value with tap targets either side — faster than a Stepper
    /// and it makes the number feel like an instrument reading.
    private func dial(label: String, value: String, unit: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Button { Haptics.tap(); decrement() } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkMuted).frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.mono(26, weight: .semibold)).foregroundStyle(Theme.ink)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                }
            }
            .frame(minWidth: 92)
            Button { Haptics.tap(); increment() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkMuted).frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }

    private func selectRow(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkFaint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy

    private func activityTitle(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return "Sedentary"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    private func activityBlurb(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return "Desk and lectures, little walking"
        case .lightlyActive: return "Some walking, 1–3 sessions a week"
        case .moderatelyActive: return "On your feet daily, 3–5 sessions"
        case .veryActive: return "Training most days, physical job or sport"
        }
    }

    private func goalBlurb(_ goal: FitnessGoal) -> String {
        switch goal {
        case .fastBowling: return "Rotational power, sprint work, lumbar protection"
        case .hikingBackpacking: return "Loaded rucking, unilateral legs, descent control"
        case .fatLoss: return ""
        }
    }

    private func finish() {
        profile.fitnessGoals.insert(.fatLoss)
        profile.weightHistory = [WeightEntry(date: Date(), weightLbs: profile.currentWeightLbs)]
        appState.saveProfile(profile)
        Haptics.milestone()
        Task { _ = await NotificationManager.shared.requestAuthorization() }
    }
}
