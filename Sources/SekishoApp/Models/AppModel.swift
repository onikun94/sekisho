import FamilyControls
import Foundation
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var authorizationStatus: AuthorizationStatus
    @Published var selectedApps: FamilyActivitySelection {
        didSet {
            FamilyActivitySelectionStore.save(selectedApps)
            syncWidgetSnapshot()
        }
    }
    @Published var barrierState: BarrierState {
        didSet {
            if !isRestoringBarrierState {
                syncShieldSnapshot()
            }
            syncWidgetSnapshot()
        }
    }
    @Published var focusDurationMinutes: Int = 25
    @Published var usageLimitMinutes: Int {
        didSet {
            guard !isSynchronizingUsageLimit else {
                return
            }

            updateUsageLimit(usageLimitMinutes, for: .current())
        }
    }
    @Published private(set) var weeklyUsageRules: WeeklyUsageRules {
        didSet {
            syncWidgetSnapshot()
        }
    }
    @Published private(set) var targetLimitConfiguration: TargetUsageLimitConfiguration {
        didSet {
            syncWidgetSnapshot()
        }
    }
    @Published var isUsageLimitMonitoringEnabled = false {
        didSet {
            syncWidgetSnapshot()
        }
    }
    @Published private(set) var lastRejectedThresholdDate: Date?
    @Published private(set) var recentClosedGateDayKeys: Set<String>
    @Published private(set) var lockedIndividualTargetCount: Int
    @Published private(set) var isAppRemovalProtectionEnabled: Bool
    @Published var isFocusSessionPresented = false
    @Published var lastErrorMessage: String?

    let screenTimeController = ScreenTimeController()
    private var isSynchronizingUsageLimit = false
    private var isRestoringAuthorization = false
    private var hasAttemptedAuthorizationRestore = false
    private var isRestoringBarrierState = false

    init() {
        // The previous TestFlight build could store an all-target individual
        // lock. Discard that evidence once before restoring ManagedSettings,
        // then re-evaluate today's real target usage after initialization.
        let shouldRepairIndividualMonitoring =
            IndividualLimitDayStateStore.migrateLegacyBroadLockIfNeeded()

        let isMonitoringActive = screenTimeController.isUsageLimitMonitoringActive
        let shieldSnapshot = SharedShieldStore.readSnapshot()
        let legacyUsageLimit = UsageLimitSettingsStore.load()
        let storedRules = WeeklyUsageRulesStore.load(defaultLimitMinutes: legacyUsageLimit)
        let configuredSelection = FamilyActivitySelectionStore.load()
        let activeSelection = FamilyActivitySelectionStore.loadActive()
        let currentSelection = isMonitoringActive
            ? activeSelection ?? configuredSelection
            : configuredSelection
        let configuredTargetLimits = TargetUsageLimitConfigurationStore.loadConfigured(
            selection: configuredSelection,
            defaultLimitMinutes: storedRules.limit(for: .current())
        )
        let activeTargetLimits = TargetUsageLimitConfigurationStore.loadActive()
        let currentTargetLimits = (isMonitoringActive
            ? activeTargetLimits ?? configuredTargetLimits
            : configuredTargetLimits).normalized(
                for: currentSelection,
                defaultLimitMinutes: storedRules.limit(for: .current())
            )
        let currentLockedRuleIDs = IndividualLimitDayStateStore.reconcile(
            validRuleIDs: Set(currentTargetLimits.rules.map(\.id))
        )

        authorizationStatus = screenTimeController.authorizationStatus
        selectedApps = currentSelection
        weeklyUsageRules = storedRules
        targetLimitConfiguration = currentTargetLimits
        usageLimitMinutes = storedRules.limit(for: .current())
        isUsageLimitMonitoringEnabled = isMonitoringActive
        barrierState = Self.restoredBarrierState(
            from: shieldSnapshot,
            configuration: currentTargetLimits,
            lockedRuleIDs: currentLockedRuleIDs
        )
        lastRejectedThresholdDate = UsageLimitMonitoringStateStore.lastRejectedThresholdDate
        recentClosedGateDayKeys = WeeklyGateLogStore.recentClosedDayKeys()
        lockedIndividualTargetCount = currentLockedRuleIDs.count
        isAppRemovalProtectionEnabled = screenTimeController.isAppRemovalProtectionEnabled
        UsageLimitSettingsStore.save(usageLimitMinutes)
        TargetUsageLimitConfigurationStore.saveConfigured(currentTargetLimits)

        if authorizationStatus == .denied {
            screenTimeController.setAppRemovalProtectionEnabled(false)
            isAppRemovalProtectionEnabled = false
        } else {
            screenTimeController.restoreAppRemovalProtection()
        }

        if isUsageLimitMonitoringEnabled, activeSelection == nil {
            FamilyActivitySelectionStore.saveActive(selectedApps)
        }
        if isUsageLimitMonitoringEnabled, activeTargetLimits == nil {
            TargetUsageLimitConfigurationStore.saveActive(currentTargetLimits)
        }

        if isUsageLimitMonitoringEnabled, UsageLimitMonitoringStateStore.load() == nil {
            UsageLimitMonitoringStateStore.beginDailyInterval(
                thresholdMinutes: storedRules.limit(for: .current())
            )
        } else if isScreenTimeAuthorized, selectedTokenCount > 0, !isUsageLimitMonitoringEnabled {
            do {
                try startUsageLimitMonitoringOnController(
                    includesPastActivity: screenTimeController.hasAnyUsageLimitMonitoringActivity
                )
                isUsageLimitMonitoringEnabled = true
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        reconcileManagedShieldWithCurrentState()

        if shouldRepairIndividualMonitoring,
           isUsageLimitMonitoringEnabled,
           targetLimitConfiguration.mode == .individual,
           !targetLimitConfiguration.rules.isEmpty {
            do {
                // The old lock evidence was intentionally removed. Re-arm the
                // exact per-target events with today's past activity so an app
                // that is already over its limit is restricted again instead
                // of remaining open until tomorrow.
                try startUsageLimitMonitoringOnController(includesPastActivity: true)
                isUsageLimitMonitoringEnabled = true
            } catch {
                isUsageLimitMonitoringEnabled = screenTimeController.isUsageLimitMonitoringActive
                lastErrorMessage = error.localizedDescription
            }
        }

        syncWidgetSnapshot()
    }

    var selectedTokenCount: Int {
        selectedApps.applicationTokens.count + selectedApps.categoryTokens.count + selectedApps.webDomainTokens.count
    }

    var monitoredApps: FamilyActivitySelection {
        guard isUsageLimitMonitoringEnabled else {
            return selectedApps
        }

        return FamilyActivitySelectionStore.loadActive() ?? selectedApps
    }

    var isScreenTimeAuthorized: Bool {
        if authorizationStatus == .approved {
            return true
        }

        if #available(iOS 26.4, *), authorizationStatus == .approvedWithDataAccess {
            return true
        }

        // AuthorizationCenter resets its published value to `.notDetermined`
        // for each process. An existing registered DeviceActivity schedule plus
        // our successful-authorization marker is enough to restore UI state
        // without reopening the system authorization flow on every launch.
        return authorizationStatus == .notDetermined
            && ScreenTimeAuthorizationStateStore.hasPreviouslyAuthorized
            && screenTimeController.hasAnyUsageLimitMonitoringActivity
    }

    var strictModeEnabled: Bool {
        weeklyUsageRules.strictModeEnabled
    }

    var isIndividualLimitMode: Bool {
        targetLimitConfiguration.mode == .individual
    }

    var targetUsageLimitRules: [TargetUsageLimitRule] {
        targetLimitConfiguration.rules
    }

    var hasPartialIndividualLimit: Bool {
        isIndividualLimitMode
            && barrierState == .locked
            && lockedIndividualTargetCount > 0
            && lockedIndividualTargetCount < targetUsageLimitRules.count
    }

    var isEveryMonitoredTargetLimited: Bool {
        guard barrierState == .locked else {
            return false
        }

        guard isIndividualLimitMode else {
            return true
        }

        return !targetUsageLimitRules.isEmpty
            && lockedIndividualTargetCount >= targetUsageLimitRules.count
    }

    func isIndividualTargetLimited(ruleID: String) -> Bool {
        IndividualLimitDayStateStore.lockedRuleIDs().contains(ruleID)
    }

    var displayUsageLimitMinutes: Int {
        if isIndividualLimitMode {
            return targetLimitConfiguration.minimumIndividualLimit
                ?? weeklyUsageRules.limit(for: .current())
        }

        return weeklyUsageRules.limit(for: .current())
    }

    var isDailyConfigurationLocked: Bool {
        isUsageLimitMonitoringEnabled && selectedTokenCount > 0
    }

    var areRuleChangesLockedToday: Bool {
        strictModeEnabled && isDailyConfigurationLocked
    }

    var areTargetsLockedToday: Bool {
        isDailyConfigurationLocked
    }

    func usageLimit(for weekday: UsageWeekday) -> Int {
        weeklyUsageRules.limit(for: weekday)
    }

    func canIncreaseUsageLimit(for weekday: UsageWeekday) -> Bool {
        if weekday == .current(), isDailyConfigurationLocked {
            return false
        }

        return !areRuleChangesLockedToday
    }

    func requestScreenTimeAuthorization() async {
        hasAttemptedAuthorizationRestore = true

        do {
            try await screenTimeController.requestAuthorization()
            authorizationStatus = screenTimeController.authorizationStatus
            updateStoredAuthorizationState()

            if isScreenTimeAuthorized {
                screenTimeController.restoreAppRemovalProtection()
                isAppRemovalProtectionEnabled = screenTimeController.isAppRemovalProtectionEnabled
                ensureUsageLimitMonitoring()
            }
        } catch {
            authorizationStatus = screenTimeController.authorizationStatus
            updateStoredAuthorizationState()
            if !isScreenTimeAuthorized {
                ScreenTimeAuthorizationStateStore.markDenied()
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    /// `AuthorizationCenter` starts each new app process as `.notDetermined`.
    /// Re-requesting after a successful individual authorization only restores that
    /// status; iOS does not show the authorization sheet again.
    func restoreScreenTimeAuthorizationIfNeeded() async {
        guard !isRestoringAuthorization else {
            return
        }

        if isScreenTimeAuthorized {
            screenTimeController.restoreAppRemovalProtection()
            isAppRemovalProtectionEnabled = screenTimeController.isAppRemovalProtectionEnabled
            ensureUsageLimitMonitoring()
            return
        }

        if authorizationStatus == .denied {
            updateStoredAuthorizationState()
            return
        }

        guard !hasAttemptedAuthorizationRestore else {
            return
        }

        guard !ScreenTimeAuthorizationStateStore.hasPreviouslyDenied,
              ScreenTimeAuthorizationStateStore.hasPreviouslyAuthorized
                || selectedTokenCount > 0
        else {
            return
        }

        isRestoringAuthorization = true
        hasAttemptedAuthorizationRestore = true
        defer { isRestoringAuthorization = false }

        do {
            try await screenTimeController.requestAuthorization()
            authorizationStatus = screenTimeController.authorizationStatus
            updateStoredAuthorizationState()

            if isScreenTimeAuthorized {
                screenTimeController.restoreAppRemovalProtection()
                isAppRemovalProtectionEnabled = screenTimeController.isAppRemovalProtectionEnabled
                ensureUsageLimitMonitoring()
            }
        } catch {
            authorizationStatus = screenTimeController.authorizationStatus
            updateStoredAuthorizationState()
            if !isScreenTimeAuthorized {
                // A cancellation or transient failure must not reopen the
                // system authorization flow on every subsequent app launch.
                // The Settings button remains available for an explicit retry.
                ScreenTimeAuthorizationStateStore.markDenied()
            }
        }
    }

    func updateSelectedApps(_ selection: FamilyActivitySelection) {
        applySelectedApps(selection, allowsLockedOverride: false)
    }

    private func applySelectedApps(
        _ selection: FamilyActivitySelection,
        allowsLockedOverride: Bool
    ) {
        guard selection != selectedApps else {
            return
        }

        if areTargetsLockedToday, !allowsLockedOverride {
            lastErrorMessage = "見守りを開始した後は、制限する対象を変更できません。"
            return
        }

        let newTokenCount = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count

        if isUsageLimitMonitoringEnabled, selectedTokenCount > 0, newTokenCount == 0 {
            lastErrorMessage = "見守り中は、制限する対象を0件にはできません。"
            return
        }

        let previousSelection = selectedApps
        let previousTargetConfiguration = targetLimitConfiguration
        selectedApps = selection
        targetLimitConfiguration = targetLimitConfiguration.normalized(
            for: selection,
            defaultLimitMinutes: usageLimit(for: .current())
        )
        TargetUsageLimitConfigurationStore.saveConfigured(targetLimitConfiguration)

        // Once monitoring begins, only the explicit developer-menu override
        // can reach this branch. Never recreate a schedule merely because the
        // app becomes active.
        if isUsageLimitMonitoringEnabled {
            let didRestart = restartUsageLimitMonitoringForConfigurationChange()
            if !didRestart {
                // Registration is not atomic. If iOS rejects a replacement
                // schedule, keep every surface on the last successfully
                // registered target set instead of showing an unenforced edit.
                selectedApps = FamilyActivitySelectionStore.loadActive()
                    ?? previousSelection
                targetLimitConfiguration = TargetUsageLimitConfigurationStore.loadActive()
                    ?? previousTargetConfiguration
                TargetUsageLimitConfigurationStore.saveConfigured(targetLimitConfiguration)
            }
        }
    }

    func updateEverydayUsageLimit(_ minutes: Int) {
        applyEverydayUsageLimit(minutes, allowsLockedOverride: false)
    }

    private func applyEverydayUsageLimit(
        _ minutes: Int,
        allowsLockedOverride: Bool
    ) {
        let currentLimit = usageLimit(for: .current())
        guard allowsLockedOverride || canChangeTodayLimit(from: currentLimit, to: minutes) else {
            synchronizeTodayUsageLimit()
            return
        }

        var rules = weeklyUsageRules
        rules.setAllLimits(minutes)
        var targetConfiguration = targetLimitConfiguration
        targetConfiguration.setDefaultLimit(minutes)
        saveTargetLimitConfiguration(
            targetConfiguration,
            restartingMonitoring: false
        )
        saveRules(rules, restartingMonitoring: true)
    }

    func setUsageLimitMode(_ mode: UsageLimitMode) {
        applyUsageLimitMode(mode, allowsLockedOverride: false)
    }

    private func applyUsageLimitMode(
        _ mode: UsageLimitMode,
        allowsLockedOverride: Bool
    ) {
        guard targetLimitConfiguration.mode != mode else {
            return
        }

        guard allowsLockedOverride || !isDailyConfigurationLocked else {
            lastErrorMessage = "見守りを開始した後は、通常の設定画面から制限方法を変更できません。"
            return
        }

        var configuration = targetLimitConfiguration
        configuration.mode = mode
        saveTargetLimitConfiguration(configuration, restartingMonitoring: true)
    }

    func updateTargetUsageLimit(ruleID: String, minutes: Int) {
        applyTargetUsageLimit(
            ruleID: ruleID,
            minutes: minutes,
            allowsLockedOverride: false
        )
    }

    private func applyTargetUsageLimit(
        ruleID: String,
        minutes: Int,
        allowsLockedOverride: Bool
    ) {
        guard let currentRule = targetLimitConfiguration.rule(id: ruleID),
              currentRule.limitMinutes != minutes
        else {
            return
        }

        guard allowsLockedOverride || !isDailyConfigurationLocked else {
            lastErrorMessage = "見守りを開始した後は、通常の設定画面から個別の上限を変更できません。"
            return
        }

        var configuration = targetLimitConfiguration
        configuration.setLimit(minutes, forRuleID: ruleID)
        saveTargetLimitConfiguration(configuration, restartingMonitoring: true)
    }

    func updateUsageLimit(_ minutes: Int, for weekday: UsageWeekday) {
        let currentLimit = usageLimit(for: weekday)
        guard currentLimit != minutes else {
            synchronizeTodayUsageLimit()
            return
        }

        if weekday == .current(), !canChangeTodayLimit(from: currentLimit, to: minutes) {
            synchronizeTodayUsageLimit()
            return
        }

        if areRuleChangesLockedToday, minutes > currentLimit {
            lastErrorMessage = "厳格モード中は、曜日別の上限を増やせません。上限を下げる変更はできます。"
            synchronizeTodayUsageLimit()
            return
        }

        var rules = weeklyUsageRules
        rules.setLimit(minutes, for: weekday)
        saveRules(rules, restartingMonitoring: true)
    }

    func setStrictModeEnabled(_ isEnabled: Bool) {
        applyStrictModeEnabled(isEnabled, allowsLockedOverride: false)
    }

    func setAppRemovalProtectionEnabled(_ isEnabled: Bool) {
        // Enabling requires authorization, but disabling must always remain
        // available as an escape hatch if authorization state drifts.
        guard !isEnabled || isScreenTimeAuthorized else {
            lastErrorMessage = "先にScreen Timeの利用を許可してください。"
            return
        }

        guard isAppRemovalProtectionEnabled != isEnabled else {
            return
        }

        screenTimeController.setAppRemovalProtectionEnabled(isEnabled)
        isAppRemovalProtectionEnabled = isEnabled
    }

    private func applyStrictModeEnabled(
        _ isEnabled: Bool,
        allowsLockedOverride: Bool
    ) {
        guard weeklyUsageRules.strictModeEnabled != isEnabled else {
            return
        }

        guard allowsLockedOverride || !isDailyConfigurationLocked else {
            lastErrorMessage = "見守りを開始した後は、通常の設定画面から厳格モードを変更できません。"
            return
        }

        var rules = weeklyUsageRules
        rules.strictModeEnabled = isEnabled
        saveRules(rules, restartingMonitoring: false)
    }

    func closeBarrier() {
        if isIndividualLimitMode {
            reconcileManagedShieldWithCurrentState()
            return
        }

        do {
            try screenTimeController.applyShield(for: monitoredApps)
            barrierState = .locked
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    #if DEBUG || INTERNAL_TESTING
    /// Replaces the active target snapshot only from the explicit developer
    /// menu flow. Normal settings always go through the production lock.
    func debugUpdateSelectedApps(_ selection: FamilyActivitySelection) {
        applySelectedApps(selection, allowsLockedOverride: true)
    }

    /// Re-arms monitoring with a different limit only from the explicit
    /// developer menu flow.
    func debugUpdateEverydayUsageLimit(_ minutes: Int) {
        applyEverydayUsageLimit(minutes, allowsLockedOverride: true)
    }

    func debugSetUsageLimitMode(_ mode: UsageLimitMode) {
        applyUsageLimitMode(mode, allowsLockedOverride: true)
    }

    func debugUpdateTargetUsageLimit(ruleID: String, minutes: Int) {
        applyTargetUsageLimit(
            ruleID: ruleID,
            minutes: minutes,
            allowsLockedOverride: true
        )
    }

    func debugUpdateUsageLimit(_ minutes: Int, for weekday: UsageWeekday) {
        var rules = weeklyUsageRules
        rules.setLimit(minutes, for: weekday)
        saveRules(rules, restartingMonitoring: true)
    }

    func debugSetStrictModeEnabled(_ isEnabled: Bool) {
        applyStrictModeEnabled(isEnabled, allowsLockedOverride: true)
    }

    /// Clears both the system shield and the shared UI state without changing
    /// the production monitoring schedule. The threshold event has already
    /// fired when this is used, so the selected targets remain open for the
    /// rest of the current interval unless monitoring is explicitly restarted.
    func debugUnlockToday() {
        screenTimeController.clearShield()
        IndividualLimitDayStateStore.clear()
        lockedIndividualTargetCount = 0
        if let registrationID = UsageLimitMonitoringStateStore.load()?.registrationID {
            UsageLimitMonitoringStateStore.clearAllPendingLimits(
                registrationID: registrationID
            )
        }
        barrierState = .passed
        lastErrorMessage = nil
    }

    /// Applies the real ManagedSettings shield to the active target snapshot so
    /// the complete limited-state UI can be verified without waiting all day.
    func debugForceLimitNow() {
        guard !isIndividualLimitMode else {
            lastErrorMessage = "個別モードでは、制限する対象を1件選んでください。"
            return
        }

        do {
            try screenTimeController.applyShield(for: monitoredApps)
            barrierState = .locked
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Forces one concrete individual target to its limited state. Existing
    /// legitimately limited targets remain shielded, but unrelated targets are
    /// never added by this developer command.
    func debugForceIndividualLimitNow(ruleID: String) {
        guard isIndividualLimitMode,
              targetLimitConfiguration.rule(id: ruleID) != nil
        else {
            lastErrorMessage = "制限する対象を確認できませんでした。"
            return
        }

        let lockedRuleIDs = IndividualLimitDayStateStore.recordLocked(ruleID: ruleID)
        let lockedSelection = targetLimitConfiguration.selection(forRuleIDs: lockedRuleIDs)

        do {
            try screenTimeController.applyShield(for: lockedSelection)
            lockedIndividualTargetCount = lockedRuleIDs.count
            barrierState = .locked
            lastErrorMessage = nil
        } catch {
            IndividualLimitDayStateStore.reconcile(
                validRuleIDs: lockedRuleIDs.subtracting([ruleID])
            )
            lockedIndividualTargetCount = IndividualLimitDayStateStore.lockedRuleIDs().count
            lastErrorMessage = error.localizedDescription
        }
    }
    #endif

    func ensureUsageLimitMonitoring() {
        guard isScreenTimeAuthorized, selectedTokenCount > 0 else {
            return
        }

        let isActuallyMonitoring = screenTimeController.isUsageLimitMonitoringActive
        let isRepairingExistingMonitoring = screenTimeController.hasAnyUsageLimitMonitoringActivity
        if isUsageLimitMonitoringEnabled != isActuallyMonitoring {
            isUsageLimitMonitoringEnabled = isActuallyMonitoring
        }

        // DeviceActivity keeps counting while the app is closed. Stopping and
        // recreating an existing schedule here would start a new measurement
        // window, so an app launch must only restore state, never re-arm it.
        guard !isActuallyMonitoring else {
            return
        }

        do {
            try startUsageLimitMonitoringOnController(
                includesPastActivity: isRepairingExistingMonitoring
            )
            isUsageLimitMonitoringEnabled = true
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startFocusSession() {
        barrierState = .inFocus
        isFocusSessionPresented = true
    }

    func completeFocusSession() {
        barrierState = .passed
        isFocusSessionPresented = false
    }

    func markFocusInterrupted() {
        // `.locked` is reserved for a real ManagedSettings shield. A focus
        // interruption must not make Home claim that selected apps are blocked.
        barrierState = .passed
        isFocusSessionPresented = false
    }

    func refreshUsageLimitState() {
        isUsageLimitMonitoringEnabled = screenTimeController.isUsageLimitMonitoringActive
        lastRejectedThresholdDate = UsageLimitMonitoringStateStore.lastRejectedThresholdDate
        recentClosedGateDayKeys = WeeklyGateLogStore.recentClosedDayKeys()
        synchronizeTodayUsageLimit()

        if isUsageLimitMonitoringEnabled,
           let activeSelection = FamilyActivitySelectionStore.loadActive(),
           activeSelection != selectedApps {
            selectedApps = activeSelection
        }

        if isUsageLimitMonitoringEnabled,
           let activeConfiguration = TargetUsageLimitConfigurationStore.loadActive(),
           activeConfiguration != targetLimitConfiguration {
            targetLimitConfiguration = activeConfiguration
            TargetUsageLimitConfigurationStore.saveConfigured(activeConfiguration)
        }

        let lockedRuleIDs = IndividualLimitDayStateStore.reconcile(
            validRuleIDs: Set(targetLimitConfiguration.rules.map(\.id))
        )
        lockedIndividualTargetCount = lockedRuleIDs.count

        if authorizationStatus == .denied {
            barrierState = .passed
            screenTimeController.clearShield()
            screenTimeController.setAppRemovalProtectionEnabled(false)
            isAppRemovalProtectionEnabled = false
            UsageLimitMonitoringStateStore.clear()
            IndividualLimitDayStateStore.clear()
            lockedIndividualTargetCount = 0
            return
        }

        restoreBarrierState(
            Self.restoredBarrierState(
                from: SharedShieldStore.readSnapshot(),
                configuration: targetLimitConfiguration,
                lockedRuleIDs: lockedRuleIDs
            )
        )
        reconcileManagedShieldWithCurrentState()
    }

    /// DeviceActivityMonitor runs in another process. While Home is visible,
    /// observe its shared lock evidence so the mascot and status change shortly
    /// after the system applies a shield instead of waiting for the next launch.
    func refreshBarrierStateIfChanged() {
        let lockedRuleIDs = IndividualLimitDayStateStore.reconcile(
            validRuleIDs: Set(targetLimitConfiguration.rules.map(\.id))
        )
        let restoredState = Self.restoredBarrierState(
            from: SharedShieldStore.readSnapshot(),
            configuration: targetLimitConfiguration,
            lockedRuleIDs: lockedRuleIDs
        )

        guard lockedIndividualTargetCount != lockedRuleIDs.count
                || barrierState != restoredState
        else {
            return
        }

        lockedIndividualTargetCount = lockedRuleIDs.count
        restoreBarrierState(restoredState)
        reconcileManagedShieldWithCurrentState()
    }

    private func refreshUsageLimitMonitoringIfNeeded() {
        guard isUsageLimitMonitoringEnabled else {
            return
        }

        restartUsageLimitMonitoringForConfigurationChange()
    }

    @discardableResult
    private func restartUsageLimitMonitoringForConfigurationChange() -> Bool {
        do {
            try startUsageLimitMonitoringOnController(includesPastActivity: true)
            isUsageLimitMonitoringEnabled = true
            return true
        } catch {
            isUsageLimitMonitoringEnabled = screenTimeController.isUsageLimitMonitoringActive
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func startUsageLimitMonitoringOnController(
        includesPastActivity: Bool = false
    ) throws {
        try screenTimeController.startUsageLimitMonitoring(
            for: selectedApps,
            rules: weeklyUsageRules,
            targetConfiguration: targetLimitConfiguration,
            includesPastActivity: includesPastActivity
        )

        if barrierState == .locked {
            let activeSelection = FamilyActivitySelectionStore.loadActive() ?? selectedApps
            let activeConfiguration = (TargetUsageLimitConfigurationStore.loadActive()
                ?? targetLimitConfiguration).normalized(
                    for: activeSelection,
                    defaultLimitMinutes: usageLimit(for: .current())
                )

            if activeConfiguration.mode == .individual {
                let validRuleIDs = Set(activeConfiguration.rules.map(\.id))
                let lockedRuleIDs = IndividualLimitDayStateStore.reconcile(
                    validRuleIDs: validRuleIDs
                )

                if lockedRuleIDs.isEmpty {
                    // Missing per-target evidence must fail open. Inferring
                    // every target from the global locked flag caused a single
                    // individual limit to expand into an all-app lock.
                    screenTimeController.clearShield()
                    lockedIndividualTargetCount = 0
                    restoreBarrierState(.passed)
                } else {
                    try screenTimeController.applyShield(
                        for: activeConfiguration.selection(forRuleIDs: lockedRuleIDs)
                    )
                    lockedIndividualTargetCount = lockedRuleIDs.count
                }
            } else {
                try screenTimeController.applyShield(for: activeSelection)
                IndividualLimitDayStateStore.clear()
                lockedIndividualTargetCount = 0
            }
            // Restarting a schedule invokes intervalDidStart, which resets the
            // shared day state. Restore the already-enforced lock atomically.
            syncShieldSnapshot()
            syncWidgetSnapshot()
        }

        lastRejectedThresholdDate = nil
    }

    private func updateStoredAuthorizationState() {
        if isScreenTimeAuthorized {
            ScreenTimeAuthorizationStateStore.markAuthorized()
        } else if authorizationStatus == .denied {
            ScreenTimeAuthorizationStateStore.markDenied()
        }
    }

    private static func restoredBarrierState(
        from snapshot: ShieldSnapshot,
        configuration: TargetUsageLimitConfiguration,
        lockedRuleIDs: Set<String>,
        at date: Date = .now
    ) -> BarrierState {
        guard snapshot.isLockedToday(at: date) else {
            return .passed
        }

        if configuration.mode == .individual {
            return lockedRuleIDs.isEmpty ? .passed : .locked
        }

        // An individual snapshot without individual evidence must not be
        // interpreted as a combined lock after state/configuration drift.
        guard snapshot.lockScope != .individual else {
            return .passed
        }

        return .locked
    }

    private func reconcileManagedShieldWithCurrentState() {
        guard barrierState == .locked else {
            screenTimeController.clearShield()
            return
        }

        if isIndividualLimitMode {
            let validRuleIDs = Set(targetLimitConfiguration.rules.map(\.id))
            let lockedRuleIDs = IndividualLimitDayStateStore.reconcile(
                validRuleIDs: validRuleIDs
            )
            let lockedSelection = targetLimitConfiguration.selection(
                forRuleIDs: lockedRuleIDs
            )

            guard !lockedRuleIDs.isEmpty,
                  !lockedSelection.applicationTokens.isEmpty
                    || !lockedSelection.categoryTokens.isEmpty
                    || !lockedSelection.webDomainTokens.isEmpty
            else {
                screenTimeController.clearShield()
                lockedIndividualTargetCount = 0
                restoreBarrierState(.passed)
                syncShieldSnapshot()
                return
            }

            do {
                try screenTimeController.applyShield(for: lockedSelection)
                lockedIndividualTargetCount = lockedRuleIDs.count
            } catch {
                screenTimeController.clearShield()
                lockedIndividualTargetCount = 0
                restoreBarrierState(.passed)
                syncShieldSnapshot()
                lastErrorMessage = error.localizedDescription
            }
            return
        }

        do {
            try screenTimeController.applyShield(for: monitoredApps)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func restoreBarrierState(_ state: BarrierState) {
        isRestoringBarrierState = true
        barrierState = state
        isRestoringBarrierState = false
    }

    private func syncShieldSnapshot() {
        SharedShieldStore.writeSnapshot(
            ShieldSnapshot(
                barrierState: barrierState.sharedState,
                updatedAt: Date(),
                lockScope: isIndividualLimitMode ? .individual : .combined
            )
        )
    }

    private func syncWidgetSnapshot() {
        let previousSnapshot = SekishoWidgetSnapshotStore.read()
        let usedMinutes: Int

        if Calendar.current.isDate(previousSnapshot.updatedAt, inSameDayAs: .now) {
            usedMinutes = min(
                previousSnapshot.usedMinutes,
                displayUsageLimitMinutes
            )
        } else {
            usedMinutes = 0
        }

        SekishoWidgetSnapshotStore.write(
            SekishoWidgetSnapshot(
                barrierState: barrierState.sharedState,
                usageLimitMinutes: displayUsageLimitMinutes,
                usedMinutes: usedMinutes,
                selectedTargetCount: selectedTokenCount,
                isMonitoringActive: isUsageLimitMonitoringEnabled,
                updatedAt: .now,
                limitModeRawValue: targetLimitConfiguration.mode.rawValue,
                lockedTargetCount: lockedIndividualTargetCount
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "SekishoWidget")
    }

    private func canChangeTodayLimit(from oldValue: Int, to newValue: Int) -> Bool {
        guard oldValue != newValue else {
            return true
        }

        guard isDailyConfigurationLocked else {
            return true
        }

        lastErrorMessage = "見守りを開始した後は、通常の設定画面から今日の上限を変更できません。"
        return false
    }

    private func saveRules(_ rules: WeeklyUsageRules, restartingMonitoring: Bool) {
        weeklyUsageRules = rules
        WeeklyUsageRulesStore.save(rules)
        synchronizeTodayUsageLimit()

        if restartingMonitoring {
            refreshUsageLimitMonitoringIfNeeded()
        }
    }

    private func saveTargetLimitConfiguration(
        _ configuration: TargetUsageLimitConfiguration,
        restartingMonitoring: Bool
    ) {
        let previousConfiguration = targetLimitConfiguration
        targetLimitConfiguration = configuration.normalized(
            for: selectedApps,
            defaultLimitMinutes: configuration.defaultLimitMinutes
        )
        TargetUsageLimitConfigurationStore.saveConfigured(targetLimitConfiguration)

        if restartingMonitoring, isUsageLimitMonitoringEnabled {
            let didRestart = restartUsageLimitMonitoringForConfigurationChange()
            if !didRestart {
                targetLimitConfiguration = TargetUsageLimitConfigurationStore.loadActive()
                    ?? previousConfiguration
                TargetUsageLimitConfigurationStore.saveConfigured(targetLimitConfiguration)
            }
        }
    }

    private func synchronizeTodayUsageLimit() {
        let currentLimit = weeklyUsageRules.limit(for: .current())
        guard usageLimitMinutes != currentLimit else {
            return
        }

        isSynchronizingUsageLimit = true
        usageLimitMinutes = currentLimit
        isSynchronizingUsageLimit = false
        UsageLimitSettingsStore.save(currentLimit)
    }
}
