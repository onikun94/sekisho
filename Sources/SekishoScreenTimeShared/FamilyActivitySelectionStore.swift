import FamilyControls
import Foundation

enum FamilyActivitySelectionStore {
    private static let key = "familyActivitySelection"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SekishoShared.appGroupIdentifier) ?? .standard
    }

    static func load() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection()
        }

        return selection
    }

    static func save(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
