import Foundation
import SwiftData

/// Keyed JSON blob held in SwiftData. Keeps Codable domain models
/// (`UserProfile`, `DaySchedule`, …) as the schema while history can grow.
@Model
final class StoredPayload {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date

    init(key: String, data: Data) {
        self.key = key
        self.data = data
        self.updatedAt = .now
    }
}

/// On-device persistence. Values live in SwiftData as keyed JSON blobs.
/// First launch after upgrade migrates any leftover UserDefaults payloads once.
///
/// Main-actor confined because it owns a single long-lived `ModelContext`,
/// which is not thread-safe. Every caller is already on the main actor (the
/// state object, the photo store, SwiftUI actions); saying so in the type
/// makes that a checked guarantee rather than a coincidence that a future
/// background save would silently break.
@MainActor
final class PersistenceStore {
    static let shared = PersistenceStore()

    private let defaults = UserDefaults.standard
    private var context: ModelContext?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key: String, CaseIterable {
        case profile, schedule, streak, progressPhotos, dayRecords
    }

    init() {
        do {
            let schema = Schema([StoredPayload.self])
            // Under `xcodebuild test` the store is in-memory and thrown away
            // with the process. The suite exercises real save/load paths and
            // clears the store between cases, which against the on-disk store
            // would delete the profile, streak and adherence history of whoever
            // is running the tests on that simulator or device.
            let isTesting = RuntimeEnvironment.isRunningUnitTests
            let configuration = ModelConfiguration(
                "LockInStore",
                schema: schema,
                isStoredInMemoryOnly: isTesting,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
            if !isTesting { migrateFromUserDefaultsIfNeeded() }
        } catch {
            // Fall back to UserDefaults-only if the store can't open — better a
            // working MVP than a crash on launch.
            context = nil
        }
    }

    // MARK: - Public API

    func saveProfile(_ profile: UserProfile) {
        save(profile, key: .profile)
    }

    func loadProfile() -> UserProfile? {
        load(UserProfile.self, key: .profile)
    }

    func saveSchedule(_ schedule: DaySchedule) {
        save(schedule, key: .schedule)
    }

    func loadSchedule() -> DaySchedule? {
        load(DaySchedule.self, key: .schedule)
    }

    func saveStreak(_ streak: StreakStatus) {
        save(streak, key: .streak)
    }

    func loadStreak() -> StreakStatus? {
        load(StreakStatus.self, key: .streak)
    }

    func saveProgressPhotos(_ photos: [ProgressPhoto]) {
        save(photos, key: .progressPhotos)
    }

    func loadProgressPhotos() -> [ProgressPhoto] {
        load([ProgressPhoto].self, key: .progressPhotos) ?? []
    }

    func saveDayRecords(_ records: [DayRecord]) {
        save(records, key: .dayRecords)
    }

    func loadDayRecords() -> [DayRecord] {
        load([DayRecord].self, key: .dayRecords) ?? []
    }

    /// Wipes every persisted blob (profile, schedule, streak, photos metadata,
    /// day records). Used by Settings → Erase all data.
    func clearAll() {
        for key in Key.allCases {
            delete(key: key)
            // The in-memory test store has no UserDefaults side, and wiping the
            // real one there would take the developer's own data with it.
            if !RuntimeEnvironment.isRunningUnitTests {
                defaults.removeObject(forKey: key.rawValue)
            }
        }
    }

    // MARK: - Internals

    private func save<T: Encodable>(_ value: T, key: Key) {
        guard let data = try? encoder.encode(value) else { return }
        if let context {
            if let existing = fetchPayload(key: key, in: context) {
                existing.data = data
                existing.updatedAt = .now
            } else {
                context.insert(StoredPayload(key: key.rawValue, data: data))
            }
            try? context.save()
        } else {
            defaults.set(data, forKey: key.rawValue)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: Key) -> T? {
        if let context, let payload = fetchPayload(key: key, in: context) {
            return try? decoder.decode(type, from: payload.data)
        }
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func delete(key: Key) {
        guard let context, let payload = fetchPayload(key: key, in: context) else { return }
        context.delete(payload)
        try? context.save()
    }

    private func fetchPayload(key: Key, in context: ModelContext) -> StoredPayload? {
        let raw = key.rawValue
        var descriptor = FetchDescriptor<StoredPayload>(
            predicate: #Predicate { $0.key == raw }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// One-shot move of any UserDefaults JSON into SwiftData, then clear the
    /// old keys so we don't keep two sources of truth.
    private func migrateFromUserDefaultsIfNeeded() {
        guard let context else { return }
        let flag = "persistence.migratedToSwiftData.v1"
        guard !defaults.bool(forKey: flag) else { return }

        for key in Key.allCases {
            guard let data = defaults.data(forKey: key.rawValue) else { continue }
            if fetchPayload(key: key, in: context) == nil {
                context.insert(StoredPayload(key: key.rawValue, data: data))
            }
            defaults.removeObject(forKey: key.rawValue)
        }
        try? context.save()
        defaults.set(true, forKey: flag)
    }
}
