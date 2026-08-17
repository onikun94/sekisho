import FamilyControls
import Foundation
import ManagedSettings

enum UsageLimitMode: String, Codable, CaseIterable, Identifiable {
    case combined
    case individual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined:
            "合計時間"
        case .individual:
            "対象ごと"
        }
    }
}

enum UsageLimitTarget: Codable, Hashable {
    case application(ApplicationToken)
    case category(ActivityCategoryToken)
    case webDomain(WebDomainToken)

    var kindOrder: Int {
        switch self {
        case .application:
            0
        case .category:
            1
        case .webDomain:
            2
        }
    }

    func insert(into selection: inout FamilyActivitySelection) {
        switch self {
        case .application(let token):
            selection.applicationTokens.insert(token)
        case .category(let token):
            selection.categoryTokens.insert(token)
        case .webDomain(let token):
            selection.webDomainTokens.insert(token)
        }
    }
}

struct TargetUsageLimitRule: Codable, Hashable, Identifiable {
    let id: String
    let target: UsageLimitTarget
    var limitMinutes: Int

    init(
        id: String = UUID().uuidString.lowercased(),
        target: UsageLimitTarget,
        limitMinutes: Int
    ) {
        self.id = id
        self.target = target
        self.limitMinutes = Self.clamped(limitMinutes)
    }

    mutating func setLimit(_ minutes: Int) {
        limitMinutes = Self.clamped(minutes)
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, 5), 240)
    }
}

struct TargetUsageLimitConfiguration: Codable, Equatable {
    var mode: UsageLimitMode
    var defaultLimitMinutes: Int
    var rules: [TargetUsageLimitRule]

    init(
        mode: UsageLimitMode = .combined,
        defaultLimitMinutes: Int = 30,
        rules: [TargetUsageLimitRule] = []
    ) {
        self.mode = mode
        self.defaultLimitMinutes = min(max(defaultLimitMinutes, 5), 240)
        self.rules = rules
    }

    func normalized(
        for selection: FamilyActivitySelection,
        defaultLimitMinutes: Int? = nil
    ) -> TargetUsageLimitConfiguration {
        let fallbackLimit = min(
            max(defaultLimitMinutes ?? self.defaultLimitMinutes, 5),
            240
        )
        let selectedTargets = Self.targets(in: selection)
        let selectedSet = Set(selectedTargets)
        // Prefer the first persisted rule if older/corrupted data happens to
        // contain duplicates. Dictionary(uniqueKeysWithValues:) would trap and
        // make the settings screen impossible to recover from.
        let existingByTarget = rules.reduce(into: [UsageLimitTarget: TargetUsageLimitRule]()) {
            result, rule in
            if result[rule.target] == nil {
                result[rule.target] = rule
            }
        }

        var seenTargets = Set<UsageLimitTarget>()
        var retainedRules = rules.filter {
            selectedSet.contains($0.target) && seenTargets.insert($0.target).inserted
        }
        let retainedTargets = Set(retainedRules.map(\.target))

        for target in selectedTargets where !retainedTargets.contains(target) {
            retainedRules.append(
                existingByTarget[target]
                    ?? TargetUsageLimitRule(
                        target: target,
                        limitMinutes: fallbackLimit
                    )
            )
        }

        return TargetUsageLimitConfiguration(
            mode: mode,
            defaultLimitMinutes: fallbackLimit,
            rules: retainedRules
        )
    }

    func rule(id: String) -> TargetUsageLimitRule? {
        rules.first { $0.id == id }
    }

    func rule(for target: UsageLimitTarget) -> TargetUsageLimitRule? {
        rules.first { $0.target == target }
    }

    mutating func setLimit(_ minutes: Int, forRuleID ruleID: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else {
            return
        }

        rules[index].setLimit(minutes)
    }

    mutating func setDefaultLimit(_ minutes: Int) {
        defaultLimitMinutes = min(max(minutes, 5), 240)
    }

    var minimumIndividualLimit: Int? {
        rules.map(\.limitMinutes).min()
    }

    func selection(forRuleIDs ruleIDs: Set<String>) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()

        // Resolve one target per ID. Even if corrupted persisted data contains
        // duplicate IDs, one reached event must never broaden into multiple
        // shielded targets.
        for ruleID in ruleIDs {
            guard let rule = rule(id: ruleID) else {
                continue
            }
            rule.target.insert(into: &selection)
        }

        return selection
    }

    static func targets(in selection: FamilyActivitySelection) -> [UsageLimitTarget] {
        selection.applicationTokens.map(UsageLimitTarget.application)
            + selection.categoryTokens.map(UsageLimitTarget.category)
            + selection.webDomainTokens.map(UsageLimitTarget.webDomain)
    }
}

enum TargetUsageLimitConfigurationStore {
    private static let configuredKey = "targetUsageLimitConfiguration.configured.v1"
    private static let activeKey = "targetUsageLimitConfiguration.active.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func loadConfigured(
        selection: FamilyActivitySelection,
        defaultLimitMinutes: Int
    ) -> TargetUsageLimitConfiguration {
        let stored = load(forKey: configuredKey)
            ?? TargetUsageLimitConfiguration(defaultLimitMinutes: defaultLimitMinutes)
        return stored.normalized(
            for: selection,
            defaultLimitMinutes: defaultLimitMinutes
        )
    }

    static func loadActive() -> TargetUsageLimitConfiguration? {
        load(forKey: activeKey)
    }

    static func saveConfigured(_ configuration: TargetUsageLimitConfiguration) {
        save(configuration, forKey: configuredKey)
    }

    static func saveActive(_ configuration: TargetUsageLimitConfiguration) {
        save(configuration, forKey: activeKey)
    }

    static func clearActive() {
        defaults.removeObject(forKey: activeKey)
        defaults.synchronize()
    }

    private static func load(forKey key: String) -> TargetUsageLimitConfiguration? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(TargetUsageLimitConfiguration.self, from: data)
    }

    private static func save(
        _ configuration: TargetUsageLimitConfiguration,
        forKey key: String
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}

struct IndividualLimitDayState: Codable, Equatable {
    var dayStart: Date
    var lockedRuleIDs: Set<String>
}

enum IndividualLimitDayStateStore {
    private static let stateKey = "individualLimitDayState.v1"
    private static let exactShieldMigrationKey = "individualLimitDayState.exactShieldMigration.v3"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ScreenTimeLimitIdentifiers.appGroupIdentifier) ?? .standard
    }

    static func lockedRuleIDs(at date: Date = .now) -> Set<String> {
        guard let state = load(),
              Calendar.current.isDate(state.dayStart, inSameDayAs: date)
        else {
            return []
        }

        return state.lockedRuleIDs
    }

    /// Builds before the exact-target shield fix could persist every rule ID
    /// after only one individual target reached its limit. Clear that
    /// untrustworthy evidence once in the host app, then re-register today's
    /// events with past activity so genuinely overdue targets are locked again.
    @discardableResult
    static func migrateLegacyBroadLockIfNeeded(at date: Date = .now) -> Bool {
        defaults.synchronize()
        guard !defaults.bool(forKey: exactShieldMigrationKey) else {
            return false
        }

        clear(at: date)
        defaults.set(true, forKey: exactShieldMigrationKey)
        defaults.synchronize()
        return true
    }

    @discardableResult
    static func recordLocked(
        ruleID: String,
        at date: Date = .now
    ) -> Set<String> {
        var state = currentState(at: date)
        state.lockedRuleIDs.insert(ruleID)
        save(state)
        return state.lockedRuleIDs
    }

    static func recordAllLocked(
        ruleIDs: Set<String>,
        at date: Date = .now
    ) {
        save(
            IndividualLimitDayState(
                dayStart: Calendar.current.startOfDay(for: date),
                lockedRuleIDs: ruleIDs
            )
        )
    }

    static func beginDay(at date: Date = .now) {
        let state = currentState(at: date)
        save(state)
    }

    static func clear(at date: Date = .now) {
        save(
            IndividualLimitDayState(
                dayStart: Calendar.current.startOfDay(for: date),
                lockedRuleIDs: []
            )
        )
    }

    @discardableResult
    static func reconcile(
        validRuleIDs: Set<String>,
        at date: Date = .now
    ) -> Set<String> {
        var state = currentState(at: date)
        state.lockedRuleIDs.formIntersection(validRuleIDs)
        save(state)
        return state.lockedRuleIDs
    }

    private static func currentState(at date: Date) -> IndividualLimitDayState {
        if let state = load(),
           Calendar.current.isDate(state.dayStart, inSameDayAs: date) {
            return state
        }

        return IndividualLimitDayState(
            dayStart: Calendar.current.startOfDay(for: date),
            lockedRuleIDs: []
        )
    }

    private static func load() -> IndividualLimitDayState? {
        defaults.synchronize()
        guard let data = defaults.data(forKey: stateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(IndividualLimitDayState.self, from: data)
    }

    private static func save(_ state: IndividualLimitDayState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        defaults.set(data, forKey: stateKey)
        defaults.synchronize()
    }
}
