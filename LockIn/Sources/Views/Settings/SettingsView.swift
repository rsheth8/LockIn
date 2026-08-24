import SwiftUI
import FamilyControls

/// Everything tunable in one ledger-styled list: who you are, how hard the app
/// pushes, how it looks, and what it guards during lock-in blocks.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var calendarManager: CalendarManager
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
                    connectionsSection
                    paceSection
                    targetsSection
                    foodSection
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

    // MARK: - Connections

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The rest of your day").ledgerLabel()
            VStack(spacing: 0) {
                row("Calendar", calendarManager.authorized ? "Live · writes to Lock In" : "Off")
                LedgerRule()
                row("Reminders", calendarManager.remindersAuthorized ? "Due today on the timeline" : "Off")
            }
            Text("Add or move something in Calendar and today's meals and workout shift around it. Done on a reminder completes it in Reminders. Lock In events also land on a calendar named Lock In, so Watch and Calendar.app see the same day.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pace

    @ViewBuilder
    private var paceSection: some View {
        if appState.profile.goalDirection == .cut || appState.profile.goalDirection == .gain {
            VStack(alignment: .leading, spacing: 12) {
                Text("How fast").ledgerLabel()
                VStack(spacing: 0) {
                    ForEach(Array(DeficitIntensity.allCases.enumerated()), id: \.element) { index, intensity in
                        if index > 0 { LedgerRule() }
                        Button {
                            Haptics.tap()
                            var updated = appState.profile
                            updated.deficitIntensity = intensity
                            appState.saveProfile(updated)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(intensity.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                    Text(intensity.blurb)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: appState.profile.deficitIntensity == intensity ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19))
                                    .foregroundStyle(appState.profile.deficitIntensity == intensity ? accent.color : Theme.inkFaint)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if appState.profile.deficitIntensity.isBeyondRecommendedBand {
                    Text("Maximum sits past the 0.5–1% band the research supports. You'll see the safety notes on your targets.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.signal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        let macros = MetabolicEngine.dailyTargets(for: appState.profile)
        let weeks = MetabolicEngine.estimatedWeeksToGoal(profile: appState.profile, targets: macros)
        let notes = MetabolicEngine.advisories(profile: appState.profile, targets: macros)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Current targets").ledgerLabel()
            VStack(spacing: 0) {
                row("Maintenance", "\(macros.tdeeMaintenance) kcal")
                LedgerRule()
                row("Target", "\(macros.calories) kcal")
                LedgerRule()
                row("Protein", "\(macros.proteinGrams) g")
                LedgerRule()
                row("Carbs", "\(macros.carbGrams) g")
                LedgerRule()
                row("Adjustment", macros.adjustmentLabel)
                LedgerRule()
                row("Est. to goal", weeks.isFinite ? "\(Int(weeks.rounded())) weeks" : "—")
            }
            Text("Recalculated automatically as your weight drops — nothing here is hand-set.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(Theme.signal).frame(width: 2)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Food

    private var foodSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your food").ledgerLabel()

            VStack(alignment: .leading, spacing: 8) {
                Text("Kitchens").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                ChipFlow {
                    ForEach(CuisinePreference.allCases.filter { $0 != .noPreference }) { cuisine in
                        IngredientChip(
                            title: cuisine.displayName,
                            selected: appState.profile.foodPreferences.cuisines.contains(cuisine),
                            accent: accent
                        ) {
                            Haptics.tap()
                            var updated = appState.profile
                            if updated.foodPreferences.cuisines.contains(cuisine) {
                                updated.foodPreferences.cuisines.remove(cuisine)
                            } else {
                                updated.foodPreferences.cuisines.insert(cuisine)
                            }
                            appState.saveProfile(updated)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Favourites").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                IngredientChipEditor(
                    placeholder: "Add a favourite",
                    suggestions: PantrySuggestions.forCuisines(appState.profile.resolvedCuisines, pattern: appState.profile.dietaryPattern),
                    items: foodListBinding(\.favouriteIngredients),
                    accent: accent
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Hard no").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                IngredientChipEditor(
                    placeholder: "Won't eat",
                    items: foodListBinding(\.dislikedIngredients),
                    accent: accent
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Allergies").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                IngredientChipEditor(
                    placeholder: "peanut, dairy…",
                    suggestions: ["peanut", "dairy", "gluten", "soy", "shellfish"],
                    items: intolerancesBinding,
                    accent: accent
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pantry").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                PantryEditor(
                    pantry: pantryBinding,
                    suggestions: PantrySuggestions.forCuisines(appState.profile.resolvedCuisines, pattern: appState.profile.dietaryPattern),
                    accent: accent
                )
            }

            Text("Meals rebuild from this the next time the day is generated. Favourites and pantry bias the search; allergies and hard-nos never appear.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func foodListBinding(_ keyPath: WritableKeyPath<FoodPreferences, [String]>) -> Binding<[String]> {
        Binding(
            get: { appState.profile.foodPreferences[keyPath: keyPath] },
            set: { newValue in
                var updated = appState.profile
                updated.foodPreferences[keyPath: keyPath] = newValue
                appState.saveProfile(updated)
            }
        )
    }

    private var intolerancesBinding: Binding<[String]> {
        Binding(
            get: { appState.profile.effectiveIntolerances },
            set: { newValue in
                var updated = appState.profile
                let cleaned = newValue.reduced()
                updated.allergies = cleaned
                updated.foodPreferences.intolerances = cleaned
                appState.saveProfile(updated)
            }
        )
    }

    private var pantryBinding: Binding<[PantryItem]> {
        Binding(
            get: { appState.profile.foodPreferences.pantry },
            set: { newValue in
                var updated = appState.profile
                updated.foodPreferences.pantry = newValue
                appState.saveProfile(updated)
            }
        )
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
