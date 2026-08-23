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
                default: activityStep
                }
                Spacer()
                Button(step < 2 ? "Continue" : "Lock In") {
                    if step < 2 { step += 1 } else { finish() }
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

    private func finish() {
        appState.saveProfile(profile)
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
        }
    }
}
