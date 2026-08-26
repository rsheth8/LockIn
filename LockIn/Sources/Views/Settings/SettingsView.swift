import SwiftUI
import FamilyControls
import UserNotifications

/// Everything tunable in one ledger-styled list: who you are, how hard the app
/// pushes, how it looks, and what it guards during lock-in blocks.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Environment(\.accent) private var accent
    @State private var showingPicker = false
    @State private var confirmSignOut = false
    @State private var confirmErase = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var focusMessage: String?

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    accentSection
                    toneSection
                    connectionsSection
                    profileSection
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
            .pinnedHeader {
                ScreenHeader(title: "Settings", subtitle: "How the app treats you")
            }
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: Binding(
            get: { screenTimeManager.selection },
            set: { screenTimeManager.saveSelection($0) }
        ))
        .task { await refreshNotificationStatus() }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                accountManager.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your plan stays on this device. Sign back in to keep syncing with iCloud.")
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) {
                appState.eraseAllLocalData()
                accountManager.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes your profile, schedule, streak, and adherence history on this device. Progress photos in Files stay until you delete them.")
        }
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
                LedgerRule()
                row("Storage", "SwiftData on device")
            }
            Text(accountManager.isSignedIn
                 ? "Your plan syncs to your own private iCloud on every check-in. Progress photos stay on this device only."
                 : "Everything is stored on this device. Sign in to carry your plan to a new phone.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                if accountManager.isSignedIn {
                    confirmSignOut = true
                } else {
                    accountManager.signOut()
                }
            } label: {
                Text(accountManager.isSignedIn ? "Sign out" : "Set up an account")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.signal)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                confirmErase = true
            } label: {
                Text("Erase all data")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.signal)
                    .padding(.vertical, 4)
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
                permissionRow(
                    label: "Calendar",
                    status: calendarManager.authorized ? "Live · writes to Lock In" : "Off",
                    isOn: calendarManager.authorized
                ) {
                    Task { await calendarManager.requestAccess() }
                }
                LedgerRule()
                permissionRow(
                    label: "Reminders",
                    status: calendarManager.remindersAuthorized ? "Due today on the timeline" : "Off",
                    isOn: calendarManager.remindersAuthorized
                ) {
                    Task { await calendarManager.requestAccess() }
                }
                LedgerRule()
                permissionRow(
                    label: "Health",
                    status: healthKitManager.authorized ? "Weight sync on" : "Off",
                    isOn: healthKitManager.authorized
                ) {
                    Task { await healthKitManager.requestAccess() }
                }
                LedgerRule()
                permissionRow(
                    label: "Notifications",
                    status: notificationLabel,
                    isOn: notificationStatus == .authorized || notificationStatus == .provisional
                ) {
                    Task {
                        _ = await NotificationManager.shared.requestAuthorization()
                        await refreshNotificationStatus()
                    }
                }
            }
            Text("Add or move something in Calendar and today's meals and workout shift around it. Denied access can be fixed here — or in iOS Settings → Lock In.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notificationLabel: String {
        switch notificationStatus {
        case .authorized, .provisional: return "On"
        case .denied: return "Off — open iOS Settings"
        default: return "Not asked"
        }
    }

    private func permissionRow(label: String, status: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkMuted)
                Text(status)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.ink : Theme.signal)
            }
            Spacer()
            if !isOn {
                Button("Enable", action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.color)
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11)
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run { notificationStatus = status }
    }

    // MARK: - Profile body / diet / equipment

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your body & setup").ledgerLabel()
            VStack(spacing: 0) {
                stepperRow("Age", value: Int(appState.profile.age), range: 16...80) { age in
                    mutateProfile { $0.age = age }
                }
                LedgerRule()
                stepperRow("Height (in)", value: Int(appState.profile.heightInches), range: 54...84) { inches in
                    mutateProfile { $0.heightInches = Double(inches) }
                }
                LedgerRule()
                stepperRow("Weight (lb)", value: Int(appState.profile.currentWeightLbs), range: 90...400) { lbs in
                    mutateProfile { $0.currentWeightLbs = Double(lbs) }
                }
                LedgerRule()
                stepperRow("Goal (lb)", value: Int(appState.profile.goalWeightLbs), range: 90...400) { lbs in
                    mutateProfile { $0.goalWeightLbs = Double(lbs) }
                }
                LedgerRule()
                pickerRow("Sex", selection: Binding(
                    get: { appState.profile.sex },
                    set: { sex in mutateProfile { $0.sex = sex } }
                )) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                }
                LedgerRule()
                pickerRow("Activity", selection: Binding(
                    get: { appState.profile.activityLevel },
                    set: { level in mutateProfile { $0.activityLevel = level } }
                )) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                LedgerRule()
                pickerRow("Diet", selection: Binding(
                    get: { appState.profile.dietaryPattern },
                    set: { diet in mutateProfile { $0.dietaryPattern = diet } }
                )) {
                    ForEach(DietaryPattern.allCases) { diet in
                        Text(diet.displayName).tag(diet)
                    }
                }
                LedgerRule()
                stepperRow("Meals / day", value: appState.profile.mealsPerDay, range: 3...5) { meals in
                    mutateProfile { $0.mealsPerDay = meals }
                }
            }

            Text("Equipment").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            ChipFlow {
                ForEach(Equipment.allCases, id: \.self) { item in
                    IngredientChip(
                        title: item.displayName,
                        selected: appState.profile.equipment.contains(item),
                        accent: accent
                    ) {
                        Haptics.tap()
                        mutateProfile { profile in
                            if let idx = profile.equipment.firstIndex(of: item) {
                                if profile.equipment.count > 1 { profile.equipment.remove(at: idx) }
                            } else {
                                profile.equipment.append(item)
                            }
                            if profile.gymAssets.isEmpty, let first = profile.equipment.first {
                                profile.gymAssets = first.defaultAssets
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Kit in the room").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            ChipFlow {
                ForEach(GymAsset.allCases) { asset in
                    IngredientChip(
                        title: asset.displayName,
                        selected: appState.profile.gymAssets.contains(asset),
                        accent: accent
                    ) {
                        Haptics.tap()
                        mutateProfile { profile in
                            if profile.gymAssets.contains(asset) {
                                profile.gymAssets.remove(asset)
                            } else {
                                profile.gymAssets.insert(asset)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Changing weight, diet, meals, equipment, or kit rebuilds today's plan.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mutateProfile(_ body: (inout UserProfile) -> Void) {
        var updated = appState.profile
        body(&updated)
        appState.saveProfile(updated)
    }

    private func stepperRow(_ label: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Stepper(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range) {
                Text("\(value)")
                    .font(Theme.mono(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }

    private func pickerRow<T: Hashable>(_ label: String, selection: Binding<T>, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Picker(label, selection: selection, content: content)
                .labelsHidden()
                .tint(Theme.ink)
        }
        .padding(.vertical, 8)
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

            if !appState.profile.likedRecipes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your menu").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    ForEach(appState.profile.likedRecipes.prefix(20)) { recipe in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                if let cal = recipe.calories {
                                    Text("\(Int(cal)) kcal")
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                            Spacer()
                            Button {
                                Haptics.tap()
                                appState.removeLiked(id: recipe.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.signal)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        LedgerRule()
                    }
                    Text("Saved from Today — swaps prefer these first.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.top, 8)
            }
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

                Button {
                    Haptics.tap()
                    if screenTimeManager.startFocusBlock(minutes: 45) != nil {
                        focusMessage = "45-minute focus block is live."
                    } else {
                        focusMessage = "Pick at least one guarded app or category first."
                    }
                } label: {
                    Text("Start 45-min focus lock-in")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if let focusMessage {
                    Text(focusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(accent.color)
                }

                Text("Guarded apps are shielded during your workout window and any focus block you start. Open one anyway and it costs the streak.")
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

                Text("Lets LockIn shield distracting apps during workouts and focus blocks. Requires Apple to approve the Family Controls entitlement on your developer account.")
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
    /// Development only — stripped from release builds. Prefer the Lab tab
    /// for full scenario coverage; these are quick shortcuts.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug").ledgerLabel()
            Text("Use the Lab tab for personas, calendar fixtures, overdue days, and flow jumps.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
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
