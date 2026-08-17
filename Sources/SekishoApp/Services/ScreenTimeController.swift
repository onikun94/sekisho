import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class ScreenTimeController {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeLimitIdentifiers.managedSettingsStoreName))
    // Keep removal protection in its own store. Shield refreshes call
    // `clearAllSettings()` frequently, and must never disable this separate,
    // explicitly selected commitment setting as a side effect.
    private let appRemovalProtectionStore = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("sekisho.app-removal-protection")
    )
    private let activityCenter = DeviceActivityCenter()

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    var isUsageLimitMonitoringActive: Bool {
        let activeNames = Set(activityCenter.activities.map(\.rawValue))
        return Set(ScreenTimeLimitIdentifiers.allActivityNames).isSubset(of: activeNames)
            && UsageLimitMonitoringStateStore.hasCurrentRegistration
    }

    var hasAnyUsageLimitMonitoringActivity: Bool {
        let recognizedNames = Set(
            ScreenTimeLimitIdentifiers.allActivityNames
                + [ScreenTimeLimitIdentifiers.legacyDailyActivityName]
        )
        return activityCenter.activities.contains { recognizedNames.contains($0.rawValue) }
    }

    var isAppRemovalProtectionEnabled: Bool {
        AppRemovalProtectionStateStore.isEnabled
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    /// Restores the user's explicit choice after launch. Apple's setting is
    /// device-wide: while enabled, the user cannot remove any installed app,
    /// not only Sekisho.
    func restoreAppRemovalProtection() {
        if isAppRemovalProtectionEnabled {
            appRemovalProtectionStore.application.denyAppRemoval = true
        } else {
            appRemovalProtectionStore.clearAllSettings()
        }
    }

    func setAppRemovalProtectionEnabled(_ isEnabled: Bool) {
        if isEnabled {
            appRemovalProtectionStore.application.denyAppRemoval = true
        } else {
            // This named store contains only removal protection, so clearing it
            // is the strongest way to avoid leaving a stale device-wide rule.
            appRemovalProtectionStore.clearAllSettings()
        }
        AppRemovalProtectionStateStore.save(isEnabled)
    }

    func applyShield(for selection: FamilyActivitySelection) throws {
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            throw ScreenTimeControllerError.emptySelection
        }

        // This store is dedicated to Sekisho shields. Clear the previous
        // scope first so changing from a combined lock to one individual app
        // cannot leave stale applications or categories restricted.
        store.clearAllSettings()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    func startUsageLimitMonitoring(
        for selection: FamilyActivitySelection,
        rules: WeeklyUsageRules,
        targetConfiguration: TargetUsageLimitConfiguration,
        includesPastActivity: Bool
    ) throws {
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            throw ScreenTimeControllerError.emptySelection
        }

        let today = UsageWeekday.current()
        let registrationID = UUID().uuidString.lowercased()
        let activeTargetConfiguration = targetConfiguration.normalized(
            for: selection,
            defaultLimitMinutes: rules.limit(for: today)
        )
        let isIndividualMode = activeTargetConfiguration.mode == .individual
            && !activeTargetConfiguration.rules.isEmpty
        let monitoringThreshold = isIndividualMode
            ? activeTargetConfiguration.minimumIndividualLimit ?? rules.limit(for: today)
            : rules.limit(for: today)
        UsageLimitMonitoringStateStore.arm(
            thresholdMinutes: monitoringThreshold,
            startedAt: includesPastActivity
                ? Calendar.current.startOfDay(for: .now)
                : .now,
            registrationID: registrationID,
            individualThresholds: isIndividualMode
                ? activeTargetConfiguration.rules.reduce(into: [String: Int]()) {
                    $0[$1.id] = $1.limitMinutes
                }
                : [:]
        )

        // `startMonitoring` can cause the extension to run immediately when
        // past activity is included. Publish the exact new target set first so
        // that callback can never shield or validate against the old selection.
        FamilyActivitySelectionStore.saveActive(selection)
        TargetUsageLimitConfigurationStore.saveActive(activeTargetConfiguration)

        do {
            activityCenter.stopMonitoring(Self.allUsageLimitActivityNames)

            for weekday in UsageWeekday.allCases {
                let events = isIndividualMode
                    ? makeIndividualUsageLimitEvents(
                        configuration: activeTargetConfiguration,
                        includesPastActivity: includesPastActivity,
                        registrationID: registrationID
                    )
                    : makeUsageLimitEvents(
                        for: selection,
                        thresholdMinutes: rules.limit(for: weekday),
                        includesPastActivity: includesPastActivity,
                        registrationID: registrationID
                    )

                try activityCenter.startMonitoring(
                    Self.activityName(for: weekday),
                    during: Self.schedule(for: weekday),
                    events: events
                )
            }
        } catch {
            activityCenter.stopMonitoring(Self.allUsageLimitActivityNames)
            FamilyActivitySelectionStore.clearActive()
            TargetUsageLimitConfigurationStore.clearActive()
            UsageLimitMonitoringStateStore.clear()
            throw error
        }
    }

    func clearShield() {
        store.clearAllSettings()
    }

    private static let allUsageLimitActivityNames =
        [DeviceActivityName(ScreenTimeLimitIdentifiers.legacyDailyActivityName)]
        + UsageWeekday.allCases.map(activityName(for:))

    private static func activityName(for weekday: UsageWeekday) -> DeviceActivityName {
        DeviceActivityName(ScreenTimeLimitIdentifiers.activityName(for: weekday))
    }

    private static func schedule(for weekday: UsageWeekday) -> DeviceActivitySchedule {
        let nextWeekday = weekday.rawValue == UsageWeekday.saturday.rawValue
            ? UsageWeekday.sunday.rawValue
            : weekday.rawValue + 1
        var intervalStart = DateComponents()
        intervalStart.weekday = weekday.rawValue
        intervalStart.hour = 0
        intervalStart.minute = 0

        var intervalEnd = DateComponents()
        intervalEnd.weekday = nextWeekday
        intervalEnd.hour = 0
        intervalEnd.minute = 0

        return DeviceActivitySchedule(
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            repeats: true
        )
    }

    private func makeUsageLimitEvents(
        for selection: FamilyActivitySelection,
        thresholdMinutes: Int,
        includesPastActivity: Bool,
        registrationID: String
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let threshold = max(thresholdMinutes, 1)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        if threshold <= ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes {
            let confirmationMinutes = 1
            let name = DeviceActivityEvent.Name(
                ScreenTimeLimitIdentifiers.usageProgressEventName(
                    for: confirmationMinutes,
                    registrationID: registrationID
                )
            )
            events[name] = makeUsageLimitEvent(
                for: selection,
                thresholdMinutes: confirmationMinutes,
                includesPastActivity: includesPastActivity
            )
        }

        for usedMinutes in stride(
            from: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes,
            to: threshold,
            by: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes
        ) {
            let name = DeviceActivityEvent.Name(
                ScreenTimeLimitIdentifiers.usageProgressEventName(
                    for: usedMinutes,
                    registrationID: registrationID
                )
            )
            events[name] = makeUsageLimitEvent(
                for: selection,
                thresholdMinutes: usedMinutes,
                includesPastActivity: includesPastActivity
            )
        }

        let limitEventName = DeviceActivityEvent.Name(
            ScreenTimeLimitIdentifiers.usageLimitEventName(for: registrationID)
        )
        events[limitEventName] = makeUsageLimitEvent(
            for: selection,
            thresholdMinutes: threshold,
            includesPastActivity: includesPastActivity
        )

        return events
    }

    private func makeIndividualUsageLimitEvents(
        configuration: TargetUsageLimitConfiguration,
        includesPastActivity: Bool,
        registrationID: String
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        for rule in configuration.rules {
            var selection = FamilyActivitySelection()
            rule.target.insert(into: &selection)
            let confirmationMinutes = max(
                rule.limitMinutes - ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes,
                1
            )

            let progressName = DeviceActivityEvent.Name(
                ScreenTimeLimitIdentifiers.individualProgressEventName(
                    registrationID: registrationID,
                    ruleID: rule.id,
                    usedMinutes: confirmationMinutes
                )
            )
            events[progressName] = makeUsageLimitEvent(
                for: selection,
                thresholdMinutes: confirmationMinutes,
                includesPastActivity: includesPastActivity
            )

            let limitName = DeviceActivityEvent.Name(
                ScreenTimeLimitIdentifiers.individualLimitEventName(
                    registrationID: registrationID,
                    ruleID: rule.id
                )
            )
            events[limitName] = makeUsageLimitEvent(
                for: selection,
                thresholdMinutes: rule.limitMinutes,
                includesPastActivity: includesPastActivity
            )
        }

        return events
    }

    private func makeUsageLimitEvent(
        for selection: FamilyActivitySelection,
        thresholdMinutes: Int,
        includesPastActivity: Bool
    ) -> DeviceActivityEvent {
        let threshold = max(thresholdMinutes, 1)

        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: threshold),
                includesPastActivity: includesPastActivity
            )
        }

        return DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: threshold)
        )
    }
}

private enum AppRemovalProtectionStateStore {
    private static let key = "appRemovalProtection.isEnabled.v1"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func save(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: key)
    }
}

enum ScreenTimeControllerError: LocalizedError {
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "先に制限する対象を選んでください。"
        }
    }
}
