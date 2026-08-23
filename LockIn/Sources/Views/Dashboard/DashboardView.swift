import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                if let schedule = appState.todaySchedule {
                    Section {
                        StreakHeaderRow(streak: appState.streak)
                    }
                    Section("Today's Macros") {
                        MacroSummaryRow(macros: schedule.macros)
                    }
                    Section("Timeline") {
                        ForEach(schedule.events) { event in
                            EventRow(event: event)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        appState.confirm(event)
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .leading) {
                                    Button(role: .destructive) {
                                        appState.markMissed(event)
                                    } label: {
                                        Label("Missed", systemImage: "xmark")
                                    }
                                }
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

private struct StreakHeaderRow: View {
    let streak: StreakStatus
    var body: some View {
        HStack {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(streak.currentStreakDays)-day streak")
                .font(.headline)
            Spacer()
            Text("Best: \(streak.longestStreakDays)")
                .font(.caption).foregroundStyle(.secondary)
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
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.semibold))
                Text(event.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.time, style: .time).font(.caption.monospacedDigit())
        }
        .opacity(event.status == .missed ? 0.5 : 1)
    }

    private var statusIcon: some View {
        Group {
            switch event.status {
            case .confirmed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .missed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .pending, .snoozed:
                Image(systemName: event.isCritical ? "circle" : "circle.dashed")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.top, 2)
    }
}
