import Foundation
import CloudKit

/// Syncs the profile and adherence history to the signed-in user's **private**
/// CloudKit database.
///
/// Private database means: the data lives in that person's own iCloud account,
/// Apple can't read it, we operate no server, and two people using this app
/// have no shared storage between them. Progress photos are deliberately
/// excluded — they stay on-device only (see ProgressPhotoStore), because
/// syncing body photos off the device is a materially different privacy
/// decision than syncing a weight number, and it should be opt-in if ever.
actor CloudSyncEngine {
    static let shared = CloudSyncEngine()

    private let container = CKContainer(identifier: "iCloud.com.rahilsheth.lockin")
    private var database: CKDatabase { container.privateCloudDatabase }

    private enum RecordType {
        static let profile = "UserProfile"
        static let dayRecord = "DayRecord"
        static let streak = "StreakStatus"
    }

    /// Whether the device has a usable iCloud account. Sync silently no-ops
    /// when it doesn't — being signed out of iCloud must never block the app.
    func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: - Profile

    func pushProfile(_ profile: UserProfile) async {
        guard await isAvailable() else { return }
        guard let payload = try? JSONEncoder().encode(profile) else { return }

        let recordID = CKRecord.ID(recordName: "profile-\(profile.id.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: RecordType.profile, recordID: recordID)
        }
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await database.save(record)
    }

    func fetchProfile(id: UUID) async -> UserProfile? {
        guard await isAvailable() else { return nil }
        let recordID = CKRecord.ID(recordName: "profile-\(id.uuidString)")
        guard let record = try? await database.record(for: recordID),
              let payload = record["payload"] as? Data,
              let profile = try? JSONDecoder().decode(UserProfile.self, from: payload)
        else { return nil }
        return profile
    }

    /// Finds any profile already stored for this Apple user — the "I reinstalled
    /// / got a new phone" path, so they don't have to redo the quiz.
    func fetchProfileForCurrentUser() async -> UserProfile? {
        guard await isAvailable() else { return nil }
        let query = CKQuery(recordType: RecordType.profile, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        guard let result = try? await database.records(matching: query, resultsLimit: 1),
              let first = result.matchResults.first,
              let record = try? first.1.get(),
              let payload = record["payload"] as? Data,
              let profile = try? JSONDecoder().decode(UserProfile.self, from: payload)
        else { return nil }
        return profile
    }

    // MARK: - Adherence history

    func pushDayRecords(_ records: [DayRecord], profileID: UUID) async {
        guard await isAvailable(), !records.isEmpty else { return }
        guard let payload = try? JSONEncoder().encode(records) else { return }

        let recordID = CKRecord.ID(recordName: "days-\(profileID.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: RecordType.dayRecord, recordID: recordID)
        }
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await database.save(record)
    }

    func fetchDayRecords(profileID: UUID) async -> [DayRecord] {
        guard await isAvailable() else { return [] }
        let recordID = CKRecord.ID(recordName: "days-\(profileID.uuidString)")
        guard let record = try? await database.record(for: recordID),
              let payload = record["payload"] as? Data,
              let records = try? JSONDecoder().decode([DayRecord].self, from: payload)
        else { return [] }
        return records
    }

    // MARK: - Streak

    func pushStreak(_ streak: StreakStatus, profileID: UUID) async {
        guard await isAvailable() else { return }
        guard let payload = try? JSONEncoder().encode(streak) else { return }

        let recordID = CKRecord.ID(recordName: "streak-\(profileID.uuidString)")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: RecordType.streak, recordID: recordID)
        }
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await database.save(record)
    }
}
