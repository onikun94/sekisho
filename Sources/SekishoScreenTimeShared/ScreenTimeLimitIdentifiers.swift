import Foundation

enum ScreenTimeLimitIdentifiers {
    static let appGroupIdentifier = "group.com.onikun94.sekisho"
    static let dailyActivityName = "sekisho.daily-screen-time"
    static let usageLimitEventName = "sekisho.target-usage-limit"
    static let managedSettingsStoreName = "sekisho.main"
    static let todayUsageReportContext = "sekisho.today-usage-report"
}

struct UsageLimitMonitoringState: Codable, Equatable {
    var startedAt: Date
    var thresholdMinutes: Int
}

enum UsageLimitMonitoringStateStore {
    private static let stateKey = "usageLimitMonitoringState.v1"
    private static let rejectedThresholdDateKey = "usageLimitRejectedThresholdDate.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func load() -> UsageLimitMonitoringState? {
        guard let data = defaults.data(forKey: stateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageLimitMonitoringState.self, from: data)
    }

    static func arm(thresholdMinutes: Int, startedAt: Date = Date()) {
        let state = UsageLimitMonitoringState(
            startedAt: startedAt,
            thresholdMinutes: max(thresholdMinutes, 1)
        )

        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        defaults.set(data, forKey: stateKey)
        defaults.removeObject(forKey: rejectedThresholdDateKey)
    }

    static func beginDailyInterval(at date: Date = Date()) {
        guard let state = load() else {
            return
        }

        guard !Calendar.current.isDate(state.startedAt, inSameDayAs: date) else {
            return
        }

        arm(
            thresholdMinutes: state.thresholdMinutes,
            startedAt: Calendar.current.startOfDay(for: date)
        )
    }

    static func isThresholdPlausible(at date: Date = Date()) -> Bool {
        guard let state = load() else {
            return false
        }

        let minimumElapsedTime = TimeInterval(state.thresholdMinutes * 60)
        return date.timeIntervalSince(state.startedAt) + 5 >= minimumElapsedTime
    }

    static func recordRejectedThreshold(at date: Date = Date()) {
        defaults.set(date, forKey: rejectedThresholdDateKey)
    }

    static var lastRejectedThresholdDate: Date? {
        defaults.object(forKey: rejectedThresholdDateKey) as? Date
    }

    static func clear() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: rejectedThresholdDateKey)
    }
}
