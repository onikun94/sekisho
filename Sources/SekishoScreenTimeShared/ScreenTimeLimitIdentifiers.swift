import Foundation

enum ScreenTimeLimitIdentifiers {
    static let appGroupIdentifier = "group.com.onikun94.sekisho"
    static let legacyDailyActivityName = "sekisho.daily-screen-time"
    static let legacyUsageLimitEventName = "sekisho.target-usage-limit"
    static let usageLimitEventPrefix = "sekisho.target-usage-limit."
    static let usageProgressEventPrefix = "sekisho.usage-progress."
    static let individualLimitEventPrefix = "sekisho.individual-limit."
    static let individualProgressEventPrefix = "sekisho.individual-progress."
    static let usageProgressUpdateIntervalMinutes = 5
    static let managedSettingsStoreName = "sekisho.main"
    static let todayUsageReportContext = "sekisho.today-usage-report"

    static func activityName(for weekday: UsageWeekday) -> String {
        "sekisho.usage-limit.weekday-\(weekday.rawValue)"
    }

    static var allActivityNames: [String] {
        UsageWeekday.allCases.map(activityName(for:))
    }

    static func weekday(forActivityName activityName: String) -> UsageWeekday? {
        UsageWeekday.allCases.first { activityName == self.activityName(for: $0) }
    }

    static func usageLimitEventName(for registrationID: String) -> String {
        "\(usageLimitEventPrefix)\(registrationID)"
    }

    static func registrationID(forUsageLimitEventName eventName: String) -> String? {
        guard eventName.hasPrefix(usageLimitEventPrefix) else {
            return nil
        }

        let registrationID = String(eventName.dropFirst(usageLimitEventPrefix.count))
        return registrationID.isEmpty ? nil : registrationID
    }

    static func usageProgressEventName(
        for totalUsedMinutes: Int,
        registrationID: String
    ) -> String {
        "\(usageProgressEventPrefix)\(registrationID).\(totalUsedMinutes)"
    }

    static func usageProgressPayload(
        forEventName eventName: String
    ) -> (registrationID: String, usedMinutes: Int)? {
        guard eventName.hasPrefix(usageProgressEventPrefix) else {
            return nil
        }

        let payload = eventName.dropFirst(usageProgressEventPrefix.count)
        guard let separator = payload.lastIndex(of: "."),
              let usedMinutes = Int(payload[payload.index(after: separator)...])
        else {
            return nil
        }

        let registrationID = String(payload[..<separator])
        guard !registrationID.isEmpty else {
            return nil
        }

        return (registrationID, usedMinutes)
    }

    static func individualLimitEventName(
        registrationID: String,
        ruleID: String
    ) -> String {
        "\(individualLimitEventPrefix)\(registrationID).\(ruleID)"
    }

    static func individualLimitPayload(
        forEventName eventName: String
    ) -> (registrationID: String, ruleID: String)? {
        guard eventName.hasPrefix(individualLimitEventPrefix) else {
            return nil
        }

        let payload = eventName.dropFirst(individualLimitEventPrefix.count)
        let parts = payload.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }

        return (String(parts[0]), String(parts[1]))
    }

    static func individualProgressEventName(
        registrationID: String,
        ruleID: String,
        usedMinutes: Int
    ) -> String {
        "\(individualProgressEventPrefix)\(registrationID).\(ruleID).\(usedMinutes)"
    }

    static func individualProgressPayload(
        forEventName eventName: String
    ) -> (registrationID: String, ruleID: String, usedMinutes: Int)? {
        guard eventName.hasPrefix(individualProgressEventPrefix) else {
            return nil
        }

        let payload = eventName.dropFirst(individualProgressEventPrefix.count)
        let parts = payload.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              let usedMinutes = Int(parts[2])
        else {
            return nil
        }

        return (String(parts[0]), String(parts[1]), usedMinutes)
    }
}

enum UsageWeekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    static var displayOrder: [UsageWeekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    var shortTitle: String {
        switch self {
        case .monday: "月"
        case .tuesday: "火"
        case .wednesday: "水"
        case .thursday: "木"
        case .friday: "金"
        case .saturday: "土"
        case .sunday: "日"
        }
    }

    var title: String {
        "\(shortTitle)曜日"
    }

    static func current(for date: Date = Date(), calendar: Calendar = .current) -> UsageWeekday {
        UsageWeekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }
}

struct WeeklyUsageRules: Codable, Equatable {
    private var limitsByWeekday: [Int: Int]
    var strictModeEnabled: Bool

    init(defaultLimitMinutes: Int = 30, strictModeEnabled: Bool = false) {
        let limit = max(defaultLimitMinutes, 5)
        limitsByWeekday = Dictionary(
            uniqueKeysWithValues: UsageWeekday.allCases.map { ($0.rawValue, limit) }
        )
        self.strictModeEnabled = strictModeEnabled
    }

    func limit(for weekday: UsageWeekday) -> Int {
        max(limitsByWeekday[weekday.rawValue] ?? 30, 5)
    }

    mutating func setLimit(_ minutes: Int, for weekday: UsageWeekday) {
        limitsByWeekday[weekday.rawValue] = min(max(minutes, 5), 240)
    }

    mutating func setAllLimits(_ minutes: Int) {
        for weekday in UsageWeekday.allCases {
            setLimit(minutes, for: weekday)
        }
    }
}

enum WeeklyUsageRulesStore {
    private static let rulesKey = "weeklyUsageRules.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func load(defaultLimitMinutes: Int = 30) -> WeeklyUsageRules {
        guard let data = defaults.data(forKey: rulesKey),
              let rules = try? JSONDecoder().decode(WeeklyUsageRules.self, from: data)
        else {
            return WeeklyUsageRules(defaultLimitMinutes: defaultLimitMinutes)
        }

        return rules
    }

    static func save(_ rules: WeeklyUsageRules) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        defaults.set(data, forKey: rulesKey)
    }
}

struct IndividualTargetProgressState: Codable, Equatable {
    var thresholdMinutes: Int
    var latestConfirmedProgressMinutes: Int?
    var latestProgressAt: Date?
    var pendingLimitAt: Date?
}

struct UsageLimitMonitoringState: Codable, Equatable {
    var startedAt: Date
    var thresholdMinutes: Int
    /// Identifies one concrete DeviceActivity registration. Optional only so
    /// builds created before this field existed can be decoded and migrated.
    var registrationID: String?
    var latestConfirmedProgressMinutes: Int?
    var latestProgressAt: Date?
    var pendingLimitAt: Date?
    var individualTargetStates: [String: IndividualTargetProgressState]?
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

    static var hasCurrentRegistration: Bool {
        guard let registrationID = load()?.registrationID else {
            return false
        }

        return !registrationID.isEmpty
    }

    static func arm(
        thresholdMinutes: Int,
        startedAt: Date = Date(),
        registrationID: String? = nil,
        individualThresholds: [String: Int] = [:]
    ) {
        let state = UsageLimitMonitoringState(
            startedAt: startedAt,
            thresholdMinutes: max(thresholdMinutes, 1),
            registrationID: registrationID,
            latestConfirmedProgressMinutes: nil,
            latestProgressAt: nil,
            pendingLimitAt: nil,
            individualTargetStates: Dictionary(
                uniqueKeysWithValues: individualThresholds.map { ruleID, limitMinutes in
                    (
                        ruleID,
                        IndividualTargetProgressState(
                            thresholdMinutes: limitMinutes,
                            latestConfirmedProgressMinutes: nil,
                            latestProgressAt: nil,
                            pendingLimitAt: nil
                        )
                    )
                }
            )
        )

        save(state)
        defaults.removeObject(forKey: rejectedThresholdDateKey)
    }

    static func beginDailyInterval(
        thresholdMinutes: Int,
        at date: Date = Date()
    ) {
        guard var state = load() else {
            arm(
                thresholdMinutes: thresholdMinutes,
                startedAt: Calendar.current.startOfDay(for: date)
            )
            return
        }

        guard !Calendar.current.isDate(state.startedAt, inSameDayAs: date) else {
            return
        }

        state.startedAt = Calendar.current.startOfDay(for: date)
        state.thresholdMinutes = max(thresholdMinutes, 1)
        state.latestConfirmedProgressMinutes = nil
        state.latestProgressAt = nil
        state.pendingLimitAt = nil
        state.individualTargetStates = state.individualTargetStates?.mapValues { targetState in
            IndividualTargetProgressState(
                thresholdMinutes: targetState.thresholdMinutes,
                latestConfirmedProgressMinutes: nil,
                latestProgressAt: nil,
                pendingLimitAt: nil
            )
        }
        save(state)
    }

    static func isThresholdPlausible(
        thresholdMinutes: Int? = nil,
        at date: Date = Date()
    ) -> Bool {
        guard let state = load() else {
            return false
        }

        let minutes = thresholdMinutes ?? state.thresholdMinutes
        let minimumElapsedTime = TimeInterval(max(minutes, 1) * 60)
        return date.timeIntervalSince(state.startedAt) + 5 >= minimumElapsedTime
    }

    static func recordRejectedThreshold(at date: Date = Date()) {
        defaults.set(date, forKey: rejectedThresholdDateKey)
    }

    @discardableResult
    static func recordConfirmedProgress(
        _ usedMinutes: Int,
        registrationID: String,
        at date: Date = Date()
    ) -> Bool {
        guard var state = load(),
              state.registrationID == registrationID,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date)
        else {
            return false
        }

        state.latestConfirmedProgressMinutes = max(
            state.latestConfirmedProgressMinutes ?? 0,
            usedMinutes
        )
        state.latestProgressAt = date
        save(state)
        return true
    }

    static func hasConfirmedProgressBeforeLimit(
        thresholdMinutes: Int,
        registrationID: String,
        stepMinutes: Int,
        at date: Date = Date()
    ) -> Bool {
        guard let state = load(),
              state.registrationID == registrationID,
              state.thresholdMinutes == thresholdMinutes,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date)
        else {
            return false
        }

        let requiredProgress = max(thresholdMinutes - stepMinutes, 1)
        return (state.latestConfirmedProgressMinutes ?? 0) >= requiredProgress
    }

    static func markLimitPending(
        registrationID: String,
        at date: Date = Date()
    ) {
        guard var state = load(),
              state.registrationID == registrationID,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date)
        else {
            return
        }

        state.pendingLimitAt = date
        save(state)
    }

    static func hasPendingLimit(
        registrationID: String,
        at date: Date = Date()
    ) -> Bool {
        guard let state = load(),
              state.registrationID == registrationID,
              let pendingLimitAt = state.pendingLimitAt
        else {
            return false
        }

        return Calendar.current.isDate(pendingLimitAt, inSameDayAs: date)
    }

    static func clearPendingLimit(registrationID: String) {
        guard var state = load(), state.registrationID == registrationID else {
            return
        }

        state.pendingLimitAt = nil
        save(state)
    }

    @discardableResult
    static func recordConfirmedIndividualProgress(
        _ usedMinutes: Int,
        registrationID: String,
        ruleID: String,
        at date: Date = Date()
    ) -> Bool {
        guard var state = load(),
              state.registrationID == registrationID,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date),
              var targetState = state.individualTargetStates?[ruleID]
        else {
            return false
        }

        targetState.latestConfirmedProgressMinutes = max(
            targetState.latestConfirmedProgressMinutes ?? 0,
            usedMinutes
        )
        targetState.latestProgressAt = date
        state.individualTargetStates?[ruleID] = targetState
        save(state)
        return true
    }

    static func hasConfirmedIndividualProgressBeforeLimit(
        thresholdMinutes: Int,
        registrationID: String,
        ruleID: String,
        stepMinutes: Int,
        at date: Date = Date()
    ) -> Bool {
        guard let state = load(),
              state.registrationID == registrationID,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date),
              let targetState = state.individualTargetStates?[ruleID],
              targetState.thresholdMinutes == thresholdMinutes
        else {
            return false
        }

        let requiredProgress = max(thresholdMinutes - stepMinutes, 1)
        return (targetState.latestConfirmedProgressMinutes ?? 0) >= requiredProgress
    }

    static func markIndividualLimitPending(
        registrationID: String,
        ruleID: String,
        at date: Date = Date()
    ) {
        guard var state = load(),
              state.registrationID == registrationID,
              Calendar.current.isDate(state.startedAt, inSameDayAs: date),
              var targetState = state.individualTargetStates?[ruleID]
        else {
            return
        }

        targetState.pendingLimitAt = date
        state.individualTargetStates?[ruleID] = targetState
        save(state)
    }

    static func hasPendingIndividualLimit(
        registrationID: String,
        ruleID: String,
        at date: Date = Date()
    ) -> Bool {
        guard let state = load(),
              state.registrationID == registrationID,
              let pendingLimitAt = state.individualTargetStates?[ruleID]?.pendingLimitAt
        else {
            return false
        }

        return Calendar.current.isDate(pendingLimitAt, inSameDayAs: date)
    }

    static func clearPendingIndividualLimit(
        registrationID: String,
        ruleID: String
    ) {
        guard var state = load(),
              state.registrationID == registrationID,
              var targetState = state.individualTargetStates?[ruleID]
        else {
            return
        }

        targetState.pendingLimitAt = nil
        state.individualTargetStates?[ruleID] = targetState
        save(state)
    }

    static func clearAllPendingLimits(registrationID: String) {
        guard var state = load(), state.registrationID == registrationID else {
            return
        }

        state.pendingLimitAt = nil
        state.individualTargetStates = state.individualTargetStates?.mapValues { targetState in
            var clearedState = targetState
            clearedState.pendingLimitAt = nil
            return clearedState
        }
        save(state)
    }

    static var lastRejectedThresholdDate: Date? {
        defaults.object(forKey: rejectedThresholdDateKey) as? Date
    }

    static func clear() {
        defaults.removeObject(forKey: stateKey)
        defaults.removeObject(forKey: rejectedThresholdDateKey)
    }

    private static func save(_ state: UsageLimitMonitoringState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        defaults.set(data, forKey: stateKey)
        defaults.synchronize()
    }
}

enum ScreenTimeAuthorizationStateStore {
    private static let previouslyAuthorizedKey = "screenTimeAuthorization.previouslyAuthorized.v1"
    private static let previouslyDeniedKey = "screenTimeAuthorization.previouslyDenied.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static var hasPreviouslyAuthorized: Bool {
        defaults.bool(forKey: previouslyAuthorizedKey)
    }

    static var hasPreviouslyDenied: Bool {
        defaults.bool(forKey: previouslyDeniedKey)
    }

    static func markAuthorized() {
        defaults.set(true, forKey: previouslyAuthorizedKey)
        defaults.removeObject(forKey: previouslyDeniedKey)
    }

    static func markDenied() {
        defaults.removeObject(forKey: previouslyAuthorizedKey)
        defaults.set(true, forKey: previouslyDeniedKey)
    }
}

enum WeeklyGateLogStore {
    private static let closedDaysKey = "weeklyGateLog.closedDays.v1"
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func dayKey(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func recordGateClosed(on date: Date = Date()) {
        var days = Set(defaults.stringArray(forKey: closedDaysKey) ?? [])
        days.insert(dayKey(for: date))

        let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: date) ?? date
        let retainedDays = days.filter { $0 >= dayKey(for: cutoff) }.sorted()
        defaults.set(retainedDays, forKey: closedDaysKey)
    }

    static func recentClosedDayKeys(
        ending date: Date = Date(),
        dayCount: Int = 7
    ) -> Set<String> {
        let lowerBound = Calendar.current.date(
            byAdding: .day,
            value: -(max(dayCount, 1) - 1),
            to: date
        ) ?? date
        let allDays = Set(defaults.stringArray(forKey: closedDaysKey) ?? [])

        return Set(allDays.filter { $0 >= dayKey(for: lowerBound) && $0 <= dayKey(for: date) })
    }
}
