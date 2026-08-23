import SwiftUI

/// The ledger's front page. One question answered above the fold — *what do I
/// do right now* — with the rest of the day readable underneath but visually
/// subordinate. Everything numeric is monospaced so the day reads like an
/// instrument panel rather than a to-do list.
struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent
    var onOpenProgressPhoto: () -> Void

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
                                onTapDetail: { if event.kind == .progressPhoto { onOpenProgressPhoto() } }
                            )
                        }
                        if let coach = appState.coachLine {
                            coachCallout(coach)
                        }
                        vitals(schedule: schedule)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .ledgerLabel()
            Spacer()
            Text("DAY \(appState.streak.currentStreakDays)")
                .font(Theme.mono(11, weight: .semibold))
                .tracking(Theme.labelTracking)
                .foregroundStyle(appState.streak.currentStreakDays > 0 ? accent.color : Theme.inkMuted)
        }
        .padding(.top, 8)
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
                    onSkip: { skip(event) }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.time, format: .dateTime.hour().minute())
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 54, alignment: .leading)
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
