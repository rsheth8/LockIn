import SwiftUI
import FamilyControls

struct ScreenTimeSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var screenTimeManager: ScreenTimeManager
    @State private var showingPicker = false

    var body: some View {
        List {
            Section {
                if screenTimeManager.isAuthorized {
                    Label("Screen Time access granted", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Allow Screen Time Access") {
                        Task { await screenTimeManager.requestAuthorization() }
                    }
                }
            } footer: {
                Text("Required so LockIn can shield distracting apps during your workout and focus blocks, and catch you if you use them anyway.")
            }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    HStack {
                        Text("Distracting Apps")
                        Spacer()
                        Text("\(screenTimeManager.selection.applicationTokens.count + screenTimeManager.selection.categoryTokens.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!screenTimeManager.isAuthorized)
            } footer: {
                Text("These get shielded automatically during your workout window. Try to open one mid-workout and it stays blocked — and LockIn will know.")
            }

            Section("Accountability Tone") {
                Picker("Tone", selection: Binding(
                    get: { appState.profile.toneIntensity },
                    set: { newTone in
                        var updated = appState.profile
                        updated.toneIntensity = newTone
                        appState.saveProfile(updated)
                    }
                )) {
                    ForEach(ToneIntensity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Screen Time")
        .familyActivityPicker(isPresented: $showingPicker, selection: Binding(
            get: { screenTimeManager.selection },
            set: { screenTimeManager.saveSelection($0) }
        ))
    }
}
