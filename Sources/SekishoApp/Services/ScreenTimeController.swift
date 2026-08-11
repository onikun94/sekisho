import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class ScreenTimeController {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeLimitIdentifiers.managedSettingsStoreName))
    private let activityCenter = DeviceActivityCenter()

    var authorizationStatus: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    var isUsageLimitMonitoringActive: Bool {
        activityCenter.activities.contains(Self.dailyActivityName)
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func applyShield(for selection: FamilyActivitySelection) throws {
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            throw ScreenTimeControllerError.emptySelection
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.webContent.blockedByFilter = .specific(DefaultBlockedWebDomains.youtube)
    }

    func startUsageLimitMonitoring(for selection: FamilyActivitySelection, thresholdMinutes: Int) throws {
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            throw ScreenTimeControllerError.emptySelection
        }

        let threshold = max(thresholdMinutes, 1)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let event: DeviceActivityEvent
        if #available(iOS 17.4, *) {
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: threshold),
                includesPastActivity: false
            )
        } else {
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: threshold)
            )
        }

        UsageLimitMonitoringStateStore.arm(thresholdMinutes: threshold)

        do {
            activityCenter.stopMonitoring([Self.dailyActivityName])
            store.clearAllSettings()
            try activityCenter.startMonitoring(
                Self.dailyActivityName,
                during: schedule,
                events: [Self.usageLimitEventName: event]
            )
        } catch {
            UsageLimitMonitoringStateStore.clear()
            throw error
        }
    }

    func clearShield() {
        store.clearAllSettings()
    }

    private static let dailyActivityName = DeviceActivityName(ScreenTimeLimitIdentifiers.dailyActivityName)
    private static let usageLimitEventName = DeviceActivityEvent.Name(ScreenTimeLimitIdentifiers.usageLimitEventName)
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
