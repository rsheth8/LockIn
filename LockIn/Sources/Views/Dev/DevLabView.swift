#if DEBUG
import SwiftUI

/// DEBUG-only fourth tab: one-tap personas, day fixtures, and flow jumps so
/// every LockIn path can be exercised without hand-editing state.
struct DevLabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @ObservedObject private var lab = DevLabController.shared
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    statusStrip
                    if let note = lab.lastAction {
                        Text(note)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accent.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    personasSection
                    dayActionsSection
                    scheduleSection
                    mealsSection
                    historySection
                    flowsSection
                    toneQuickSection
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .pinnedHeader {
                ScreenHeader(title: "Lab", subtitle: "DEBUG · one-tap paths")
            }
        }
    }

    // MARK: - Status

    private var statusStrip: some View {
        VStack(spacing: 0) {
            row("Profile", appState.profile.name.isEmpty ? "(blank)" : appState.profile.name)
            LedgerRule()
            row("Direction", "\(appState.profile.goalDirection.rawValue) · \(appState.profile.toneIntensity.rawValue)")
            LedgerRule()
            row("Equipment", appState.profile.equipment.map(\.displayName).joined(separator: ", "))
            LedgerRule()
            row("Meals", lab.forceLocalMeals ? "Forced local DB" : (Secrets.hasSpoonacular ? "Spoonacular allowed" : "No API key"))
            LedgerRule()
            row("Calendar", lab.hasScheduleOverride ? "Override active" : "Live EventKit")
            LedgerRule()
            row("Streak", "\(appState.streak.currentStreakDays) (best \(appState.streak.longestStreakDays))")
            LedgerRule()
            row("Meal source", appState.todaySchedule?.mealSource.label ?? "—")
        }
    }

    // MARK: - Personas

    private var personasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personas").ledgerLabel()
            Text("Swaps the whole profile and rebuilds today.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
            ForEach(DevPersona.allCases) { persona in
                Button {
                    Haptics.tap()
                    appState.applyDevPersona(persona)
                    lab.requestRebuild(note: "Applied \(persona.title)")
                } label: {
                    scenarioRow(title: persona.title, detail: persona.blurb)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Day actions

    private var dayActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's day").ledgerLabel()
            actionButton("Confirm all critical") {
                appState.confirmAllCriticalToday()
                lab.lastAction = "All critical confirmed"
            }
            actionButton("Miss next critical") {
                appState.missNextCritical()
                lab.lastAction = "Missed next critical — check coach line"
            }
            actionButton("Reset all statuses to pending") {
                appState.resetTodayStatuses()
                lab.requestRebuild(note: "Statuses reset (rebuild preserves pending)")
            }
            actionButton("Make pending events overdue") {
                appState.makePendingEventsOverdue()
                lab.lastAction = "Hero should show Overdue"
            }
            actionButton("Mark schedule as yesterday (stale)") {
                appState.markScheduleAsYesterday()
                lab.lastAction = "Schedule stale — background the app or tap Rebuild"
            }
            actionButton("Rebuild today now") {
                lab.requestRebuild(note: "Manual rebuild")
            }
            actionButton("Inject distraction event") {
                appState.injectDistractionEvent()
                lab.lastAction = "Distraction drained — streak should reset"
            }
        }
    }

    // MARK: - Schedule fixtures

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar fixtures").ledgerLabel()
            Text("Overrides EventKit until you clear them.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
            actionButton("Packed day (no workout gap)") {
                lab.applyPackedDay()
            }
            actionButton("Light day (workout should fit)") {
                lab.applyLightDay()
            }
            actionButton("Empty calendar") {
                lab.applyEmptyCalendar()
            }
            actionButton("Clear override → live Calendar") {
                lab.clearScheduleOverride()
            }
        }
    }

    // MARK: - Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals").ledgerLabel()
            Toggle(isOn: Binding(
                get: { lab.forceLocalMeals },
                set: { on in
                    lab.forceLocalMeals = on
                    lab.requestRebuild(note: on ? "Forcing built-in meals" : "Spoonacular allowed again")
                }
            )) {
                Text("Force built-in food database")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.signal)
            Text(Secrets.hasSpoonacular
                 ? "Key present. Toggle on to test the silent fallback path."
                 : "No Spoonacular key — already on the local path.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record / streak").ledgerLabel()
            actionButton("Seed ~4 months history") {
                appState.loadDemoHistory()
                lab.lastAction = "Promise grid + weight chart populated"
            }
            actionButton("Clear history") {
                appState.clearDemoHistory()
                lab.lastAction = "History cleared"
            }
            actionButton("Streak = 12 days") {
                appState.applyDevStreak(days: 12, longest: 21)
                lab.lastAction = "Streak set to 12"
            }
            actionButton("Streak = 0 (broken)") {
                appState.applyDevStreak(days: 0, longest: 21)
                lab.lastAction = "Streak broken"
            }
            actionButton("Streak = 7 (win message day)") {
                appState.applyDevStreak(days: 7)
                lab.lastAction = "Weekly win coach line eligible when day is clean"
            }
        }
    }

    // MARK: - Flows

    private var flowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flows").ledgerLabel()
            actionButton("Re-run onboarding quiz") {
                appState.reopenOnboarding()
                lab.lastAction = "QuizFlowView"
            }
            actionButton("Jump to sign-in") {
                accountManager.signOut()
                lab.lastAction = "SignInView"
            }
            if screenTimeManager.isAuthorized {
                actionButton("Start 10-min focus lock-in") {
                    _ = screenTimeManager.startFocusBlock(label: "Lab focus", minutes: 10)
                    lab.lastAction = "10-min focus block scheduled"
                }
            }
        }
    }

    // MARK: - Tone

    private var toneQuickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tone quick-switch").ledgerLabel()
            Picker("Tone", selection: Binding(
                get: { appState.profile.toneIntensity },
                set: { tone in
                    var p = appState.profile
                    p.toneIntensity = tone
                    appState.saveProfile(p)
                    lab.lastAction = "Tone → \(tone.rawValue)"
                }
            )) {
                Text("Gentle").tag(ToneIntensity.gentle)
                Text("Tough").tag(ToneIntensity.toughLove)
                Text("Hardcore").tag(ToneIntensity.hardcore)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Rows

    private func scenarioRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.rule, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value)
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }
}
#endif
