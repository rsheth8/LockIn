import SwiftUI

/// Minimal MVP onboarding: collect the numbers MetabolicEngine/SleepEngine need,
/// then request Calendar/Health/Notifications permissions up front so the first
/// generated schedule is real, not a placeholder.
struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var profile = UserProfile.default
    @State private var step = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch step {
                case 0: basicsStep
                case 1: goalStep
                case 2: activityStep
                default: fitnessGoalStep
                }
                Spacer()
                Button(step < 3 ? "Continue" : "Lock In") {
                    if step < 3 { step += 1 } else { finish() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Set Up LockIn")
        }
    }

    private var basicsStep: some View {
        Form {
            Section("About you") {
                Stepper("Age: \(profile.age)", value: $profile.age, in: 13...90)
                Picker("Sex", selection: $profile.sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Height: \(Int(profile.heightInches))\"", value: $profile.heightInches, in: 48...84)
            }
        }
    }

    private var goalStep: some View {
        Form {
            Section("Weight goal") {
                Stepper("Current: \(Int(profile.currentWeightLbs)) lb", value: $profile.currentWeightLbs, in: 80...400)
                Stepper("Goal: \(Int(profile.goalWeightLbs)) lb", value: $profile.goalWeightLbs, in: 80...400)
            }
        }
    }

    private var activityStep: some View {
        Form {
            Section("Activity & tone") {
                Picker("Activity level", selection: $profile.activityLevel) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Accountability tone", selection: $profile.toneIntensity) {
                    ForEach(ToneIntensity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }

    private var fitnessGoalStep: some View {
        Form {
            Section(content: {
                ForEach(FitnessGoal.allCases.filter { $0 != .fatLoss }) { goal in
                    Toggle(goal.displayName, isOn: Binding(
                        get: { profile.fitnessGoals.contains(goal) },
                        set: { isOn in
                            if isOn { profile.fitnessGoals.insert(goal) } else { profile.fitnessGoals.remove(goal) }
                        }
                    ))
                }
            }, header: {
                Text("Train for")
            }, footer: {
                Text("Fat loss is always included. Your workout split adds bowling- or hiking-specific sessions on top based on what you pick here.")
            })
        }
    }

    private func finish() {
        profile.fitnessGoals.insert(.fatLoss)
        appState.saveProfile(profile)
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
        }
    }
}
