import SwiftUI

/// The ledger's front page. One question answered above the fold — *what do I
/// do right now* — with the rest of the day readable underneath but visually
/// subordinate. Everything numeric is monospaced so the day reads like an
/// instrument panel rather than a to-do list.
struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @Environment(\.accent) private var accent
    var onOpenProgressPhoto: () -> Void

    @State private var weighInEvent: ScheduledEvent?
    @State private var weighInText = ""
    @State private var focusStartedMessage: String?
    @State private var proofEvent: ScheduledEvent?
    @State private var mealActionEvent: ScheduledEvent?
    @State private var workoutModeEvent: ScheduledEvent?
#if DEBUG
    @ObservedObject private var lab = DevLabController.shared
#endif

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if let schedule = appState.todaySchedule {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
#if DEBUG
                        if lab.hasScheduleOverride || lab.forceLocalMeals {
                            labBanner
                        }
#endif
                        if let event = appState.currentEvent {
                            HeroCard(
                                event: event,
                                onConfirm: { confirm(event) },
                                onSkip: { skip(event) },
                                onTapDetail: { if event.kind == .progressPhoto { onOpenProgressPhoto() } }
                            )
                        }
                        if let coach = appState.coachLine {
                            coachCallout(coach)
                        }
                        if let focusStartedMessage {
                            Text(focusStartedMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(accent.color)
                        }
                        vitals(schedule: schedule)
                        timeline(schedule: schedule)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 4)
                    // Clears the floating tab bar so the last event isn't trapped under it.
                    .padding(.bottom, 96)
                }
                .pinnedHeader { header }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.inkMuted)
                    Text("Building today's plan…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .alert("Morning weigh-in", isPresented: Binding(
            get: { weighInEvent != nil },
            set: { if !$0 { weighInEvent = nil } }
        )) {
            TextField("Weight (lb)", text: $weighInText)
                .keyboardType(.decimalPad)
            Button("Log") { submitWeighIn() }
            Button("Cancel", role: .cancel) { weighInEvent = nil }
        } message: {
            Text("Same time, same conditions. This updates Health and recalculates today's macros.")
        }
        .sheet(item: $proofEvent) { event in
            CheckInProofSheet(
                event: event,
                onVerified: {
                    proofEvent = nil
                    finishConfirm(event)
                },
                onOverride: {
                    proofEvent = nil
                    finishConfirm(event)
                },
                onCancel: { proofEvent = nil }
            )
        }
        .confirmationDialog("Meal", isPresented: Binding(
            get: { mealActionEvent != nil },
            set: { if !$0 { mealActionEvent = nil } }
        ), titleVisibility: .visible) {
            Button("Swap for another recipe") {
                if let event = mealActionEvent {
                    let ok = appState.swapMeal(for: event)
                    mealActionEvent = nil
                    ok ? Haptics.confirm() : Haptics.miss()
                }
            }
            Button("Save to my menu") {
                if let event = mealActionEvent {
                    appState.likeCurrentMeal(for: event)
                    mealActionEvent = nil
                    Haptics.confirm()
                }
            }
            Button("Cancel", role: .cancel) { mealActionEvent = nil }
        } message: {
            Text(mealActionEvent?.title ?? "Change this meal")
        }
        .fullScreenCover(item: $workoutModeEvent) { event in
            WorkoutModeView(session: todayWorkoutSession) {
                workoutModeEvent = nil
                // Guided session is the proof — skip the photo sheet.
                finishConfirm(event)
            }
        }
    }

    /// Rebuilds today's Hybrid PPL session from the live profile so Workout
    /// Mode always matches the event detail ScheduleEngine wrote.
    private var todayWorkoutSession: WorkoutSession {
        WorkoutEngine.session(
            for: Date(),
            goals: appState.profile.fitnessGoals,
            equipment: appState.profile.equipment,
            assets: appState.profile.gymAssets,
            brief: appState.profile.trainingBrief
        )
    }

#if DEBUG
    private var labBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "flask.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(labBannerText)
                .font(Theme.mono(11, weight: .semibold))
                .tracking(Theme.labelTracking)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.signal)
        .padding(.top, 4)
    }

    private var labBannerText: String {
        var parts: [String] = ["Lab"]
        if lab.hasScheduleOverride { parts.append("calendar override") }
        if lab.forceLocalMeals { parts.append("local meals") }
        return parts.joined(separator: " · ")
    }
#endif

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .ledgerLabel()
            Spacer()
            if appState.isRefreshingMeals {
                Text("Fetching recipes…")
                    .font(Theme.mono(11, weight: .semibold))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                Text("DAY \(appState.streak.currentStreakDays)")
                    .font(Theme.mono(11, weight: .semibold))
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(appState.streak.currentStreakDays > 0 ? accent.color : Theme.inkMuted)
            }
        }
    }

    // MARK: - Coach callout
    //
    // Deliberately the only place accent-red type appears on this screen, and it
    // only renders when there's something real to say. Silence most days is what
    // keeps the callouts from going numb.

    private func coachCallout(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.signal)
                .frame(width: 2)
            Text(text)
                .font(Theme.coach)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vitals strip

    private func vitals(schedule: DaySchedule) -> some View {
        VStack(spacing: 14) {
            LedgerRule()
            HStack(alignment: .top, spacing: 0) {
                vital(
                    label: "Today",
                    value: "\(appState.confirmedCriticalToday)/\(appState.criticalEventsToday.count)",
                    detail: "promises"
                )
                vital(
                    label: "Streak",
                    value: "\(appState.streak.currentStreakDays)",
                    detail: "best \(appState.streak.longestStreakDays)",
                    valueColor: appState.streak.currentStreakDays > 0 ? accent.color : Theme.ink
                )
                vital(
                    label: "Weight",
                    value: "\(Int(appState.profile.currentWeightLbs))",
                    detail: "goal \(Int(appState.profile.goalWeightLbs))"
                )
            }
            LedgerRule()
            fuelRow(schedule: schedule)
            if screenTimeManager.isAuthorized {
                focusRow
            }
        }
    }

    private var focusRow: some View {
        Button {
            Haptics.tap()
            if screenTimeManager.startFocusBlock(minutes: 45) != nil {
                focusStartedMessage = "45-minute focus block started — guarded apps are shielded."
            } else {
                focusStartedMessage = "Pick guarded apps in Settings before starting a focus block."
            }
        } label: {
            HStack {
                Text("Start 45-min focus lock-in")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func vital(label: String, value: String, detail: String, valueColor: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ledgerLabel()
            Text(value)
                .font(Theme.mono(22, weight: .semibold))
                .foregroundStyle(valueColor)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shows what today's meals actually add up to — not the target.
    ///
    /// These are two different numbers whenever the recipe pool can't reach the
    /// protein goal, and showing the target here made a 130g day read as 180g.
    /// The target stays visible underneath only when the plan misses it, so a
    /// good day is one clean line and a bad day says so.
    private func fuelRow(schedule: DaySchedule) -> some View {
        let macros = schedule.macros
        let planned = schedule.plannedMacros
        let shortfall = schedule.proteinShortfall

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fuel").ledgerLabel()
                Spacer()
                Text(schedule.mealSource.label)
                    .font(Theme.mono(10, weight: .semibold))
                    .tracking(Theme.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(schedule.mealSource == .spoonacular ? accent.color : Theme.inkMuted)
                Text("\(Int((planned?.calories ?? Double(macros.calories)).rounded()))")
                    .font(Theme.mono(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("kcal")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                Text(plannedMacroLine(planned: planned, macros: macros))
                    .font(Theme.mono(12))
                    .foregroundStyle(shortfall > 0 ? Theme.signal : Theme.inkMuted)
                    .padding(.leading, 4)
            }
            if shortfall > 0 {
                Text("\(shortfall)g under your \(macros.proteinGrams)g protein target — today's recipes couldn't reach it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plannedMacroLine(planned: MacroTargetsLite?, macros: MacroTargets) -> String {
        guard let planned else {
            return "P\(macros.proteinGrams)  F\(macros.fatGrams)  C\(macros.carbGrams)"
        }
        return "P\(Int(planned.proteinG.rounded()))  F\(Int(planned.fatG.rounded()))  C\(Int(planned.carbG.rounded()))"
    }

    // MARK: - Timeline

    private func timeline(schedule: DaySchedule) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Day").ledgerLabel()
                Spacer()
                if schedule.events.contains(where: { $0.kind == .commitment || $0.kind == .task }) {
                    Text("Live")
                        .font(Theme.mono(11, weight: .semibold))
                        .tracking(Theme.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(accent.color)
                }
            }
            .padding(.bottom, 10)
            ForEach(schedule.events) { event in
                TimelineRow(
                    event: event,
                    isCurrent: event.id == appState.currentEvent?.id,
                    onConfirm: { confirm(event) },
                    onSkip: { skip(event) },
                    onMealOptions: event.kind == .meal ? { mealActionEvent = event } : nil
                )
                .onTapGesture {
                    if event.kind == .progressPhoto {
                        Haptics.tap()
                        onOpenProgressPhoto()
                    } else if event.kind == .meal {
                        Haptics.tap()
                        mealActionEvent = event
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func confirm(_ event: ScheduledEvent) {
        if event.kind == .weighIn {
            weighInText = String(format: "%.1f", appState.profile.currentWeightLbs)
            weighInEvent = event
            return
        }
        if event.kind == .workout {
            Haptics.tap()
            workoutModeEvent = event
            return
        }
        if CheckInVerifier.requiresProof(event.kind) {
            proofEvent = event
            return
        }
        finishConfirm(event)
    }

    private func finishConfirm(_ event: ScheduledEvent) {
        let before = appState.streak.currentStreakDays
        withAnimation(.snappy) { appState.confirm(event) }
        if event.kind == .task, let id = event.externalIdentifier {
            calendarManager.completeReminder(identifier: id)
        }
        appState.streak.currentStreakDays > before ? Haptics.milestone() : Haptics.confirm()
    }

    private func submitWeighIn() {
        guard let event = weighInEvent else { return }
        let value = Double(weighInText.replacingOccurrences(of: ",", with: "."))
            ?? appState.profile.currentWeightLbs
        withAnimation(.snappy) {
            appState.applyWeighIn(pounds: value, event: event, healthKit: healthKitManager)
        }
        weighInEvent = nil
        Haptics.confirm()
    }

    private func skip(_ event: ScheduledEvent) {
        withAnimation(.snappy) { appState.markMissed(event) }
        Haptics.miss()
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    let event: ScheduledEvent
    let onConfirm: () -> Void
    let onSkip: () -> Void
    let onTapDetail: () -> Void

    /// Live countdown so the card feels present rather than static.
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isOverdue ? "Overdue" : "Next").ledgerLabel()
                    .foregroundStyle(isOverdue ? Theme.signal : Theme.inkMuted)
                Spacer()
                Text(event.time, style: .time)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 14)

            Text(event.title)
                .font(Theme.hero)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(relativeLine)
                .font(Theme.heroSub)
                .foregroundStyle(isOverdue ? Theme.signal : Theme.inkMuted)
                .padding(.top, 4)

            if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .onTapGesture(perform: onTapDetail)
            }

            HStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text(primaryActionTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(Theme.inkMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.rule, lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerCard()
        .onReceive(tick) { now = $0 }
    }

    private var isOverdue: Bool { now > event.time && event.status == .pending }

    private var primaryActionTitle: String {
        switch event.kind {
        case .weighIn: return "Log weight"
        case .workout: return "Start workout"
        default: return "Done"
        }
    }

    private var relativeLine: String {
        let delta = event.time.timeIntervalSince(now)
        let minutes = abs(Int(delta / 60))
        let stamp = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        if delta < 0 { return "\(stamp) late" }
        return "in \(stamp)"
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let event: ScheduledEvent
    let isCurrent: Bool
    let onConfirm: () -> Void
    let onSkip: () -> Void
    var onMealOptions: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Wide enough for "12:15 PM" — at 54pt the meridiem wrapped onto a
            // second line for any two-digit afternoon hour.
            Text(event.time, format: .dateTime.hour().minute())
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 72, alignment: .leading)
                .padding(.top, 2)

            marker

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(event.status == .missed ? Theme.inkMuted : Theme.ink)
                    .strikethrough(event.status == .missed, color: Theme.inkMuted)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)

            // Calendar commitments are context, not promises — no check-in.
            if event.kind != .commitment, event.status == .pending || event.status == .snoozed {
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Theme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Mark as done", systemImage: "checkmark", action: onConfirm)
                    Button("Skip it", systemImage: "xmark", role: .destructive, action: onSkip)
                    if event.kind == .meal, let onMealOptions {
                        Button("Swap / save recipe", systemImage: "arrow.triangle.2.circlepath", action: onMealOptions)
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .opacity(event.status == .confirmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    /// Dot language: filled = kept, hollow ring = still owed, red = broken.
    /// Non-critical events get a smaller, fainter dot so the eye reads the
    /// load-bearing promises first.
    private var marker: some View {
        Group {
            switch event.status {
            case .confirmed:
                Circle().fill(Theme.kept)
            case .missed:
                Circle().fill(Theme.signal)
            case .pending, .snoozed:
                Circle()
                    .strokeBorder(isCurrent ? Theme.ink : Theme.inkFaint,
                                  lineWidth: event.isCritical ? 2 : 1)
            }
        }
        .frame(width: event.isCritical ? 9 : 6, height: event.isCritical ? 9 : 6)
        .padding(.top, 5)
        .padding(.horizontal, event.isCritical ? 0 : 1.5)
    }
}
