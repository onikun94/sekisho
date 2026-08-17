import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import WidgetKit

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeLimitIdentifiers.managedSettingsStoreName))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard let weekday = ScreenTimeLimitIdentifiers.weekday(forActivityName: activity.rawValue) else {
            return
        }

        // Each weekday owns a separate repeating activity. A delayed callback
        // from yesterday must never lock today's targets.
        guard weekday == UsageWeekday.current() else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        let rules = WeeklyUsageRulesStore.load()
        let selection = FamilyActivitySelectionStore.loadActive()
            ?? FamilyActivitySelectionStore.load()
        let targetConfiguration = (TargetUsageLimitConfigurationStore.loadActive()
            ?? TargetUsageLimitConfigurationStore.loadConfigured(
                selection: selection,
                defaultLimitMinutes: rules.limit(for: weekday)
            )).normalized(
                for: selection,
                defaultLimitMinutes: rules.limit(for: weekday)
            )
        let isIndividualMode = targetConfiguration.mode == .individual
            && !targetConfiguration.rules.isEmpty
        let limitMinutes = isIndividualMode
            ? targetConfiguration.minimumIndividualLimit ?? rules.limit(for: weekday)
            : rules.limit(for: weekday)
        let existingSnapshot = SharedShieldStore.readSnapshot()
        UsageLimitMonitoringStateStore.beginDailyInterval(
            thresholdMinutes: limitMinutes
        )
        IndividualLimitDayStateStore.beginDay()

        // Re-registering DeviceActivity schedules can invoke intervalDidStart
        // again during the same day. Preserve an already-enforced lock in that
        // case; only a genuinely new day is allowed to clear it.
        let lockedRuleIDs = IndividualLimitDayStateStore.reconcile(
            validRuleIDs: Set(targetConfiguration.rules.map(\.id))
        )
        let shouldPreserveIndividualLock = isIndividualMode && !lockedRuleIDs.isEmpty
        let shouldPreserveCombinedLock = !isIndividualMode && existingSnapshot.isLockedToday()
        if shouldPreserveIndividualLock {
            applyShield(
                for: targetConfiguration.selection(forRuleIDs: lockedRuleIDs)
            )
        } else if shouldPreserveCombinedLock {
            applyShield(for: selection)
        } else {
            store.clearAllSettings()
        }

        writeSnapshot(
            state: shouldPreserveIndividualLock || shouldPreserveCombinedLock
                ? .locked
                : .passed,
            usageLimitMinutes: limitMinutes,
            lockScope: isIndividualMode ? .individual : .combined
        )
        reloadWidget()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard let weekday = ScreenTimeLimitIdentifiers.weekday(forActivityName: activity.rawValue) else {
            return
        }

        // The seven schedules reuse across weeks, but only today's weekday is
        // allowed to change today's gate. Ignore a delayed event from another
        // weekday before looking at its threshold.
        guard weekday == UsageWeekday.current() else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        let rules = WeeklyUsageRulesStore.load()
        let selection = FamilyActivitySelectionStore.loadActive()
            ?? FamilyActivitySelectionStore.load()
        let targetConfiguration = (TargetUsageLimitConfigurationStore.loadActive()
            ?? TargetUsageLimitConfigurationStore.loadConfigured(
                selection: selection,
                defaultLimitMinutes: rules.limit(for: weekday)
            )).normalized(
                for: selection,
                defaultLimitMinutes: rules.limit(for: weekday)
            )

        if targetConfiguration.mode == .individual,
           !targetConfiguration.rules.isEmpty {
            handleIndividualEvent(
                event,
                configuration: targetConfiguration
            )
            return
        }

        let limitMinutes = rules.limit(for: weekday)

        if let progress = ScreenTimeLimitIdentifiers.usageProgressPayload(
            forEventName: event.rawValue
        ) {
            guard UsageLimitMonitoringStateStore.load()?.registrationID == progress.registrationID else {
                UsageLimitMonitoringStateStore.recordRejectedThreshold()
                return
            }

            guard UsageLimitMonitoringStateStore.isThresholdPlausible(
                thresholdMinutes: progress.usedMinutes
            ) else {
                return
            }

            guard UsageLimitMonitoringStateStore.recordConfirmedProgress(
                progress.usedMinutes,
                registrationID: progress.registrationID
            ) else {
                return
            }

            recordUsageProgress(
                usedMinutes: progress.usedMinutes,
                limitMinutes: limitMinutes
            )

            if UsageLimitMonitoringStateStore.hasPendingLimit(
                registrationID: progress.registrationID
            ), UsageLimitMonitoringStateStore.hasConfirmedProgressBeforeLimit(
                thresholdMinutes: limitMinutes,
                registrationID: progress.registrationID,
                stepMinutes: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes
            ) {
                enforceLimit(
                    registrationID: progress.registrationID,
                    limitMinutes: limitMinutes
                )
            }
            return
        }

        guard let registrationID = ScreenTimeLimitIdentifiers.registrationID(
            forUsageLimitEventName: event.rawValue
        ), UsageLimitMonitoringStateStore.load()?.registrationID == registrationID else {
            if event.rawValue == ScreenTimeLimitIdentifiers.legacyUsageLimitEventName {
                UsageLimitMonitoringStateStore.recordRejectedThreshold()
            }
            return
        }

        // iOS 26 can occasionally deliver a newly registered event
        // immediately. Selected-app usage cannot exceed the wall-clock time
        // elapsed since a fresh (non-past) monitor was armed, so reject that
        // impossible transition instead of locking unrelated apps by mistake.
        guard UsageLimitMonitoringStateStore.isThresholdPlausible(
            thresholdMinutes: limitMinutes
        ) else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        guard UsageLimitMonitoringStateStore.hasConfirmedProgressBeforeLimit(
            thresholdMinutes: limitMinutes,
            registrationID: registrationID,
            stepMinutes: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes
        ) else {
            // When iOS delivers callbacks out of order, retain the limit event
            // and let the final progress callback confirm it. If that progress
            // never arrives, failing open is safer than blocking after 1 minute.
            UsageLimitMonitoringStateStore.markLimitPending(
                registrationID: registrationID
            )
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        enforceLimit(
            registrationID: registrationID,
            limitMinutes: limitMinutes
        )
    }

    private func enforceLimit(
        registrationID: String,
        limitMinutes: Int
    ) {
        UsageLimitMonitoringStateStore.clearPendingLimit(
            registrationID: registrationID
        )

        let selection = FamilyActivitySelectionStore.loadActive()
            ?? FamilyActivitySelectionStore.load()
        let activeConfiguration = TargetUsageLimitConfigurationStore.loadActive()

        // A delayed combined-mode event must never broaden an individual-mode
        // lock. Configuration changes re-register events, but iOS can still
        // deliver an old callback while that replacement is settling.
        guard activeConfiguration?.mode != .individual else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            return
        }

        // Make the state visible to the host app and shield UI before applying
        // ManagedSettings, so every surface observes the same transition.
        WeeklyGateLogStore.recordGateClosed()
        SekishoWidgetSnapshotStore.recordUsageProgress(usedMinutes: limitMinutes)
        writeSnapshot(state: .locked)

        applyShield(for: selection)
        reloadWidget()
    }

    private func handleIndividualEvent(
        _ event: DeviceActivityEvent.Name,
        configuration: TargetUsageLimitConfiguration
    ) {
        if let progress = ScreenTimeLimitIdentifiers.individualProgressPayload(
            forEventName: event.rawValue
        ) {
            guard UsageLimitMonitoringStateStore.load()?.registrationID == progress.registrationID,
                  let rule = configuration.rule(id: progress.ruleID),
                  progress.usedMinutes < rule.limitMinutes
            else {
                UsageLimitMonitoringStateStore.recordRejectedThreshold()
                return
            }

            guard UsageLimitMonitoringStateStore.isThresholdPlausible(
                thresholdMinutes: progress.usedMinutes
            ) else {
                return
            }

            guard UsageLimitMonitoringStateStore.recordConfirmedIndividualProgress(
                progress.usedMinutes,
                registrationID: progress.registrationID,
                ruleID: progress.ruleID
            ) else {
                return
            }

            SekishoWidgetSnapshotStore.recordIndividualProgress(
                usedMinutes: progress.usedMinutes,
                limitMinutes: rule.limitMinutes,
                lockedTargetCount: IndividualLimitDayStateStore.lockedRuleIDs().count
            )
            reloadWidget()

            if UsageLimitMonitoringStateStore.hasPendingIndividualLimit(
                registrationID: progress.registrationID,
                ruleID: progress.ruleID
            ), UsageLimitMonitoringStateStore.hasConfirmedIndividualProgressBeforeLimit(
                thresholdMinutes: rule.limitMinutes,
                registrationID: progress.registrationID,
                ruleID: progress.ruleID,
                stepMinutes: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes
            ) {
                enforceIndividualLimit(
                    registrationID: progress.registrationID,
                    rule: rule,
                    configuration: configuration
                )
            }
            return
        }

        guard let payload = ScreenTimeLimitIdentifiers.individualLimitPayload(
            forEventName: event.rawValue
        ), UsageLimitMonitoringStateStore.load()?.registrationID == payload.registrationID,
           let rule = configuration.rule(id: payload.ruleID)
        else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        guard UsageLimitMonitoringStateStore.isThresholdPlausible(
            thresholdMinutes: rule.limitMinutes
        ) else {
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        guard UsageLimitMonitoringStateStore.hasConfirmedIndividualProgressBeforeLimit(
            thresholdMinutes: rule.limitMinutes,
            registrationID: payload.registrationID,
            ruleID: payload.ruleID,
            stepMinutes: ScreenTimeLimitIdentifiers.usageProgressUpdateIntervalMinutes
        ) else {
            UsageLimitMonitoringStateStore.markIndividualLimitPending(
                registrationID: payload.registrationID,
                ruleID: payload.ruleID
            )
            UsageLimitMonitoringStateStore.recordRejectedThreshold()
            return
        }

        enforceIndividualLimit(
            registrationID: payload.registrationID,
            rule: rule,
            configuration: configuration
        )
    }

    private func enforceIndividualLimit(
        registrationID: String,
        rule: TargetUsageLimitRule,
        configuration: TargetUsageLimitConfiguration
    ) {
        UsageLimitMonitoringStateStore.clearPendingIndividualLimit(
            registrationID: registrationID,
            ruleID: rule.id
        )

        let lockedRuleIDs = IndividualLimitDayStateStore.recordLocked(
            ruleID: rule.id
        )
        let lockedSelection = configuration.selection(forRuleIDs: lockedRuleIDs)
        guard !lockedSelection.applicationTokens.isEmpty
                || !lockedSelection.categoryTokens.isEmpty
                || !lockedSelection.webDomainTokens.isEmpty
        else {
            return
        }

        WeeklyGateLogStore.recordGateClosed()
        SekishoWidgetSnapshotStore.recordIndividualProgress(
            usedMinutes: rule.limitMinutes,
            limitMinutes: rule.limitMinutes,
            lockedTargetCount: lockedRuleIDs.count
        )
        writeSnapshot(state: .locked, lockScope: .individual)
        applyShield(for: lockedSelection)
        reloadWidget()
    }

    private func applyShield(for selection: FamilyActivitySelection) {
        guard !selection.applicationTokens.isEmpty ||
              !selection.categoryTokens.isEmpty ||
              !selection.webDomainTokens.isEmpty
        else {
            return
        }

        store.clearAllSettings()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    private func recordUsageProgress(
        usedMinutes: Int,
        limitMinutes: Int
    ) {
        guard usedMinutes > 0, usedMinutes < limitMinutes else {
            return
        }

        SekishoWidgetSnapshotStore.recordUsageProgress(usedMinutes: usedMinutes)
        reloadWidget()
    }

    private func writeSnapshot(
        state: SharedBarrierState,
        usageLimitMinutes: Int? = nil,
        lockScope: ShieldLockScope = .combined
    ) {
        SharedShieldStore.writeSnapshot(
            ShieldSnapshot(
                barrierState: state,
                updatedAt: Date(),
                lockScope: lockScope
            )
        )

        if let usageLimitMinutes {
            SekishoWidgetSnapshotStore.beginDailyInterval(
                usageLimitMinutes: usageLimitMinutes,
                barrierState: state
            )
        } else {
            SekishoWidgetSnapshotStore.updateBarrierState(state)
        }
        SekishoWidgetSnapshotStore.updateLimitMode(
            rawValue: lockScope.rawValue,
            lockedTargetCount: IndividualLimitDayStateStore.lockedRuleIDs().count
        )
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "SekishoWidget")
    }
}
