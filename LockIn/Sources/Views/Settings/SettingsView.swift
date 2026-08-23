import SwiftUI
import FamilyControls

/// Everything tunable in one ledger-styled list: who you are, how hard the app
/// pushes, how it looks, and what it guards during lock-in blocks.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @EnvironmentObject var accountManager: AccountManager
    @Environment(\.accent) private var accent
    @State private var showingPicker = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    ScreenHeader(title: "Settings", subtitle: "How the app treats you")
                    accentSection
                    toneSection
                    targetsSection
                    screenTimeSection
                    goalsSection
                    accountSection
#if DEBUG
                    debugSection
#endif
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: Binding(
            get: { screenTimeManager.selection },
            set: { screenTimeManager.saveSelection($0) }
        ))
    }

    // MARK: - Accent

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Highlight colour").ledgerLabel()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8), spacing: 12) {
                ForEach(AppAccent.allCases) { option in
                    Button {
                        Haptics.tap()
                        var updated = appState.profile
                        updated.accentColor = option
                        withAnimation(.snappy) { appState.saveProfile(updated) }
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(height: 32)
                            .overlay(
                                Circle().strokeBorder(Theme.ink, lineWidth: appState.profile.accentColor == option ? 2 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Used for highlights and your streak. The alert red stays fixed — it only ever means you're slipping, so it shouldn't blend in with your colour.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account").ledgerLabel()
            VStack(spacing: 0) {
                row("Status", accountManager.isSignedIn ? "Signed in" : "On this device")
                LedgerRule()
                row("Recipes", Secrets.hasSpoonacular ? "Spoonacular" : "Built-in database")
            }
            Text(accountManager.isSignedIn
                 ? "Your plan syncs to your own private iCloud. Progress photos stay on this device only."
                 : "Everything is stored on this device. Sign in to carry your plan to a new phone.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                accountManager.signOut()
            } label: {
                Text(accountManager.isSignedIn ? "Sign out" : "Set up an account")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.signal)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tone

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How hard should it push").ledgerLabel()
            Picker("Tone", selection: Binding(
                get: { appState.profile.toneIntensity },
                set: { newTone in
                    Haptics.tap()
                    var updated = appState.profile
                    updated.toneIntensity = newTone
                    appState.saveProfile(updated)
                }
            )) {
                Text("Gentle").tag(ToneIntensity.gentle)
                Text("Tough").tag(ToneIntensity.toughLove)
                Text("Hardcore").tag(ToneIntensity.hardcore)
            }
            .pickerStyle(.segmented)

            Text(toneBlurb)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toneBlurb: String {
        switch appState.profile.toneIntensity {
        case .gentle: return "Reminders, no edge. Good for a deload week."
        case .toughLove: return "Direct callouts when you slip. Names the action, never you."
        case .hardcore: return "No cushion. Every skip gets called what it is."
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        let macros = MetabolicEngine.dailyTargets(for: appState.profile)
        let weeks = MetabolicEngine.estimatedWeeksToGoal(profile: appState.profile, targets: macros)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Current targets").ledgerLabel()
            VStack(spacing: 0) {
                row("Maintenance", "\(macros.tdeeMaintenance) kcal")
                LedgerRule()
                row("Target", "\(macros.calories) kcal")
                LedgerRule()
                row("Protein", "\(macros.proteinGrams) g")
                LedgerRule()
                row("Deficit", "\(Int(macros.deficitPercent * 100))%")
                LedgerRule()
                row("Est. to goal", weeks.isFinite ? "\(Int(weeks.rounded())) weeks" : "—")
            }
            Text("Recalculated automatically as your weight drops — nothing here is hand-set.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Screen Time

    private var screenTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lock-in enforcement").ledgerLabel()

            if screenTimeManager.isAuthorized {
                Button {
                    Haptics.tap()
                    showingPicker = true
                } label: {
                    HStack {
                        Text("Guarded apps")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(guardedCount)")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Text("These get shielded automatically during your workout window. Open one anyway and it stays blocked — and it costs you the streak.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    Task { await screenTimeManager.requestAuthorization() }
                } label: {
                    Text("Grant Screen Time Access")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Lets LockIn shield distracting apps during workouts and catch you if you use them anyway. Requires Apple to approve the Family Controls entitlement on your developer account.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guardedCount: Int {
        screenTimeManager.selection.applicationTokens.count + screenTimeManager.selection.categoryTokens.count
    }

    // MARK: - Training goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training for").ledgerLabel()
            VStack(spacing: 0) {
                ForEach(Array(FitnessGoal.allCases.filter { $0 != .fatLoss }.enumerated()), id: \.element) { index, goal in
                    if index > 0 { LedgerRule() }
                    Toggle(isOn: Binding(
                        get: { appState.profile.fitnessGoals.contains(goal) },
                        set: { isOn in
                            Haptics.tap()
                            var updated = appState.profile
                            if isOn { updated.fitnessGoals.insert(goal) } else { updated.fitnessGoals.remove(goal) }
                            appState.saveProfile(updated)
                        }
                    )) {
                        Text(goal.displayName)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.signal)
                    .padding(.vertical, 10)
                }
            }
        }
    }

#if DEBUG
    /// Development only — stripped from release builds.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug").ledgerLabel()
            HStack(spacing: 10) {
                Button("Seed history") {
                    Haptics.tap()
                    withAnimation(.snappy) { appState.loadDemoHistory() }
                }
                Button("Clear") {
                    Haptics.tap()
                    withAnimation(.snappy) { appState.clearDemoHistory() }
                }
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.bordered)
            .tint(Theme.inkMuted)
        }
    }
#endif

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value)
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 11)
    }
}
