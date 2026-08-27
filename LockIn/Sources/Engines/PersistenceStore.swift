import Foundation

/// Simple on-device JSON persistence via UserDefaults for the MVP.
/// Swap for SwiftData/Core Data once the schema stabilizes (weight history,
/// meal logs, and event confirmations will grow unbounded and want a real store).
final class PersistenceStore {
    static let shared = PersistenceStore()
    private let defaults = UserDefaults.standard

    private enum Key: String {
        case profile, schedule, streak, progressPhotos, dayRecords, loggedMeals, shoppingList
    }

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

    /// Off-plan meals. Small by construction — each entry is a name, a portion
    /// string and four numbers, with no image data — so these stay cheap to
    /// keep indefinitely alongside the rest of the JSON state.
    func saveLoggedMeals(_ meals: [LoggedMeal]) {
        save(meals, key: .loggedMeals)
    }

    func loadLoggedMeals() -> [LoggedMeal] {
        load([LoggedMeal].self, key: .loggedMeals) ?? []
    }

    /// The Shop Smart list. Survives relaunch by design — it's written at the
    /// kitchen table and read in the shop, which is a different session.
    func saveShoppingList(_ items: [ShoppingListItem]) {
        save(items, key: .shoppingList)
    }

    func loadShoppingList() -> [ShoppingListItem] {
        load([ShoppingListItem].self, key: .shoppingList) ?? []
    }

    func saveDayRecords(_ records: [DayRecord]) {
        save(records, key: .dayRecords)
    }

    func loadDayRecords() -> [DayRecord] {
        load([DayRecord].self, key: .dayRecords) ?? []
    }

    private func save<T: Encodable>(_ value: T, key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    private func load<T: Decodable>(_ type: T.Type, key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
