import SwiftUI

/// The ledger's front page. One question answered above the fold — *what do I
/// do right now* — with the rest of the day readable underneath but visually
/// subordinate. Everything numeric is monospaced so the day reads like an
/// instrument panel rather than a to-do list.
struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent
    var onOpenProgressPhoto: () -> Void

    /// Non-nil while the log sheet is up. Carries the event being swapped, or
    /// `.adHoc` for the always-available entry point.
    @State private var logTarget: LogTarget?
    /// Non-nil while an already-logged meal is being corrected.
    @State private var editingMeal: LoggedMeal?

    /// Identifiable wrapper so `.sheet(item:)` can drive both entry points
    /// through one presentation.
    private struct LogTarget: Identifiable {
        let event: ScheduledEvent?
        var id: String { event?.id.uuidString ?? "ad-hoc" }
        static let adHoc = LogTarget(event: nil)
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if let schedule = appState.todaySchedule {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if let event = appState.currentEvent {
                            HeroCard(
                                event: event,
                                onConfirm: { confirm(event) },
                                onSkip: { skip(event) },
                                onAteSomethingElse: event.kind == .meal
                                    ? { logTarget = LogTarget(event: event) }
                                    : nil,
                                onTapDetail: { if event.kind == .progressPhoto { onOpenProgressPhoto() } }
                            )
                        }
                        if let coach = appState.coachLine {
                            coachCallout(coach)
                        }
                        vitals(schedule: schedule)
                        if !appState.loggedMealsToday.isEmpty {
                            loggedMealsSection
                        }
                        timeline(schedule: schedule)
                    }
                    .padding(.horizontal, Theme.gutter)
                    // Clears the floating tab bar so the last event isn't trapped under it.
                    .padding(.bottom, 96)
                }
            } else {
                ProgressView().tint(Theme.inkMuted)
            }
        }
        .sheet(item: $logTarget) { target in
            // Built here, where the profile and the log actually live, rather
            // than reached for from inside two nested sheets.
            LogMealView(
                replacingEvent: target.event,
                shopSmart: ShopSmartContext.build(
                    profile: appState.profile, loggedMeals: appState.loggedMeals
                )
            ) { meal in
                withAnimation(.snappy) { appState.log(meal) }
            }
        }
        .sheet(item: $editingMeal) { meal in
            EditLoggedMealView(
                meal: meal,
                onSave: { updated in withAnimation(.snappy) { appState.updateLoggedMeal(updated) } },
                onDelete: { old in withAnimation(.snappy) { appState.deleteLoggedMeal(old) } }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .ledgerLabel()
            Spacer()
            // Always reachable — eating off-plan is the common case, and it
            // shouldn't require finding the right meal row first.
            Button {
                Haptics.tap()
                logTarget = .adHoc
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("LOG A MEAL")
                        .font(Theme.mono(10, weight: .semibold))
                        .tracking(Theme.labelTracking)
                }
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule().strokeBorder(Theme.rule, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            Text("DAY \(appState.streak.currentStreakDays)")
                .font(Theme.mono(11, weight: .semibold))
                .tracking(Theme.labelTracking)
                .foregroundStyle(appState.streak.currentStreakDays > 0 ? accent.color : Theme.inkMuted)
                .padding(.leading, 10)
        }
        .padding(.top, 8)
    }

    // MARK: - Off-plan meals

    /// What was actually eaten outside the plan today, with its macro cost.
    private var loggedMealsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Off plan").ledgerLabel()
                Spacer()
                let logged = appState.loggedMacrosToday
                Text("+\(Int(logged.calories.rounded())) kcal")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 10)

            ForEach(appState.loggedMealsToday) { meal in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: meal.identifiedFromPhoto ? "camera.fill" : "square.and.pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 16)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("\(meal.portionDescription) · \(Int(meal.macros.calories.rounded()))kcal · P\(Int(meal.macros.proteinG.rounded())) F\(Int(meal.macros.fatG.rounded())) C\(Int(meal.macros.carbG.rounded()))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                // Tap to correct. A number you can't fix is worse than no
                // number, so this is a plain tap rather than a buried menu item.
                .onTapGesture {
                    Haptics.tap()
                    editingMeal = meal
                }
                .contextMenu {
                    Button("Edit", systemImage: "slider.horizontal.3") {
                        editingMeal = meal
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { appState.deleteLoggedMeal(meal) }
                    }
                }
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
            fuelRow(macros: schedule.macros)
        }
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

    private func fuelRow(macros: MacroTargets) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Fuel").ledgerLabel()
            Spacer()
            Text("\(macros.calories)")
                .font(Theme.mono(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("kcal")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
            Text("P\(macros.proteinGrams)  F\(macros.fatGrams)  C\(macros.carbGrams)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.inkMuted)
                .padding(.leading, 4)
        }
    }

    // MARK: - Timeline

    private func timeline(schedule: DaySchedule) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The Day").ledgerLabel().padding(.bottom, 10)
            ForEach(schedule.events) { event in
                TimelineRow(
                    event: event,
                    isCurrent: event.id == appState.currentEvent?.id,
                    onConfirm: { confirm(event) },
                    onSkip: { skip(event) },
                    onAteSomethingElse: event.kind == .meal
                        ? { logTarget = LogTarget(event: event) }
                        : nil
                )
                .onTapGesture {
                    if event.kind == .progressPhoto {
                        Haptics.tap()
                        onOpenProgressPhoto()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func confirm(_ event: ScheduledEvent) {
        let before = appState.streak.currentStreakDays
        withAnimation(.snappy) { appState.confirm(event) }
        appState.streak.currentStreakDays > before ? Haptics.milestone() : Haptics.confirm()
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
    /// Only set for meals — nothing else has a meaningful substitute.
    let onAteSomethingElse: (() -> Void)?
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
                    Text("Done")
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

            // Third path for meals: you ate, just not this. Kept visually
            // quieter than Done/Skip so the planned meal stays the default.
            if let onAteSomethingElse {
                Button(action: onAteSomethingElse) {
                    Text("Ate something else")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerCard()
        .onReceive(tick) { now = $0 }
    }

    private var isOverdue: Bool { now > event.time && event.status == .pending }

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
    let onAteSomethingElse: (() -> Void)?

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

            // Pending rows carry their own confirm affordance so you can clear
            // anything from the timeline without scrolling back to the hero card.
            if event.status == .pending || event.status == .snoozed {
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
                    if let onAteSomethingElse {
                        Button("Ate something else", systemImage: "camera", action: onAteSomethingElse)
                    }
                    Button("Skip it", systemImage: "xmark", role: .destructive, action: onSkip)
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
