import Foundation
import HealthKit

/// Syncs body weight, workouts, active energy, and sleep with Health so
/// LockIn's numbers and Apple Watch/Health data stay in one place.
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()
    @Published var authorized = false

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
    }

    private var writeTypes: Set<HKSampleType> {
        [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.workoutType()
        ]
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            await MainActor.run { self.authorized = true }
        } catch {
            await MainActor.run { self.authorized = false }
        }
    }

    func logWeight(_ pounds: Double, date: Date = Date()) {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        store.save(sample) { _, _ in }
    }

    func latestWeight() async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .pound())
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
