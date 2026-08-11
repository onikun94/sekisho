import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeLimitIdentifiers.managedSettingsStoreName))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard activity.rawValue == ScreenTimeLimitIdentifiers.dailyActivityName else {
            return
        }

        UsageLimitMonitoringStateStore.beginDailyInterval()
        store.clearAllSettings()
        writeSnapshot(state: .passed)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard activity.rawValue == ScreenTimeLimitIdentifiers.dailyActivityName,
              event.rawValue == ScreenTimeLimitIdentifiers.usageLimitEventName
        else {
            return
        }

        guard UsageLimitMonitoringStateStore.isThresholdPlausible() else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        let selection = FamilyActivitySelectionStore.load()
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            return
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.webContent.blockedByFilter = .specific(DefaultBlockedWebDomains.youtube)
        writeSnapshot(state: .locked)
    }

    private func writeSnapshot(state: SharedBarrierState) {
        SharedShieldStore.writeSnapshot(
            ShieldSnapshot(
                barrierState: state,
                updatedAt: Date()
            )
        )
    }
}
