import SwiftUI

/// Branching setup quiz. Replaces the old fixed five-screen flow, which
/// hard-assumed one person's situation (male, vegetarian, cutting, cricket).
/// Each answer narrows the next question, and the final screen shows the
/// computed targets *with* their safety advisories before anything is saved —
/// nobody should be handed a calorie number without seeing how it was derived.
struct QuizFlowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent

    @State private var profile = UserProfile.blank
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, name, body, direction, targetWeight, activity, diet, cuisine, equipment, sport, meals, tone, review

        /// Steps that don't apply to every path get skipped rather than shown
        /// with a "not applicable" state.
        static func next(after step: Step, profile: UserProfile) -> Step {
            var candidate = Step(rawValue: step.rawValue + 1) ?? .review
            while !candidate.applies(to: profile), candidate != .review {
                candidate = Step(rawValue: candidate.rawValue + 1) ?? .review
            }
            return candidate
        }

        static func previous(before step: Step, profile: UserProfile) -> Step {
            var candidate = Step(rawValue: step.rawValue - 1) ?? .welcome
            while !candidate.applies(to: profile), candidate != .welcome {
                candidate = Step(rawValue: candidate.rawValue - 1) ?? .welcome
            }
            return candidate
        }

        func applies(to profile: UserProfile) -> Bool {
            switch self {
            // Maintaining doesn't need a target weight.
            case .targetWeight: return profile.goalDirection != .maintain
            default: return true
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 10)
                    .padding(.bottom, 32)

                ScrollView(showsIndicators: false) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                primaryButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { step = Step.previous(before: step, profile: profile) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkFaint).frame(height: 3)
                    Capsule().fill(accent.color)
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(height: 20)
    }

    private var progress: Double {
        Double(step.rawValue) / Double(Step.review.rawValue)
    }

    private var primaryButton: some View {
        Button {
            Haptics.tap()
            if step == .review {
                finish()
            } else {
                withAnimation(.snappy) { step = Step.next(after: step, profile: profile) }
            }
        } label: {
            Text(step == .review ? "Start" : (step == .welcome ? "Begin" : "Continue"))
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.ink)
                .foregroundStyle(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(step == .name && profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(step == .name && profile.name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .name: nameStep
        case .body: bodyStep
        case .direction: directionStep
        case .targetWeight: targetWeightStep
        case .activity: activityStep
        case .diet: dietStep
        case .cuisine: cuisineStep
        case .equipment: equipmentStep
        case .sport: sportStep
        case .meals: mealsStep
        case .tone: toneStep
        case .review: reviewStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Wordmark(size: 42)
            Text("A few questions to build your plan. Everything after this — what to eat, when to train, when to sleep — comes out of your answers and published research, not a template.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Takes about a minute.")
                .font(Theme.coach)
                .foregroundStyle(Theme.ink)

            Button {
                Haptics.tap()
                profile = UserProfile.rahilPreset
                withAnimation(.snappy) { step = .review }
            } label: {
                Text("Use Rahil's preset instead")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent.color)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private var nameStep: some View {
        QuizStep(label: "First things first", title: "What should I call you?") {
            TextField("Your name", text: $profile.name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .padding(.vertical, 14)
            LedgerRule()
            Text("Used when the app talks to you. Nothing leaves your device.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 10)
        }
    }

    private var bodyStep: some View {
        QuizStep(label: "The baseline", title: "Your numbers") {
            QuizDial(label: "Age", value: "\(profile.age)", unit: "yrs",
                     decrement: { profile.age = max(13, profile.age - 1) },
                     increment: { profile.age = min(90, profile.age + 1) })
            LedgerRule()
            QuizDial(label: "Height", value: "\(Int(profile.heightInches / 12))′\(Int(profile.heightInches) % 12)″", unit: "",
                     decrement: { profile.heightInches = max(48, profile.heightInches - 1) },
                     increment: { profile.heightInches = min(84, profile.heightInches + 1) })
            LedgerRule()
            QuizDial(label: "Weight", value: "\(Int(profile.currentWeightLbs))", unit: "lb",
                     decrement: { profile.currentWeightLbs = max(80, profile.currentWeightLbs - 1) },
                     increment: { profile.currentWeightLbs = min(400, profile.currentWeightLbs + 1) })
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
            .padding(.vertical, 10)
            Text("Used for the BMR equation — it's a term in the formula, not a judgement.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 4)
        }
    }

    private var directionStep: some View {
        QuizStep(label: "The goal", title: "What are you after?") {
            ForEach(Array(GoalDirection.allCases.enumerated()), id: \.element) { index, direction in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: direction.displayName, subtitle: direction.blurb,
                              isSelected: profile.goalDirection == direction, accent: accent) {
                    profile.goalDirection = direction
                    // Keep the target sane when the direction flips.
                    switch direction {
                    case .cut: profile.goalWeightLbs = min(profile.goalWeightLbs, profile.currentWeightLbs - 5)
                    case .gain: profile.goalWeightLbs = max(profile.goalWeightLbs, profile.currentWeightLbs + 5)
                    case .maintain, .recomp: profile.goalWeightLbs = profile.currentWeightLbs
                    }
                }
            }
        }
    }

    private var targetWeightStep: some View {
        QuizStep(label: "The target", title: "Where are you going?") {
            QuizDial(label: "Goal weight", value: "\(Int(profile.goalWeightLbs))", unit: "lb",
                     decrement: { profile.goalWeightLbs = max(80, profile.goalWeightLbs - 1) },
                     increment: { profile.goalWeightLbs = min(400, profile.goalWeightLbs + 1) })
            let delta = abs(Int(profile.currentWeightLbs - profile.goalWeightLbs))
            if delta > 0 {
                Text("\(delta) lb to \(profile.goalDirection == .gain ? "gain" : "lose"). I'll show you the timeline on the next-to-last screen.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 12)
            }
        }
    }

    private var activityStep: some View {
        QuizStep(label: "Baseline output", title: "How much do you move?") {
            ForEach(Array(ActivityLevel.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: level.displayName, subtitle: level.blurb,
                              isSelected: profile.activityLevel == level, accent: accent) {
                    profile.activityLevel = level
                }
            }
        }
    }

    private var dietStep: some View {
        QuizStep(label: "Food", title: "How do you eat?") {
            ForEach(Array(DietaryPattern.allCases.enumerated()), id: \.element) { index, pattern in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: pattern.displayName, subtitle: "",
                              isSelected: profile.dietaryPattern == pattern, accent: accent) {
                    profile.dietaryPattern = pattern
                }
            }
        }
    }

    private var cuisineStep: some View {
        QuizStep(label: "Food", title: "What do you actually like?") {
            ForEach(Array(CuisinePreference.allCases.enumerated()), id: \.element) { index, cuisine in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: cuisine.displayName, subtitle: "",
                              isSelected: profile.cuisinePreference == cuisine, accent: accent) {
                    profile.cuisinePreference = cuisine
                }
            }
            Text("Biases recipe search so the plan is food you'd eat anyway. Adherence beats optimality.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 12)
        }
    }

    private var equipmentStep: some View {
        QuizStep(label: "Training", title: "What do you have access to?") {
            ForEach(Array(Equipment.allCases.enumerated()), id: \.element) { index, item in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: item.displayName, subtitle: item.blurb,
                              isSelected: profile.equipment.contains(item), accent: accent) {
                    if let existing = profile.equipment.firstIndex(of: item) {
                        if profile.equipment.count > 1 { profile.equipment.remove(at: existing) }
                    } else {
                        profile.equipment.append(item)
                    }
                }
            }
        }
    }

    private var sportStep: some View {
        QuizStep(label: "Optional", title: "Training for anything specific?") {
            ForEach(Array(FitnessGoal.allCases.filter { $0 != .fatLoss }.enumerated()), id: \.element) { index, goal in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: goal.displayName, subtitle: sportBlurb(goal),
                              isSelected: profile.fitnessGoals.contains(goal), accent: accent) {
                    if profile.fitnessGoals.contains(goal) {
                        profile.fitnessGoals.remove(goal)
                    } else {
                        profile.fitnessGoals.insert(goal)
                    }
                }
            }
            Text("Optional — skip if you just want general training. These add sport-specific sessions to your split.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 12)
        }
    }

    private var mealsStep: some View {
        QuizStep(label: "Structure", title: "How many meals a day?") {
            QuizDial(label: "Meals", value: "\(profile.mealsPerDay)", unit: "",
                     decrement: { profile.mealsPerDay = max(3, profile.mealsPerDay - 1) },
                     increment: { profile.mealsPerDay = min(5, profile.mealsPerDay + 1) })
            Text("Total daily intake matters far more than meal timing for fat loss. Pick whatever you'll actually stick to — 3 to 4 protein servings spread through the day is the one timing detail worth caring about.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 12)
        }
    }

    private var toneStep: some View {
        QuizStep(label: "Accountability", title: "How hard should I push?") {
            ForEach(Array(ToneIntensity.allCases.enumerated()), id: \.element) { index, tone in
                if index > 0 { LedgerRule() }
                QuizSelectRow(title: toneTitle(tone), subtitle: toneBlurb(tone),
                              isSelected: profile.toneIntensity == tone, accent: accent) {
                    profile.toneIntensity = tone
                }
            }
        }
    }

    // MARK: - Review

    private var reviewStep: some View {
        let targets = MetabolicEngine.dailyTargets(for: profile)
        let advisories = MetabolicEngine.advisories(profile: profile, targets: targets)
        let weeks = MetabolicEngine.estimatedWeeksToGoal(profile: profile, targets: targets)
        let rate = MetabolicEngine.weeklyRatePercent(profile: profile, targets: targets)

        return QuizStep(label: "Your plan", title: profile.name.isEmpty ? "Here's the math" : "Here's the math, \(profile.name)") {
            VStack(spacing: 0) {
                reviewRow("Maintenance", "\(targets.tdeeMaintenance) kcal")
                LedgerRule()
                reviewRow("Daily target", "\(targets.calories) kcal")
                LedgerRule()
                reviewRow("Protein", "\(targets.proteinGrams) g")
                LedgerRule()
                reviewRow("Fat", "\(targets.fatGrams) g")
                LedgerRule()
                reviewRow("Carbs", "\(targets.carbGrams) g")
                LedgerRule()
                reviewRow("Adjustment", targets.adjustmentLabel)
                if profile.goalDirection != .maintain && weeks.isFinite {
                    LedgerRule()
                    reviewRow("Estimated", "\(Int(weeks.rounded())) weeks")
                    LedgerRule()
                    reviewRow("Rate", String(format: "%.1f%% BW/week", rate))
                }
            }

            ForEach(advisories, id: \.self) { note in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(Theme.signal).frame(width: 2)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)
            }

            Text("These are general, evidence-based estimates from your inputs — not medical advice. If you have a health condition or take medication, run them past a doctor or dietitian first.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value).font(Theme.mono(14, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 11)
    }

    // MARK: - Copy

    private func sportBlurb(_ goal: FitnessGoal) -> String {
        switch goal {
        case .fastBowling: return "Rotational power, sprint work, lumbar protection"
        case .hikingBackpacking: return "Loaded rucking, unilateral legs, descent control"
        case .fatLoss: return ""
        }
    }

    private func toneTitle(_ tone: ToneIntensity) -> String {
        switch tone {
        case .gentle: return "Gentle"
        case .toughLove: return "Tough love"
        case .hardcore: return "Hardcore"
        }
    }

    private func toneBlurb(_ tone: ToneIntensity) -> String {
        switch tone {
        case .gentle: return "Reminders, no edge"
        case .toughLove: return "Direct callouts. Names the action, never you."
        case .hardcore: return "No cushion. Every skip gets called what it is."
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

// MARK: - Shared quiz building blocks

struct QuizStep<Content: View>: View {
    let label: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).ledgerLabel()
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }
}

struct QuizDial: View {
    let label: String
    let value: String
    let unit: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
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
}

struct QuizSelectRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accent: AppAccent
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? accent.color : Theme.inkFaint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
