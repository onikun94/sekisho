import FamilyControls
import Foundation

enum FamilyActivitySelectionStore {
    private static let key = "familyActivitySelection"
    private static let activeKey = "activeFamilyActivitySelection.v1"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func load() -> FamilyActivitySelection {
        load(forKey: key) ?? FamilyActivitySelection()
    }

    /// The immutable target set captured when DeviceActivity monitoring starts.
    /// The monitor, report and shield must all use this same snapshot.
    static func loadActive() -> FamilyActivitySelection? {
        load(forKey: activeKey)
    }

    static func save(_ selection: FamilyActivitySelection) {
        save(selection, forKey: key)
    }

    static func saveActive(_ selection: FamilyActivitySelection) {
        save(selection, forKey: activeKey)
    }

    static func clearActive() {
        defaults.removeObject(forKey: activeKey)
        defaults.synchronize()
    }

    private static func load(forKey key: String) -> FamilyActivitySelection? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private static func save(_ selection: FamilyActivitySelection, forKey key: String) {
        guard let data = try? JSONEncoder().encode(selection) else {
            return
        }

        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
