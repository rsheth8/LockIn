import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                if let schedule = appState.todaySchedule {
                    Section("Today's Macros") {
                        MacroSummaryRow(macros: schedule.macros)
                    }
                    Section("Timeline") {
                        ForEach(schedule.events) { event in
                            EventRow(event: event)
                        }
                    }
                } else {
                    ProgressView("Building today's plan…")
                }
            }
            .navigationTitle("LockIn")
        }
    }
}

private struct MacroSummaryRow: View {
    let macros: MacroTargets
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(macros.calories) kcal").font(.headline)
                Text("P\(macros.proteinGrams) · F\(macros.fatGrams) · C\(macros.carbGrams)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(macros.deficitPercent * 100))% deficit")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct EventRow: View {
    let event: ScheduledEvent
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.semibold))
                Text(event.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.time, style: .time).font(.caption.monospacedDigit())
        }
        .opacity(event.status == .missed ? 0.5 : 1)
    }
}
