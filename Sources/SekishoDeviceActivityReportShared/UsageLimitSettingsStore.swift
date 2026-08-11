import Foundation

enum UsageLimitSettingsStore {
    private static let appGroupIdentifier = "group.com.onikun94.sekisho"
    private static let usageLimitMinutesKey = "usageLimitMinutes"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func load(defaultValue: Int = 30) -> Int {
        let value = defaults.integer(forKey: usageLimitMinutesKey)
        return value > 0 ? value : defaultValue
    }

    static func save(_ minutes: Int) {
        defaults.set(max(minutes, 1), forKey: usageLimitMinutesKey)
    }
}
