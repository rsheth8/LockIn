import Foundation

/// Pulls the latest bodyweight from HealthKit and, when it's meaningfully newer
/// than what's on the profile, updates `currentWeightLbs` and appends to
/// `weightHistory`. MetabolicEngine reads `currentWeightLbs` directly, so this
/// is what keeps calorie/protein targets honest as you actually lose weight —
/// recalculating off a stale 220 for the whole cut would overshoot the deficit
/// as you approach 180.
enum WeightSyncEngine {
    /// Only re-sync once every `minHoursBetweenSyncs` so we're not hammering
    /// HealthKit on every launch, and so one noisy same-day reading doesn't
    /// whipsaw the day's targets.
    static func shouldSync(profile: UserProfile, minHoursBetweenSyncs: Double = 20) -> Bool {
        guard let last = profile.weightHistory.last else { return true }
        return Date().timeIntervalSince(last.date) > minHoursBetweenSyncs * 3600
    }

    /// Returns an updated profile if HealthKit had a newer weight reading, else nil.
    static func sync(profile: UserProfile, healthKit: HealthKitManager) async -> UserProfile? {
        guard let latest = await healthKit.latestWeight() else { return nil }

        // Ignore obviously bad readings (fat-finger entries, sensor noise) —
        // a >15lb single-reading jump is treated as an outlier, not truth.
        if let last = profile.weightHistory.last, abs(latest - last.weightLbs) > 15 {
            return nil
        }

        var updated = profile
        updated.currentWeightLbs = latest
        updated.weightHistory.append(WeightEntry(date: Date(), weightLbs: latest))
        return updated
    }
}
